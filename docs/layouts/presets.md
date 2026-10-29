# TwichUI presets: authoring, publishing and bundling them

The setup wizard's **TwichUI helpers** question offers a few presets ("Leave them as they are", "On-screen helpers", "Helpers and
navigation"). This page is for the person who maintains them: how to change them in game, add more, publish them, and ship
exactly what you approved inside TwichUI. Built 2026-10-28, offline-tested only: nothing here has been run on WoW: Forever
(`implementation-status.md`). `architecture.md` is the contract; this page is the procedure.

## What a preset is

A preset is one option of that question. It names a set of TwichUI settings and, for each one, either **a value** (on, off, 0,
a word, a colour, a font name) or **reset to TwichUI's default**. A setting it doesn't name is **not managed**: picking the preset
never changes it, and never "resets" it by leaving it out.

| A preset may name | A preset never names |
|---|---|
| Any TwichUI setting the layout adapter manages: profile-scoped, not kept local, not a list. Feature switches (on and off), and the looks and behaviour of each feature | Anything that acts for you (selling, auto-filling trades, accepting summons, the guide's automation), talks to other players (sharing, party pins, map pings, vendors and trainers' sharing), records and personal lists (reminders, pins, Chronicle, NPC knowledge), account-wide settings (stat weights, the settings window's motion), lists (marker order, restock items, chat rules, class-bar overrides, known ammunition, Healer Watch phrases, hazard rules), **positions** (where things sit belongs to the layout), another addon's setting, or a setting another wizard choice sets (accent, tooltip, friendly plates, size) |

The workspace's editor has a **Never in a preset** view that lists each of these with its reason. Nothing here widens what the
layout adapter allowed before: the adapter's allowlist (`AdapterTwichUI.lua`, `TwichConfig.LOCAL`) is the one rule.

**Leave them as they are** is a structural option: it names nothing, can't be captured into or removed, and leaves every setting
the presets manage as the player has it. It does **not** stop the layout's own TwichUI looks (the shared base: about 200 looks and
behaviour settings, never feature switches) from applying; those apply whichever option is picked. The wizard's review says how
many of the presets' settings the layout's looks also set.

**Precedence** (lowest to highest): the layout's shared base, the layout variant, the picked preset, the other wizard choices (which
never name a TwichUI setting a preset names: two choices may not write the same setting), the screen layer (positions only; a
preset has none), then the player's own kept or owned settings on an update.

## 1. Save your current settings into On-screen helpers

1. Set TwichUI up in game the way the preset should leave it (in the profile you use, or any other profile).
2. `/tui layout author` opens the workspace. Section **4. TwichUI presets** lists the options.
3. **Read settings from**: the profile to read, by its exact name; it starts as the profile in use. Use the arrows for another one.
   It is only read: never switched to, never written.
4. Click **On-screen helpers**, then **Capture current settings into this preset**. The editor opens ("not saved to the draft").
   - The preset keeps **its own scope**: the settings it already manages take your profile's values, as the feature uses them. A
     setting you left at TwichUI's default is captured as that value, so a feature you switched off is captured as off.
   - A setting the preset doesn't manage is listed under **Not managed** (the ones you changed from TwichUI's default first). It is
     never added unless you tick it.
