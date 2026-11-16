"""Smoke permits evidenced simulator limits; unexpected errors and other origins fail."""
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


VOICE = """SIMLAB voice-capability native=true unavailable=true
SIMLAB smoke-clock begin
SIMLAB tick t=17.0
Lua error: C_VoiceChat.CanAccessSettings: settings access has not been supplied
stack traceback:
    (string):1: in main chunk
    [C]: in function 'AdvanceTime'
    (string):54: in main chunk
    [C]: ?

SIMLAB smoke-clock end
"""

class NativeVoiceErrors(unittest.TestCase):
    passed = SmokeErrors.passed

    def test_native_timer_with_read_only_probe_is_disclosed(self):
        self.assertTrue(self.passed(HELLO + VOICE))
        result = verdict.classify_smoke(VOICE)
        self.assertEqual(result['known']['voice-settings-unsupplied']['first_tick'], 17.0)
        duplicate = VOICE.replace('    [C]: ?', "    [C]: ?\n    [Interface/AddOns/Blizzard_ScriptErrors/Blizzard_ScriptErrors.lua]:59: in function 'GetErrorData'")
        self.assertTrue(self.passed(duplicate))

    def test_missing_probe_scope_and_native_stack_fail(self):
        for old, new in (
            ('native=true', 'native=false'), ('unavailable=true', 'unavailable=false'),
            ('stack traceback:\n', ''), ('    (string):54: in main chunk\n', ''),
            ('SIMLAB voice-capability native=true unavailable=true\n', ''),
            ('SIMLAB smoke-clock begin\n', ''), ('SIMLAB smoke-clock end\n', ''),
            ("[C]: in function 'AdvanceTime'", "[C]: in function 'OtherCall'"),
            ('    (string):54: in main chunk', "    [Interface/AddOns/!!!TwichUI/Core.lua]:54: in function 'bad'"),
            ('settings access has not been supplied', 'unexpected voice failure'),
        ):
            with self.subTest(change=old):
                self.assertFalse(self.passed(VOICE.replace(old, new)))
        self.assertFalse(self.passed(VOICE + 'Lua error: deliberate unexpected failure\n'))
        raw = VOICE.split('SIMLAB tick t=17.0\n')[1].split('SIMLAB smoke-clock end')[0]
        self.assertFalse(self.passed(VOICE + raw))
        self.assertFalse(self.passed(VOICE.replace('SIMLAB smoke-clock begin\n', 'SIMLAB smoke-clock begin\n' * 2)))

    def test_suppressed_summary_needs_full_native_occurrence(self):
        summary = 'Lua error suppressed 2 additional times: C_VoiceChat.CanAccessSettings: settings access has not been supplied\n'
        self.assertTrue(self.passed(VOICE.replace('SIMLAB smoke-clock end', summary + 'SIMLAB smoke-clock end')))
        first = VOICE.index('Lua error:')
        end = VOICE.index('SIMLAB smoke-clock end')
        self.assertFalse(self.passed(VOICE[:first] + summary + VOICE[end:]))
