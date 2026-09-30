# TwichUI changelog

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
