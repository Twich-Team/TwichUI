# W10 — Live merchant quote for the Craft Queue

Batch 12: **Implemented safe review/quote; purchasing Blocked**. The owner
explicitly authorized this fallback when Forever purchase sequencing could not
be verified. There is no Purchase button, no automatic buy and no simulated
success. Buy materials manually through the merchant's normal controls.

After Workshop has loaded and experimental consent remains enabled, opening a
merchant with a relevant outstanding ShoppingPlan buy material offers a compact
leather quote. It reads the current merchant's listings (never historical Vendor
prices), shows material icons/quality names, remaining need, live stock, whole
purchase quantities, copper per purchase and exact estimated total with coin
artwork. Partial, sold-out, non-gold/unreadable and missing listings are identified.
The first listing for each item is quoted, with stock conservatively treated as
items; duplicates are not aggregated. Whole bundles round down so quotes never
exceed outstanding demand. A remainder stays unquoted. Capacity is explicitly
unverified and insufficient/unknown money is shown. This is an estimate, never
spending authorization; there are no selected purchase controls in this fallback.

An owned planner completion listener exists only during an active merchant review
and updates pending plans; bag, merchant,
money and item metadata events refresh the quote, coalesced into one callback.
Queue changes use the planner's existing notifications. Bag events invalidate nested
material plans even while the main Workshop window is hidden. Refresh quote re-reads
everything. Pending plans and unknown root/nested/intermediate bag counts do not reuse
old need estimates or quote unverified outstanding needs.
Close/Escape dismiss for the visit. Merchant close/combat/Workshop suspension
clear rows and invalidate pending redraws; resume registers only owned work.
No preferences or behavior of Vendor Restock are changed. No saved data added.

## Source evidence and purchase blocker

Forever source `bebcb6bf309cf41b41bd74f8ca651e6a105b2676`:
`Blizzard_UIPanels_Game/Mainline/MerchantFrame.lua` uses
`C_MerchantFrame.GetItemInfo`, `GetMerchantItemID`, `GetMerchantItemCostInfo`,
`GetMerchantItemMaxStack` and `BuyMerchantItem`. `price` covers `stackCount`;
BuyMerchantItem takes item quantities in whole purchase steps. The existing
`modules/Restock.lua` records the same evidence. But `numAvailable` units are not
specified sufficiently for limited multi-item purchases. Restock also explicitly
states its purchase flow has not been observed in-game: it waits for bag arrival,
stops on timeout/error, and has its own independently consented target model.
That does not prove transaction completion/correlation for a changing Workshop
queue or interleaving selling/Restock purchases. Do not borrow Restock consent or
silently reinterpret an observed bag increase as success for Workshop.

To enable a purchase action later, obtain owner-directed native evidence for
bundle/limited-stock units, maximum transaction size, partial delivery, event
ordering, failures and interaction with Restock/selling. Then implement a separate
itemized selection and explicit confirm, bounded approved quantities/cost and
per-step revalidation of merchant identity, outstanding queue need/consent,
stock, price, funds, compatible bag capacity and protected/combat state. A changed
estimate must return to review; uncertain completion stops without retries. This
batch deliberately implements no transaction sequencing.

## Evidence and owner checks

[Structural merchant capture and reproduction](../evidence/batch12-merchant/README.md);
[combined verification and limitations](batch12-verification.md).

Unit-tested: synthetic live listing reads, bundles/partial stock, sold-out,
non-gold/missing/secret data, planning/unknown counts, caps/truncation, identity
change, combat/consent/held-queue rejection, dismissal and pending callback cleanup.
The quote is rare/event-driven and has a 512-row bound; no profiling scope added.
`MerchantReview.Stats()` reads only two booleans for troubleshooting. No claim of
measured performance or real-client verification.

Owner: load Workshop, queue recipes needing vendor materials, visit a matching
merchant; check common/rare names, long names at typical/narrow scales, remaining
quantities, bundle sizes, partial stock and exact copper total. Spend nothing via
TwichUI (there is no purchase action). Buy manually and verify bag events update
need; change queue and Refresh; try insufficient money, sold-out/unsupported costs,
merchant closing, Escape, combat and disabling Workshop. Confirm independent
Vendor Restock choices remain unchanged. All native checks remain unchecked.
