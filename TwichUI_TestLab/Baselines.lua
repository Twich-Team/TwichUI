-- TwichUI Test Lab: recorded benchmark baselines (TL.Baselines). DATA ONLY.
-- The first real-client baseline is pasted here by hand (docs/testlab.md, "Collecting the first Forever baseline"): the "B1 ..." lines of a
-- Performance run's report, nothing else. They are read as plain text by Bench.DecodeAll (validated field by field; nothing is executed),
-- and a later run is compared with them by BN.Compare, which calls two runs incomparable when the fixture, the workload version, the
-- client build, the host or the clock differ. Empty until a run in the game has been recorded; offline figures never belong here.
local R = TwichUI
local TL = R.TestLab

TL.BaselineText = [[
]]

TL.Baselines = TL.Bench and TL.Bench.DecodeAll(TL.BaselineText) or {}
