"""Fast synthetic vector/package verification; never native Forever evidence."""
import base64
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import unittest
import zipfile
import zlib

ROOT = Path(__file__).resolve().parents[1]
TOOL = ROOT / 'tools/codec-probe'


def module(name, path):
    if str(TOOL) not in sys.path:
        sys.path.insert(0, str(TOOL))
    spec = importlib.util.spec_from_file_location(name, path)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


class CodecProbe(unittest.TestCase):
    def test_external_vectors_with_independent_existing_lua_decoder(self):
        generator = module('codec_vectors', TOOL / 'generate_vectors.py')
        fixtures = dict(generator.fixtures())
        with tempfile.TemporaryDirectory(prefix='codec-probe-test-') as directory:
            temp = Path(directory)
            manifest = generator.make(temp)
            text = (temp / 'Vectors.lua').read_text()
            reference = json.loads((TOOL / 'vectors.json').read_text())
            self.assertEqual([(r['name'], r['expected_bytes'], r['sha256']) for r in manifest['fixtures']],
                             [(r['name'], r['expected_bytes'], r['sha256']) for r in reference['fixtures']])
            checks = []
            for row in manifest['fixtures']:
                name = row['name']
                section = text.split(f'P.Payloads.{name} = ', 1)[1].split('\n}', 1)[0]
                expected = re.search(r'expected = \[=\[(.*?)\]=\]', section, re.S)[1].encode()
                self.assertEqual(expected, fixtures[name])
                self.assertEqual(hashlib.sha256(expected).hexdigest(), row['sha256'])
                self.assertLessEqual(len(expected), 524288)
                raw_file = temp / f'{name}.expected'
                raw_file.write_bytes(expected)
                for mode, bits in [('raw', -15), ('zlib', 15)]:
                    encoded_match = re.search(r'\b' + mode + r' = \[=\[([^]]*)\]=\]', section)
                    encoded = encoded_match[1] if encoded_match else re.search(r'\braw = \[=\[([^]]*)\]=\]', section)[1]
                    packed = base64.b64decode(encoded, validate=True)
                    if not encoded_match:
                        prefix = re.search(r'zlibPrefix = "([^"]*)"', section)[1]
                        suffix = re.search(r'zlibSuffix = "([^"]*)"', section)[1]
                        literal = lambda s: bytes(int(x) for x in re.findall(r'\\(\d{3})', s))
                        packed = literal(prefix) + packed + literal(suffix)
                    self.assertEqual(zlib.decompress(packed, bits), expected)
                    if name == 'small':
                        with self.assertRaises(zlib.error):
                            zlib.decompress(packed[:len(packed)//2], bits)
                        bad = b'\x07' if mode == 'raw' else b'\x78\x9c\x07\x00\x00\x00\x01'
                        with self.assertRaises(zlib.error):
                            zlib.decompress(bad, bits)
                    self.assertEqual(hashlib.sha256(packed).hexdigest(), row['encodings'][mode]['sha256'])
                    path = temp / f'{name}.{mode}'
                    path.write_bytes(packed)
                    checks.append((mode, path, raw_file))
            # This is the pre-existing vendored library, used OFFLINE ONLY. It is
            # not copied to or used by the temporary addon/native measurements.
            lua = "local D=dofile(arg[1]);local function read(p)local f=assert(io.open(p,'rb'));local s=f:read('*a');f:close();return s end\n"
            lua += "for i=2,#arg,3 do local mode=arg[i];local input,expected=read(arg[i+1]),read(arg[i+2]);local output;if mode=='raw'then output=D:DecompressDeflate(input)else output=D:DecompressZlib(input)end;assert(output==expected,'independent vector mismatch: '..arg[i+1])end\n"
            script = temp / 'verify.lua'
            script.write_text(lua)
            args = ['lua5.1', str(script), str(ROOT / '!!!TwichUI/libs/LibDeflate/LibDeflate.lua')]
            for mode, path, expected in checks:
                args += [mode, str(path), str(expected)]
            subprocess.run(args, check=True, capture_output=True, timeout=20)

    def test_package_contains_only_required_isolated_development_files(self):
        packager = module('codec_package', TOOL / 'package_probe.py')
        with tempfile.TemporaryDirectory(prefix='codec-probe-zip-') as directory:
            out = Path(directory) / 'probe.zip'
            result = packager.package(out, '1' * 40)
            self.assertFalse(result['real_game_executed'])
            self.assertLess(result['zip_bytes'], 1024 * 1024)
            with zipfile.ZipFile(out) as archive:
                self.assertEqual(len(archive.namelist()), 5)
                toc = archive.read('TwichUI_CodecProbe/TwichUI_CodecProbe.toc').decode()
                self.assertNotIn('SavedVariables', toc)
                self.assertNotIn('LoadOnDemand', toc)
                entries = [line.strip() for line in toc.splitlines() if line.strip() and not line.startswith('#')]
                self.assertEqual(entries, ['Build.lua', 'Vectors.lua', 'Engine.lua', 'Probe.lua'])
                self.assertIn('## Interface: 16001', toc)
                for name in ('Engine.lua', 'Probe.lua'):
                    source = archive.read('TwichUI_CodecProbe/' + name).decode()
                    for forbidden in ('loadstring(', 'loadfile(', 'dofile(', 'SetCVar(', 'SendAddonMessage(', 'ReloadUI('):
                        self.assertNotIn(forbidden, source)
                build = archive.read('TwichUI_CodecProbe/Build.lua').decode()
                self.assertIn('1' * 40, build)
                self.assertIn(result['files_sha256']['Probe.lua'], build)
            self.assertIn('  - tools\n', (ROOT / '.pkgmeta').read_text())


if __name__ == '__main__':
    unittest.main()
