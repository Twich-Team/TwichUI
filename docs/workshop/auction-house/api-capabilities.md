# AH-0: Forever Auction House capabilities

Research date: 2026-11-14. Scope: feasibility and architecture only. No replacement
UI, gameplay requests, market schema changes or live-client operations were made.
Continue with [architecture](architecture.md), [integration](integration.md) and
the [implementation roadmap](implementation-roadmap.md).

AH-1a follow-up: an explicit, default-off anchor-only diagnostic and its
[lifecycle evidence/real-client checklist](lifecycle-proof.md) now exist.
Simulator evidence cannot establish native search or replacement compatibility;
real Forever acceptance is still pending.

## Evidence boundary

TwichUI baseline: `feature/workshop`, `13aa14f168bf34d2ec03dccecdbca407c68a071a`;
clean working tree, upstream `origin/feature/workshop`, fetched and equal before
research. Native Linux Git/WSL was used. `AGENTS.md`, `CLAUDE.md`, the relevant
engineering rules, testing/performance docs and current Workshop documents were
read. The explicit AH-0 request authorizes these documents and commits; the
generic research-only instruction to edit nothing does not override that request.

The read-only sibling `wow-ui-source` is on `forever` at
`4cd0ab752a77164f654ccbca9d0c1fe8dafceebe`; `version.txt` says **1.60.1.70888**.
This is a source snapshot, not evidence of the currently running game build.
There is no client executable/server implementation here. Generated API metadata
and Blizzard call sites prove exposed contracts, not server timing or permission
rules. Shared, Mainline, Classic and Camelot files coexist. Even this snapshot's
AH TOC has `AllowLoadGameType: mainline, cata, mists`; do not infer the runtime
family selection from the branch name or a Camelot filename. Record actual build,
loaded addon and item classification in later client checks.

Verification vocabulary:

| Label | Meaning in AH-0 |
|---|---|
| **Verified from source** | The pinned generated contract or inspected UI code contains the stated fact; runtime behavior remains untested |
| **Verified in simulator** | A simulator scenario actually established the behavior; **none run for AH-0** |
| **Verified in real client** | Genuine player/client evidence for this replacement; **none available** |
| **Inferred but unverified** | Proposed behavior or a conclusion beyond the source contract |
| **Unsupported** | No supported contract/evidence found for the claimed feature, or outside the approved safety boundary; not a claim of universal engine impossibility |

The screenshots were all **screenshot-reviewed** as design references. They are
illustrative data, not client evidence. No AH-0 runtime unit or simulator testing
is claimed. Static documentation/evidence checks are recorded in the roadmap.

## Source locators

Client locators below are relative to `../wow-ui-source/Interface/AddOns/` from
the TwichUI repository root, at the pinned revision above. Names after `:` identify
functions, event records or structures, which are more stable than line numbers.

