-- TwichUI Layouts: composing the layers (architecture.md §2). Pure: the same layers always give the same result,
-- and nothing here reads saved variables or calls the game.
--
-- Precedence is per unit: the highest layer that names a unit decides it, and below the unit nothing is merged (a list
-- or a module blob is replaced whole). REMOVE in a layer means "inherit the layer below"; with nothing below, the unit
-- becomes unmanaged and is never written. A unit inside another (an EllesmereUI field inside its module blob, parents
-- below) is dropped when a higher layer replaces the whole blob it sits in. A retained unit (the recipient changed it
-- since the last install) keeps the recipient's value and is not written, unless it is reset.

local R = TwichUI
local LY = R.Layouts
local REMOVE = LY.REMOVE

local function Sorted(set)
    local list = {}
    for u in pairs(set) do list[#list + 1] = u end
    table.sort(list)
    return list
end

-- layers: { { name, units = { [unit] = value | REMOVE } }, ... }, lowest first.
-- parents: { [unit] = the unit it sits inside }. retained, reset: { [unit] = true } or nil.
-- Returns { units = { [unit] = value }, layer = { [unit] = layer name }, list = { { unit, value, layer } } (sorted by unit),
--   unmanaged = { units removed with nothing below }, superseded = { units whose blob a higher layer replaced },
--   retained = { units kept as the recipient has them } }. Every list is sorted, so the result does not depend on the
--   order pairs() visits anything in.
function LY.Compose(layers, parents, retained, reset)
    parents = parents or {}
    local named = {}
    for _, layer in ipairs(layers) do
        for u in pairs(layer.units) do named[u] = true end
    end
    local value, at, unmanaged = {}, {}, {}
    for u in pairs(named) do
        local found
        for i = #layers, 1, -1 do
            local v = layers[i].units[u]
            if v ~= nil and v ~= REMOVE then found = i break end
        end
        if found then value[u], at[u] = layers[found].units[u], found else unmanaged[u] = true end
    end
    local superseded = {}
    for u, i in pairs(at) do
        local p = parents[u]
        if p ~= nil and at[p] ~= nil and at[p] > i then superseded[u] = true end
    end
    for u in pairs(superseded) do value[u], at[u] = nil, nil end
    local kept = {}
    for u in pairs(retained or {}) do
        if value[u] ~= nil and not (reset and reset[u]) then
            kept[u] = true
            value[u], at[u] = nil, nil
        end
    end
    local out = { units = {}, layer = {}, list = {}, unmanaged = Sorted(unmanaged), superseded = Sorted(superseded),
        retained = Sorted(kept) }
    for _, u in ipairs(Sorted(value)) do
        local v = LY.Copy(value[u])
        out.units[u] = v
        out.layer[u] = layers[at[u]].name
        out.list[#out.list + 1] = { unit = u, value = v, layer = layers[at[u]].name }
    end
    return out
end
