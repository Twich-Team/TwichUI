# Development branches

Protected **main → short-lived feature/fix branch → reviewed PR → main** is the permanent TwichUI workflow.
Main is the single development baseline. Candidates use exact verified commits, immutable artifacts
and explicit owner-authorized release workflow dispatch. Pushes, tags and PR merges do not publish. Respect any configured publication hold; only the owner authorizes release.

Final main-to-Workshop synchronization: [PR #41](https://github.com/Twich-Team/TwichUI/pull/41), merged
at `0f25a23ddd1b0acf8ea269c508417ae8717b3629`. Both histories are preserved. Complete tree
`7d6bdac4aa86f83dd41f39116579bfa46d1ca95c` equals main `3a33269fc75d9daa5c24525c4e66f0095e2a194f`.
Workshop's only exclusive pre-sync commit was its earlier synchronization merge; no runtime work was
dropped. Focused Workshop/core/Settings/AH/release checks passed. M2 starts from and targets main.

Keep `feature/workshop` and `release/v1.3` as historical branches, not feature bases or integration
targets. Do not delete them during M2. Retire only after reviewing unique merge history, recording
immutable archival refs and PR links, verifying source preservation on main, and updating owner
tools/docs depending on those branch names. No new permanent release branch is needed.

This policy applies to TwichUI. Market retains its separately approved integration/deployment branches.
