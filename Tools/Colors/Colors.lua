local T, W, I, C = unpack(Twich)
---@type ToolsModule
local TM = T:GetModule("Tools")


---@class TwichColorGroup
---@field PRIMARY_ACCENT string        # Main highlight / brand accent
---@field SECONDARY_ACCENT string      # Links, secondary highlights
---@field TERTIARY_ACCENT string       # Toggles, special buttons
---@field GOLD_ACCENT string           # Currency, premium highlights
---@field RARE_ACCENT string           # Rare/elite, keystone-style
---@field APP_BG string                # Overall background
---@field PANEL_BG string              # Main frames
---@field ELEVATED_BG string           # Tooltips, popups
---@field SUNKEN_BG string             # Inset areas
---@field DISABLED_BG string           # Disabled / low emphasis
---@field BORDER_STRONG string         # Outer frame outlines
---@field BORDER_SUBTLE string         # Dividers, inner borders
---@field BORDER_FOCUS string          # Keyboard/mouse focus
---@field BORDER_ERROR string          # Error outlines
---@field BORDER_SUCCESS string        # Success outlines
---@field TEXT_PRIMARY string          # Main text
---@field TEXT_SECONDARY string        # Labels, secondary info
---@field TEXT_MUTED string            # Hints, disabled text
---@field TEXT_ON_ACCENT string        # Text on accent buttons
---@field TEXT_ERROR string            # Error messages
---@field TEXT_SUCCESS string          # Success messages
---@field TEXT_WARNING string          # Warnings
---@field STATE_HOVER_BG string        # Row/button hover
---@field STATE_ACTIVE_BG string       # Pressed button
---@field STATE_SELECTED_BG string     # Selected row/tab
---@field STATE_INFO_FILL string       # Info status
---@field STATE_ERROR_FILL string      # Error background
---@field STATE_SUCCESS_FILL string    # Success background


---@class Warcraft_Currency_ColorGroup
---@field GOLD string
---@field SILVER string
---@field COPPER string

---@class Warcraft_Faction_ColorGroup
---@field ALLIANCE string
---@field ALLIANCE_BRIGHT string
---@field HORDE string
---@field HORDE_BRIGHT string

---@class Warcraft_Group
---@field CURRENCY Warcraft_Currency_ColorGroup
---@field FACTION Warcraft_Faction_ColorGroup

---@class Colors
---@field RED string
---@field ORANGE string
---@field YELLOW string
---@field GREEN string
---@field BLUE string
---@field INDIGO string
---@field VIOLET string
---@field WHITE string
---@field GRAY string
---@field BLACK string
---@field TWICH TwichColorGroup
---@field WARCRAFT Warcraft_Group

---@type Colors
TM.Colors = {
    RED = " #FF0000",
    ORANGE = "#FFA500",
    YELLOW = "#FFDE21",
    GREEN = "#008000",
    BLUE = "#0000FF",
    INDIGO = "#560591",
    VIOLET = "#7F00FF",
    WHITE = "#FFFFFF",
    GRAY = "#808080",
    BLACK = "#000000",
    TWICH = {
        -- Accent / brand
        PRIMARY_ACCENT     = "#9580FF", -- main highlight / brand accent
        SECONDARY_ACCENT   = "#4CC9F0", -- links, secondary highlights
        TERTIARY_ACCENT    = "#FF9F45", -- toggles, special buttons
        GOLD_ACCENT        = "#F5C06B", -- currency, premium highlights
        RARE_ACCENT        = "#6A5ACD", -- rare/elite, keystone-style

        -- Surfaces
        APP_BG             = "#111318", -- overall background
        PANEL_BG           = "#171A21", -- main frames
        ELEVATED_BG        = "#1F242E", -- tooltips, popups
        SUNKEN_BG          = "#0C0F14", -- inset areas
        DISABLED_BG        = "#242A34", -- disabled / low emphasis

        -- Borders
        BORDER_STRONG      = "#2D3442", -- outer frame outlines
        BORDER_SUBTLE      = "#272D39", -- dividers, inner borders
        BORDER_FOCUS       = "#4C8DFF", -- keyboard/mouse focus
        BORDER_ERROR       = "#D9534F", -- error outlines
        BORDER_SUCCESS     = "#3CB371", -- success outlines

        -- Text
        TEXT_PRIMARY       = "#E5E9F0", -- main text
        TEXT_SECONDARY     = "#C2CAD6", -- labels, secondary info
        TEXT_MUTED         = "#808694", -- hints, disabled text
        TEXT_ON_ACCENT     = "#0B0F16", -- text on accent buttons
        TEXT_ERROR         = "#FF6B6B", -- error messages
        TEXT_SUCCESS       = "#6ED29C", -- success messages
        TEXT_WARNING       = "#FFCC66", -- warnings

        -- States
        STATE_HOVER_BG     = "#232936", -- row/button hover
        STATE_ACTIVE_BG    = "#1B202B", -- pressed button
        STATE_SELECTED_BG  = "#283348", -- selected row/tab
        STATE_INFO_FILL    = "#5BC0EB", -- info status
        STATE_ERROR_FILL   = "#3B1014", -- error background
        STATE_SUCCESS_FILL = "#102319", -- success background
    },

    WARCRAFT = {
        CURRENCY = {
            GOLD = "#FFD700",
            SILVER = "#C0C0C0",
            COPPER = "#B87333"
        },
        FACTION = {
            ALLIANCE = "#162c57",
            ALLIANCE_BRIGHT = "#2b529e",
            HORDE = "#8c1616",
            HORDE_BRIGHT = "#d92323",

        }
    },
}