| Locator | Source |
|---|---|
| API | [Blizzard_APIDocumentationGenerated/AuctionHouseDocumentation.lua](https://github.com/Gethe/wow-ui-source/blob/4cd0ab752a77164f654ccbca9d0c1fe8dafceebe/Interface/AddOns/Blizzard_APIDocumentationGenerated/AuctionHouseDocumentation.lua) |
| ENUM | [Blizzard_APIDocumentationGenerated/AuctionHouseEnumsDocumentation.lua](https://github.com/Gethe/wow-ui-source/blob/4cd0ab752a77164f654ccbca9d0c1fe8dafceebe/Interface/AddOns/Blizzard_APIDocumentationGenerated/AuctionHouseEnumsDocumentation.lua) |
| PIM | `Blizzard_APIDocumentationGenerated/PlayerInteractionManagerDocumentation.lua` |
| MANAGER | `Blizzard_UIPanels_Game/Shared/PlayerInteractionFrameManager.lua` |
| BOOT | `Blizzard_AuctionHouseUI/Shared/Blizzard_AuctionHouseUI_Bootstrap.lua` |
| FRAME | `Blizzard_AuctionHouseUI/Shared/Blizzard_AuctionHouseFrame.lua` |
| XML / TOC | `Blizzard_AuctionHouseUI/Shared/Blizzard_AuctionHouseFrame.xml` / `Blizzard_AuctionHouseUI/Blizzard_AuctionHouseUI.toc` |
| BROWSE / SEARCH | `Blizzard_AuctionHouseUI/Shared/Blizzard_AuctionHouseBrowseResultsFrame.lua` / `Blizzard_AuctionHouseSearchBar.lua` in the same directory |
| BUY / IBUY | `Blizzard_AuctionHouseUI/Shared/Blizzard_AuctionHouseBuyDialog.lua` / `Blizzard_AuctionHouseItemBuyFrame.lua` |
| CBUY | `Blizzard_AuctionHouseUI/Shared/Blizzard_AuctionHouseCommoditiesBuyFrame.lua` |
| SELL / ISELL / CSELL | `Blizzard_AuctionHouseUI/Shared/Blizzard_AuctionHouseSellFrame.lua` / `Blizzard_AuctionHouseItemSellFrame.lua` / `Blizzard_AuctionHouseCommoditiesSellFrame.lua` |
| OWN | `Blizzard_AuctionHouseUI/Shared/Blizzard_AuctionHouseAuctionsFrame.lua` |
| MAIL | `Blizzard_MailFrame/MailFrame.lua`, invoice rendering around lines 790–852 |
| TSCAN / TPOST / TPRICE | TwichUI `!!!TwichUI/auction/Scan.lua`, `Window.lua`, `Price.lua` |
| WSCAN / WAUTO | TwichUI `TwichUI_Workshop/Scan.lua`, `!!!TwichUI/WorkshopAuto.lua` |
| TSM | Read-only `../reference_addons/TradeSkillMaster/LibTSMWoW/Source/API/AuctionHouse.lua` and `AuctionHouseWrapper.lua` |
| MOVE | Read-only `../reference_addons/TradeSkillMaster/LibTSMWoW/Source/Service/Move.lua` |

TSM explicitly has Forever branches but is third-party corroboration, not an
authoritative client restriction specification. It is not a Git checkout here.
Its code was inspected only; no code was copied or executed. Auctionator is not
present as a standalone reference addon; LibAHTab and TwichUI's Auctionator skin
are available. No new reference checkout or supporting-repository edit was made.

## Capability verdict

| Area | Confirmed contract | Practical verdict / remaining gate |
|---|---|---|
| Frame replacement | Auctioneer lifecycle events, load-on-demand Blizzard UI, normal frame and switchable presentation | **Conditionally viable**, not client-validated. Hiding the shown Blizzard root closes the AH. Reversible offscreen presentation is a candidate requiring AH-1 client acceptance |
| Browse | Browse query, item-key detail query, class/quality filters, sorts, partial-result APIs | Ready to implement behind lifecycle gate; no fixed 50-result/page guarantee |
| Buy | Item auction-ID bid/buyout; commodity quantity quote/confirm contracts | Ready to design; enable each mode only after classification, click permissions, quote signature and completion checks in client |
| Sell | Bag `ItemLocation`, validity/count/deposit, item/commodity posting and warning confirmation | Ready to implement with existing safeguards; arbitrary stack-size posting is not established |
| My Auctions | Owned records, ID, quantity, status, optional time, query and cancel event | Active/cancel view feasible; disappearance is unknown outcome. Revenue/sell-rate panel is unsupported today |
| Market | Existing saved listing observations and valuation services | Read-only integration feasible; demand, sales confidence and seller population are not derivable from current saved data |

All confirmed entries in this table are **Verified from source**, not simulator
or real-client acceptance of the replacement.

## Reading the API matrices

All `C_AuctionHouse` names below use that namespace unless another is written.
`K` means `{itemID, itemLevel=0, itemSuffix=0, battlePetSpeciesID=0}`;
`Sort[]` means `{sortOrder=Enum.AuctionHouseSortOrder.*, reverseSort=bool}`.
Indices marked `luaIndex` are one-based; replicate records use the separately
specified numeric index (existing WSCAN starts at zero).

**R** means the generated API explicitly has `HasRestrictions = true`.
**S** means `SecretArguments = "AllowedWhenUntainted"` is declared. This is
metadata, not permission to manipulate secret values. **N** means no explicit
`HasRestrictions` flag in this record; it does **not** prove unrestricted,
combat-safe or hardware-independent execution. The native restriction details
are unavailable. Later buy/post/cancel calls must originate in the player's
explicit action and be revalidated centrally, irrespective of N/R. No timer,
event callback or button programmatic click may initiate a spend/post/cancel.
Each matrix row is **Verified from source** for its contract only unless stated
otherwise. Required contexts are the UI's supported use, not experimentally
discovered engine preconditions.

## Lifecycle and presentation matrix

| API/event | Parameters/results and purpose | Context / restrictions | Evidence and limitations |
|---|---|---|---|
| `PLAYER_INTERACTION_MANAGER_FRAME_SHOW/HIDE` | Payload `type: PlayerInteractionType`; match `Enum.PlayerInteractionType.Auctioneer` | Event handlers; deduplicate with AH events | PIM event records; MANAGER:OnEvent. Documented synchronous; relative order with other AH events unverified |
| `AUCTION_HOUSE_SHOW`, `AUCTION_HOUSE_CLOSED`, `AUCTION_HOUSE_DISABLED` | No payload; available/ended/unavailable signals | Session availability, never proof a frame is visible | API event records; WSCAN handles close/disabled |
| `C_PlayerInteractionManager.IsInteractingWithNpcOfType(type)` / `IsValidNPCInteraction(type)` | `bool` current interaction / validity | S; available API check before use | PIM. Candidate supplemental context checks; actual auctioneer behavior untested |
| `AuctionHouseFrame_LoadUI()` | `LoadAddOnWithErrorHandling(AddonName)` result | Loads `Blizzard_AuctionHouseUI` on demand | BOOT and TOC; never substitute loading for a valid auctioneer interaction |
| `ShowAuctionHouseFrame()` / `HideAuctionHouseFrame()` | Load + `ShowUIPanel(root)` / `HideUIPanel(root)` if loaded | Blizzard bootstrap functions; ordinary UI presentation | BOOT; root OnShow can search favorites and open bags |
| `RegisterPlayerInteraction(type, frameInfo)` | Frame name + optional load/show/hide functions; replaces private registry entry | MANAGER's supported Lua registration pattern; combat/taint unverified | MANAGER has no public getter/unregister. Overriding ownership can clobber another addon; not the recommended first approach |
| `SetPlayerInteractionConditions(type, conditions)` | Optional load/show/hide predicates | Replaces private condition entry | MANAGER + BOOT: trial-mode gate. Do not replace or bypass it |
| `AuctionHouseFrameMixin:OnHide()` | Unregisters events, resets browse, clears posting, closes popups/bags, calls `CloseAuctionHouse()` | Any actual hide, including through hidden parent | FRAME:448. A secure post-hook cannot prevent the close that already occurred |
| `CloseAuctionHouse()` | No args/results | Actual close only; N | API + FRAME:OnHide. Idempotent cleanup required; never call while merely switching appearances |
| `ADDON_LOADED(name)` | Gate attach/build on named addon and current readiness | Also inspect already-loaded state | FRAME:OnLoad/OnEvent; TPOST:Attach/PLAYER_LOGIN. One-time hooks; late and failed load paths needed |

XML defines `AuctionHouseFrame` under `UIParent`, hidden initially, without a
secure-template inheritance in that declaration. This does **not** establish
that it and all descendants can be manipulated safely in combat. Default to
Blizzard during combat. A shown frame can be moved/scaled without intentionally
calling Hide; TSM's modern path does this (MOVE:SetDefaultUIOffScreen;
TSM:SetSelectedTab/RestoreDefaultUI). Suitability on this client's panel manager,
input routing and bag behavior is **Inferred but unverified**.

## Browse/search matrix

| API/event | Parameters/results | Context / restrictions | Evidence and limitations |
|---|---|---|---|
| `SendBrowseQuery(query)` | `{searchString, sorts, minLevel?, maxLevel?, filters?, itemClassFilters?}`; no return | Open AH; S, N | API:AuctionHouseBrowseQuery; FRAME:SendBrowseQueryInternal. Browse groups item keys; not individual purchasable auctions |
| `GetFilterGroups()` / `GetAuctionItemSubClasses(classID)` | Filter groups / number[] subclasses | S on subclass call; N | API, ENUM; query classes `{classID, subClassID?, inventoryType?}`. Expose only applicable runtime filters |
| `GetBrowseResults()` | `BrowseResultInfo[]` (structure below) | Read current client cache; N | API + BROWSE:UpdateBrowseResults; contents may belong to another consumer |
| `HasFullBrowseResults()` / `RequestMoreBrowseResults()` | bool / request next results, no return | Open AH; N | API + BROWSE refresh callback; continuation, not numbered server pages. Server cap/page size unspecified |
| `AUCTION_HOUSE_BROWSE_RESULTS_UPDATED/ADDED/FAILURE` | None / `addedBrowseResults[]` / none | Match outstanding browse intent locally | API + BROWSE:OnEvent. No request ID or original query payload |
| `MakeItemKey(itemID, itemLevel?, itemSuffix?, species?)` | K; optional fields default zero | S, N | API; preserve all four identity fields |
| `GetItemKeyInfo(K, restrictQualityToFilter=false)` | Optional `ItemKeyInfo` | S, N | API + OWN summary line. Nil is pending/unknown; not commodity=false |
| `GetItemKeyFromItem(ItemLocation)` / `GetItemCommodityStatus(ItemLocation)` | K / Unknown, Item, Commodity enum | Bag item context; S, N | API; do not classify all cloth/ore as commodities from item name/class |
| `GetItemKeyRequiredLevel(K)` / `GetItemKeySampleLink(K)` | number / optional stripped sample link | S, N | API; sample removes player enchants/gems/reforges. Required level is not item level |
| `ITEM_KEY_ITEM_INFO_RECEIVED(itemID)` / `EXTRA_BROWSE_INFO_RECEIVED(itemID)` | Late metadata signals | Only update affected identities | API + OWN summary line. Query membership may need recomputation without resetting viewport |
| `SendSearchQuery(K, Sort[], separateOwnerItems, minLevel=0, maxLevel=0)` | Request details for an item key; no return | Open AH; S, N | API explicitly **100 calls/minute**. Not for enumerating the whole AH |
| `SendSellSearchQuery(K, Sort[], separateOwnerItems)` | Sell competition query | Open AH; S, N | API: same 100/minute wording; **clear itemLevel and suffix** first. Exact variant matching must happen after results |
| `GetNumItemSearchResults(K)` / `GetItemSearchResultInfo(K, index)` | count / optional `ItemSearchResultInfo` | S, N | API; quantity belongs to that record; buyout is total amount, not automatically unit price |
| `GetNumCommoditySearchResults(itemID)` / `GetCommoditySearchResultInfo(itemID, index)` | count / optional `CommoditySearchResultInfo` | S, N | API; unitPrice is per item; quantity/own quantity require careful exclusion |
| `GetItemSearchResultsQuantity(K)` / `GetCommoditySearchResultsQuantity(itemID)` | total quantity | S, N | API; a quantity is not a number of sellers or necessarily number of auction rows |
| `HasFullItemSearchResults(K)` / `HasFullCommoditySearchResults(itemID)` | bool | S, N | API; false means current read is incomplete |
| `RequestMoreItemSearchResults(K)` / `RequestMoreCommoditySearchResults(itemID)` | bool `hasFullResults` | Open AH; S, N | API; finish if true, otherwise await updates; no fixed page limit guaranteed |
| `RefreshItemSearchResults(K, minLevel?, maxLevel?)` / `RefreshCommoditySearchResults(itemID)` | Refresh detail cache | Open AH; S, N | API + FRAME:RefreshSearchResults. Serialize refreshes with queries |
| `ITEM_SEARCH_RESULTS_UPDATED/ADDED` | K, optional `newAuctionID` for UPDATED / K | Match full K and live intent | API; no request ID. Same-key old responses cannot be conclusively attributed |
| `COMMODITY_SEARCH_RESULTS_UPDATED/ADDED` / `COMMODITY_SEARCH_RESULTS_RECEIVED` | itemID / itemID / no payload | Match ID where available | API; no-payload event alone cannot identify a request |
| `AUCTION_HOUSE_NEW_RESULTS_RECEIVED` | optional K; nil for browse | Supplemental signal | API explicitly addon convenience. Not a unique request correlation mechanism |
| `IsThrottledMessageSystemReady()` | bool readiness | Open AH; N | API + TSCAN. Not a guarantee of remaining minute quota or exclusivity |
| `AUCTION_HOUSE_THROTTLED_SYSTEM_READY`, `...MESSAGE_SENT/QUEUED/RESPONSE_RECEIVED/DROPPED` | No payload | Shared client message system | API. Cannot reliably attribute a dropped message to one addon/request |
| `ReplicateItems()` / `REPLICATE_ITEM_LIST_UPDATE` | Whole-house observation request / no payload | Existing explicit Scan prices only; N | API + WSCAN. Not a list of purchase handles. No new automatic scan or query-all loop |

Query quality filters include `UsableOnly`, `ExactMatch`, Poor/Common/Uncommon/
Rare/Epic/Legendary/Artifact qualities; other version-oriented filters in ENUM
must be gated by runtime applicability. Sort enum: Price, Name, Level, Bid,
Buyout, TimeRemaining. Blizzard's FRAME limits its own sort preference list to
two; the generated API does not establish an independent server maximum.
The Camelot data file overrides the level-column choice to required level.
Do not label a required-level query range as item-level range without client
verification; preserve the mockup control position with an accurate label.

Client filtering of returned records is feasible (**Verified from source**:
TSCAN:Read/TPRICE:SummariseItems already filter exact variants). Counts/categories
derived from loaded results must say that scope. A zero filtered result is not
proof of no listings when the server result is partial. Exact-name can use the
query filter; "stacks only" is a local quantity predicate, not a documented
server filter. Missing metadata stays pending; never spin/request every catalog
identity. A UI page size of 50 is a local view preference, not a native API fact.

### Result structures and price units

| Structure | Documented fields relevant to the replacement |
|---|---|
| `BrowseResultInfo` | `itemKey, appearanceLink?, totalQuantity, minPrice, containsOwnerItem` |
| `ItemKeyInfo` | `itemID, battlePetSpeciesID, itemName, battlePetLink?, appearanceLink?, quality, iconFileID, isPet, isCommodity, isEquipment` |
| `ItemSearchResultInfo` | `itemKey, owners[], totalNumberOfOwners, timeLeft, auctionID, quantity, itemLink?, containsOwnerItem, containsAccountItem, containsSocketedItem, bidder?, minBid?, bidAmount?, buyoutAmount?, timeLeftSeconds?` |
| `CommoditySearchResultInfo` | `itemID, quantity, unitPrice, auctionID, owners[], totalNumberOfOwners, timeLeftSeconds?, numOwnerItems, containsOwnerItem, containsAccountItem` |
| `OwnedAuctionInfo` | `auctionID, itemKey, itemLink?, status, quantity, timeLeftSeconds?, timeLeft?, bidAmount?, buyoutAmount?, bidder?` |

API declares money primarily as `BigUInteger`. Do not assume ordinary safe Lua
integer arithmetic over its entire range. Preserve exact server totals; validate
finite, unsecret, representable amounts at the adapter boundary, use existing
`MAX_COPPER`/numeric guards, and refuse out-of-range actions. For item auctions,
display unit price as total/quantity with explicit display rounding, but send the
original buyout total. Do not reconstruct it from a rounded unit price.
Nil buyout is a bid-only listing, never free. Commodity unit pricing and preview
cost across tiers differ from purchasing an entire item-auction record.

## Buying matrix

| API/event | Parameters/results | Context / restrictions | Evidence and limitations |
|---|---|---|---|
| `PlaceBid(auctionID, bidAmount)` | No synchronous success value; buyout uses full `buyoutAmount` | Open AH, selected live ID, explicit confirmation; R/S | API + FRAME:BUYOUT_AUCTION/BID_AUCTION. Item buyout purchases whole record; no partial-quantity parameter |
| `GetAuctionInfoByID(auctionID)` | Optional `AuctionInfo`: K, link, minBid, bidAmount, buyoutAmount, bidder | S, N | API; candidate final recheck, not a server reservation |
| `AUCTION_HOUSE_PURCHASE_COMPLETED(auctionID)` | ID-correlated completion | Await pending item buyout | API + FRAME:BuyoutDialogOnEvent. Real emission and ordering still require supervised buy |
| `ITEM_PURCHASED(itemID)` / `BID_ADDED(bidID)` / `BIDS_UPDATED` | Item ID / bid ID / none | Supplemental inventory/bid evidence | API; item ID not enough to distinguish multiple purchases; a bid isn't a completed acquisition |
| `StartCommoditiesPurchase(itemID, quantity)` | Begins quote; no synchronous result | Open AH; R/S, explicit player action | **Contract discrepancy:** API lists two args; FRAME:StartCommoditiesPurchase passes a third unitPrice, as does TSM. Do not silently adopt another version's signature. Real-client quote gate required |
| `COMMODITY_PRICE_UPDATED(unitPrice, totalPrice)` / `COMMODITY_PRICE_UNAVAILABLE` | Authoritative updated quote / no quote | Only one active commodity intent | API + BUY:OnEvent; no item ID/token in these events |
| `GetQuoteDurationRemaining()` | Seconds until expiry | Live quote; N | API + BUY:OnUpdate; never hard-code quote lifetime |
| `ConfirmCommoditiesPurchase(itemID, quantity)` | Commits quoted purchase | Explicit player confirmation; S, N flag (hardware rule unknown) | API + BUY:BuyNow. Revalidate item, quantity, total and quote lifetime. Changed price needs fresh consent |
| `CancelCommoditiesPurchase()` | Abandons quote | On cancel/close/switch; N | API + BUY:OnHide. Does not roll back a completed purchase |
| `COMMODITY_PURCHASE_SUCCEEDED/FAILED` | No payload | Single serialized pending operation | API + BUY:OnEvent. Uncorrelated; another addon can cause ambiguity |
| `COMMODITY_PURCHASED(itemID, quantity)` | Acquisition detail | Supplemental matching signal | API. Completion does not prove item delivered into bags; delivery may be delayed |
| `AUCTION_HOUSE_SHOW_ERROR(error)` | AuctionHouseError enum | May be global to another operation | API + FRAME; errors include not enough money, unavailable item, own bid, higher bid, database failure |

Blizzard source uses explicit accept dialogs for item bids/buyouts and a
quote/Buy Now dialog for commodities. User action is a **design requirement** for
every transaction, and R calls have an additional native restriction marker.
It would be inaccurate to claim every operation's exact hardware requirements
were established by Lua source. Do not call any spending API from AH-0 probes.

Vanished auctions: recheck ID/amount, handle error as refused or unknown, clear
the armed action, offer player-initiated refresh. Never substitute the next row
or a dearer tier. A timeout alone does not prove failure; reconcile before a
retry. Commodity aggregate quantity buying exists in the exposed contracts,
but which Forever items actually use that path remains unverified.

## Selling matrix

| API/event | Parameters/results | Context / restrictions | Evidence and limitations |
|---|---|---|---|
| `C_Container.GetContainerItemInfo(bag, slot)` + `ItemLocation` | Bag identity/count/lock data; construct bag-slot location | Current bags; read only | TPOST:bag grouping/Location; SELL:SetItem takes location directly, no cursor pickup required |
| `IsSellItemValid(location, displayError=true)` | bool | Selected live item; S, N | API + SELL:SetItem. Eligibility is authoritative here, not just binding/category heuristics; closed-AH behavior unknown |
| `GetAvailablePostCount(location)` | Count available for listing | S, N | API + SELL:GetMaxQuantity. Count semantics depend on item/commodity mode |
| `SupportsCopperValues()` | bool price precision | N | API + SELL price input + TPOST. Query rather than hard-code copper support |
| `CalculateCommodityDeposit(itemID, durationIndex, quantity)` / `CalculateItemDeposit(location, durationIndex, quantity)` | Optional deposit cost | Open AH, valid draft; S, N | API + CSELL/ISELL:UpdateDeposit. Nil means unavailable; commission is not included |
| `PostCommodity(location, durationIndex, quantity, unitPrice)` | bool `needsConfirmation` | Player Post click; R/S | API + CSELL:StartPost; returned false is not posting failure or proof of success |
| `PostItem(location, durationIndex, quantity, bid?, buyout?)` | bool `needsConfirmation` | Player Post click; R/S | API + ISELL:StartPost; existing TPOST lists quantity single-item auctions. No separate stackSize argument |
| `ConfirmPostCommodity(...)` / `ConfirmPostItem(...)` | Same draft args, no result | Player warning accept; R/S | API + CSELL/ISELL:ConfirmPost. Do not reuse Blizzard's warning callback for a different pending draft |
| `AUCTION_HOUSE_POST_WARNING/POST_ERROR` | No payload | Pending posting only | API + FRAME:OnEvent/ShowPostConfirmationDialog; default warning delegates to Blizzard sell frames. Replacement needs its own correctly bound consent flow |
| `AUCTION_HOUSE_AUCTION_CREATED(auctionID)` | Created ID | Correlate single pending post, then refresh owned state | API describes addon convenience signal; an attempted call is not success |
| `AUCTION_MULTISELL_START/UPDATE/FAILURE` | repetitions / createdCount,totalToCreate / none | Native authorized batch progress | API + ISELL:OnEvent. Partial creation possible; don't equate first creation with entire batch success |
| `CancelSell()` | Stops remaining native multisell | Player cancel or context teardown; N | API + ISELL:OnHide. Already created listings remain; not cancellation of those auctions |

Duration choices are **indices 1–3**, using `AUCTION_DURATION_ONE/TWO/THREE`
(SELL:AuctionHouseAlignedDurationMixin). The local snapshot doesn't establish
the localized hour strings. Use the game's labels; the mockup's 12/24/48 hours
must pass real-client verification. Don't pass hours as duration indices.

Eligibility error enum includes bound, conjured, damaged, charges-used, wrapped,
nonempty bag, limited-duration and other failures (ENUM:AuctionHouseError).
Checking `IsSellItemValid`, count, item identity, locks, money/deposit and combat
again at click time is necessary. Listing slots can move after bag updates.

No API here takes an arbitrary legacy `stackSize × numberOfStacks` posting
pair. Quantity editing is supported; arbitrary stack construction through bag
splitting is **Unsupported for the minimum replacement**. Follow runtime item
classification and Blizzard's posting model; do not add automatic bag splitting.
Existing TPOST already has a below-vendor confirmation with a hold and binds it
to draft identity; preserve it, along with combat/throttle/price validation.

## My Auctions, fees and outcomes matrix

| API/event | Parameters/results | Context / restrictions | Evidence and limitations |
|---|---|---|---|
| `QueryOwnedAuctions(Sort[])` | Requests player's listing snapshot | Open AH; S, N; one serialized read | API + FRAME:QueryAll/OWN:RefreshSearchResults |
| `GetOwnedAuctions()` / `GetNumOwnedAuctions()` / `GetOwnedAuctionInfo(index)` | Array / count / optional owned record | Read current cache; S on indexed accessor, N | API. No listing-created timestamp, original quantity or proceeds field |
| `HasFullOwnedAuctionResults()` | bool | Read completeness | API; incomplete absence cannot resolve outcomes. No RequestMoreOwnedAuctions API is declared |
| `OWNED_AUCTIONS_UPDATED` | No payload | Reconcile by auctionID | API + OWN:OnEvent. It means cache changed, not sale |
| `GetTimeLeftBandInfo(band)` | Min/max seconds for band | S, N | API + ENUM:TimeLeftBand. Use range when exact seconds absent; no invented minute-precise expiry |
| `CanCancelAuction(ownedAuctionID)` / `GetCancelCost(id)` | bool / cancellation cost | Current own active listing; S, N | API + FRAME:CANCEL_AUCTION; recheck at accept time |
| `CancelAuction(ownedAuctionID)` | No synchronous success value | Player accept; R/S | API + FRAME:CANCEL_AUCTION. Cancellation isn't free by assumption |
| `AUCTION_CANCELED(auctionID)` | ID-confirmed cancel signal | Match pending own ID | API + OWN:OnEvent; return of items can be delayed |
| `AUCTION_HOUSE_AUCTIONS_EXPIRED(auctionID)` | ID-specific expiry | Track only current session evidence | API; don't infer that every disappearance emits it |
| `AuctionStatus.Active/Sold` | Owned record status enum 0/1 | Read returned status exactly | API. Sold is server-reported sale state, not proof of proceeds collected |
| `AUCTION_HOUSE_SHOW_FORMATTED_NOTIFICATION(notification, text, auctionID?)` / `...SHOW_NOTIFICATION(notification)` | Notification enum; optional ID on formatted event | Sale/expiry/outbid/etc hint | API + ENUM:AuctionHouseNotification. Optional identity, no amount; never parse localized text into ledger data |
| `GetInboxInvoiceInfo(index)` | Invoice type, item/player names, bid, buyout, deposit, consignment, delay/ETA, count, commerce flag in MAIL call site | Mailbox, not AH; protected details not established by AH API metadata | MAIL: seller renders `bid + deposit - consignment`; temporary invoice means pending funds. No auctionID in these shown returns; no reliable ID join established |
| Existing `R.MailGold` | Matches requested mail money with PLAYER_MONEY gain, per visit | Actual mail collection, no persistence | `!!!TwichUI/auction/Mail.lua`; includes non-auction money. Not a sales ledger or per-item realized revenue |

No authoritative prospective commission-rate getter was found in the AH API
snapshot. `Prices.CUT` remains unconfirmed; don't assume 5% or neutral/faction
rules. Deposit and cancel-cost APIs can show quoted costs, while seller invoices
may establish historical consignment for that invoice after a future supervised
check. Seller invoices and Sold status can support qualified sale evidence, but
they do not supply a validated durable listing-to-payment ledger. That work is
deferred; no data schema is changed in AH-0.

Reposting requires cancellation confirmation, item return/availability, then a
new validated Sell draft and separate Post action. It is not an atomic API and
must not run from `AUCTION_CANCELED`. "Selling well", sell rate, time-to-sell,
actual per-item revenue and demand are **Unsupported** by current Workshop data.

## Major unresolved gates

1. **Lifecycle, critical:** reversible frame parking, panel-manager reposition,
   popup/input focus, bags, Escape, close/error recovery and restoration in the
   actual Forever client; combat/reload and other addon interaction.
2. **Transactions, critical:** native permissions for each restricted call and
   confirmation; genuine event payload/timing, rejected/expired listings, money
   effects and delayed delivery. No AH-0 transaction was attempted.
3. **Commodity mode, high:** actual classification for Forever trade goods,
   quantity/stack semantics, StartCommoditiesPurchase's 2-vs-3-argument discrepancy.
4. **Live query ownership, high:** same-key stale responses and no-payload global
   events cannot be reliably correlated when other addons send concurrently.
5. **Market identity, high:** `UnitFactionGroup("npc")` is WSCAN's current rule,
   not proven neutral/cross-faction partitioning. Keep unknown separate; test a
   faction and neutral auctioneer before promising partition accuracy.
6. **Fees/outcomes, medium:** actual duration labels, copper precision, cancel
   fees, exact expiry availability, Sold/expiry notification behavior and invoice
   evidence. Unsupported statistics stay unavailable until separately verified.

These are implementation/release gates, not reasons to invent engine facts or
extend AH-0 into interface implementation.
