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

-- What to hand PlaySoundFile for a sound name, and the dropdown's list: modules/Media.lua's.
function S.Resolve(name) return R:ResolveSound(name) end
function S.Choices(current) return R:SoundChoices(current) end

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
