# Try the TwichUI Auction House

Install or update TwichUI normally, then reload. The standard seven-addon package
contains the complete Auction House; no separate addon, custom ZIP or development
marker is required. Test Lab remains a development tool and is not needed.

1. Open `/tui settings`, choose **Workshop**, enable Workshop if needed, then enable
   **Use TwichUI Auction House (Experimental)**. Alternatively use `/tui ahdebug on`.
2. Visit an auctioneer. Use Browse, Shopping, Sell, My Auctions and Market normally.
   Click Search or Refresh to request live results. Opening pages never starts a scan.
3. Inspect listings and review quantities, exact totals, posting drafts or cancellation
   costs. Each final transaction button explains its native activation gate. TwichUI
   enables no transaction modes: Forever hardware/permission/completion checks remain
   outstanding. Saved Market research remains available independently.
4. Use **Blizzard Auction House** in the header, then the **TwichUI Auction House**
   return button to switch back during the same visit.
5. Turn the setting off, or use `/tui ahdebug off`, to return to Blizzard.

There is no proof command, acknowledgement or 30-second presentation limit.
The optional **Debug** button explains live requests, responses, empty/partial results,
errors, restoration and timing. For a detailed capture, load Diagnostics before your
visit and use `/tui perf start auction 2`.

Emergency recovery: `/tui ahproof restore`. Outside combat, `/tui ahdebug off` also
restores owned native anchors. If recovery is waiting for combat to end, leave combat
and retry; `/reload` clears temporary presentation state. Turn the setting off before
revisiting if you want Blizzard as your default. `/tui ahdebug status` reports the choice.

Please report your client build, the page/action, the Debug message, and any native
error or taint. Simulator results do not establish native Forever acceptance.
