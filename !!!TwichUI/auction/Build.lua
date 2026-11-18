-- Production remains false. The internal development archive stamps this field
-- only; saved debug preferences can never activate an ordinary release build.
TwichUI.AuctionBuild = {
    development = false,
    -- Per-operation native evidence is separate from presentation testing.
    -- Quote signature / hardware restrictions / completion remain unverified
    -- in the new presentation. Controllers and review forms remain testable.
    verified = {},
}
