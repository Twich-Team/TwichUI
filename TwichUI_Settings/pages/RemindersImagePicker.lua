-- Reminders compatibility adapter for the one shared Settings artwork chooser.
-- Reminders owns display modes and atomic persistence through Gallery.Choose.
local R = TwichUI
local IP = {}
R.RemindersImagePicker = IP
local binding
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"
local function Picker() return R.SettingsArtworkPicker end
local function Gallery() return R.Reminders.Gallery end
local function State()
    local p = Picker()
    local state = p and binding and p.State(binding.owner)
    return state and state.owner == binding.owner and state.key == binding and state or nil
end
local function Legacy(ref)
    if not ref then return nil end
    local g = Gallery()
    if ref.kind == "art" then
        return g.ForArt(ref.id) or { kind = "art", target = ref.id, id = ref.id, name = "Artwork unavailable" }
    elseif ref.kind == "icon" then
        return g.ForIcon(ref.id) or { kind = "icon", target = ref.id, id = "icon-" .. ref.id, name = "Artwork unavailable" }
    elseif ref.kind == "item" then return g.ItemCandidate(ref.id) end
end
local function Reference(candidate)
    if not candidate then return nil end
    return R.Artwork.Check({ kind = candidate.kind, id = candidate.kind == "item" and candidate.item or candidate.target })
end
function IP.Shown() return State() ~= nil and Picker().Shown() end
function IP.Frame() return Picker() and Picker().Frame() end
function IP.ReminderId() return State() and binding.id end
function IP.Candidate() local state = State(); return state and Legacy(state.candidate) end
function IP.Source() local state = State(); return state and state.source end
function IP.Cancel()
    local state = State()
    if state then return Picker().Close(binding.owner) end
    binding = nil
    return false
end
function IP.Apply() if State() then return Picker().Apply(binding.owner) end return false end
function IP.Draw(texture, candidate, size)
    local ref = Reference(candidate)
    if ref and R.Artwork.Draw(texture, ref, size) then return end
    texture:SetVertexColor(1, 1, 1, 1); texture:SetAlpha(1)
    texture:SetTexture(QUESTION); texture:SetTexCoord(0.08, 0.92, 0.08, 0.92); texture:SetSize(size, size)
end
for _, name in ipairs({ "SetSource", "SetCategory", "SetQuery", "TakeItem", "Refresh", "Say" }) do
    IP[name] = function(...) if State() then return Picker()[name](...) end end
end
function IP.Open(id, env)
    local page, picker = R.RemindersPage, Picker()
    local value = R.Reminders.Get(id)
    if not (value and page and picker) then return false end
    if IP.Shown() and binding.id == id then IP.Cancel(); return false end
    if R.RemindersDesigner and R.RemindersDesigner.Shown() then return false end
    local owner = page.Parts().frame
    if not (owner and owner:IsVisible() and page.EditorActive() and page.Selected() == id) then return false end
    local source = Gallery().Source(value.display)
    local selection = R.Artwork.Check({ kind = source, id = source == "item" and value.display.item or source == "icon" and value.display.icon or value.display.art })
    local nextBinding = { id = id, owner = owner, raw = value.raw, env = env }
    local function Current()
        local v = R.Reminders.Get(id)
        return page.EditorActive() and page.Selected() == id and v ~= nil and v.raw == nextBinding.raw
    end
    -- The shared chooser owns the companion place, but knows no Reminder objects.
    if R.RemindersCatalog then R.RemindersCatalog.Hide() end
    if R.RemindersPreview then R.RemindersPreview.Hide() end
    local ok, why = picker.Open(owner, {
        key = nextBinding, selection = selection, IsCurrent = Current,
        subtitle = "Select an illustration for your reminder.",
        fallback = { name = "default artwork", Draw = function(tex, size)
            R.Artwork.Draw(tex, { kind = "art", id = R.Reminders.DISPLAY_DEFAULTS.art }, size)
        end },
        OnApply = function(ref) return Gallery().Choose(id, Legacy(ref)) end,
        OnClosed = function(reason)
            if binding == nextBinding then binding = nil end
            if reason == "applied" and env and env.Changed then env.Changed() end
            page.QueueRefresh()
        end,
    })
    if ok then binding = nextBinding else page.QueueRefresh() end
    return ok, why
end
