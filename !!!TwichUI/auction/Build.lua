-- The integrated buy/post paths are enabled for owner-requested in-game
-- iteration. This is not real-client verification; keep that evidence separate.
-- Auctioneer/experimental consent and per-click checks still apply centrally.
TwichUI.AuctionBuild = {
    verified = {},
    integrated = {buyItem=true,buyCommodity=true,postItem=true,postCommodity=true},
}
