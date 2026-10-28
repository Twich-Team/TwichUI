# Updating the layout that ships with TwichUI

How to take the layouts you have set up in game and make them the Classic Adventure and Compact Adventure that everyone gets
with TwichUI. The short version is one command:

```
tools/update_bundled_layout.sh
```

The rest of this page says what to do before running it, what it does, how to read what it prints, and what to do when
something stops it.

## Shipping it versus sending it

There are two ways to give a layout to other players. They don't affect each other.

| | Ship it in the addon (this page) | Send it from the game |
|---|---|---|
| How | `tools/update_bundled_layout.sh`, then a release | `/tui layout author`: Capture, Publish, Send (`publishing.md`) |
| Who gets it | Everyone who installs or updates TwichUI | Only the players you send it to, after they accept |
| Where it ends up | `TwichUI_Layouts/ClassicData.lua` and `CompactData.lua` in the repository | Your saved settings, and theirs |
| Good for | The real release | Trying a change with a friend first |

## Before you run it

1. **Set the layouts up in game**, on these profiles (the script's defaults; other names can be given, see "Options"):

   | Layout | EllesmereUI profile | TwichUI profile |
   |---|---|---|
   | Classic Adventure | `TwichUI - Classic Adventure` | `Default` |
   | Compact Adventure | `TwichUI - Minimal Adventure` | (shares Classic's TwichUI settings) |

   The TwichUI settings (looks, and where TwichUI's own pieces sit) come from `Default` for both layouts. The profile you
   are using in game doesn't matter: the script reads the named profiles, wherever they are.

2. **Use TwichUI's fonts.** A font from your own font folder (an addon like `MyFonts`) isn't on other players' computers.
   The script swaps one for TwichUI's copy when TwichUI ships the same file, and warns when it can't. Fonts from TwichUI,
   EllesmereUI and the game itself are fine.

3. **Log out (or `/reload`).** The game writes your settings to disk only then. The script prints the time each file was
   last written, so you can see it is the change you just made.

4. **Commit or put aside your other work.** The script changes five files (listed below), so a clean working tree makes it
   easy to see and undo exactly what it did.

You need `lua5.1` with luabitop (`sudo apt install lua5.1 lua-bitop`) and `python3`, as the tests do.

## Running it

From the repository root, in WSL:

```
tools/update_bundled_layout.sh                  # WoW: Forever's saved settings (the default)
tools/update_bundled_layout.sh --client retail  # Retail's, while Forever has none
```

It finds the World of Warcraft folder at `/mnt/c/Program Files (x86)/World of Warcraft` and the account folder by itself
when there is only one.

### What it does

1. **Copies** your `EllesmereUI.lua` and `!!!TwichUI.lua` saved files to a temporary folder. The originals are only read.
2. **Captures Classic Adventure** with `tools/layout_capture.lua` into `TwichUI_Layouts/ClassicData.lua`, and writes a
   report to `docs/layouts/capture-classic-adventure.md`.
3. **Captures Compact Adventure** into `TwichUI_Layouts/CompactData.lua`, keeping only what differs from Classic (the
   modules both share are kept once), with its report in `docs/layouts/capture-compact-adventure.md`.
4. **Fixes font paths** that point into another addon's folder, when TwichUI has the same font.
5. **Raises the package revision** in `TwichUI_Layouts/Classic.lua` (for example 3 to 4). This is what makes players who
   already have the layout see the new one as an update.
6. **Runs the offline tests** (`./tests/run.sh`, a few minutes).
7. **Shows what changed** and what to do next.

The capture keeps only what a layout may carry: EllesmereUI's look, its modules and layout links, and TwichUI's looks and
places that differ from TwichUI's defaults. It never takes key bindings, action bar contents, spell layouts, spec overrides,
character data, other profiles or your UI scale. It also scans everything it keeps for your character names, GUIDs, item
links and BattleTags, and writes nothing if it finds any.

### Files it changes

| File | What |
|---|---|
| `TwichUI_Layouts/ClassicData.lua` | Classic Adventure's settings (generated) |
| `TwichUI_Layouts/CompactData.lua` | What Compact Adventure has of its own (generated) |
| `TwichUI_Layouts/Classic.lua` | Only the `revision` number |
| `docs/layouts/capture-classic-adventure.md`, `capture-compact-adventure.md` | The reports: what was kept, what was left out, the scan's result |

If a capture fails, the script puts these files back as they were. Nothing is committed, deployed or released.

### Options

| Option | Meaning |
|---|---|
| `--client forever\|retail` | Which game client's saved settings to read (default `forever`) |
| `--account NAME` | The account folder under `WTF/Account`, when there is more than one |
| `--sv DIR` | Read the two saved files from this folder instead (for example a copy from another computer) |
| `--wow DIR` | Where World of Warcraft is installed |
| `--classic-profile NAME`, `--compact-profile NAME`, `--twichui-profile NAME` | Other profile names |
| `--no-bump` | Don't raise the revision (for example when running it a second time before releasing) |
| `--no-tests` | Skip the tests |

Run it again as often as you like before you commit. Use `--no-bump` on the second and later runs, or the revision goes up
each time. A revision that went up more than once does no harm, it just skips numbers.

## After it runs

1. **Read the two reports.** Check that what was kept is what you meant to change, and that nothing you care about is under
   "Left out".
2. **Look at the diff**: `git diff --stat`, then `git diff` on the data files. Changing a few settings should change a few
   lines.
3. **Try it in game**: copy the addons into the game (`tools/deploy.sh` if you use it; it copies to `_retail_`), then
   `/tui layout`. On a character that already has the layout, Set up again: the review shows it as an update and lists what
   changes.
4. **Commit** the five files, with the reason for the change in the message.
5. **Release** as `RELEASING.md` says (tag the commit and push the tag; the workflow packages and publishes).

To throw a run away before committing:

```
git checkout -- TwichUI_Layouts/ClassicData.lua TwichUI_Layouts/CompactData.lua TwichUI_Layouts/Classic.lua \
  docs/layouts/capture-classic-adventure.md docs/layouts/capture-compact-adventure.md
```

## What players see

- **A new player** gets your layouts the first time they open `/tui layout`.
- **A player who already installed the layout** opens `/tui layout` and chooses Set up again. Because the revision went up,
  it is an update: the changes they made themselves are kept, your changes to everything else are applied, and where you
  both changed the same setting theirs is kept unless they choose yours (`updates.md`). They can undo the update. Nothing
  happens until they open the setup: there is no "update available" notice.

## When something stops it

| Message | What to do |
|---|---|
| `no EllesmereUI.lua in …` | No settings saved from that client yet. Log in and out once, or use `--client retail` |
| `more than one account folder` | Add `--account NAME` (the folder names are listed in the message) |
| `no EllesmereUI profile with that name` | Check the profile's exact name in EllesmereUI's profile list, or pass `--classic-profile` / `--compact-profile` |
| `no TwichUI profile with that name` | Check the name under TwichUI's settings, Profiles, or pass `--twichui-profile` |
| The scan found a name, GUID, link or BattleTag | Something in a profile holds personal text (often a custom label). Remove it in game, log out, run again. The report says how many were found, never what |
| A look key (fonts, accent, colours) differs between the two layouts | Both layouts share one look. Make the two EllesmereUI profiles' fonts, accent and dark-mode colours the same, then run again |
| `WARNING … is in another addon's folder and TwichUI has no copy of it` | Pick one of TwichUI's fonts (or EllesmereUI's) for that setting in game, log out, run again |
| `World of Warcraft looks like it is running` | Only a warning: the files are from your last logout or reload |
| `lua5.1 can't load luabitop` | `sudo apt install lua-bitop` |

### When tests fail

The script keeps the new files and lists the failing checks. Most tests don't depend on what your layout holds, but a few
check the captured layout exactly:

| Test | What it checks | If you changed that on purpose |
|---|---|---|
| `test_layout_geometry.lua` | Each attached position on your canvas, the component boxes, how many positions are placed | Update the expected numbers. If you moved pieces a long way, the component boxes in `TwichUI_Layouts/Classic.lua` (measured from your layout) may need adjusting too |
| `test_layouts.lua` §16, §18 | Where the minimap, chat, marker bar and Healer Watch land on a 1920 × 1080 screen; placed-row counts | Update the expected positions |
| `test_layout_update.lua` | That a few fonts and modules exist in the package (class bars' and navigation's font, the Bags and Chat modules) | Only if you removed one of those |

The publishing tests follow the shipped revision by themselves, so raising it needs no test changes.

## Things to know

- **The package is still a preview.** `Classic.lua` keeps `dev = true` until the layouts have been checked on WoW: Forever,
  and the setup tells players so. Removing it is a separate decision (D20 in `implementation-status.md`).
- **Compact shares Classic's TwichUI settings.** To give Compact TwichUI places of its own, it needs its own TwichUI profile
  and a change to how the package is put together (`wizard.md`, "Phase 6 handoff").
- **Choices stay as they are.** The wizard's choices (helpers, accent colours, size) and the screen rules are written in
  `Classic.lua`, not captured. Changing those is an edit to that file.
- **Running the capture by hand** works too: the header of `tools/layout_capture.lua` has the commands. The script only adds
  copying the saved files, the font fix, the revision and the test run around them.
