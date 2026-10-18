# Chat cleaning

For anyone changing the feature. Code: `modules/ChatCleanMatch.lua` (reading a message, checking and compiling rules,
the built-in filters; pure functions), `modules/ChatClean.lua` (settings, the filter, channels, repeat memory, the
live-view hook, the tester), `diag/ChatClean.lua` (counts for `/tui diagnostics`), the settings in
`TwichUI_Settings/pages/ChatClean.lua` (General), `ChatCleanChannels.lua`, `ChatCleanRules.lua` and
`ChatCleanLive.lua` (tabs), `modules.chatClean` in `Core.lua` and `Switches.lua`, the two sharing groups in
`setup/TwichConfig.lua`. Tests: `tests/test_chat_clean.lua`. **Nothing here has been tried in the game.**

Behavioral references: BadBoy, BadBoy_CCleaner and BadBoy_Guilded (`../reference_addons/`, "All Rights Reserved").
Only their behavior was studied (decide once per line ID, look only at system channels, never hide friends, guild or
group, a short repeat buffer, a plain keyword list, recruitment as its own opt-in). No code, keyword list or data was
copied, and TwichUI neither requires nor calls them. Their reporting, ignoring, chat-bubble and frame re-registration
tricks are deliberately not reproduced.

## What it does

Hides messages in the public channels the player chooses (typically General and Trade) that match a built-in filter
or a custom rule. Off by default (`modules.chatClean`, only an explicit `true` is on). Turning it on from the settings
asks first and lists the channels and filters that will apply; the recommended choice (General and Trade, with the
spam and repeat filters) is shown on the page for review before that, and nothing is hidden after an upgrade.

Never looked at: whispers (Battle.net included), party, raid, instance, guild, officer, say, yell, emotes, system
messages, combat text, and any channel not chosen. Only `CHAT_MSG_CHANNEL` is filtered. Never hidden: messages from the
player, friends (`C_FriendList.IsFriend`), Battle.net friends (`C_BattleNet.GetGameAccountInfoByGUID`), the group
(`C_PartyInfo.IsGUIDInGroup`), the guild (`C_GuildInfo.MemberExistsByName`), and GM/DEV-flagged senders. Nothing is
reported, ignored, blocked or sent.

## Client behavior, and where it comes from

Verified in `../wow-ui-source` (`forever` branch, 1.60.1):

- `ChatFrameUtil.AddMessageEventFilter(event, fn)` / `RemoveMessageEventFilter` (`Blizzard_ChatFrameBase/Shared/ChatFrameFilters.lua`).
  `ChatFrame_AddMessageEventFilter` is only a deprecation alias (`Blizzard_DeprecatedChatInfo`), used as a fallback.
- `ChatFrameMixin:MessageEventHandler` (`Mainline/ChatFrameOverrides.lua`) runs the filters for every `CHAT_MSG_*`
  event, per chat frame, **before** its channel-membership check and before drawing. A filter returning `true`
  discards the message for that frame; `false` with no second value passes it unchanged and the next filter runs; a
  second value would replace the arguments (never done here).
- Each filter is wrapped: it is skipped when `canaccessvalue(...)` fails (secret values in chat messaging lockdown),
  and called through `securecallfunction`, so an error lets the message through.
- `CHAT_MSG_CHANNEL` payload (`ChatInfoDocumentation.lua`): text, sender, ..., `specialFlags` (6), `zoneChannelID` (7),
  `channelIndex` (8), `channelBaseName` (9), `lineID` (11), `guid` (12). Text, sender and GUID may be secret in chat
  messaging lockdown; the channel fields and the line ID are never secret.
- `C_ChatInfo.GetGeneralChannelID()`, `GetChannelShortcutForChannelID(id)`, `GetChannelInfoFromIdentifier(localID)`
  (`{ name, shortcut, localID, instanceID, zoneChannelID, channelType }`). There is **no** call for Trade's ID.
- Events for the Channels tab: `CHANNEL_UI_UPDATE`, `CHANNEL_LEFT`, `CHAT_MSG_CHANNEL_NOTICE`, `ZONE_CHANGED_NEW_AREA`.

EllesmereUI's chat (read-only: the 9.3.5 reference copy and the installed 9.6) keeps the game's chat frames fully
registered as its "secure formatting/data plane" and draws its own windows from a `hooksecurefunc(cf, "AddMessage")`
bridge (`EllesmereUIChat_Engine.lua`); its session history captures from the same bridge. A message discarded by a
filter never reaches `AddMessage`, so it is absent from EllesmereUI's windows and history too. No EllesmereUI-specific
code exists here, and its absence, presence or late start changes nothing. Its own URL filter (`UrlFilter`) may run
before TwichUI's and wrap web addresses in link markup; matching reads the visible text, so that is harmless.

Not verified anywhere: Trade's zone channel ID on Forever (2 is used only to preselect it for review), the exact
`shortcut` names Forever gives, and that channel IDs never change between client builds.

## Channels

