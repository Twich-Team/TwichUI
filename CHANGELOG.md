# TwichUI changelog

## Unreleased
- **New training** (new, on by default): when you level up and there are class spells or ranks you could train and don't know yet, a short title card near the top of the screen, below where the zone card appears, says **New Training Available** over the zone card's bronze rule, lists each spell with its icon and rank (with the level it became available beside each when they differ; two columns from seven spells, up to twelve and "and N more"), and ends with "Visit a class trainer". Like the zone card it has no frame or background, takes no clicks, and settles in and fades away by itself, staying a little longer for a longer list. They're available to train at your class trainer; nothing is learned for you. Spells from earlier levels you haven't trained are listed too, and when several ranks of one spell are waiting only the highest is shown. Only spells for your class, faction and race are listed, and only when you know their earlier rank and any required talent (or those are waiting too) and don't know them already. Quick level-ups give one card. You can move it in Edit Mode: while Edit Mode is open, a **New Training** outline stands where the card appears; drag it to move the card (the place is kept straight away, for all characters) or right-click it to put it back. Nothing shows when there is nothing to train, nor at login or reload; it waits until you're out of combat and until the zone card has gone, and makes way when combat starts. No sound, no chat; only the place you move it to is saved. Spell data is What's Training?'s WoW: Forever data (MIT licensed), bundled; What's Training? doesn't need to be installed. New option **Show new training when I level up** in the overview's General section; Reduced motion (Zone arrival page) applies. `/tui training` shows the card for your current level, `/tui training 20` for another.
- **Sell from Bags** (new, on by default): a fourth tab along the bottom of the Auction House. It lists the items in your bags the auction house will take (stacks of the same thing on one row; bound items are left out and counted). Picking an item searches its current listings, for that item only, and suggests matching the lowest comparable listing, never undercutting it. It shows what the suggestion is based on: the lowest price and how many are available at it, how many comparable listings were found, and what was left out (your own listings, bid-only listings, and for equipment other item levels or suffixes). It says when results are partial, when the search was made, and when they are out of date. You set quantity, price each and duration, and see the deposit and total; nothing is posted until you press **Post**, and when the game asks you to confirm a posting, its own dialog does. Opening the tab never searches, searches follow the auction house's limits without retrying by themselves, and results are kept only while the Auction House is open. With EllesmereUI's third-party skins on, the tab and page take its look to match the skinned Auction House. New page **Auction House** in the options with the switch **Add a Sell from Bags tab to the Auction House**.
- **Welcome Back** bookmark (new, on by default): when you log in to a character with Chronicle entries, a small card near the bottom of the screen shows "Last noted: The Barrens · 2 hours ago" with an **Open Chronicle** link and a close button, then fades away by itself. "Last noted" is the newest Chronicle entry that has a place and a date, not where you logged out. It shows only on a real login (not after a reload or a loading screen), waits for the zone card's quiet time, and is skipped in combat, on a flight path or while the zone card or another banner is up. It adds no Chronicle entry, makes no sound or chat line, stores nothing and sends nothing. New option **Show a Welcome Back bookmark** on the Journey Chronicle page; Reduced motion (Zone arrival page) applies. `/tui welcome` shows the bookmark now so you can see it without logging in again.
- **Options reorganised**: Esc > Options > AddOns > TwichUI is now a short overview (a row per feature with its status and an Open button, plus Custom fonts and sounds, Hide addon welcome messages and Show advanced options) with a page for each feature under it: **Gear comparison** (with Stat weights beneath it), **Zone arrival**, **Journey Chronicle**, **Addon skins** and **Configuration sharing**. Every option and saved value is unchanged; they just moved. With **Show advanced options** on, each page that has them shows an **Advanced** group. The Chronicle window's Options button opens the Journey Chronicle page.
- **Zone arrival** (new, on by default): arriving in a new zone shows its name as a short title card near the top of the screen, a thin bronze rule with the zone in parchment and the smaller place you're in beneath it. It settles in, stays a moment and fades away, in place of the game's own zone text. Nothing shows when you log in or reload, or while on a flight path (only where you land), and quick crossings show only the last place. Options in the new **Zone arrival** section: **Also for smaller places** (on by default; a quieter card when you walk into a town or other subzone) and **Reduced motion** (fade only); with **Show advanced options** on, **How long the card stays** (Brief, Standard, Long or Longer). No sound, and nothing is sent to anyone. If another addon also replaces the zone text, you may see both.
- **Zone arrival** for dungeons and raids: walking into one shows its name in the same title card with "Dungeon" or "Raid" beneath it, once, instead of the zone text. Nothing shows when you log in or reload inside one, or when moving around within it. New option **Show dungeon and raid arrival cards** (on by default); off gives the ordinary zone card there, as before. Battlegrounds, arenas and scenarios are unchanged.
- **Backups**: export and import. **Export** on a backup shows it as a text string you can copy (Ctrl+A, Ctrl+C) and paste into a text file to keep or move to another computer; WoW can't save files itself. **Import backup** takes such a string, checks all of it, and shows a preview (name, date, addons, size, addons not installed here) before **Import as backup** adds it to your Backups list. Importing never changes your current settings; only Restore does, with Undo as usual. Strings that are cut off, damaged, from another export format, over 8 MB, or already imported are refused and nothing is saved. Imports are limited to 20 backups and 32 MB in total. Nothing is sent to anyone.

