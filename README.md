## Notice

Preperation is underway for the initial launch of WoW: Forever. This addon is under heavy development and the features and stability it provides will fluctuate until the launch of the game.

## Addon

Its purpose is to refine the experience, not replace it. Small, thoughtful touches should help players read the game and make their own decisions while preserving the atmosphere, discovery, and sense of place that make Forever compelling.

This addon is intended to work alongside EllesmereUI.

## Features

**Welcome:** A new installation opens one short "Welcome to TwichUI" page the first time you log in, once for the whole account, and never for an upgrade. It points to the settings, the notification previews and the troubleshooting report, and changes nothing. `/tui about` shows it again.

**Fonts and sounds:** Adds various thematic fonts to the game, allowing them to be utilized for interface customization.

  
**Quiet login:** Attempts to hide all addon welcome messages when logging in to prevent being brought out of immersion by being inundated with unnecessary information. 

**Upgrade hints:** When something you could wear looks better than what you have, its tooltip gets one quiet line such as "Likely upgrade for Fury". Hold Shift (your compare-items key) to see why: what it's compared with, the stat changes that mattered most and which weights were used. Items that aren't upgrades, or that you can't use, get nothing unless you ask.

**Sell from Bags:** A tab at the bottom of the Auction House that lists what in your bags can be listed. Pick an item and it searches that item's current listings (only that item, only when you pick it) and suggests a price that matches the lowest comparable listing, saying what that's based on: how many listings it found, and which it left out (your own, bid-only, or other versions of a piece of equipment). You choose the quantity, price and duration; nothing is posted until you press Post. Nothing is saved or sent.

**Addon skins:** Provides EllemereUI skinning to various addons to create a cohesive look and feel. Currently supprts: Attune, Auctionator, DungeonJournal, and WhatsTraining.