| Key | Meaning |
|---|---|
| `zone:<zoneChannelID>` | a system channel (General, Trade, LocalDefense, LookingForGroup...). The same in every zone and city, whatever its number in the player's list, in any language. |
| `custom:<lowercased name>` | a custom channel (`zoneChannelID` 0): it has nothing else, so it is matched by name, ignoring case. A custom channel named "Trade" is not the Trade channel. |

The Channels tab lists the channels the player is in (from `GetChannelInfoFromIdentifier(1..20)`) and the ones chosen
before; a channel left keeps its choice. The filter itself tracks nothing: each message carries its own key.

## Saved data

Per profile, `TwichUIDB.ui.chatClean` (only through `ChatClean.lua`'s functions):

| Key | Meaning |
|---|---|
| `channels` | `{ [key] = { on, spam, repeats, recruit, label } }`, at most 32. Missing: the recommended choice is in use and not saved; the first change saves it with the change. `label` is only for showing a channel the player isn't in. |
| `rules` | `{ { id, name, mode, text, case, enabled, all, channels = { [key] = true } }, ... }`, at most 50, in the order they are checked. `all`: every channel being cleaned. |
| `nextId` | the next rule's id |

Reading never writes; an entry that can't be read is skipped and left as it is. Nothing about messages is saved:
no captured chat, no senders, no counts, no repeat memory.

## What a message is checked against

The filter runs once per chat frame; the decision is made the first time a `lineID` is seen and repeated for the other
frames, so each message is evaluated, counted and listed once. Then, in this order (the first match is the reason):

1. The channel's enabled custom rules, in list order (the Custom rules tab can move them).
2. **Gold selling spam** (recommended): a web address (plain, or spelled out: `www . x . c o m`, `x dot com`, any of a
   short list of top-level domains), something sold (gold, boost, power-levelling, levelling, carry, account) **and** a
   price or discount ($, €, £, `10%`, USD/EUR, cheap, price, discount, coupon, promo, sale, delivery), all three.
   A community or guild invitation link (`|HclubFinder:` / `|HclubTicket:`, which opens the Guild & Communities window
   with Accept and Decline) needs only two: something sold plus a web address or a price. The name shown on such a
   link is free text, so gold sellers use it as the advert. The link type alone never hides anything, so ordinary
   guild-finder links are untouched (Guild recruitment, below, is the filter for those).
3. **Guild recruitment** (opt-in): the word "recruit", or "guild" with join/invite/whisper/apply/members/looking for.
4. **Repeated messages** (recommended): the same text, ignoring case, spaces and punctuation, from the same player
   (GUID, else name) within 60 seconds of their previous copy. The first copy is shown; repeats stay hidden while they
   keep coming. Memory: at most 200 entries of a player ID and a 31-bit hash of the text (never the text), swept by a
   one-shot timer that runs only while there are entries, and forgotten when cleaning is turned off or the profile
   changes.

Exemptions are checked only after a match, so allowed messages cost nothing extra. Allowed messages are never
copied or changed; the filter returns only `true` or `false`.

Limits (said in the settings): the spam filter misses disguised spam (look-alike letters are not translated, unlike
BadBoy) and can catch an unusual ordinary message that has all three signs; recruitment also catches "looking for a
guild" and some other guild talk; repeats hide a genuine player's repeated LFG post within the window.

## Reading a message

Rules and filters read the **visible** text (`ChatCleanMatch.Visible`): `|c...`/`|cn...:`/`|r` colors, `|T`/`|A`
textures, `|K` protected names and stray `|` codes are removed, a link `|H<data>|h[text]|h` becomes `[text]`, `|n`
becomes a space, and `||` becomes `|`. A rule never matches a link's hidden data. At most 512 bytes are read (chat
lines are at most 255). Case-insensitive matching lowers A–Z only (`string.lower`); other letters compare as typed.

## Custom rule syntax

| Mode | Meaning | Examples |
|---|---|---|
| Contains text (default) | the text anywhere; every character literal; spaces around it trimmed | `cheap gold`, `50%`, `[gold]`, `a.b` |
| Wildcard | `*` any run of characters (or none), `?` one character (a whole UTF-8 character); everything else literal; matches anywhere | `wts*boost` hides "WTS mythic boost"; `l?g` matches "lfg" and "lag" |
| Lua pattern (expert) | a Lua 5.1 pattern, **not** a regular expression, matched as written (case included) | `%d+%s*g%f[%A]` finds "500 g"; `^WTS` |

Limits: 100 characters of text (names 40); no control characters; valid UTF-8. Wildcards compile into literal pieces
found earliest-first with plain `find` (exact for `*`/`?`, never backtracks). A Lua pattern is checked for shape before
it is accepted (closed sets and captures, no trailing `%`, `%b` with two characters, `%f` with a set) and refused when
it has more than 2 unbounded repetitions (`*`, `+`, `-`, `%b`), a back-reference (`%1`) or more than 80 bytes; it runs
under `pcall` per rule (an error skips that rule for that message and is counted). Measured with plain Lua 5.1 outside
the game (not in the game): a deliberately worst-case allowed pattern (`a.-a.-b` on 255 "a"s) took about 8 ms per
message; the worst wildcard (`a*a*a*a*a*a*b`) and the built-in filters took well under 0.1 ms. `pcall` catches
malformed patterns; it does not bound cost, which is why the shape limits exist.

