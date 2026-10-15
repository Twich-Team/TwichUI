# Recipe: add a slash command

TwichUI's commands are words after `/tui` (or `/twichui`). They live in one ordered table, `COMMANDS`, in
`!!!TwichUI/Core.lua`, and `R.RunCommand` parses them: the first word picks the command (a unique prefix of its
name also works), and the rest of the line, trimmed, is passed as `arg` (a string, maybe `""`).
Add an entry to `COMMANDS`; never add a new `SLASH_` global (the only other one is `/way` in `!!!TwichUI/pins/Way.lua`).

## Steps
1. In `COMMANDS`, add one entry above the alias entries (the lines with `alias =`; find them with
   `grep -n 'name = "' '!!!TwichUI/Core.lua'`). An entry has `name`, `usage`, `desc`, `hidden` and `fn(arg)`:
   `{ name = "word", usage = "word", desc = "what it does", hidden = true, fn = function() if R.X then R.X.Toggle() else Unavailable("Feature name") end end },`
2. Keep `hidden = true`. `tests/test_commands.lua` requires `/tui help` to stay under 20 lines, and it prints 19
   now. Name the command in its feature's settings tooltip instead, as `pins` and `sell` do (a changed tooltip
   needs the contract fixture regenerated: `docs/recipes/add-switch.md` step 6).
3. Pick a name that does not start with `res`, `ver` or `abo`: the test types those prefixes and expects
   `restore`, `version` and `about`.
4. In `fn`, reach the feature through `R` and guard it, so a missing module gives a message instead of an error:
   `if R.X then R.X.Show() else Unavailable("Feature name") end` (`Unavailable` is a local function in Core.lua).
5. Chat output: `R.Print("format %s", value)`. For text that may contain `%`: `R.Print("%s", text)`. Print only
   in answer to the command, never from timers or events.
6. A command that opens settings calls `R:OpenSettings("pageKey")` (page keys: `docs/recipes/add-settings-page.md`).
   One that turns a feature on or off calls `R:SetEnabled("switchKey", on)`; never write `TwichUIDB` directly.
7. A second name for an existing command: `{ name = "other", alias = "word", hidden = true },` with the aliases.
8. `luac5.1 -p '!!!TwichUI/Core.lua'`, then
   `(cd tests && lua5.1 -e 'require("bit"); ROOT="../!!!TwichUI/"; REPO="../"; TESTS="./"' test_commands.lua)`
   (prints `COMMANDS TEST PASSED`), then `./tests/run.sh`.

## Worked example: `/tui sell` and `/tui training [level]` (from `COMMANDS` in `!!!TwichUI/Core.lua`)
```lua
    { name = "sell", usage = "sell", desc = "what selling ordinary food and drink would keep and sell (Mages; listed in the Mage options)", hidden = true, fn = function()
        if R.MageSellWindow then R.MageSellWindow.Toggle() else Unavailable("Selling ordinary food and drink") end
    end },
```
```lua
    { name = "training", usage = "training [level]", desc = "preview the new training card for a level", fn = function(arg)
        if not R.Training then Unavailable("New training") return end
        local level = (arg or ""):match("^(%d+)$")
        local ok, why
        if level then ok, why = R.Training.Preview(tonumber(level))
        elseif (arg or "") == "" then ok, why = R.Training.Preview()
        else ok, why = false, "Type /tui training, or /tui training 20 for another level." end
        if not ok then R.Print(why) end
    end },
```
An alias entry: `{ name = "journal", alias = "chronicle", hidden = true },`
