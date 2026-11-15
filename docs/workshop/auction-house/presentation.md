# AH-1b through AH-3: standalone presentation

The separately authorized presentation campaign builds an independent preview
while AH-1a real-client acceptance remains pending. This is an exception to the
older roadmap's page-construction dependency, **not** acceptance of takeover.
The existing Host proof, native Auction House and manual scan policy are intact.

Open with `/tui ahpreview`, without an auctioneer. It loads existing Workshop
services through the launcher without opening Workshop's window or Settings.
Nothing opens automatically. The five left destinations build lazily. Sell,
My Auctions and Market remain clearly labeled placeholders. The header's
Blizzard switch closes only the preview and explains that replacement is off.
Close/Escape and viewport changes operate solely on the independent root.
No presentation state is persisted.

## Checkpoint 1

Shared leather/bronze shell, header branding, five left navigation destinations,
close and safe Blizzard switch. Reuses CraftLook, FrameLook, Workshop controls,
existing painted artwork and the screen-fitting helper. No new design system.

Unit tests cover lazy construction, navigation, repeated open/close with bounded
frames, listener cleanup, combat refusal, native-mutation and auction-call
sentinels. Simulator catalog includes normal, replay, narrow, scaled and an
intentional wrong-expectation control; each uses synthetic native boundaries.
Screenshots establish structural appearance only; real fonts, pointer input,
combat/taint, scale and Blizzard compatibility require the real client.

The campaign stops after AH-3. No AH-4/5/6/7, transaction or takeover activation.

Checkpoint-1 verified in native WSL: `fast auction-house` 5 files pass;
`feature auction-house` 50 files, five preview launches and four AH-1a
proof launches pass (104.677 s, exit 0). Normal and narrow screenshots reviewed
after fixing exclusive page visibility on reopen; scaled capture also produced.
No real-client acceptance is claimed. Ignored evidence: the feature runner's
report and `test-output/simlab/artifacts/auctionpreview-Oy991zuU/`.
