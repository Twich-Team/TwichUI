-- TwichUI: troubleshooting report, environment
-- Versions, the client, optional addons and libraries, EllesmereUI, and which TwichUI switches are on.
-- Nothing here names the player: no character, realm, guild or account details.
-- Where a value cannot be read it says "unknown" and why, rather than guessing.

local R = TwichUI
local D = R.Diag

-- Addons TwichUI works with when they are there; none is required.
local OPTIONAL_ADDONS = {
    "EllesmereUI", "EllesmereUIBlizzardSkin", "Auctionator", "WhatsTraining", "ForeverDungeonJournal",
    "Attune", "Leatrix_Plus",
}
-- Libraries TwichUI carries itself (LibStub shares one copy between addons, so the loaded copy may be
-- another addon's newer one) and ones it only uses if something else provides them.
local BUNDLED_LIBS = { "CallbackHandler-1.0", "LibSharedMedia-3.0", "AceComm-3.0", "LibSerialize", "LibDeflate" }
local EXTERNAL_LIBS = { "LibDataBroker-1.1", "LibAHTab-1-0" }

local function Metadata(addon, field)
    local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    if not get then return nil end
    local ok, value = pcall(get, addon, field)
    if ok and type(value) == "string" and value ~= "" and not value:find("^@") then return value end
    return nil
end

local function Presence(addon)
    local state = R.Setups and R.Setups.AddonState and R.Setups.AddonState(addon)
    local loaded = C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded(addon)
    if state == "missing" then return "not installed" end
    if state == "disabled" then return "installed, turned off" end
    if loaded then return "loaded" end
    if state == "ready" then return "installed, not loaded yet" end
    return "unknown (the addon list could not be read)"
end

local function Library(name)
    if not LibStub then return "unknown (LibStub is not available)" end
    local lib, minor = LibStub:GetLibrary(name, true)
    if not lib then return "not available" end
    return "available" .. (minor and (", revision " .. tostring(minor)) or "")
end

-- Which of the settings are on, as two lists of keys: the report's compact view of "configured".
local function Switches()
    local on, off = {}, {}
    for key in pairs(R.DEFAULT_MODULES or {}) do
        if R:Enabled(key) then on[#on + 1] = key else off[#off + 1] = key end
    end
    table.sort(on)
    table.sort(off)
    return on, off
end

local function Environment()
    local lines = {}
    local function Line(fmt, ...) lines[#lines + 1] = fmt:format(...) end

    local version = Metadata(R.ADDON, "Version")
    Line("TwichUI version: %s", version or "unknown (the addon list gave no version)")
    Line("TwichUI build: unknown (this package carries no commit or build identifier; the version above is all it records)")
    local toc = Metadata(R.ADDON, "Interface")
    local clientVersion, clientBuild, _, clientToc
    if GetBuildInfo then clientVersion, clientBuild, _, clientToc = GetBuildInfo() end
    Line("client: version %s, build %s, interface %s",
        clientVersion and tostring(clientVersion) or "unknown", clientBuild and tostring(clientBuild) or "unknown",
        clientToc and tostring(clientToc) or "unknown")
    if toc and clientToc then
        Line("TwichUI interface %s %s the client's", toc, tostring(toc) == tostring(clientToc) and "matches" or "differs from")
    else
        Line("TwichUI interface: %s", toc or "unknown (not readable from the addon list)")
    end
    Line("locale: %s", GetLocale and tostring(GetLocale()) or "unknown")

    for _, name in ipairs(OPTIONAL_ADDONS) do
        local v = Metadata(name, "Version")
        Line("optional addon %s: %s%s", name, Presence(name), v and (", version " .. v) or "")
    end
    for _, name in ipairs(BUNDLED_LIBS) do Line("library %s (bundled): %s", name, Library(name)) end
    for _, name in ipairs(EXTERNAL_LIBS) do Line("library %s (not bundled; optional): %s", name, Library(name)) end

    -- EllesmereUI: what TwichUI can see of it. All of it optional.
    local eui = rawget(_G, "EllesmereUI")
    if type(eui) ~= "table" then
        Line("EllesmereUI integration: not active (EllesmereUI is %s)", Presence("EllesmereUI"))
    else
        Line("EllesmereUI version: %s", tostring(Metadata("EllesmereUI", "Version") or (type(eui.VERSION) == "string" and eui.VERSION) or "unknown"))
        Line("EllesmereUI skin registration: TwichUI registered=%s, skin toolkit received=%s",
            D.Flag(R.euiRegistered == true), D.Flag(R.S ~= nil))
        local borders = R.Borders
        Line("EllesmereUI border textures usable: %s", (borders and borders.Ellesmere) and D.Flag(borders.Ellesmere() ~= nil) or "unknown (the border module is not loaded)")
        if R.euiRegistered and not R.S then
            Line("the skin toolkit arrives only if EllesmereUI's third-party addon skins are on; until then TwichUI uses its plain look")
        end
    end

    local on, off = Switches()
    local function Wrapped(label, list)
        local text, first = "", true
        for _, key in ipairs(list) do
            if #text + #key > 140 then
                lines[#lines + 1] = (first and (label .. ": ") or "    ") .. text
                text, first = "", false
            end
            text = text .. (text == "" and "" or ", ") .. key
        end
        lines[#lines + 1] = (first and (label .. ": ") or "    ") .. (text == "" and "none" or text)
    end
    Wrapped(("switches on (%d)"):format(#on), on)
    Wrapped(("switches off (%d)"):format(#off), off)
    return lines
end

D.Register("environment", {
    title = "Environment",
    order = 10,
    snapshot = function()
        return {
            configured = nil, initialized = true, status = "ready",
            lines = Environment(),
            limits = { "A switch being on is only its setting; each module's own section says whether it is working." },
        }
    end,
})
