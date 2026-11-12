-- Opt-in painted settings components. Artwork owns relief; native frames own input and geometry.
-- No page names, saved data, timers or configuration behavior belong here.
-- The implementation moved to the core (!!!TwichUI/CraftLook.lua) so load-on-demand windows such as the Workshop can draw with the same
-- painted sheets without loading this addon; R.SettingsCraft is that table, so every settings caller is unchanged:
--   Sheet(host, skin, opts), Frame(host), LegacyRails(shell, shown), Control(control, kind, when), Thumb(texture)
local R = TwichUI
R.SettingsCraft = R.CraftLook
