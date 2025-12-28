local T = unpack(Twich)

--- @type LoggerModule
local LM = T:GetModule("Logger")

--- @type ToolsModule
local TM = T:GetModule("Tools")

--------------------------------------------------------------------------------
-- Simple named dirty-flag cache
--------------------------------------------------------------------------------

--- Simple dirty-flag cache object.
--- Caches an arbitrary value and only recomputes it when marked dirty.
--- @class GenericCache
--- @field name string     Human-readable cache name (for logging).
--- @field value any       Cached value.
--- @field dirty boolean   Whether the cache needs recomputing.
local Cache = {}
Cache.__index = Cache

--- Get the cached value, recomputing it if the cache is dirty.
--- @param computeFn fun(): any Function that computes and returns the value.
--- @return any value The cached (or freshly computed) value.
function Cache:get(computeFn)
    if self.dirty then
        if LM and LM.Debug then
            LM.Debug(("Rebuilding cache: %s"):format(self.name or "unnamed"))
        end
        self.value = computeFn()
        self.dirty = false
    end
    return self.value
end

--- Mark the cache as dirty so it will recompute on next get().
function Cache:invalidate()
    if LM and LM.Debug then
        LM.Debug(("Invalidating cache: %s"):format(self.name or "unnamed"))
    end
    self.dirty = true
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

--- Cache API namespace for TwichUI.
--- @class GenericCache
--- @field New fun(name: string): GenericCache Create a new named cache.
local CacheAPI = {}

--- Create a new named cache instance.
--- @param name string Human-readable cache name for logging.
--- @return GenericCache cache A new cache object.
function CacheAPI.New(name)
    return setmetatable({
        name  = name or "unnamed",
        value = nil,
        dirty = true,
    }, Cache)
end

TM.Generics.Cache = CacheAPI