**Quality of life:** Four small conveniences, all off by default and each on its own page switch: accept summons (from friends, guild and group members, or whoever you choose, after a short wait), accept resurrection (keeping the game's own waiting time, and combat resurrections only if you ask), release in battlegrounds (battlegrounds only, never when a resurrection or self-resurrection is on offer, hold Shift to keep your body), and decline duel requests (except from the people you allow). Nothing is sent to chat. Where Leatrix Plus does the same, each tooltip says so.

**Food and Drink buttons:** Optional (off by default). Two small buttons that hold the food and drink in your bags that restore the most, and eat or drink it when you click them. TwichUI never uses anything itself, skips buff food and feasts, and changes the choice out of combat only. Optionally it prefers Mage-conjured food and water over ordinary ones, food and water chosen separately. Each button can be switched off, and their size, spacing, layout, border (texture, thickness, color or class color, opacity) icon zoom and opacity (with an option to fade them until the mouse is over them) are yours to set.

**Mage Travel:** For Mages, on by default, and shown through a data bar addon that lists LibDataBroker launchers (such as EllesmereUI's Broker Plugin block). It shows its icon with "Travel" or "Portals" (or just the icon), as you choose. A small menu of the teleports and portals your faction can learn on WoW: Forever. Click a learned one to cast it through the game's own secure button; ones you haven't learned stay readable, and their tooltip gives the level they are trained at. It can't be opened in combat and closes when combat starts.

**Mage Conjuring:** For Mages, on by default, beside Mage Travel on your data bar. A small menu with one entry each for Conjure Food and Conjure Water: the highest rank you have learned of each. Click one to cast it. If you haven't learned any rank of one, its first rank is shown muted with the level it is trained at. Shift-left-click the launcher to conjure water and shift-right-click to conjure food, each at your highest rank. Its data bar text is "Conjure", "Food & Water" or none, as you choose.

**Mage refreshments:** For Mages, off until you turn it on (Mage options page). A small panel (`/tui refreshments`, a key in Key Bindings > TwichUI, the Mage Conjuring menu, or its own data bar plugin, "TwichUI Mage Refreshments", showing how many of your group are supplied) that works out how much conjured water and food your party or raid needs: each class's share (single items, separate amounts for a party and a raid, set on the Refreshment shares page), at the best rank each person's level can use, plus what you keep, against what is in your bags. Its Water and Food buttons conjure the rank still needed, once per click or key press; drag one to an action bar to hold a key with the game's Press and Hold Casting instead (the game repeats a held cast only from its own bars, and TwichUI can't stop it at a target: the bar turns green and you let go). A checklist shows who you've supplied; you mark it yourself, and it starts again when you leave the group or reload. When you trade with someone in your group, a strip under the trade window offers **Fill trade**: on your click it puts their share of the planned rank into empty slots (a part stack takes a second click), never moves what is already there, and never accepts. A trade counts as handed over only when the game says it was completed; otherwise the panel asks you to confirm it. The panel's look (background and border texture, color, opacity and thickness, including EllesmereUI's own border textures) is yours to set on the Mage options page. TwichUI never casts, opens or accepts trades, or whispers for you, and nothing about your group is saved. **Experimental: needs checking in the game.**

**Broker menu appearance:** For Mages, the background and border of the Mage Travel and Mage Conjuring menus are yours to set on the Mage options page: texture (None, a flat color, the game's own, or any LibSharedMedia background or border), color, opacity, and border thickness, with a preview and a reset. Background and border opacity are separate, so text and icons never fade.

**New training:** After a level-up, a short title card in the zone card's style lists the class spells you could train and don't know yet, including any from earlier levels you haven't trained, showing only the highest rank of each. It never trains anything for you, shows nothing when there is nothing new, and fades by itself.

**Friend login:** When a Battle.net friend comes online, a small card in the zone card's style shows their name, a Horde or Alliance mark if the game says which faction they play, and the character they're on, in place of the game's own friend-online pop-up. Other pop-ups (going offline, broadcasts, requests) and the chat line are unchanged, the game's own Social options still apply, and it stays quiet at login and in combat. It plays a soft chime (you choose which game volume it follows) that can be switched off. Switch the card off to get the game's pop-up back. Nothing is sent.

**Zone arrival:** Arriving somewhere new shows the zone's name as a brief, quiet title card in place of the game's zone text: not at login, not while on a flight path, and only for the last place when crossing zones quickly. Walking into a dungeon or raid shows its name with "Dungeon" or "Raid" beneath it. Smaller places within a zone, dungeon and raid cards, and Reduced motion are optional.

**Journey Chronicle:** A private journal for each character (`/tui chronicle`). Write your own short notes, and let it keep a few moments for you: levels, new zones and defeated encounters, with deaths off until you choose them. Automatic entries are on by default for a new installation and each kind can be switched off; a quiet line in your own chat window (never sent to anyone) says when one is added, and that can be switched off too. Never shared or backed up with your configuration. At login, an optional small "Welcome Back" bookmark can remind you of the last place the Chronicle noted.

**Configuration sharing** Provides an ecosystem to share your addon configurations with friends.

  * Pick the addons whose settings you want to share and save them as your addon configuration.
  * Send it to a friend in game. They get a prompt, it downloads with a progress bar, and they choose what to apply. Their own settings are backed up first; Undo puts them back.
  * Later sends only include addons you changed.
  * Your recommended addon list travels with it, with a download link for each addon they're missing.
  * **EllesmereUI** is shared one profile at a time (**EllesmereUI profile** on the Share setup page), never as a whole saved-data table. Your friend reviews it and it is added as a **new profile** with an unused name; none of their profiles, spec assignments or global settings are replaced. EllesmereUI has no import that doesn't switch to the new profile, so the review says that it becomes the profile in use, and their previous one stays saved. The profile's look (fonts, custom colours, dark mode, accent) comes with it; UI scale, window skins, click-cast and per-character data are left out.

**Backups:** Save your own settings before you tinker, go back any time.

**Export & import configuration:** Your configuration backups can easily be exported to a string. The addon also allows imports of your own saved exports or your friends.

**Addon data:** A read-only look at what your addons keep between sessions (`/tui data`): which data belongs to which addon, about how big it is, and what's in it, opened a level at a time. Only addons loaded right now can be shown, since the game doesn't load data for addons that are off or removed and addons can't read files on disk. Sizes are estimates. Nothing can be changed or deleted there, except TwichUI's own data through its Saved data list.

**Troubleshooting:** If something does not work, `/tui diagnostics` opens a report you can read and copy: versions, which optional addons are present, and what each part of TwichUI says about itself. Optional temporary tracing (`/tui diagnostics start`) records TwichUI's own decisions for a few minutes, in memory only. It holds codes and counts, not names, chat or Chronicle entries, and nothing is ever sent anywhere unless you copy it out yourself.
