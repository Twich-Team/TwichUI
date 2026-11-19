"""Presentation regressions only; applied to disposable copies by mutate.py."""
SUITE = {"targets": ("!!!TwichUI/auction/Host.lua", "TwichUI_Workshop/auction/Window.lua")}
TEST = "test_workshop_auction_fallback.lua"
HOST = "!!!TwichUI/auction/Host.lua"
WINDOW = "TwichUI_Workshop/auction/Window.lua"
MUTATIONS = [
    dict(id="auction.visibility.ignore-viewport", file=HOST,
         find="s.usable = b.left >= v.left-1", replace="s.usable = true or b.left >= v.left-1",
         why="shown windows outside the viewport qualify for native takeover", tests=(TEST,)),
    dict(id="auction.render.ignore-receipts", file=WINDOW,
         find="or not s.initialized or not s.rendered", replace="",
         why="a swallowed OnShow failure qualifies without a completed page render", tests=(TEST,)),
    dict(id="auction.restore.foreign-offscreen-success", file=HOST,
         find="if ok and not usable and not ended then", replace="if false then",
         why="an ownership mismatch releases recovery while foreign anchors remain offscreen", tests=(TEST,)),
    dict(id="auction.restore.discard-failed-lease", file=HOST,
         find='reason = l.foreign and "restore-blocked-owner" or "restore-failed"',
         replace='lease = nil; reason = l.foreign and "restore-blocked-owner" or "restore-failed"',
         why="a failed restoration loses the snapshot required for retry", tests=(TEST,)),
    dict(id="auction.render.lose-fallback", file=WINDOW,
         find='if context == "auctioneer" and R.AuctionHost then R.AuctionHost.ReplacementFailed(hostVisit, where) end',
         replace='-- render failure no longer restores the native window',
         why="later render exceptions leave the native window parked", tests=(TEST,)),
    dict(id="auction.restore.lose-close-receipt", file=HOST,
         find='    if lease then lease.ended=true end', replace='    -- close receipt lost',
         why="hidden native close faults while interaction readback still says active", tests=("test_auction_host.lua",)),
    dict(id="auction.restore.proof-implies-closed", file=HOST,
         find='local ended = l.ended==true or (not usable and not Available())',
         replace='local ended = not visiting or (not usable and not Available())',
         why="proof mode without a normal visit discards a failed restoration lease", tests=("test_auction_host.lua",)),
]
