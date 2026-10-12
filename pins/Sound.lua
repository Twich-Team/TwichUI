-- TwichUI: Party pins, the arrival sound
-- When a pin arrives from another player (PN.OnReceived: new pins only, never updates, your own or ones you
-- already held) one short sound plays, so a group notices a pin without looking at the map. It is on by
-- default and the player chooses the sound and which game volume it follows (pins/Look.lua, PL.Sound).
-- PlaySoundFile has no volume of its own: a quieter or louder sound is the channel's slider in the game's
-- Audio options. Pins you place yourself make no sound, and nothing is written in chat.

local R = TwichUI
local PN = R.Pins
local PL = R.PinsLook
local SD = PL.Sound
local S = {}
R.PinsSound = S

-- Several pins arriving in a moment (a member placing a handful, or messages in a burst) give one sound.
local MIN_GAP = 2

local lastPlayed
local stats = { played = 0, refused = 0, held = 0, fallback = false }

local function SharedMedia() return LibStub and LibStub("LibSharedMedia-3.0", true) end

-- What to hand PlaySoundFile for a sound name: TwichUI's own by its file (found without LibSharedMedia,
-- and whether or not the media module registered them), then LibSharedMedia's list. nil when it isn't there.
function S.Resolve(name)
    local file = R.MediaSounds and R.MediaSounds[name]
    if file then return R:SoundPath(file) end
    local lib = SharedMedia()
    if lib and lib.Fetch then return lib:Fetch("sound", name, true) end
    return nil
end

-- { { name, label }, ... }: TwichUI's sounds, then every other LibSharedMedia sound. current stays listed,
-- marked, when it has gone.
function S.Choices(current)
    local list, seen = {}, {}
    local own = {}
    for name in pairs(R.MediaSounds or {}) do own[#own + 1] = name end
    table.sort(own)
    for _, name in ipairs(own) do
        seen[name] = true
        list[#list + 1] = { name, name }
    end
    local lib = SharedMedia()
    local names = lib and lib.List and lib:List("sound") or {}
    for _, name in ipairs(names) do
        if name ~= "None" and not seen[name] then
            seen[name] = true
            list[#list + 1] = { name, name }
        end
    end
    if current and not seen[current] then list[#list + 1] = { current, current .. " (not available)" } end
    return list
end

-- Plays the chosen sound once on the chosen channel; the default when the chosen one isn't available.
-- Returns whether the game took it. Not limited by MIN_GAP (that is for arrivals).
function S.Play()
    if not PlaySoundFile then return false end
    local path = S.Resolve(SD.Get("sound"))
    stats.fallback = false
    if not path then
        path = S.Resolve(SD.DEFAULTS.sound)
        stats.fallback = true
    end
    if not path then return false end
    local ok = PlaySoundFile(path, SD.Get("channel"))
    if ok then stats.played = stats.played + 1 else stats.refused = stats.refused + 1 end
    return ok and true or false
end

local function OnReceived()
    if not (R:Enabled("partyPins") and SD.Get("enabled")) then return end
    local now = GetTime()
    if lastPlayed and now >= lastPlayed and now - lastPlayed < MIN_GAP then
        stats.held = stats.held + 1
        return
    end
    lastPlayed = now
    S.Play()
end

PN.OnReceived(OnReceived)

-- Read only, for /tui diagnostics: counts and flags, never a sound's name or path.
function S.Snapshot()
    return { played = stats.played, refused = stats.refused, held = stats.held, fallback = stats.fallback }
end
