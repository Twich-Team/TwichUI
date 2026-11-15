"""The known group hello error is disclosed; unexpected errors still fail smoke."""
import importlib.util
from pathlib import Path
import sys
import subprocess
import unittest

SIMLAB = Path(__file__).resolve().parent.parent / 'tools/simlab'
sys.path.insert(0, str(SIMLAB))
spec = importlib.util.spec_from_file_location('smoke_verdict', SIMLAB / 'verdict.py')
verdict = importlib.util.module_from_spec(spec)
spec.loader.exec_module(verdict)

HELLO = """SIMLAB tick t=3.2
Lua error: Lua Error: string at argument 2 is not valid UTF-8
[ChatThrottleLib.lua]:391: in function 'PerformSend'
[Share.lua]:425: in function 'SendControl'
[Group.lua]:84: in function 'SayHello'

"""

class SmokeErrors(unittest.TestCase):
    def test_isolated_python_can_import_verdict(self):
        code = "import runpy; runpy.run_path(%r, run_name='probe')" % str(SIMLAB / 'verdict.py')
        result = subprocess.run([sys.executable, '-I', '-c', code], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)

    def passed(self, text):
        return all(ok for _, ok, _ in verdict.kf.verdict_lines(verdict.classify_smoke(text)))

    def test_exact_hello_is_classified_and_timed(self):
        result = verdict.classify_smoke(HELLO)
        self.assertTrue(self.passed(HELLO))
        self.assertEqual(result['known']['addon-message-invalid-utf8']['first_tick'], 3.2)

    def test_unexpected_error_and_other_utf8_origin_fail(self):
        self.assertFalse(self.passed(HELLO + 'Lua error: deliberate unexpected failure\n'))
        for context in ('SayHello', 'SendControl', 'PerformSend'):
            self.assertFalse(self.passed(HELLO.replace(context, 'other_function')))
        self.assertFalse(self.passed('Lua error: string at argument 2 is not valid UTF-8\n'))
