# F13 — Leave Me Alone communication quieting

Batch 12: **Investigated; runtime Deferred**. On 2026-11-23 Fishing
[PR #143](https://github.com/Twich-Team/TwichUI/pull/143) was OPEN, unmerged.
Its actual QuietScreen diff replaces the single state with player state plus
owner holds, adds `Player`, `Hold`, `Holding`, and changes listener semantics.
Per the owner's conflict rule, this batch edits neither QuietScreen nor Fishing.
Do not cherry-pick Fishing into this branch. Recheck status and rebase after merge.

## Source findings

Baseline main `eb866ce` has a temporary, unsaved `QuietScreen.On/Set/OnChange`.
`modules/ChatClean.lua` registers only `CHAT_MSG_CHANNEL`, through
`ChatFrameUtil.AddMessageEventFilter`; preserve that policy. Forever source
`bebcb6b` (`1.60.1 (70938)`) establishes:

- `Blizzard_ChatFrameBase/Shared/ChatFrameFilters.lua`: owned message filters can
  be added/removed; restricted values skip addon processing. Fail open.
- `Blizzard_ChatFrameBase/Mainline/ChatFrameOverrides.lua`: incoming WHISPER and
  BN_WHISPER use `SOUNDKIT.TELL_MESSAGE`; text filters do not establish control
  of every notification path or another addon's audio.
- `Blizzard_StaticPopup_Game/GameDialogDefs.lua`: PARTY_INVITE specifies
  `SOUNDKIT.IG_PLAYER_INVITE`. Hiding this popup invokes decline behavior; never
  hide it to silence sound. `Blizzard_StaticPopup/StaticPopup.lua` plays the
  dialog's sound independently of chat filters.

No verified, scoped, reversible sound-suppression ownership contract was found.
Do not replace PlaySound, change global volume/CVars, alter dialog definitions,
post-hook a sound that already played, or promise muting from a text filter.
Sound capabilities remain evidence-gated and must be disabled/unavailable with
an explanation until an eligible notification path is proven.

## Implementation-ready slice after Fishing merges

1. Add a feature-owned communication module after QuietScreen, using its public
   API. Gate communication hiding on the explicit player's switch (`Q.Player()`
   after merge), not Fishing holds: Fishing's quiet visuals must never silently
   hide whispers. Subscribe once to OnChange and re-read player state, because
   callbacks report effective quiet state. Turning the player switch off must
   remove filters even if Fishing still holds visual quiet.
2. Expose three independent options, all missing/false => OFF: Hide incoming
   whisper text; mute eligible incoming whisper notifications; mute eligible
   group-invitation notification sounds. Keep activation temporary and unsaved;
   preferences alone never activate Leave Me Alone. Feature-owned setters only,
   no changes to ChatClean or another addon's preferences.
3. Text implementation registers one owned filter per eligible WHISPER and
   BN_WHISPER event while the player switch and text option are on. It returns
   true only for those incoming types; leaves outgoing informs and unrelated chat
   untouched. No payload inspection/retention is needed. Unknown/restricted paths
   remain visible under the game's filter contract. Unregister only owned filters
   on off, option change, disable and teardown. No replies, network blocking,
   ignores, invitation actions, logs or catch-up replay.
4. Place controls with Leave Me Alone's existing entry, using existing settings
   components once the merged launcher/menu settles. Show: **Incoming whispers
   may be hidden while Leave Me Alone is active. Hidden text may not be available
   in chat history.** Do not claim secure storage or recovery. For unavailable
   audio capabilities show why; do not persist a false success indication.
5. Add count-only diagnostics for owned filter count/active status if needed;
   no sender, message text or message identifiers. No continuous work required.

## Acceptance tests for that implementation

Unit fixtures: defaults off; active and inactive transitions; repeated toggles
have at most two filters; changing each preference immediately updates ownership;
third-party filters survive cleanup; outgoing/public/group chat passes; restricted
messages fail open; disable/reload restores normal behavior. Model Fishing hold
on + player off, then player on/off while hold persists. Sound tests must prove
scoped ownership and restoration, or assert capability unavailable.

Owner with cooperating member: check incoming character and Battle.net whispers,
visible history and eligible sounds, outgoing messages, unrelated public/group
chat, invite sounds and invitation accept/decline controls. Turn mode off while
Fishing remains active, then turn all options off. Real-client tests are unchecked;
this document is source investigation, not runtime implementation or native proof.