Warnings (asked before saving, never silent): a rule that matches every message (`*`, `?*`, or a pattern matching a
set of probe texts including the empty one) and text of two characters or fewer. Empty rules are refused. No rule text
is ever run as Lua.

## Live view and tester

Live view (`ChatCleanLive.lua`): `ChatClean.SetCapture(fn)` is set in the tab frame's `OnShow` (unless paused) and
cleared in its `OnHide`, which the window fires for another tab, another page, a search or closing. Hiding also forgets
everything listed and empties the rows. Pause clears the capture (filtering goes on); Clear forgets the list. At most
100 entries, plain text made as each arrives (`ChatCleanMatch.Plain`: visible text with `|` doubled, so nothing in the
list is a link, color or texture), at most 100 reused rows, newest first. Nothing is saved, shared, put in a report, or
replayed into chat. A capture callback that errors is dropped and noted.

Tester: `ChatClean.Test(text, key)` runs the same compiled checks for one channel, for a stranger, without touching the
repeat memory or sending anything. It says when chat cleaning is off or the channel isn't cleaned.

## Sharing and profiles

Per profile, like every `ui` group (`Profiles.lua` swaps it; `ChatClean.lua` recompiles on `OnApply("views")` and
forgets its repeat memory). Two sharing groups: **Chat cleaning** (the switch, shared; the review says plainly when an
import turns it on or off) and **Chat cleaning channels and rules** (custom group: validated, merged, reviewable,
undoable; see `docs/twichui-sharing.md`). Nothing about messages travels.

## Diagnostics

`/tui diagnostics` › Chat cleaning: on/off, whether the filter is registered, whether the channel choice was changed,
channels with something to check, rule counts, messages checked and hidden this session, errors, repeat memory size,
whether the live view is capturing. Never names, rule text, senders or messages. An unexpected error lets the message
through and is recorded with `R.Diag.Error` (coalesced); nothing is printed to chat and the game's error handler is not
called for it.

## In-game checklist (safe: local tests and ordinary incoming traffic only)

Never post test spam to a public channel. Turn on Display Lua Errors. Test TwichUI alone, then with EllesmereUI chat.

1. **Upgrade.** Log in with an existing save: nothing is hidden; Chat cleaning shows "Off" and the recommended choice.
2. **Opt-in.** Turn on "Clean public channels": the question names General and Trade (in the client's names) and what is
   never touched; Cancel leaves it off; Accept turns it on.
3. **Channels.** In a city, the Channels tab lists General, Trade and LocalDefense with their numbers. Swap channel
   numbers in the game's chat settings (or leave and rejoin Trade): the choice holds. Change zone: General stays chosen.
   Join a custom channel: it appears, "recognised by name". Confirm Trade's row is the real Trade channel (ID 2 is
   assumed; report if it isn't).
4. **Tester.** On Live view, try "cheap gold www.example.com 10% off" in Trade: would be hidden by Gold selling spam. Try
   "WTS [any item] 5g": would be shown. Try in a channel not cleaned: says so. Nothing appears in chat.
5. **Live view.** Leave Live view open in a busy city for a few minutes: hidden spam (if any) appears once per message,
   with time, channel, sender and reason, also when several chat tabs show Trade. Links appear as plain text and can't
   be clicked. Pause: the list stops, chat stays clean. Switch tab and back: the list is empty.
6. **Custom rule.** Add Contains "lfg" for Trade only; watch Trade LFG messages disappear from chat and appear in Live
   view; General's stay. Turn the rule off: they show again (earlier ones don't come back). Remove it.
7. **Warnings.** Add a Wildcard "*": asked before saving; cancel. Add a Lua pattern "[abc": refused with the reason.
8. **Never hidden.** A friend, guildmate or group member posting a matching message in Trade (ask them for an ordinary
   message your temporary rule matches): shown. Your own message: shown. Whispers, party, guild: never affected.
9. **EllesmereUI.** With EllesmereUI chat: hidden messages are absent from its windows and from its session scrollback
   after a reload; everything else unchanged. Without it: the same in the game's chat.
10. **Off.** Turn it off: everything shows; `/tui diagnostics` › Chat cleaning says the filter is not registered.
11. **Profiles and sharing.** Another profile has its own channels and rules. Send a TwichUI share to yourself
    (`/tui share test`) with chat cleaning included: the review names the channels and rules and whether it turns
    cleaning on; Undo puts them back.
12. **Combat and instances.** In a dungeon or during an encounter (chat messaging lockdown), nothing errors; messages in
    lockdown are not filtered (the game skips addon filters for secret values).