5. Review: **Managed**, **Changed** (against the draft: changed, newly managed, no longer managed), **Not managed**, **Never in a
   preset**; a category and a search narrow the list. For a switch or a word, the value button changes the preset's value; a
   number, colour or font name has a field (checked by the setting's own rule); **Reset** makes it "TwichUI's default".
6. **Save to draft.** Nothing is in the package before this; **Discard** drops the edit.

The first change you save turns the selector into **editable presets** (package format 6): each option keeps exactly the
settings and values it had, the empty option becomes "Leave them as they are", and the question's description is replaced by one
that no longer says "only turns things on" (edit it in **Question's description**). TwichUI versions before this one refuse a
format 6 package rather than misread it.

## 2. Create another preset

- **Create preset from current settings**: a new option, with a new id, managing **whether each feature is on or off** (every
  feature switch a preset may manage) with your profile's values. Name it in the editor, add looks and behaviour settings under
  **Not managed**, then **Save to draft**.
- **Duplicate**: a copy of the selected preset with a new id, next to it ("Copy of ..."). Rename it and adjust it.
- At most 8 options in all, and 256 settings per preset.

## 3. Choose which settings a preset manages

**Review settings** opens the editor without capturing again. Tick or untick settings; **Include all shown** / **Leave out all
shown** act on what the list shows (so with a category chosen, on that category). Including more than 256 is refused as a whole.
A setting a preset newly manages takes the value your source profile has when you tick it.

## 4. Update a preset without changing its id

Capturing into a preset, reviewing it, renaming it (**Name**) and describing it (**Description**) all keep its **stable id**
(**Show details** shows it). Players' picks are remembered by the id, so renaming is safe. Order (the arrows), **Make default**
and **Remove** are draft edits too:
- **Remove** asks first. The default can't be removed until another option is the default. A removed option's id goes in the
  package's `retired` list and is never given to a new option, so a player who picked it is told it is gone, never handed a
  different preset with the same name.

## 5. Publish and send it

Section 5 **Check** validates the draft as a recipient's TwichUI will (and lists any preset problem); section 6 **Publish** keeps an
immutable snapshot; section 7 **Send** offers it to a named player (`publishing.md`). Closing the workspace with preset work that
isn't saved or published asks first (**Close**), and **Escape** keeps the session until you reload.

## 6. Bundle the approved package for the next release

The package TwichUI ships is built from repository files. To ship exactly what you published:

1. In section 7, press **Export for bundling** on the published package. A window shows one line of text (the published bytes
   with the package id, revision, fingerprint and size in front). Click **Select all**, press Ctrl+C, paste it into a text file,
   for example `~/twichui-export.txt`. (The game gives an addon no clipboard and no files: this is the copy you make.)
   Or skip this and use your saved file: log out or `/reload` so the game writes `!!!TwichUI.lua`.
2. From the repository root (WSL):

   ```
   tools/update_bundled_layout.sh --from-published --text ~/twichui-export.txt
   # or, from the published list in your saved files (found as for a recapture; --sv DIR, --client, --account work the same):
   tools/update_bundled_layout.sh --from-published --list            # what is published there
   tools/update_bundled_layout.sh --from-published --revision 5      # import that one
   ```

3. It copies the source to a temporary folder (the original is only read), unpacks the package with the transport's own bounded
   decoder, checks it with `Pub.Check` (the recipient's check), and compares it with the repository's package. It writes:

   | File | What |
   |---|---|
   | `TwichUI_Layouts/ChoicesData.lua` | The package's choices, exactly (the presets among them): generated, never hand-edited |
   | `TwichUI_Layouts/ClassicData.lua`, `CompactData.lua` | Only when the published layers differ from the repository's, written back in the form `Classic.lua` composes |
   | `TwichUI_Layouts/Classic.lua` | Only the `revision` line (the published revision) |
   | `docs/layouts/import-published.md` | The report: the source, fingerprint, what it resolves to, what changed, the presets it holds |

4. Then the round trip, in a fresh process: `tools/check_bundled_layout.lua --published ...` loads the bundled package from those
   files, unpacks the published entry again, and requires them to resolve the same (`Pub.Compare`), the choices to be identical
   byte for byte (labels and descriptions too) and the revision to match. A failure puts every file back. Then the offline tests
   (`--no-tests` skips them; the result then says "not tested").

**A layout's copy of a shared module is left out when it adds nothing.** The workspace's review compares exactly, so a layout whose
profile was set up from an install (positions written to two decimals, numbers to 15 digits) can publish its own copy of a module the
shared base already holds, differing only in how the numbers were written. Bundled as it is, that copy would stop later changes to the
base from reaching that layout. The import (`LD.DropSharedCopies`, `tools/layout_data.lua`) leaves such a copy out, and the round trip
leaves it out of the published package too before comparing. It matches a number only to about 12 digits, or a position or size (10 and
up) to its two-decimal rounding, never a colour or an opacity; and it does not compare a setting an enum choice always writes (the
friendly-plates choice's `showFriendlyPlayers`), since the picked option replaces whatever the layer holds. Any other difference keeps the
copy. The report lists what was left out and what was kept, and why.

**Only these may differ** between the bundled and the published package: the title, `made` and `source` (the publication's own
words), the developer flag (`dev = true` stays until the layouts are checked on WoW: Forever), and the declared format (the
bundled package declares the lowest its choices need). None of them changes what an install resolves to.

**It stops, writing nothing, when**: the text is damaged or isn't an export; the package fails the recipient's check; it is
another package than `twichui-adventure`; its screen rules, target profiles or requirements differ from `Classic.lua`'s (those are
written there by hand: change them there, or publish from the same); its revision isn't higher than the bundled one while its
contents differ; more than one published package matches (name one with `--revision`/`--hash`); or its layers hold something the
data files can't (a TwichUI setting kept in one layout only). **Already bundled** (the same contents) writes nothing and exits 0.
Running it twice gives the same files byte for byte.

**The profile recapture keeps your presets.** `tools/update_bundled_layout.sh` without `--from-published` recaptures the layers
from saved profiles and never writes `ChoicesData.lua` (`updating-the-bundled-layout.md`). Its revision bump is its own.

5. Read the report and `git diff`, try it in game (`tools/deploy.sh`, then `/tui layout`), commit the files, release as
   `RELEASING.md` says. Nothing is committed, deployed or released by the tools.

## 7. Test it, and undo it

- **In the wizard**: `/tui layout` on a character. The Helpers step shows one card for each option, whatever their number, with a one-sentence
  description; **View included settings** on a card lists what it turns on and off, how many other settings it sets or resets, and what it
  leaves alone (and the author's full description). The Review step says which preset, what it turns on and off, changes, resets, finds already set, leaves
  alone (settings only other presets manage), and which of its settings stay as you have them.
- **On an installed setup**: picking a *different* preset than the one installed is a deliberate switch: its settings take the
  preset's values (the review still offers "keep mine" for each, and says plainly when a kept or owned setting means the preset
  isn't fully in effect). Staying on the *same* preset while the package changed it follows the update's normal rules (your own
  changes are kept unless you choose otherwise). A preset that is no longer offered is named on the Helpers step and the setup
  waits for a pick.
- **Undo this update** puts back what the last update changed; **Restore** goes back to before the first install; **Keep this
  setup** ends the journal and keeps managing (`updates.md`). Every preset setting is snapshotted, verified by value, and part of
  the baseline like any other TwichUI setting.
- **The draft**: Discard an edit, or close the workspace (it asks). A published package is never changed by later edits.
- **The bundling**: `git checkout -- TwichUI_Layouts/ChoicesData.lua TwichUI_Layouts/ClassicData.lua TwichUI_Layouts/CompactData.lua TwichUI_Layouts/Classic.lua`
  and delete `docs/layouts/import-published.md` if git doesn't know it.

## Limits and what isn't checked

- Offline only. In game, still to check: the workspace's presets section and editor at 1080p and larger fonts; a capture from a
  real profile; the Export window with an 80 KB line (copying it out); a real install, reload and check with an editable preset.
- 8 options per choice, 256 settings per preset, 32 retired ids; a whole package stays within the existing bounds (8 MB canonical,
  768 KB on the wire).
- A preset can't move anything (positions are the layout's) and can't hold lists. Settings the profile recapture would capture
  only as values different from the default are captured by a preset at their effective value, whatever it is.
- Editing other wizard questions (accent, tooltip, plates, size) isn't part of the workspace: they are data in `ChoicesData.lua`,
  carried exactly by the import. The accent's "Aged gold" option holds its own colour there, so a recapture that changes the look's
  accent doesn't change what that option applies (`check_bundled_layout.lua` notes it).
