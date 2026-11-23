-- TwichUI Diagnostics: what the operations are, and the gauges read while recording
-- The operation catalog names the scopes TwichUI's code opens (R.Perf ids): which module, in plain words, and what
-- kind of work, so the window and the findings can say "a rebuild" or "a layout". A module may add its own with
-- R.Perf.Describe; those win.
--
-- Gauges are numbers read at an interval (and when a window cycle ends): listener counts, pools, caches, what is
-- shown. They come from what TwichUI's modules already report about themselves (their Snapshot functions and a few
-- read-only counts); reading one never builds, loads or changes anything. Each is registered with R.Perf.Gauge, the
-- same way a module adds its own:
--   R.Perf.Gauge("npcs.map.pool", { label = "...", unit = "count", kind = "pool", group = "map", read = function() ... end })
-- kind: "listeners" (callbacks registered somewhere), "pool" (frames made and kept for reuse), "cache" (derived data
-- kept), "state" (0 or 1: something shown or running), "work" (a module's own running count of something it did).

local R = TwichUI
local DX = R.DiagnosticsKit
local Perf = R.Perf

-- file: the TwichUI file that opens the scope (relative to the AddOns folder's TwichUI folders; the core is
-- "!!!TwichUI/", the settings window "TwichUI_Settings/"), where: the function, so a report can name what to read.
-- every = how often it is expected to run, so a report can tell "runs often" from "runs on demand".
DX.OPS = {
    ["workshop.opportunityCallback"]={module="workshop",label="Whole incremental worker callback",kind="work",file="TwichUI_Workshop/OpportunityEngine.lua",where="Engine.Schedule",every="includes source check, work and rescheduling; no scope spans callbacks"},
    ["workshop.opportunitySource"]={module="workshop",label="Indivisible opportunity source check",kind="work",file="TwichUI_Workshop/OpportunityEngine.lua",where="Engine.Step",every="source validity check within the elapsed batch budget"},
    ["workshop.opportunities.partialReuses"]={module="workshop",label="Provisional membership arrays reused",kind="count",file="TwichUI_Workshop/OpportunityEngine.lua",where="Engine.Present",every="metadata-only filters during pending calculation"},
    ["workshop.opportunityRow"]={module="workshop",label="First-use opportunity row construction",kind="work",file="TwichUI_Workshop/ViewOpportunities.lua",where="MakeOppRow",every="bounded viewport pool growth only"},
    ["workshop.opportunities.catalogBuilds"]={module="workshop",label="Recipe catalog builds",kind="count",file="TwichUI_Workshop/OpportunityEngine.lua",where="Engine.Request",every="new context or catalog only"},
    ["workshop.opportunities.errors"]={module="workshop",label="Calculation job failures",kind="count",file="TwichUI_Workshop/OpportunityEngine.lua",where="incremental calculation/presentation",every="bounded opt-in aggregate"},
    ["workshop.opportunities.cancelled"]={module="workshop",label="Obsolete calculation jobs cancelled",kind="count",file="TwichUI_Workshop/OpportunityEngine.lua",where="incremental calculation/presentation",every="bounded opt-in aggregate"},
    ["workshop.opportunities.detailUpdates"]={module="workshop",label="Changed selected recipe details",kind="count",file="TwichUI_Workshop/ViewOpportunities.lua",where="incremental calculation/presentation",every="bounded opt-in aggregate"},
    ["workshop.opportunities.cellUpdates"]={module="workshop",label="Changed money cells",kind="count",file="TwichUI_Workshop/ViewOpportunities.lua",where="incremental calculation/presentation",every="bounded opt-in aggregate"},
    ["workshop.opportunities.rowPaints"]={module="workshop",label="Visible row presentations",kind="count",file="TwichUI_Workshop/ViewOpportunities.lua",where="incremental calculation/presentation",every="bounded opt-in aggregate"},
    ["workshop.opportunities.fullInvalidations"]={module="workshop",label="Complete context invalidations",kind="count",file="TwichUI_Workshop/OpportunityEngine.lua",where="incremental calculation/presentation",every="bounded opt-in aggregate"},
    ["workshop.opportunities.partialPublications"]={module="workshop",label="Provisional list publications",kind="count",file="TwichUI_Workshop/OpportunityEngine.lua",where="incremental calculation/presentation",every="bounded opt-in aggregate"},
    ["workshop.opportunities.fullPublications"]={module="workshop",label="Final ranked list publications",kind="count",file="TwichUI_Workshop/OpportunityEngine.lua",where="incremental calculation/presentation",every="bounded opt-in aggregate"},
    ["workshop.opportunities.sorts"]={module="workshop",label="Completed ranking passes",kind="count",file="TwichUI_Workshop/OpportunityEngine.lua",where="incremental calculation/presentation",every="bounded opt-in aggregate"},
    ["workshop.opportunities.batches"]={module="workshop",label="Calculation work slices",kind="count",file="TwichUI_Workshop/OpportunityEngine.lua",where="incremental calculation/presentation",every="bounded opt-in aggregate"},
    ["workshop.opportunities.reused"]={module="workshop",label="Completed estimates reused during catalog reconciliation",kind="count",file="TwichUI_Workshop/OpportunityEngine.lua",where="incremental calculation/presentation",every="bounded opt-in aggregate"},
    ["workshop.opportunities.cacheHits"]={module="workshop",label="Compatible catalog reads",kind="count",file="TwichUI_Workshop/OpportunityEngine.lua",where="incremental calculation/presentation",every="bounded opt-in aggregate"},
    ["workshop.opportunities.invalidations"]={module="workshop",label="Dependent recipes invalidated",kind="count",file="TwichUI_Workshop/OpportunityEngine.lua",where="incremental calculation/presentation",every="bounded opt-in aggregate"},
    ["workshop.opportunities.calculated"]={module="workshop",label="Recipe preparation passes",kind="count",file="TwichUI_Workshop/OpportunityEngine.lua",where="incremental calculation/presentation",every="bounded opt-in aggregate"},
    ["workshop.opportunities.crafts"]={module="workshop",label="Actual recipe calculations",kind="count",file="TwichUI_Workshop/OpportunityEngine.lua",where="incremental calculation/presentation",every="bounded opt-in aggregate"},
    ["workshop.opportunityBatch"]={module="workshop",label="Incremental opportunity work slice",kind="work",file="TwichUI_Workshop/OpportunityEngine.lua",where="Engine.Step",every="requested work only; total/worst synchronous CPU"},
    ["workshop.opportunityQuestion"]={module="workshop",label="Indivisible estimator service question",kind="work",file="TwichUI_Workshop/Estimate.lua",where="Est.Ask",every="memo misses; no scope spans a coroutine yield"},
    ["workshop.pricing.completed"]={module="workshop",label="Terminal cold requests measured",kind="count",file="TwichUI_Workshop/Pricing.lua",where="opt-in diagnostics",every="bounded capture aggregate"},
    ["workshop.pricing.cancelled"]={module="workshop",label="Pending price requests cancelled",kind="count",file="TwichUI_Workshop/Pricing.lua",where="opt-in diagnostics",every="bounded capture aggregate"},
    ["workshop.pricing.initialVisibleRows"]={module="workshop",label="Initially visible opportunity cohort size",kind="count",file="TwichUI_Workshop/Pricing.lua",where="opt-in diagnostics",every="bounded capture aggregate"},
    ["workshop.pricing.visibleTruncated"]={module="workshop",label="Visible cohort capped at 128 rows",kind="count",file="TwichUI_Workshop/Pricing.lua",where="opt-in diagnostics",every="bounded capture aggregate"},
    ["workshop.summary.historyPreemptions"]={module="workshop",label="History validation paused for current prices",kind="count",file="TwichUI_Workshop/Summary.lua",where="opt-in diagnostics",every="bounded capture aggregate"},
    ["workshop.preparedLoad"]={module="workshop",label="Prepared current addon load",kind="init",file="TwichUI_Workshop/Prepared.lua",where="load",every="once per requested physical partition"},
    ["workshop.preparedVerify"]={module="workshop",label="Prepared record/proof work slice",kind="work",file="TwichUI_Workshop/Summary.lua",where="Q.Step",every="requested work; shares history budget"},
    ["workshop.historyValidate"]={module="workshop",label="Historical partition validation slice",kind="work",file="TwichUI_Workshop/Summary.lua",where="Q.Step",every="explicit historical reads only"},
    ["workshop.historyLoad"]={module="workshop",label="Historical partition addon load",kind="work",file="TwichUI_Workshop/Summary.lua",where="loadPart",every="explicit historical reads only"},
    ["workshop.summary.currentDecodes"]={module="workshop",label="Current partition decode starts",kind="count",file="TwichUI_Workshop/Summary.lua",where="loadPart",every="opt-in aggregate"},
    ["workshop.summary.historyDecodes"]={module="workshop",label="History partition decode starts",kind="count",file="TwichUI_Workshop/Summary.lua",where="loadPart",every="opt-in aggregate"},
    ["workshop.priceWait"]={module="workshop",label="Usable Market reference wait",kind="wait",file="TwichUI_Workshop/Pricing.lua",where="record completion",every="uncached requests admitted in this capture"},
    ["workshop.priceSettlementWait"]={module="workshop",label="Market terminal price response wait",kind="wait",file="TwichUI_Workshop/Pricing.lua",where="record completion",every="includes terminal missing"},
    ["workshop.firstColdPrice"]={module="workshop",label="First cold Market reference",kind="wait",file="TwichUI_Workshop/Pricing.lua",where="completed",every="once per capture"},
    ["workshop.tenColdPrices"]={module="workshop",label="First ten cold Market references",kind="wait",file="TwichUI_Workshop/Pricing.lua",where="completed",every="once per capture"},
    ["workshop.firstVisiblePrice"]={module="workshop",label="First initially visible opportunity priced",kind="wait",file="TwichUI_Workshop/Pricing.lua",where="ObserveView",every="once per capture"},
    ["workshop.tenVisiblePrices"]={module="workshop",label="Ten initially visible opportunities priced",kind="wait",file="TwichUI_Workshop/Pricing.lua",where="ObserveView",every="once per capture if cohort has ten priced rows"},
    ["workshop.visibleSettled"]={module="workshop",label="Initially visible opportunities settled",kind="wait",file="TwichUI_Workshop/Pricing.lua",where="ObserveView",every="once per capture; includes missing"},
    ["workshop.opportunitiesSettled"]={module="workshop",label="All known opportunities settled",kind="wait",file="TwichUI_Workshop/Pricing.lua",where="ObserveView",every="once per capture; includes missing"},
    ["workshop.partitionQueueWait"]={module="workshop",label="Partition queue wait",kind="wait",file="TwichUI_Workshop/Summary.lua",where="startNext",every="queued in this capture"},
    ["workshop.currentValidationWait"]={module="workshop",label="Current partition validation wall time",kind="wait",file="TwichUI_Workshop/Summary.lua",where="Q.Step completion",every="started in this capture"},
    ["workshop.historyValidationWait"]={module="workshop",label="History partition validation wall time",kind="wait",file="TwichUI_Workshop/Summary.lua",where="Q.Step completion",every="started in this capture"},
    ["workshop.pricing.uniquePending"] = {module="workshop",label="New pending identities",kind="count",file="TwichUI_Workshop/Pricing.lua",where="request/completion",every="opt-in aggregate"},
    ["workshop.pricing.deduplicated"] = {module="workshop",label="Pending queries coalesced",kind="count",file="TwichUI_Workshop/Pricing.lua",where="request/completion",every="opt-in aggregate"},
    ["workshop.pricing.readerCalls"] = {module="workshop",label="Actual price reader calls",kind="count",file="TwichUI_Workshop/Pricing.lua",where="request/completion",every="opt-in aggregate"},
    ["workshop.pricing.baseKeys"] = {module="workshop",label="Base identity hashes",kind="count",file="TwichUI_Workshop/Pricing.lua",where="request/completion",every="opt-in aggregate"},
    ["workshop.pricing.settled"] = {module="workshop",label="Pending identities processed",kind="count",file="TwichUI_Workshop/Pricing.lua",where="request/completion",every="opt-in aggregate"},
    ["workshop.pricing.notifications"] = {module="workshop",label="Pricing completion refreshes",kind="count",file="TwichUI_Workshop/Pricing.lua",where="request/completion",every="opt-in aggregate"},
    ["workshop.pricing.fullLists"] = {module="workshop",label="Full Opportunities calculations",kind="count",file="TwichUI_Workshop/Session.lua",where="request/completion",every="opt-in aggregate"},
    ["workshop.pricingComplete"] = {module="workshop",label="Budgeted price completion slice",kind="work",file="TwichUI_Workshop/Summary.lua",where="Q.Step handoff",every="pending compact transfers; total/worst CPU"},
    ["workshop.summary.decodeStarts"] = {module="workshop",label="Partition decode starts",kind="count",file="TwichUI_Workshop/Summary.lua",where="loadPart",every="opt-in aggregate"},
    ["workshop.summary.decodeRepeats"] = {module="workshop",label="Previously validated partition decodes",kind="count",file="TwichUI_Workshop/Summary.lua",where="loadPart",every="opt-in aggregate"},
    ["bugsack.broker.update"] = { module = "bugsack", label = "BugSack broker: current-session count", kind = "hook", file = "modules/BugSackBroker.lua", where = "OnUpdate (hook BugSack.UpdateDisplay)", every = "when BugSack updates its display" },
    ["gathering.evaluate"] = { module = "qol", label = "Gathering target and interaction settings", kind = "evaluate", file = "!!!TwichUI/qol/GatheringSparkles.lua", where = "G.Poll", every = "interaction/nameplate events and every 0.2 seconds while enabled" },
    ["qol.groupFinderZones.row"] = { module = "qol", label = "Group Finder zones: a listing row drawn", kind = "hook", file = "!!!TwichUI/qol/GroupFinderZones.lua", where = "Z.Draw (hook LFGBrowseSearchEntry_Update)", every = "each Group Finder row the game draws or updates, only after the switch was first turned on" },
    ["gathering.refresh"] = { module = "qol", label = "Gathering sparkle lifecycle", kind = "work", file = "!!!TwichUI/qol/GatheringSparkles.lua", where = "G.Refresh", every = "settings, profiles, login and addon changes" },
    ["gathering.animate"] = { module = "qol", label = "Gathering sparkle animation", kind = "update", file = "!!!TwichUI/qol/GatheringSparklesDisplay.lua", where = "Animate", every = "per frame while the one gathering overlay is shown" },
    ["workshop.summaryLoad"] = { module="workshop",label="Summary partition addon load",kind="init",file="TwichUI_Workshop/Summary.lua",where="loadPart",every="once per requested partition" },
    ["workshop.summaryValidate"] = { module="workshop",label="Summary validation slice",kind="work",file="TwichUI_Workshop/Summary.lua",where="Q.Step",every="while validating header or requested partition" },
    ["workshop.summaryHistory"] = { module="workshop",label="Market daily history projection",kind="work",file="TwichUI_Workshop/Summary.lua",where="Q.History",every="selected external item/metric/window" },
    ["workshop.summaryLookup"] = { module="workshop",label="Exact summary lookup",kind="work",file="TwichUI_Workshop/Summary.lua",where="Q.Record",every="external research only" },

    ["auction.actionReview"] = {module="auction", label="AH action validation and explicit submission", kind="evaluate", file="TwichUI_Workshop/auction/Actions.lua", where="Prepare/Confirm", every="explicit review or confirmation only", visible="auction.previewShown"},
    ["auction.chartPrepare"] = { module="auction", label="Market chart preparation", kind="rebuild", file="TwichUI_Workshop/auction/AdvancedChart.lua", where="Set", every="evidence replacement" },
    ["auction.chartDraw"] = { module="auction", label="Market chart geometry", kind="layout", file="TwichUI_Workshop/auction/AdvancedChart.lua", where="Render", every="evidence or geometry change" },
    ["auction.readSnapshot"] = { module = "auction", label = "AH experimental read normalization", kind = "rebuild", file = "TwichUI_Workshop/auction/ReadRequests.lua", where = "Event", every = "explicit response only; at most 500 rows" },
    ["auction.marketDetails"] = { module="auction", label="AH Market selected-item services", kind="rebuild", file="TwichUI_Workshop/auction/MarketData.lua", where="Project", every="selected item/generation change only", visible="auction.previewShown" },
    ["auction.previewSearch"] = { module = "auction", label = "AH preview: stored catalog/filter/sort slice", kind = "rebuild", file = "TwichUI_Workshop/auction/BrowseData.lua", where = "Job.Step", every = "bounded slices only while Browse is visible", visible = "auction.previewShown" },
    ["auction.previewPageBuild"] = { module = "auction", label = "AH preview: lazy page construction", kind = "init", file = "TwichUI_Workshop/auction/Window.lua", where = "Page", every = "first visit to each preview page" },
    ["auction.previewResize"] = { module = "auction", label = "AH preview: resize", kind = "layout", file = "TwichUI_Workshop/auction/Window.lua", where = "A.Resize", every = "at most 20 Hz during an explicit resize drag", visible = "auction.previewShown" },
    ["auction.previewBuild"] = { module = "auction", label = "AH preview: shell construction", kind = "init", file = "TwichUI_Workshop/auction/Window.lua", where = "Build", every = "first explicit preview open" },
    ["auction.previewRender"] = { module = "auction", label = "AH preview: visible page render", kind = "rebuild", file = "TwichUI_Workshop/auction/Window.lua", where = "A.Render", every = "visible page changes and coalesced refreshes", visible = "auction.previewShown" },
    ["auction.switch"] = { module = "auction", label = "AH supervised interface switch", kind = "layout", file = "auction/Host.lua", where = "Switch", every = "explicit test visit or return action only" },
    ["auction.proof"] = { module = "auction", label = "AH-1a presentation switch/recovery", kind = "layout", file = "auction/Host.lua", where = "Activate, Restore", every = "explicit diagnostic command, or recovery of its active lease" },
    ["auction.proofWatch"] = { module = "auction", label = "AH-1a lease check", kind = "update", file = "auction/Host.lua", where = "Watch", every = "every 0.25 s only while Host owns a proof or supervised replacement" },
    ["core.savedData"] = { module = "core", label = "Saved data check at load (Persist.LoadMain)", kind = "init", file = "Core.lua", where = "ADDON_LOADED handler > Persist.LoadMain", every = "once per load" },
    ["core.startupHook"] = { module = "core", label = "Start-up hooks (each module's OnInit)", kind = "init", file = "Core.lua", where = "R.initHooks loop", every = "once per load, per module" },
    ["inventory.plan"] = { module = "inventory", label = "Magic Inventory plan (bags read, rules matched)", kind = "rebuild", file = "inventory/Plan.lua", where = "MI.CurrentPlan", every = "when a mailbox, bank or guild bank opens or its bags change (coalesced), and per review drawn" },
    ["inventory.guildRead"] = { module = "inventory", label = "Magic Inventory: guild bank tab list and shown tab read (98 slots)", kind = "rebuild", file = "inventory/GuildBank.lua", where = "GB.Capture", every = "when the guild bank opens, shows a tab or changes, only while the feature is on" },
    ["inventory.guildPlan"] = { module = "inventory", label = "Magic Inventory guild bank placement preview (rules matched, slots placed)", kind = "rebuild", visible = "settings.shown", file = "inventory/GuildPlan.lua", where = "MI.CurrentGuildPlan", every = "on request: a preview or refresh button in the settings" },
    ["inventory.designTray"] = { module = "inventory", label = "Magic Inventory arrangement tray: bag and guild bank item references gathered", kind = "rebuild", visible = "settings.shown", file = "TwichUI_Settings/pages/MagicInventoryGuild.lua", where = "Known", every = "when the arrangement editor is drawn after the bags or the guild bank changed" },
    ["inventory.guildReview"] = { module = "inventory", label = "Magic Inventory guild bank run: the review before a confirmation (plan, bags and the tabs read so far)", kind = "rebuild", file = "inventory/GuildRun.lua", where = "BuildReview", every = "on request: Deposit or Organize bank pressed, when a confirmation starts, and in each summary rebuild at the guild bank" },
    ["inventory.guildPrep"] = { module = "inventory", label = "Magic Inventory guild bank panel: the summary of what Deposit and Organize bank would do (two reviews)", kind = "rebuild", file = "inventory/GuildPrep.lua", where = "Replan", every = "while the guild bank is open with a saved arrangement, once per burst of bag or bank changes (coalesced 0.4 s), never during a run" },
    ["inventory.guildRun"] = { module = "inventory", label = "Magic Inventory guild bank run: one move handed to the game", kind = "bulk", file = "inventory/GuildRun.lua", where = "Dispatch", every = "per move, only while the player's confirmed run is going" },
    ["inventory.step"] = { module = "inventory", label = "Magic Inventory: one stack picked up and attached or deposited", kind = "bulk", file = "inventory/Run.lua", where = "AttachNext, DepositNext", every = "per stack, only while the player's transfer runs" },
    ["npcs.search"] = { module = "npcs", label = "NPC search (map toolbar)", kind = "search", file = "npcs/Search.lua", where = "SR.Run", every = "per search typed" },
    ["npcs.knowledge.rebuild"] = { module = "npcs", label = "NPC knowledge rows rebuilt", kind = "rebuild", file = "npcs/Knowledge.lua", where = "Build", every = "when the NPC list changes" },
    ["npcs.map.layout"] = { module = "npcs", label = "NPC markers placed on the world map", kind = "layout", visible = "map.open", file = "npcs/Map.lua", where = "NMAP.Layout", every = "per map change, zoom or pan" },
    ["guildloc.tick"] = { module = "guildloc", label = "Guild Locations: one send tick (position read, movement test, preflight, hand-over)", kind = "update", file = "guildloc/Comm.lua", where = "TickWork", every = "every 10 to 60 s (jittered) while sharing in a guild" },
    ["guildloc.receive"] = { module = "guildloc", label = "Guild Locations: one message taken in (checks, roster lookup, epoch rules)", kind = "bulk", file = "guildloc/Comm.lua", where = "Receive", every = "per guildmate message, about 1 in 4 s per sharing guildmate, none while off" },
    ["guildloc.roster"] = { module = "guildloc", label = "Guild Locations: guild roster index rebuilt", kind = "rebuild", file = "guildloc/Roster.lua", where = "Rebuild", every = "when the roster changes (coalesced, at most every 5 s), only while not off" },
    ["guildloc.map.layout"] = { module = "guildloc", label = "Guild Locations: class badges placed on the world map", kind = "layout", visible = "map.open", file = "guildloc/Map.lua", where = "GM.Layout", every = "when the map or its size changes, and at most every 0.5 s for position changes; nothing while the map is hidden" },
    ["guildloc.search"] = { module = "guildloc", label = "Guild Locations: one search of the held guildmates (map search field)", kind = "bulk", file = "guildloc/Map.lua", where = "GM.Search", every = "once per search after typing pauses, only while the map search field is used" },
    ["npcs.import"] = { module = "npcs", label = "NPC reports merged in (a received list)", kind = "bulk", file = "npcs/Store.lua", where = "NS.MergeReported", every = "per received list" },
    ["npcs.cleanup"] = { module = "npcs", label = "NPC entries removed (World Knowledge cleanup)", kind = "bulk", file = "npcs/Store.lua", where = "NS.ForgetMany", every = "on request" },
    ["npcs.minimap.tick"] = { module = "npcs", label = "NPC markers on the minimap, one update", kind = "update", file = "npcs/Minimap.lua", where = "Update > Step", every = "10 times a second (25 when the minimap rotates) while the feature is on" },
    ["npcs.map.pulse"] = { module = "npcs", label = "Ring pulse on a found NPC, one frame", kind = "update", file = "npcs/Map.lua", where = "PulseTick", every = "every frame for a few seconds after a find" },
    ["pins.map.layout"] = { module = "pins", label = "Pins placed on the world map", kind = "layout", visible = "map.open", file = "pins/Map.lua", where = "PM.Layout", every = "per map change, zoom or pan" },
    ["pins.minimap.tick"] = { module = "pins", label = "Pins on the minimap, one update", kind = "update", file = "pins/Minimap.lua", where = "Update > Step", every = "10 times a second (25 when rotating) while a pin is eligible" },
    ["pins.ping.tick"] = { module = "pins", label = "A map ping animating, one frame", kind = "update", file = "pins/PingMap.lua", where = "Tick > Step", every = "every frame while a ping shows" },
    ["nav.load"] = { module = "nav", label = "Navigation data addon loaded (first route)", kind = "init", file = "nav/Data.lua", where = "ND.Load > C_AddOns.LoadAddOn", every = "once per session, when the first route is asked for" },
    ["workshop.load"] = { module = "workshop", label = "Workshop addon loaded", kind = "init", file = "WorkshopLauncher.lua", where = "L.Load > C_AddOns.LoadAddOn", every = "once per session, the first time the Workshop is opened" },
    ["workshop.read"] = { module = "workshop", label = "Workshop: the open profession's recipes read (list, learned flags; queued recipes refreshed)", kind = "rebuild", file = "TwichUI_Workshop/Session.lua", where = "S.Observe > Observe.Read; S.ReadMerchant", every = "when the Workshop opens and per burst of profession or merchant window changes while it is shown" },
    ["workshop.bank"] = { module = "workshop", label = "Workshop: the open bank (or the shown guild bank tab) read and remembered", kind = "bulk", file = "TwichUI_Workshop/Bank.lua", where = "RunBank, GuildAnswer", every = "per burst of changes (0.4 s settle) while a bank is open and the Workshop addon is loaded; none otherwise" },
    ["workshop.worth"] = { module = "workshop", label = "Workshop: \"What's it worth?\" lines added to an item tooltip (saved prices read, nothing asked of the auction house)", kind = "rebuild", file = "TwichUI_Workshop/WorthTip.lua", where = "T.OnItem > Add", every = "per rebuild of the tooltip of an item in the bags or bank, only after the Workshop was loaded in the session" },
    ["workshop.scan"] = { module = "workshop", label = "Workshop: auction listings read for a price scan (a batch of up to 400) and merged into the saved prices (a step of up to 120 items)", kind = "bulk", file = "TwichUI_Workshop/Scan.lua", where = "BeginRead > Step, SaveStep", every = "per batch or step, only during a scan the player started at the auction house" },
    ["workshop.junkTest"] = { module = "workshop", label = "Workshop: junk rule item test and bag survey (reads, decides, writes nothing)", kind = "rebuild", visible = "settings.shown", file = "TwichUI_Workshop/Junk.lua", where = "J.Inspect, J.Survey > Step", every = "on request: one item when chosen or after an edit, 30 slots per slice for a survey; only while the rule builder is open" },
    ["settings.junkBuilder.layout"] = { module = "settings", label = "Junk marking: the rule builder drawn", kind = "layout", visible = "settings.shown", file = "TwichUI_Settings/pages/JunkBuilder.lua", where = "Layout", every = "per edit, click or item test while the rule builder is open; never per frame" },
    ["workshop.junk"] = { module = "workshop", label = "Workshop: vendor recommendation junk marking", kind = "rebuild", file = "TwichUI_Workshop/Junk.lua", where = "J.Request > Step", every = "40 carried slots per slice after coalesced inventory, pricing or planning changes; opt-in only" },
    ["workshop.advisorSearch"] = { module = "workshop", label = "Workshop: Item Advisor search batch", kind = "rebuild", file = "TwichUI_Workshop/ViewAdvisor.lua", where = "Search > Step", every = "at most 160 cached identities per slice while Item Advisor is open" },
    ["workshop.advisor"] = { module = "workshop", label = "Workshop: Item Advisor discovery batch", kind = "rebuild", file = "TwichUI_Workshop/AdvisorData.lua", where = "job:Step", every = "bounded discovery batches while the Item Advisor is open" },
    ["workshop.bridgeLoad"] = { module = "workshop", label = "External data addon load", kind = "init", file = "TwichUI_Workshop/Bridge.lua", where = "B.Load", every = "only after explicit external source selection" },
    ["workshop.bridgeValidate"] = { module = "workshop", label = "External generation validation slice", kind = "bulk", file = "TwichUI_Workshop/Bridge.lua", where = "B.Step", every = "only after explicit external source selection" },
    ["workshop.bridgeRecord"] = { module = "workshop", label = "External exact-variant record read", kind = "evaluate", file = "TwichUI_Workshop/Bridge.lua", where = "B.Record", every = "only after explicit external source selection" },
    ["workshop.bridgeHistory"] = { module = "workshop", label = "External selected history read", kind = "evaluate", file = "TwichUI_Workshop/Bridge.lua", where = "B.History", every = "only after explicit external source selection" },
    ["workshop.market"] = { module = "workshop", label = "Workshop: one item's market figures read (value, quality, supply, competition) for the Opportunities details or an item tooltip; a cached item costs nothing", kind = "rebuild", file = "TwichUI_Workshop/MarketFacts.lua", where = "F.Of > Ask", every = "per item whose figures are not cached: a recipe selected, a tooltip first shown, or after a scan; never per frame" },
    ["workshop.estimate"] = { module = "workshop", label = "Workshop: every known recipe estimated for Opportunities (listings walked, competing prices, fees, confidence; each item and quantity asked once per draw)", kind = "rebuild", file = "TwichUI_Workshop/Session.lua", where = "S.Opportunities > Estimate.Craft", every = "per draw of Opportunities, the Overview or the Crafting totals; never per frame" },
    ["ledger.record"] = { module = "workshop", label = "Gold ledger: one observed gold change recorded (a balance reading, the journal entry, the day's totals)", kind = "work", file = "!!!TwichUI/auction/Ledger.lua", where = "OnMoney > Lg.Observe", every = "per PLAYER_MONEY while the Workshop is on; the Workshop addon need not be loaded" },
    ["ledger.vendor"] = { module = "workshop", label = "Gold ledger: merchant evidence observation", kind = "work", file = "!!!TwichUI/auction/Vendor.lua", where = "native post-hooks, Try", every = "bounded snapshots and settlement during merchant visits; no polling or gameplay actions" },
    ["ledger.auction"] = { module = "workshop", label = "Gold ledger: owned auction cash evidence", kind = "work", file = "!!!TwichUI/auction/LedgerAuction.lua", where = "Try, Foreign", every = "only while one explicit controller operation is awaiting completion or money" },
    ["ledger.mail"] = { module = "workshop", label = "Gold ledger: mailbox evidence and invoice validation", kind = "work", file = "!!!TwichUI/auction/Mail.lua", where = "Snapshot, Record, OnMoney", every = "bounded by inbox/request limits during explicit mailbox takes; no automatic collection" },
    ["ledger.cost"] = { module = "workshop", label = "Gold ledger: cost basis, one verified transaction remembered (a lot, a realized result)", kind = "work", file = "!!!TwichUI/auction/LedgerCost.lua", where = "Attached > Dispatch", every = "once per attributed vendor purchase/sale, Auction House purchase or sale; no polling, no money recorded" },
    ["ledger.chartDraw"] = { module = "workshop", label = "Gold Flow chart drawn (columns, net line, axis, legend); skipped when its data, zoom and size are unchanged", kind = "rebuild", file = "TwichUI_Workshop/LedgerChart.lua", where = "Draw", every = "when the Gold Ledger page is drawn with changed data, a range, zoom or size change; never per hover" },
    ["ledger.costquery"] = { module = "workshop", label = "Gold Ledger page: realized item results and profession totals of the chosen days (cached until the recorder or filter changes)", kind = "rebuild", file = "TwichUI_Workshop/LedgerQuery.lua", where = "LQ.Results, LQ.ProfessionRows", every = "when the page is drawn with changed data" },
    ["ledger.query"] = { module = "workshop", label = "Gold Ledger page: the totals, daily series and source split of the chosen days (cached until the recorder or the filter changes)", kind = "rebuild", file = "TwichUI_Workshop/LedgerQuery.lua", where = "LQ.Summary (from V.Draw)", every = "per redraw of the page while it is shown, when the cache is stale" },
    ["ledger.draw"] = { module = "workshop", label = "Gold Ledger page drawn (cards, Gold Flow chart, sources, transaction list)", kind = "rebuild", file = "TwichUI_Workshop/ViewLedger.lua", where = "V.Draw", every = "when the page is shown, a filter changes, or a burst of gold changes settles; never while the page is hidden" },
    ["workshop.render"] = { module = "workshop", label = "Workshop: the window drawn (recipe rows, queue, materials against the bags, the shopping list and its plan)", kind = "rebuild", file = "TwichUI_Workshop/Window.lua", where = "Win.Render", every = "per burst of profession, bag or item-name changes and per click, only while the Workshop is shown" },
    ["layouts.load"] = { module = "layouts", label = "Layout tools addon loaded", kind = "init", file = "LayoutsLauncher.lua", where = "L.Load > C_AddOns.LoadAddOn", every = "once per session, for /tui layout or after a reload while an install is being finished" },
    ["layouts.plan"] = { module = "layouts", label = "Layout install planned (package checked, layers composed, each addon read, an update compared with the baseline)", kind = "rebuild", file = "TwichUI_Layouts/Engine.lua", where = "LY.Plan", every = "on request (/tui layout plan, and again inside apply)" },
    ["layouts.apply"] = { module = "layouts", label = "Layout install applied (EllesmereUI import, TwichUI profile and values)", kind = "bulk", file = "TwichUI_Layouts/Engine.lua", where = "LY.Apply", every = "on request" },
    ["layouts.verify"] = { module = "layouts", label = "Layout install, restore or undone update checked (and the baseline taken)", kind = "evaluate", file = "TwichUI_Layouts/Engine.lua", where = "LY.Verify, LY.VerifyRestore, LY.VerifyUndo", every = "on request, and once after the reload that finishes an install, a restore or an undo" },
    ["layoutwizard.load"] = { module = "layouts", label = "Layout setup addon loaded", kind = "init", file = "LayoutsLauncher.lua", where = "L.LoadWizard > C_AddOns.LoadAddOn", every = "once per session, when /tui layout (or a Home or Troubleshooting button) opens the setup" },
    ["layoutwizard.build"] = { module = "layouts", label = "Layout setup window built (first open)", kind = "init", file = "TwichUI_LayoutWizard/Window.lua", where = "Build", every = "once per session, at the first open" },
    ["layoutwizard.preview"] = { module = "layouts", label = "Layout setup preview drawn", kind = "layout", file = "TwichUI_LayoutWizard/Preview.lua", where = "Draw", every = "when a step with the preview is shown, a choice changes or the screen changes (never while closed)" },
    ["layoutwizard.preview.follow"] = { module = "layouts", label = "Layout setup preview: the sample tooltip moved with the pointer", kind = "layout", file = "TwichUI_LayoutWizard/Preview.lua", where = "view:Track (the throttled OnUpdate)", every = "about 30 a second, only while the pointer is over the miniature with the tooltip scenario and Follow mouse picked (never otherwise)" },
    ["layoutwizard.overlay.build"] = { module = "layouts", label = "Layout setup full-size preview built (first time it opens)", kind = "init", file = "TwichUI_LayoutWizard/Overlay.lua", where = "Build", every = "once per session, the first time the full-size preview opens" },
    ["layoutwizard.overlay"] = { module = "layouts", label = "Layout setup full-size preview drawn", kind = "layout", file = "TwichUI_LayoutWizard/Overlay.lua", where = "Draw", every = "when the full-size preview opens, a layout or scenario is picked in it, or the screen changes (never while closed)" },
    ["layouts.capture"] = { module = "layouts", label = "Layout authoring: profiles captured through the adapters' allowlists and scanned", kind = "bulk", file = "TwichUI_LayoutWizard/Author.lua", where = "A.Capture", every = "on request (the workspace's Capture button)" },
    ["layouts.publish.build"] = { module = "layouts", label = "Layout package published (copied, checked, metadata derived)", kind = "rebuild", file = "TwichUI_Layouts/Publish.lua", where = "Pub.Build", every = "on request (Publish in the authoring workspace)" },
    ["layouts.publish.check"] = { module = "layouts", label = "Layout package checked (shape, package, derived metadata, media)", kind = "evaluate", file = "TwichUI_Layouts/Publish.lua", where = "Pub.Check", every = "on request, when a package arrives, and when a stored one is opened" },
    ["layouts.publish.compare"] = { module = "layouts", label = "Two layout packages compared (what each resolves to)", kind = "evaluate", file = "TwichUI_Layouts/Publish.lua", where = "Pub.Compare", every = "on request (/tui layout compare, typed)" },
    ["layouts.publish.receive"] = { module = "layouts", label = "Layout package that arrived checked against its offer and kept", kind = "bulk", file = "TwichUI_Layouts/Store.lua", where = "LY.Receive", every = "once per package a player accepts" },
    ["layouts.store.open"] = { module = "layouts", label = "Stored layout package checked after being unpacked", kind = "evaluate", file = "TwichUI_Layouts/Store.lua", where = "Store.Open", every = "when a stored package is chosen in the setup or the workspace" },
    ["layoutwizard.author.build"] = { module = "layouts", label = "Layout authoring window built (first open)", kind = "init", file = "TwichUI_LayoutWizard/AuthorWindow.lua", where = "Build", every = "once per session, at the first open of /tui layout author" },
    ["layoutwizard.author.review"] = { module = "layouts", label = "Layout authoring: the review table put in order (filters, sort, attention flags, impact)", kind = "rebuild", file = "TwichUI_LayoutWizard/AuthorReview.lua", where = "RV.Rebuild", every = "when a filter or the sort changes, after a capture, and the first time the table is shown (never per page or per click)" },
    ["layoutwizard.author.review.detail"] = { module = "layouts", label = "Layout authoring: the leaf differences of the change whose details are open", kind = "evaluate", file = "TwichUI_LayoutWizard/AuthorReview.lua", where = "RV.Detail", every = "when a change is picked, or its values or destination change while it is open" },
    ["layoutwizard.presets.capture"] = { module = "layouts", label = "Layout authoring: a TwichUI profile read for a preset (every setting a preset may manage)", kind = "bulk", file = "TwichUI_LayoutWizard/AuthorPresets.lua", where = "AP.ReadAll", every = "on request (Capture current settings into this preset, Create preset from current settings)" },
    ["layouts.restore"] = { module = "layouts", label = "Layout install restored, or its last update undone", kind = "bulk", file = "TwichUI_Layouts/Engine.lua", where = "LY.Restore, LY.Undo", every = "on request" },
    ["nav.search"] = { module = "nav", label = "Route search, one slice", kind = "update", file = "nav/Nav.lua", where = "StepJob", every = "every frame while a route is being searched" },
    ["nav.position"] = { module = "nav", label = "Navigation: position read and announced", kind = "update", file = "nav/Nav.lua", where = "OnUpdate > ReadPosition + Emit(position)", every = "POS_EVERY seconds while navigating" },
    ["nav.progress"] = { module = "nav", label = "Navigation: progress along the route", kind = "update", file = "nav/Nav.lua", where = "Progress", every = "PROGRESS_EVERY seconds while navigating" },
    ["nav.ticker"] = { module = "nav", label = "Navigation: a trail or arrow updater, one frame", kind = "update", file = "nav/Nav.lua", where = "OnUpdate > tickers (nav/MapTrail.lua, nav/MinimapTrail.lua, nav arrow)", every = "every frame while navigating" },
    ["map.view.step"] = { module = "map", label = "Map glide or zoom animation, one frame", kind = "update", file = "map/View.lua", where = "Step", every = "every frame during a glide" },
    ["map.view.follow"] = { module = "map", label = "Map following the view, one frame", kind = "update", file = "map/View.lua", where = "FollowStep", every = "every frame after the view moved, until still" },
    ["map.view.notify"] = { module = "map", label = "Map view change announced", kind = "update", file = "map/View.lua", where = "Notified", every = "once after a view change" },
    ["classbars.anim"] = { module = "classbars", label = "Class bar animation, one step", kind = "update", file = "classbars/Anim.lua", where = "OnUpdate > obj.Step", every = "every frame while a bar animates" },
    ["reminders.refresh"] = { module = "reminders", label = "Reminders: everything decided again", kind = "rebuild", file = "reminders/Controller.lua", where = "Refresh", every = "when a setting or the situation changes" },
    ["reminders.decide"] = { module = "reminders", label = "Reminders: one reminder decided", kind = "evaluate", file = "reminders/Controller.lua", where = "Decide (local)", every = "when an observation it uses changes" },
    ["reminders.event"] = { module = "reminders", label = "Reminders: a game event reached the state watcher", kind = "event", file = "reminders/State.lua", where = "OnEvent (its own frame, not the event bus)", every = "per event the active reminders listen for (aura and bag events can be frequent)" },
    ["reminders.designer.layout"] = { module = "reminders", label = "Reminders: the When designer laid out", kind = "layout", visible = "settings.shown", file = "TwichUI_Settings/pages/RemindersDesigner.lua", where = "s:Layout", every = "per redraw of the Reminders page while it is shown" },
    ["partyDeath.event"] = { module = "partyDeath", label = "Party member fallen: a unit or roster event", kind = "event", file = "modules/PartyDeath.lua", where = "OnEvent (its own frame)", every = "per health, flag or connection event of a party member, and per roster event" },
    ["healer.update"] = { module = "healer", label = "Healer Watch panel update", kind = "update", file = "healer/Watch.lua", where = "Update (local)", every = "when the watched healer's state changes" },
    ["healer.event"] = { module = "healer", label = "Healer Watch: a game event (chat, roster)", kind = "event", file = "healer/Watch.lua", where = "OnEvent (its own frame)", every = "per chat or roster event while watching" },
    ["healer.unitEvent"] = { module = "healer", label = "Healer Watch: a unit event for the watched healer", kind = "event", file = "healer/Watch.lua", where = "OnUnitEvent (its own frame)", every = "per power, health or aura event of that one unit" },
    ["buffback.aura"] = { module = "buffback", label = "Return the Favor: your own aura or cast event", kind = "event", file = "buffback/Watch.lua", where = "OnEvent (its unit frame)", every = "per UNIT_AURA or UNIT_SPELLCAST_SUCCEEDED of yours while it is on" },
    ["buffback.event"] = { module = "buffback", label = "Return the Favor: a game event (zone, combat, target, group)", kind = "event", file = "buffback/Watch.lua", where = "OnEvent (its own frame)", every = "per zone, resting, combat, target, group or spell change while it is on" },
    ["loot.victory.event"] = { module = "loot", label = "Loot victory: confirmed win relay", kind = "event", file = "loot/Victory.lua", where = "Sync (private event frame)", every = "one confirmed self-win while replacing native winning alerts" },
    ["loot.victory.tick"] = { module = "loot", label = "Loot victory: one-shot reveal or fade", kind = "update", file = "loot/Victory.lua", where = "Animate / Rest", every = "per frame for 1.75 s celebration and 0.3 s fade; no updates at rest" },
    ["loot.event"] = { module = "loot", label = "Loot Rolls: a loot roll, history or item event", kind = "event", file = "loot/Roll.lua", where = "OnEvent (its own frame)", every = "per group-loot roll event and per item-info event while a card could be showing; nothing while it is off" },
    ["loot.layout"] = { module = "loot", label = "Loot Rolls: the card stack laid out and drawn", kind = "layout", file = "loot/Cards.lua", where = "Layout (local)", every = "when a roll starts, changes or ends, or a setting changes; never per frame" },
    ["loot.tick"] = { module = "loot", label = "Loot Rolls: countdown bars and numbers", kind = "update", file = "loot/Cards.lua", where = "Tick (the stack's OnUpdate)", every = "about 20 times a second, only while a card is counting down or coming in" },
    ["camping.look"] = { module = "camping", label = "Camping bar look: bags, skills and recipes read, buttons filled", kind = "rebuild", file = "camping/Bar.lua", where = "Update (via Look)", every = "when bags, skills, recipes or a setting change, one look per burst, out of combat only" },
    ["camping.rest"] = { module = "camping", label = "Camping bar: the sleeping bag bar read a game event (resting, bag cooldown, your aura or cast)", kind = "event", file = "camping/Rest.lua", where = "OnEvent (its own frame)", every = "per resting, bag cooldown, or your own aura or cast event while the bar and its switch are on" },
    ["buffback.render"] = { module = "buffback", label = "Return the Favor list update", kind = "layout", file = "buffback/List.lua", where = "Render (local)", every = "when the list or a setting changes, out of combat only" },
    ["glows.evaluate"] = { module = "glows", label = "Action bar glows: one look at what is due (reads what went stale, decides, draws)", kind = "rebuild", file = "glows/Controller.lua", where = "Evaluate", every = "once per burst of events (coalesced 0.05 s), while it is on" },
    ["glows.map"] = { module = "glows", label = "Action bar glows: every action button read again (Blizzard's, EllesmereUI's, the stance bar)", kind = "rebuild", file = "glows/Buttons.lua", where = "BT.Map", every = "after a bar, page, form, macro or spell change, at most once per look" },
    ["glows.event"] = { module = "glows", label = "Action bar glows: a game event (bars, combat, target, cooldowns, usability, bags, tracking, group)", kind = "event", file = "glows/Controller.lua", where = "OnEvent (its own frame)", every = "per event of those while it is on" },
    ["glows.unit"] = { module = "glows", label = "Action bar glows: your own aura, inventory or cast event", kind = "event", file = "glows/Controller.lua", where = "OnEvent (its unit frame)", every = "per UNIT_AURA, UNIT_INVENTORY_CHANGED or cast of yours while it is on" },
    ["glows.group"] = { module = "glows", label = "Action bar glows: a group member's aura changed", kind = "event", file = "glows/Controller.lua", where = "OnGroupAura", every = "per UNIT_AURA, only out of combat in a group with group buffs on" },
    ["targetart.event"] = { module = "targetart", label = "Target artwork: a target event", kind = "event", file = "targetart/Display.lua", where = "OnEvent (its own frame)", every = "per target change or classification change" },
    ["refreshments.cast"] = { module = "refreshments", label = "Mage refreshments: a cast by the player", kind = "event", file = "modules/Refreshments.lua", where = "castFrame OnEvent (UNIT_SPELLCAST_SUCCEEDED, player)", every = "per spell the player casts (builds a small closure each time)" },
    ["rxp.skin.render"] = { module = "restedxp", label = "RestedXP skin: RestedXP drew its frame", kind = "hook", file = "modules/RestedXPSkin.lua", where = "OnRender (hooksecurefunc RXP.RenderFrame)", every = "whenever RestedXP renders its guide frame" },
    ["rxp.skin.stepText"] = { module = "restedxp", label = "RestedXP skin: current step text updated", kind = "hook", file = "modules/RestedXPSkin.lua", where = "OnStepText (hook CurrentStepFrame.UpdateText)", every = "whenever RestedXP updates the step text" },
    ["rxp.skin.arrow"] = { module = "restedxp", label = "RestedXP skin: arrow redrawn, resized or re-fonted", kind = "hook", file = "modules/RestedXPSkin.lua", where = "Arrow.OnVisuals / OnSize / OnFont (hooks on RestedXP's arrow)", every = "whenever RestedXP updates its arrow (can be many times a second while moving)" },
    ["rxp.skin.tray"] = { module = "restedxp", label = "RestedXP skin: a tray's visuals updated", kind = "hook", file = "modules/RestedXPSkin.lua", where = "OnTrayVisuals (hook tray.UpdateVisuals)", every = "whenever RestedXP updates a tray" },
    ["rxp.skin.scale"] = { module = "restedxp", label = "RestedXP skin: a frame was scaled", kind = "hook", file = "modules/RestedXPSkin.lua", where = "OnScale (hooks on SetScale)", every = "when RestedXP rescales" },
    ["rxp.skin.fontSize"] = { module = "restedxp", label = "RestedXP skin: guide font size changed", kind = "hook", file = "modules/RestedXPSkin.lua", where = "OnFontSize (hook RXP.UpdateGuideFontSize)", every = "when the font size changes" },
    ["rxp.skin.currentTick"] = { module = "restedxp", label = "RestedXP skin: current-step button hover check", kind = "update", file = "modules/RestedXPSkin.lua", where = "Current.Tick (button OnUpdate)", every = "several times a second while the button shows" },
    ["rxp.timers.start"] = { module = "restedxp", label = "RestedXP timers: a timer started", kind = "hook", file = "modules/RestedXPTimers.lua", where = "OnStart (hook RXP.StartTimer)", every = "per RestedXP timer" },
    ["rxp.timers.show"] = { module = "restedxp", label = "RestedXP timers: timers shown", kind = "hook", file = "modules/RestedXPTimers.lua", where = "OnShow (hook RXP.ShowTimers)", every = "per RestedXP timer display" },
    ["rxp.waypoint.sync"] = { module = "restedxp", label = "RestedXP waypoint sync", kind = "hook", file = "qol/GuideWaypoint.lua", where = "W.Sync (hooks UpdateMap, UpdateGotoSteps, ResetArrowPosition)", every = "whenever RestedXP updates its map or goto steps" },
    ["settings.describe"] = { module = "settings", label = "Settings pages described (first open)", kind = "init", file = "TwichUI_Settings/Window.lua", where = "K.Describe", every = "once, first open" },
    ["settings.window.build"] = { module = "settings", label = "Settings window built (first open)", kind = "init", file = "TwichUI_Settings/Window.lua", where = "BuildWindow", every = "once, first open" },
    ["settings.page.build"] = { module = "settings", label = "A settings page drawn for the first time", kind = "build", file = "TwichUI_Settings/Window.lua", where = "BuildView", every = "once per page, first visit" },
    ["settings.page.layout"] = { module = "settings", label = "A settings page laid out", kind = "layout", visible = "settings.shown", file = "TwichUI_Settings/Window.lua", where = "Layout(view)", every = "per page shown or resized" },
    ["settings.companion"] = { module = "settings", label = "A settings sample refreshed", kind = "layout", visible = "settings.shown", file = "TwichUI_Settings/Companion.lua", where = "Update(view)", every = "on a visible sample or preference change" },
    ["settings.search"] = { module = "settings", label = "Settings search results drawn", kind = "search", visible = "settings.shown", file = "TwichUI_Settings/Window.lua", where = "DrawResults", every = "per search typed" },
    ["settings.search.index"] = { module = "settings", label = "Settings search index built", kind = "rebuild", file = "TwichUI_Settings/Search.lua", where = "Search.Build", every = "once, first search" },
}

-- Code that carries no scope yet. A report whose TwichUI CPU is mostly outside every scope names these as the places
-- to add one next (a scope is `local pt = Perf.on and Perf.Start(id) ... if pt then Perf.Stop(pt) end`, or Perf.Wrap(id, fn)
-- for a hook or a frame's OnEvent, or Perf.Call(id, fn, ...)).
DX.UNSCOPED = {
    "hooksecurefunc / HookScript callbacks on other addons' or Blizzard's frames, except the RestedXP ones named rxp.* (Look.lua, Arrival.lua, WhatsTrainingSkin.lua, gear/Tooltip.lua, gear/Rolls.lua, markers/Bar.lua)",
    "private event frames not listed above: hazard/Alerts.lua, reminders/Display.lua, modules/Training.lua, modules/FriendLogin.lua, chronicle/Recorder.lua, auction/Window.lua, auction/Scan.lua",
    "C_Timer callbacks (modules/Restock.lua, setup/Share.lua, npcs/Share.lua, setup/Group.lua, pins/PingMap.lua, chronicle/Recorder.lua, qol/Guide*.lua)",
    "other OnUpdate scripts: Look.lua (settings-window easing), guides/CozyBagWindow.lua, setup/Window.lua (transfer line), setup/Share.lua, setup/StoredData.lua, setup/Explorer.lua (background jobs), classbars on-bar scripts",
    "tooltip post-calls and bag/inventory scans in gear/, auction/ and modules/ that run from game callbacks rather than TwichUI's event bus",
}

-- The description of an operation id: the module's own (R.Perf.Describe), the catalog's, or one made from the id.
function DX.Op(id)
    local d = Perf.ops[id] or DX.OPS[id]
    if d then return d end
    local event = type(id) == "string" and id:match("^event:(.+)$")
    if event then
        return { module = "events", label = "Callbacks for " .. event, kind = "event", file = "Core.lua",
            where = "R.frame's OnEvent dispatch; the listeners are each module's R:On(\"" .. event .. "\", fn)", every = "per event the client sends" }
    end
    return { module = (type(id) == "string" and id:match("^([%w_]+)%.")) or "other", label = id, kind = "other" }
end

---------------------------------------------------------------------------
-- Built-in gauges
---------------------------------------------------------------------------
local scratch = {}
local function Listeners()
    if not R.ListenerCounts then return nil end
    for k in pairs(scratch) do scratch[k] = nil end
    R.ListenerCounts(scratch)
    local total = 0
    for _, n in pairs(scratch) do total = total + n end
    return total
end
local function Events()
    if not R.ListenerCounts then return nil end
    local n = 0
    for _ in pairs(scratch) do n = n + 1 end   -- after Listeners (gauges are read in order)
    return n
end
local function Snap(module)
    local M = R[module]
    if not (M and M.Snapshot) then return nil end
    local ok, s = pcall(M.Snapshot)
    return ok and type(s) == "table" and s or nil
end
local function Field(module, field)
    return function()
        local s = Snap(module)
        return s and DX.Num(s[field]) or nil
    end
end
local function Flag(v) if v == nil then return nil end return v and 1 or 0 end

local function AuctionPreview(field)
    return function()
        local A = R.Workshop and R.Workshop.AuctionUI
        return A and DX.Num(A.Snapshot()[field]) or 0
    end
end
local G = {
    { "auction.previewReads", "AH experimental pending read", "state", "core", AuctionPreview("reads") },
    { "auction.previewLiveResults", "AH experimental retained rows (max 500)", "cache", "core", AuctionPreview("liveResults") },
    { "auction.previewShown", "AH preview shown", "state", "core", AuctionPreview("shown") },
    { "auction.previewPages", "AH preview pages built (at most five)", "pool", "core", AuctionPreview("pages") },
    { "auction.previewEvents", "AH preview visible listeners", "listeners", "core", AuctionPreview("events") },
    { "auction.previewResults", "AH preview retained results", "cache", "core", AuctionPreview("results") },
    { "auction.previewSubscriptions", "AH preview shared-plan/stock observers", "listeners", "core", AuctionPreview("subscriptions") },
    { "auction.previewTimers", "AH preview refresh timer", "state", "core", AuctionPreview("timers") },
    { "auction.previewJobs", "AH preview pending catalog jobs", "state", "core", AuctionPreview("jobs") },
    { "auction.catalogStarts", "AH catalog discovery starts", "counter", "core", AuctionPreview("catalog_starts") },
    { "auction.catalogCompleted", "AH catalog completions", "counter", "core", AuctionPreview("catalog_completions") },
    { "auction.catalogCanceled", "AH catalog cancellations", "counter", "core", AuctionPreview("catalog_cancellations") },
    { "auction.catalogErrors", "AH catalog errors", "counter", "core", AuctionPreview("catalog_errors") },
    { "auction.catalogActive", "AH active cooperative jobs", "state", "core", AuctionPreview("catalog_active") },
    { "auction.catalogFilters", "AH cached filter projections", "counter", "core", AuctionPreview("catalog_projections") },
    { "auction.catalogMetadata", "AH relevant metadata events", "counter", "core", AuctionPreview("catalog_metadata") },
    { "auction.catalogPatches", "AH changed metadata rows", "counter", "core", AuctionPreview("catalog_patches") },
    { "auction.catalogRowUpdates", "AH individual visible row updates", "counter", "core", AuctionPreview("catalog_rowUpdates") },
    { "auction.catalogInvalidations", "AH source invalidations", "counter", "core", AuctionPreview("catalog_invalidations") },
    { "auction.catalogPaints", "AH result list presentations", "counter", "core", AuctionPreview("catalog_paints") },
    { "auction.catalogLongest", "AH longest catalog slice (ms)", "state", "core", AuctionPreview("catalog_longest") },
    { "auction.previewRows", "AH preview pooled rows", "pool", "core", AuctionPreview("rows") },
    { "core.listeners", "TwichUI event bus: listeners", "listeners", "core", Listeners },
    { "core.events", "TwichUI event bus: events listened for", "listeners", "core", Events },
    { "core.switchListeners", "Switch change listeners", "listeners", "core", function() return R.Switches and type(R.Switches.listeners) == "table" and #R.Switches.listeners or nil end },
    { "core.settingsClosers", "Settings-closed callbacks", "listeners", "core", function() local L = R.SettingsLauncher return L and type(L.closers) == "table" and #L.closers or nil end },
    { "core.easing", "Window effects easing now", "state", "core", function() local M = R.Look and R.Look.Motion return M and M.Count and DX.Num(M.Count()) or nil end },
    { "settings.shown", "Settings window shown", "state", "settings", function() local UI = R.SettingsUI return Flag(UI ~= nil and UI.IsShown() or false) end },
    { "settings.sampleScenes", "Settings sample renderers kept (maximum four)", "pool", "settings", function()
        return R.SettingsCompanion and R.SettingsCompanion.SceneCount() or 0
    end },
    { "settings.sampleShown", "Settings sample shown", "state", "settings", function()
        return Flag(R.SettingsCompanion ~= nil and R.SettingsCompanion.Active() ~= nil)
    end },
    { "settings.pagesDrawn", "Settings pages drawn (kept until a reload)", "cache", "settings", function()
        local UI = R.SettingsUI
        if not (UI and UI.Stats) then return nil end
        local ok, s = pcall(UI.Stats)
        return ok and type(s) == "table" and DX.Num(s.drawn) or nil
    end },
    { "settings.searchIndex", "Settings search index made", "cache", "settings", function()
        local UI = R.SettingsUI
        if not (UI and UI.Stats) then return nil end
        local ok, s = pcall(UI.Stats)
        return ok and type(s) == "table" and Flag(s.searchIndex) or nil
    end },
    { "map.open", "World map shown", "state", "map", function() return Flag(WorldMapFrame ~= nil and WorldMapFrame:IsShown() or false) end },
    { "npcs.map.pool", "NPC map markers made (pool)", "pool", "map", Field("NpcMap", "pool") },
    { "npcs.map.drawn", "NPC map markers in use", "pool", "map", Field("NpcMap", "drawn") },
    { "npcs.map.layouts", "NPC map layouts so far (module count)", "work", "map", Field("NpcMap", "layouts") },
    { "guildloc.records", "Guild Locations: live positions held", "state", "map", Field("GuildLoc", "records") },
    { "guildloc.tombstones", "Guild Locations: withdrawals held", "state", "map", Field("GuildLoc", "tombstones") },
    { "guildloc.buckets", "Guild Locations: senders rate-tracked", "pool", "map", Field("GuildLoc", "buckets") },
    { "guildloc.roster", "Guild Locations: roster entries indexed", "cache", "map", Field("GuildLoc", "roster") },
    { "guildloc.timers", "Guild Locations: timers outstanding", "state", "map", Field("GuildLoc", "timers") },
    { "guildloc.events", "Guild Locations: event registrations", "listeners", "map", Field("GuildLoc", "events") },
    { "guildloc.map.pool", "Guild Locations: map markers made (pool)", "pool", "map", Field("GuildLoc", "mapPool") },
    { "guildloc.map.drawn", "Guild Locations: map markers in use", "pool", "map", Field("GuildLoc", "mapDrawn") },
    { "guildloc.map.layouts", "Guild Locations: map layouts so far (module count)", "work", "map", Field("GuildLoc", "mapLayouts") },
    { "pins.map.pool", "Pin markers made (pool)", "pool", "map", Field("PinsMap", "pool") },
    { "pins.map.drawn", "Pin markers in use", "pool", "map", Field("PinsMap", "drawn") },
    { "map.detail.tiles", "Map detail tiles in use", "pool", "map", Field("MapDetail", "tiles") },
    { "map.detail.pooled", "Map detail tiles kept for reuse", "pool", "map", Field("MapDetail", "pooled") },
    { "nav.decodedTiles", "Navigation tiles decoded (cache)", "cache", "map", Field("NavData", "decodedTiles") },
    { "reminders.active", "Reminders running", "state", "group", Field("ReminderController", "active") },
    { "reminders.keys", "Reminders: observations listened for", "listeners", "group", Field("ReminderController", "keys") },
    { "reminders.timed", "Reminders: waiting on a time boundary (one timer each)", "listeners", "group", Field("ReminderController", "timed") },
    { "reminders.decisions", "Reminders: decisions so far (module count)", "work", "group", Field("ReminderController", "decisions") },
    { "reminders.designer.cards", "Reminders designer: condition cards made (pool)", "pool", "settings", Field("RemindersDesigner", "cards") },
    { "reminders.designer.pickerRows", "Reminders designer: picker rows made (pool)", "pool", "settings", Field("RemindersDesigner", "pickerRows") },
    { "junk.builder.cards", "Junk rule builder: condition cards made (pool)", "pool", "settings", Field("JunkBuilder", "cards") },
    { "junk.builder.groups", "Junk rule builder: group boxes made (pool)", "pool", "settings", Field("JunkBuilder", "groups") },
    { "junk.builder.open", "Junk rule builder: window open", "state", "settings", Field("JunkBuilder", "open") },
    { "reminders.designer.open", "Reminders designer: an editor or picker open", "state", "settings", Field("RemindersDesigner", "open") },
    { "partyDeath.events", "Party member fallen: events registered", "listeners", "group", Field("PartyDeath", "events") },
    { "partyDeath.tracked", "Party member fallen: members tracked", "state", "group", Field("PartyDeath", "tracked") },
    { "healer.events", "Healer Watch: events registered", "listeners", "group", Field("HealerWatcher", "events") },
    { "workshop.queue", "Workshop: recipes queued (this character)", "state", "core", Field("Workshop", "queue") },
    { "workshop.recipes", "Workshop: recipes held while the window is open", "cache", "core", Field("Workshop", "recipes") },
    { "workshop.cache", "Workshop: recipe details remembered while the window is open", "cache", "core", Field("Workshop", "cache") },
    { "workshop.events", "Workshop: events registered (zero while the window is hidden)", "listeners", "core", Field("Workshop", "events") },
    { "workshop.rows", "Workshop: list rows made (pool)", "pool", "core", Field("Workshop", "rows") },
    { "workshop.prices", "Workshop: items with a saved price (newest scan of this realm)", "state", "core", Field("Workshop", "prices") },
    { "workshop.history", "Workshop: items with saved price history (newest scan of this realm; bounded per market)", "state", "core", Field("Workshop", "history") },
    { "workshop.vendor", "Workshop: items with a saved vendor price (at most 400)", "state", "core", Field("Workshop", "vendor") },
    { "workshop.stored", "Workshop: item counts remembered from the bank and guild banks (bounded)", "state", "core", Field("Workshop", "storedItems") },
    { "workshop.bankEvents", "Workshop: bank events registered (a few always; more only while a bank is open)", "listeners", "core", Field("Workshop", "bankEvents") },
    { "workshop.advisorItems", "Workshop: discovered item identities (released when Advisor hides)", "cache", "core", Field("Workshop", "advisorItems") },
    { "workshop.advisorResults", "Workshop: matching Advisor results", "cache", "core", Field("Workshop", "advisorResults") },
    { "workshop.marketFacts", "Workshop: items whose market figures are cached for display (at most 48)", "cache", "core", Field("Workshop", "marketFacts") },
    { "workshop.picks", "Workshop: source choices held on the shopping list (this session)", "state", "core", Field("Workshop", "picks") },
    { "camping.events", "Camping bar: events registered", "listeners", "core", Field("Camping", "events") },
    { "camping.buttons", "Camping bar: buttons made (pool)", "pool", "core", Field("Camping", "buttons") },
    { "camping.rest.events", "Camping bar: sleeping bag bar events registered", "listeners", "core", Field("CampingRest", "events") },
    { "camping.rest.ticks", "Camping bar: sleeping bag bar clock ticks so far (module count)", "work", "core", Field("CampingRest", "ticks") },
    { "camping.looks", "Camping bar: looks so far (module count)", "work", "core", Field("Camping", "looks") },
    { "loot.victories", "Loot victories: queued and showing", "state", "core", Field("LootRolls", "victories") },
    { "loot.retainedDisplays", "Loot rolls: recent presentation snapshots", "cache", "core", Field("LootRolls", "retainedDisplays") },
    { "loot.victoryPool", "Loot victories: artwork frames made", "pool", "core", Field("LootRolls", "victoryPool") },
    { "loot.victoryEvents", "Loot victories: native win event relay", "listeners", "core", Field("LootRolls", "victoryEvents") },
    { "loot.events", "Loot Rolls: events registered", "listeners", "core", Field("LootRolls", "events") },
    { "loot.records", "Loot Rolls: roll records held (bounded, this session)", "state", "core", Field("LootRolls", "records") },
    { "loot.cards", "Loot Rolls: card frames made (pool)", "pool", "core", Field("LootRolls", "pool") },
    { "loot.parked", "Loot Rolls: the game's roll frames stepped aside", "state", "core", Field("LootRolls", "parked") },
    { "loot.scheduled", "Loot Rolls: automatic choices counting down", "state", "core", Field("LootRolls", "scheduled") },
    { "buffback.events", "Return the Favor: events registered", "listeners", "core", Field("BuffBackWatch", "events") },
    { "buffback.rows", "Return the Favor: rows made (pool)", "pool", "core", Field("BuffBackList", "rows") },
    { "glows.events", "Action bar glows: events registered", "listeners", "core", Field("BarGlowController", "events") },
    { "glows.overlays", "Action bar glows: glow frames made (pool)", "pool", "core", Field("BarGlowController", "overlays") },
    { "glows.glowing", "Action bar glows: buttons glowing now", "state", "core", Field("BarGlowController", "glowing") },
    { "glows.buttons", "Action bar glows: action buttons found", "cache", "core", Field("BarGlowController", "buttons") },
    { "glows.active", "Action bar glows: reminders due and allowed", "state", "core", Field("BarGlowController", "active") },
    { "healer.fx.motes", "Healer Watch: particle textures made (pool)", "pool", "group", Field("HealerDisplay", "fxMotes") },
    { "healer.fx.bursts", "Healer Watch: particle bursts so far (module count)", "work", "group", Field("HealerDisplay", "fxBursts") },
    { "classbars.events", "Class bars: events registered", "listeners", "group", Field("ClassBars", "events") },
    { "bag.offer.events", "Cozy Bag offer: events registered", "listeners", "core", Field("CozyBagOffer", "events") },
    { "bag.offer.looks", "Cozy Bag offer: looks so far (module count)", "work", "core", Field("CozyBagOffer", "looks") },
    { "bag.button.built", "Cozy Bag button frame made", "pool", "core", function() local s = Snap("CozyBagButton") return s and Flag(s.built) or nil end },
    { "bag.button.shown", "Cozy Bag button shown", "state", "core", function() local s = Snap("CozyBagButton") return s and Flag(s.shown) or nil end },
}
for _, g in ipairs(G) do
    Perf.Gauge(g[1], { label = g[2], kind = g[3], group = g[4], unit = "count", read = g[5], builtin = true })
end

-- Keep Host metrics out of the legacy capture's first-40 budget. The scoped
-- Auction House preset selects these builtin gauges without displacing existing
-- core/settings measurements. All reads are passive snapshots.
for _, entry in ipairs({ {"hostState", "stateCode"}, {"hostPending", "pending"},
    {"host_failed", "failed"}, {"host_restoreFailed", "restoreFailed"},
    {"host_switches", "switches"}, {"host_openMS", "openMS"},
    {"host_firstLoadMS", "firstLoadMS"},
    {"host_restoreMS", "restoreMS"}, {"host_switchMS", "switchMS"} }) do
    local field = entry[2]
    Perf.Gauge("auction." .. entry[1], { label = "Auction House " .. field, kind = "state", group = "auction", builtin = true,
        unit = field:match("MS$") and "ms" or "count", read = function()
            local s = Snap("AuctionHost")
            return s and DX.Num(s[field]) or 0
        end })
end
for _, field in ipairs({"pages", "events", "rows", "jobs", "timers", "subscriptions", "reads"}) do
    Perf.Gauge("auction.lifecycle_" .. field, { label = "Auction House " .. field, kind = "state", group = "auction", builtin = true,
        unit = "count", read = AuctionPreview(field) })
end

for _,field in ipairs({"pending","listeners","timers"}) do
    local key=field
    Perf.Gauge("auction.action_"..key,{label="Auction action "..key,kind="state",group="auction",builtin=true,unit="count",read=function()
        local w=R.Workshop;local t=w and w.AuctionActions
        local s=t and t.Snapshot();return s and s[key] or 0
    end})
end

-- The gauges a capture reads (groups nil: all), in registration order.
function DX.GaugeList(groups,ids)
    local out = {}
    -- A narrow preset can select passive proxies even before its addon loads,
    -- without competing with unrelated gauges for the unchanged first-40 cap.
    if ids then
        for _,id in ipairs(ids)do
            for _,g in ipairs(Perf.gauges)do
                if g.id==id and type(g.read)=="function"then out[#out+1]=g;break end
            end
            if #out>=40 then break end
        end
        return out
    end
    for _, g in ipairs(Perf.gauges) do
        local wanted = not groups
        if groups then
            for _, k in ipairs(groups) do if g.group == k or not g.builtin then wanted = true end end
        end
        if wanted and type(g.read) == "function" then out[#out + 1] = g end
        if #out >= 40 then break end
    end
    return out
end

for _,spec in ipairs({
    {"workshop.currentRawBytes","Current raw bytes","current_bytes","bytes"},
    {"workshop.historyRawBytes","Historical raw bytes","history_bytes","bytes"},
    {"workshop.currentDecodedRows","Decoded current rows","decoded_current_rows","count"},
    {"workshop.historyDecodedRows","Decoded historical rows","decoded_history_rows","count"},
    {"workshop.cold.parked","Paused historical decoder","parked_history","count"},
    {"workshop.cold.loadedParts","Loaded current parts","loaded_parts","count"},
    {"workshop.cold.checkedParts","Validated current parts","checked_parts","count"},
    {"workshop.cold.historyParts","Loaded historical parts","history_loaded_parts","count"},
})do
    local field=spec[3]
    Perf.Gauge(spec[1],{label=spec[2],kind="cache",group="workshop",builtin=true,unit=spec[4],read=function()
        local q=R.Workshop and R.Workshop.Summary;local value=q and q.Status()[field]
        return type(value)=="number" and value or value and 1 or 0
    end})
end
for _,spec in ipairs({{"pending","PendingCount"},{"references","CacheSize"}})do
    local method=spec[2]
    Perf.Gauge("workshop.cold."..spec[1],{label="Market "..spec[1],kind="cache",group="workshop",builtin=true,unit="count",read=function()
        local p=R.Workshop and R.Workshop.Pricing;return p and p[method]()or 0
    end})
end

-- Passive even before the Workshop loads. Never starts an engine or reads prices.
for _,spec in ipairs({{"known","Known recipes"},{"pending","Queued recipes"},{"waiting","Recipes awaiting prices"},
    {"settled","Settled recipe estimates"},{"retained","Recipe results retained"}})do
    local key,label=spec[1],spec[2]
    Perf.Gauge('workshop.opportunities.'..key,{label=label,kind='cache',group='workshop',builtin=true,unit='count',read=function()
        local w=R.Workshop;local session=w and w.Session
        return session and session.OpportunityStatus and session.OpportunityStatus()[key]or 0
    end})
end

-- Prepared counters must exist before the lazy Workshop addon loads so a cold
-- capture selects them. Reading only inspects existing state, never starts work.
for _,key in ipairs({'loads','bytes','hashes','verified','full','flag_words','cache_hits','pending','cancelled'})do
    Perf.Gauge('workshop.prepared.'..key,{label='Prepared current '..key,kind='cache',group='workshop',builtin=true,unit=key=='bytes'and 'bytes'or 'count',read=function()
        local q=R.Workshop and R.Workshop.Summary;local status=q and q.Status()
        return status and status.prepared and status.prepared[key]or 0
    end})
end
