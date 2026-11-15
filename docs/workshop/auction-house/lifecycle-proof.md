# AH-1a: lifecycle and fallback proof

Date: 2026-11-14. Scope: diagnostic lifecycle infrastructure only. No replacement
window, pages, transactions or scan policy changes. **Real-client acceptance is
pending; AH-1b is blocked.** The proof must stay disabled by default.

## Source review and decision

Reviewed on clean `feature/workshop` at `b89f84b9`. Forever source is read-only
`../wow-ui-source`, branch `forever`, revision
`4cd0ab752a77164f654ccbca9d0c1fe8dafceebe`, version `1.60.1.70888`.
Locators below are relative to its `Interface/AddOns/` directory. These are
**source-confirmed contracts**, not real-client evidence.

| Concern | Evidence and consequence |
|---|---|
| Opening/load order | `Blizzard_AuctionHouseUI/Shared/Blizzard_AuctionHouseUI_Bootstrap.lua`: registers Auctioneer with the interaction manager; loads the addon then calls `ShowUIPanel`. The TOC is load-on-demand. Leave this path and its trial restriction intact. Activation must inspect an already loaded, visible root; never manufacture a session or load the native UI itself. |
| Availability | Generated `PlayerInteractionManagerDocumentation.lua`: SHOW/HIDE carry interaction type and are synchronous; `IsInteractingWithNpcOfType` and `IsValidNPCInteraction` return booleans. Generated `AuctionHouseDocumentation.lua`: SHOW/CLOSED/DISABLED events have no payload. Relative ordering between event families and actual server usability remain unverified. Require both interaction checks; visibility alone is insufficient. |
| Show effects | `Blizzard_AuctionHouseFrame.lua`, `OnLoad`, `OnEvent`, `OnShow`: initializes tabs, queries bids at addon load, may query favorites on show, selects Buy, opens bags, registers events and plays sound. Moving a shown root must not invoke Show again. Native queries are distinct from proof-issued queries. |
| Hide effects | Same file, `OnHide`: unregisters events, clears posting, resets Browse, calls `C_AuctionHouse.CloseAuctionHouse`, hides popups/progress and closes bags. Hiding the root or a parent is unsuitable for presentation switching. A post-hook cannot prevent that close. |
| Structure/input | `Blizzard_AuctionHouseFrame.xml`: root under UIParent, initially hidden, mouse enabled, portrait template; search, sell/buy views and tabs descend from it. Ancestor hiding affects effective visibility. Moving it does not disable child keyboard focus, handlers, timers, narration or detached popups. |
| Panel positioning | `Blizzard_UIParentPanelManager/Shared/UIParentPanelManager.lua`, `FramePositionDelegate:UpdateUIPanelPositions`, `ShowUIPanel`, `HideUIPanel`: secure delegation and repeated ClearAllPoints/SetPoint; local getter lazily initializes layout attributes. The proof should change anchors only, avoid all panel attributes, and yield when layout changes rather than continuously repark. |
| Combat/protection | Same panel functions check protected-function permission. Frame APIs mark many mutations protected. Lack of a secure template on the AH root proves nothing about descendants, hooks or future taint. Refuse takeover in combat; retain a failed/deferred restoration for retry outside combat. Never queue takeover. |
| Existing TwichUI hooks | `auction/Window.lua`: independent Sell from Bags holder, native display/overlay hooks and explicit posting state; `auction/Scan.lua`: explicit searches. Refuse proof while the custom page or any known scanner is active. Do not cancel or hide a posting operation as part of activation. |
| Workshop | `WorkshopLauncher.lua`: lazy guarded service load, optional delayed login load, no window opened by Load. Workshop `Window.lua` only subscribes while shown; `AuctionButton.lua` can attach to native AH after service load; `Scan.lua` checks native visibility; `WorkshopAuto.POLICY` is manual. Host should neither load Workshop nor duplicate its observation/scan listeners. Test loaded and unloaded cases. |
| Other AH owners | Read-only TSM `LibTSMWoW/Source/Service/Move.lua`: Forever lock checks, pending restoration, offscreen anchors, panel attributes and position hooks. This corroborates the idea, not compatibility. Refuse known loaded AH owners; unknown hooks/layout changes remain possible. No code copied. |

**Decision:** test anchor-only parking of the already shown native root with an
independent diagnostic Restore button. Compared with Hide/hidden-parent/alpha-0,
this avoids known interaction closure or invisible onscreen click regions.
Compared with registry replacement or TSM-style panel mutations it leases less
state and does not claim another owner's registry. It is only a candidate:
the native UI still occupies a panel slot and can be hidden or repositioned by
Blizzard. If the test cannot keep interaction and input usable, reject the
mechanism; do not suppress OnHide, replace globals, or force a position fight.

## Risks and acceptance boundary

- Offscreen descendants may retain focus or bindings; independently positioned
  popups/tooltips and narration/gamepad navigation may escape root geometry.
  Refuse an AH-focused edit box, observe real input and accessibility behavior.
- Different scales, resolution changes, clamping, skin offsets and external
  anchors can defeat parking. Preserve scale and all original anchors, refuse
  clamped roots, check root geometry and monitor only while the proof owns it.
- Secure hooks do not establish taint safety. Real combat, blocked actions,
  Escape, bag behavior and later reopen require client acceptance.
- Out-of-combat restoration can be immediate; no promise of immediate protected
  frame restoration in combat or after arbitrary engine/addon corruption is
  possible. A retained restoration and recovery instructions are essential.
  Deferred restoration is a **release blocker**, not acceptance of the AH-0
  switch-at-any-time contract.
- Restore only owned anchors. Preserve another owner's later anchors; do not
  clobber external scale, parent, input, panel attributes or scripts. No automatic
  reactivation after a close, error, combat, login or reload.

Implementation, verification evidence and exact real-client steps follow in the
implementation checkpoint. No simulator or real-client result is claimed by this
source-review checkpoint.
