# Compact loot cards and independent rule actions

Loot Rules can choose a roll, change the card presentation, or do both. This extends
the existing roll model, controls, previews and victory renderer. It adds no global
display preference: an unmatched card remains Expanded.

## Actions and precedence

Each saved rule has `action = none | need | greed | pass` and
`display = none | expanded | collapsed`. The builder separates **Roll** and
**Card display**. A rule with both choices set to No change is marked **Needs
attention**, explains the no-op, and never participates in either decision.

Both channels read enabled, complete rules in the same top-to-bottom order:

1. Skip a rule with No change in the channel being evaluated, even if its conditions
   would be unknown. It cannot block that channel.
2. Skip a definite non-match. The first match with an explicit action wins.
3. Preserve the engine's conservative unknown semantics: an unknown stops only
   that channel, pending more item facts. It cannot block the other channel.

Thus a high-priority Need rule with no display action and a lower-priority
display-only Collapse rule can both apply. Reversing those rules still permits
Need. An explicit Expanded rule above a broad Collapse rule wins presentation.
Two conflicting roll actions retain the existing first-match/unknown behavior.

Display evaluation runs independently of the automation master switch, pause,
Need permission and upgrade-automation permission. It uses existing observed
upgrade facts, without authorizing an automatic choice. `Auto.lua` still owns
automatic decisions and its existing visible, cancellable countdown; `Roll.lua`
remains the only roll-submission path. Editing only presentation or toggling a
card preserves the existing automatic deadline.

Existing saved rules need no migration. Missing `display` reads as No change,
without writing that field into old saved data. Existing Need/Greed/Pass rules
keep their behavior. New blank rules start with both choices set to No change;
named automation templates retain their original roll actions. Display-only
rules save/load, duplicate, summarize as “Collapse card”/“Expand card,” and preview
with manual choices. They are never described as automatic rolls.

## Presentation and lifecycle

The established width is 384 UI pixels, multiplied by the player's existing card
scale. Mini active cards are 72 pixels high; Mini victories are about 67
(80 reference pixels at the renderer's existing 384/460 scale). Expanded cards
retain their layout, with room reserved for the new toggle.

Mini active cards reuse the same item tooltip, quality color, choice handlers,
availability restrictions and confirmation path. Manual Need/Greed/Pass targets
remain 62×26 pixels with artwork and labels. Scheduled rolls retain Roll now and
Stop auto roll. The thin bar and right-hand number use `Roll.Remaining`; the auto
countdown in the secondary line uses the existing scheduled fire time. Neither
creates a second authoritative clock. Long names fit at UTF-8 character boundaries;
the original name remains available in the item tooltip.

The toggle instantly changes this instance, without creating a card, choosing a
roll, restarting its timer, or changing saved rules. Rule-selected display and
the manual override belong to the unique roll key. Manual choice takes precedence
for the remainder of that instance. The existing stack already sums renderer
return heights, so all four card types reflow using their actual height, in both
growth directions, without reserving Expanded slots for Mini cards.

Confirmed victories copy the effective display and manual override from a unique
matching roll. To handle a winner arriving after the active record disappears,
the renderer retains at most 32 recent presentation snapshots for 60 seconds,
pruning on removal/acceptance, without an idle timer. Matching uses the full item
link and existing known self-winner/value checks across **both live and departed
instances**. It never indexes a preference by item ID or card slot.

An ambiguous match (including identical live/departed drops) uses the existing
native-alert fallback. A completely uncorrelated confirmed win uses Expanded,
without reevaluating unrelated rules. An accepted late match consumes its snapshot;
expired snapshots cannot supply a preference. Disable clears retention. Finished
notifications release their entry and any still-owned source override.

## Artwork and animation

The Mini victory is a separate layout of the existing pooled renderer: two-line
title and paired laurels, item, roll emblem/value, optional upgrade icon/tooltip,
and toggle. Nine slices of the supplied bronze/leather frame omit the Expanded
internal dividers and preserve corner proportions. The supplied victory cue plays
for both layouts and uses the existing Victory Sound option.

The Expanded motion, duration, envelopes and effect positions are unchanged.
Mini uses authored shorter sweep/particle paths and repositioned bursts, retaining
the same bright cores, rarity rise and easing rather than shrinking every effect.
Full uses twelve bounded paths; Subtle uses four; Off is static. Additive light
uses the measured supplied UVs and unclipped sweep canvas. The shared 1.85-second
reveal settles before the existing configured hold and fade. Layout switching
preserves animation time, played-sound state, and dismissal timer.

Existing `loot.layout`, `loot.tick`, `loot.victory.event` and `loot.victory.tick`
scopes cover the work. The added `loot.retainedDisplays` read-only gauge exposes
bounded retained snapshots (including expired entries awaiting lazy pruning).
No recurring work was added while cards are idle.

## Verification

See [captures and verification](evidence/loot-roll-compact/README.md). Offline and
simulator checks cover independent priorities/unknowns, no-ops, legacy/save-load
behavior, manual actions/restrictions, countdowns, toggles, mixed stacks, late and
ambiguous events, qualities, upgrade visibility, long names, intensities and
cleanup. Native Forever visual/input/taint verification has not been performed.