## 3.0.7
- **Journey Chronicle** fixes: notes in languages with accented or non-Latin letters are no longer cut in the middle of a letter, and the "n / 240" counter counts letters. When the Chronicle is full, zone arrivals are removed first so level-ups, bosses and professions last longest, and extra "Tracking resumed" lines can be cleared too. Saved entries over the limit or with overlong text are trimmed on load. If the game hasn't listed your professions yet at login, TwichUI looks again before deciding you have none, so existing professions aren't written as newly learned.
- **Journey Chronicle**: the header now shows your total played time ("Journey time: 3d 7h 24m", a dash until the game answers; asked for only when you open the Chronicle and after a level-up). New optional **Professions** entries: "Learned Alchemy" when you learn a profession, and "Alchemy reached 150" when a skill first reaches 75, 150, 225, 300, 375 or 450, each once, with the profession's icon. Professions and skill you already have when tracking begins are not added. New option **Play Chronicle opening sound** (on by default): a soft page turn when the Chronicle opens, following your game sound settings. The frame is a little warmer and lighter: a lighter umber background, a more distinct entries panel and warm edge highlights.
- **Journey Chronicle** date filter: a small "All time" control above the list opens a compact calendar. Pick a day to see **That day** or **Since this day** (local calendar days), or use Today, Last 7 days and Last 30 days; days with entries carry a small marker, and **Clear filter** returns to All time. While filtered, the header says "X of N entries". Filtering only changes what is shown, never what is stored, and it resets each time the Chronicle opens. Entries whose saved time can't be read as a date show as "Date unknown" and appear only under All time.
- **Journey Chronicle** additions (all quiet, automatic and switchable): level entries now say how long you spent at the level you just finished and your total played time ("Level 12 to 13: 2h 34m · Total journey: 1d 5h 14m"; the time at the level only appears when TwichUI saw the whole level, never guessed). New optional entries: **Gold earned** milestones (10, 50, 100, 500, 1,000, 5,000 and 10,000 gold, counted from when tracking begins; spending doesn't lower it) and **Learning to ride**. Travelling by flight path no longer records every zone you fly over; only where you land.
- **Journey Chronicle** is now on by default for new installs (automatic entries; your own notes always work, and you can turn it off in the options). New option **Show Chronicle entries in chat** (on by default): when an entry is added automatically, a quiet line with its icon appears in your own chat window. It's never sent to anyone, and entries are still recorded when it's off.
- **Journey Chronicle** data bar source: a LibDataBroker object named "TwichUI Chronicle" shows "Journey Chronicle" with its icon, a tooltip (character, count, latest entry) and opens the Chronicle on click. In EllesmereUI add a Broker Plugin block to a data bar and pick "TwichUI Chronicle". Needs a broker display; nothing changes without one.
- **Journey Chronicle** icons: each entry shows a small icon for what happened (level, new zone, defeated encounter, fall, your own note). New optional entry, **Falling in battle** (off by default): records when your character dies and where.
- **Journey Chronicle** look: warm umber and bronze frame with a title band, quieter byline and status line (details in a tooltip), ledger-style entries with a small marker for automatic entries versus your own notes, a bronze "Write a note" button, a quieter Options button, and Edit / Delete that appear when you point at an entry.
- **Journey Chronicle** (new, optional): a quiet, private journal for each character. Open it with
  `/tui chronicle` or Options > AddOns > TwichUI > Journey Chronicle. Write short notes of your own
  (with the zone you're in, if you like) and edit or delete them any time. Automatic entries are off by
  default; turn them on to keep level milestones, new zones and defeated encounters, each switchable on its
  own. Nothing from before you turn it on is added, and nothing is announced in chat. Entries stay on that
  character (up to 500; the oldest automatic ones go first, your notes are never removed for you) and are
  never part of configuration sharing, setups or backups. Times show in 12-hour format by default;
  switch to 24-hour in the same options section.
- **Gear comparison**: the bag upgrade mark now also shows in EllesmereUI Bags (bags, reagent bag and bank), using its item overlay API.
- **Version and group check** is on by default for new installs (hidden addon messages; players
  without TwichUI see nothing). Anyone who already has the option saved keeps their choice.
- **Commands**: `/tui` is a short form of `/twichui`. `/tui` alone (or `/tui help`) now lists
  the commands instead of opening options; use `/tui options`. Unknown commands say so and point to
  `/tui help`. New `/tui share` (was `/pack`) and `/tui skin` (was `/aeskin`). The old `/pack` and `/aeskin` commands are removed.
- **Temporary**: `/tui commtest party|guild|whisper <name>` checks whether addon messages are
  delivered, by asking another TwichUI user to answer a tiny probe. Remove with setup/CommTest.lua.
- **Sharing window**: now three pages: **Share setup**, **Received setups** and **Backups**
  (Restore points are now called Backups). Share setup shows a short summary of what's
  included with Choose addons (searchable) and Scan installed addons; recommendations
  ("Recommend addons to friends") and the party compatibility check open from there. Received
  setups start with a summary and a Review step before anything can be applied, and
  "Use on this alt" is now "Use profiles already applied on another character". Saved data,
  the setup format and every option are unchanged.
- **Options**: TwichUI's settings now all live in Esc > Options > AddOns > TwichUI, grouped
  by feature (General, Gear comparison, Addon skins, Chat, Configuration sharing). Rarely
  changed options show when you tick "Show advanced options"; they keep working while hidden.
- **gear**: the separate upgrade hints window is gone. Talent tree, possible upgrades, higher
  levels, strictness, reveal key and bag mark style are ordinary options; stat weights and
  stat priority moved to a "Stat weights" page under TwichUI (`/twichui gear` opens it).
  Your existing choices carry over unchanged.
- **Addon skins**: each skin says whether its addon is installed, and its tooltip shows
  whether the skin is active, waiting for EllesmereUI or needs a reload.
- **Configuration sharing**: before applying, each addon shows whether your settings will be
  replaced or added, and a summary (repeated in the confirmation) says exactly what changes.

## 3.0.5
- Updated toc to reference only Forever build and match version of addon appropriately.

## 3.0.4
- **gear**: now supports either stat weights or stat priority gear analysis methods.
- **gear**: options panel is not fully skinned.
- **Auctionator skin**: fixed an issue that caused Auctionator's tabs on the Auction House interface to overlap.

## 3.0.3
- New **upgrade hints**: when something you could wear looks better for your class and main
  talent tree, its tooltip gets a quiet "Likely upgrade" line. Hold Shift to see why. Gear
  held back only by your level is compared too ("Likely upgrade at level 32").
  Toggles: "Upgrade hints in item tooltips" and "Mark upgrades in my bags" (off by default)
  in `/twichui`. `/twichui gear` picks the talent tree, values stats by a ranked stat
  priority (as guides list them) or by editable stat weights, and sets how hints behave
  (glance, strictness, reveal key, bag icon style).
- New **Attune skin**: the Attune window (`/attune`) and its quest panels get the EllesmereUI look.
  Toggle: "Skin Attune" in `/twichui`.
- New **Dungeon Journal skin**: the Forever Dungeon Journal window (`/fj`) gets the EllesmereUI look.
  Toggle: "Skin Dungeon Journal" in `/twichui`.
- New **WhatsTraining skin**: the floating window (`/wt`) gets the EllesmereUI look.
  Toggle: "Skin WhatsTraining" in `/twichui`.

## 3.0.1
- Version and group check is now **off by default** (opt-in). Turn it on in
  `/twichui` or with the button on the Group tab; everyone who wants to show up
  in a group check needs it on. The automatic switch back to direct messages
  also needs it, since it tests over the same channel.

## 3.0.0
- **Group check**: `/twichui check` or the Group tab shows everyone in your
  group, their TwichUI version, and which of your recommended addons they're missing.
- **Version check**: when you're grouped, TwichUI tells you if someone has a newer
  version, or one too old to share configurations with. Group channel only, a few bytes.
- **Direct messages come back automatically**: once per game build TwichUI tests
  whether Forever delivers addon whispers again, and switches sharing back to them.
- **Restore points**: save your own addon settings and go back to them later.
- New "Version and group check" option; the window gained Group and Restore points tabs.
- Release packaging for CurseForge/Wago, offline test suite, licenses.

## 2.6.x
- Sending options: group and guild channels are opt-in, with an explanation of why
  Forever needs them. Auctionator skin covers item icons, bag headers, refresh
  button, scroll bar frames and gold labels.

## 2.5.x
- Sharing works on Forever (group/guild routing, first-and-last names). Large
  configurations pack over several frames. Fixed a division-by-zero error in the
  serializer that stopped every send in game.

## 2.0 - 2.4
- Combined media, Auctionator skin and configuration sharing into one addon.
  In-game sending, addon list with download links, quiet login, saved data manager.
