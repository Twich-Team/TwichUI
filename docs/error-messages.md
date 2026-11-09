# Hide error messages and error speech

`!!!TwichUI/qol/ErrorMessages.lua` (`R.QoLErrors`), three switches, all in Quality of life:

| Switch | Default | Does |
|---|---|---|
| `qolHideErrors` | off | Hides the red error text ("Not enough rage", "Out of range"), with the voice and sound the game plays for it. |
| `qolHideErrorsKeep` | on (needs the one above) | Still shows a full bag, a full quest log, being dead and raid-only actions (`E.IMPORTANT`, global strings compared exactly). |
| `qolHideErrorSpeech` | off | Silences only the voice; the text stays. |

## How
- Blizzard_UIErrorsFrame adds the line and plays the voice (`C_Sound.PlayVocalErrorSound`) or sound in one place,
  `UIErrorsMixin:TryDisplayMessage`, on `UI_ERROR_MESSAGE`. Hiding errors unregisters that event from `UIErrorsFrame`
  (Leatrix Plus swaps the OnEvent script instead; this leaves Blizzard's script alone). Information messages
  (`UI_INFO_MESSAGE`), `SYSMSG` and anything an addon adds with `UIErrorsFrame:AddMessage` (TwichUI's own notices)
  are other paths and are untouched.
- The important few are passed to `UIErrorsFrame:TryDisplayMessage` from TwichUI's own `UI_ERROR_MESSAGE` listener,
  which exists only while hiding and the exception are both on. A secret or non-string message counts as not important.
- Speech is the game's CVar `Sound_EnableErrorSpeech` (Settings > Audio). On: set to 0, the old value kept in
  `TwichUIDB.ui.qol.errorSpeechWas`. Off: put back only if the CVar is still 0; a CVar already 0 is never written or
  turned on, a damaged record is dropped. `ui.qol` is not shared (configuration sharing keeps it local).
- The three switches are kept local in configuration sharing (`other`): speech writes a game setting.

## Not covered
The ping system's error line (Leatrix also unregisters `PING_SYSTEM_ERROR` from UIParent), errors in chat, other addons' messages.

## Checks
Unit-tested: `tests/test_qol_errors.lua` (event wiring, exception, CVar bookkeeping). Not tested in the real client:
that unregistering the event hides the line, that the voice stops with the CVar, the message strings matching.
Diagnostics: no scope or gauge; the only recurring work is one string comparison per error while the exception is on.
