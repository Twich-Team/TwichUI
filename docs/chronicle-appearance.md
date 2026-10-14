# Chronicle appearance

Journey Chronicle options (`/tui options` > Journey Chronicle) end with an **Appearance** section. It changes how
the Chronicle window looks and nothing else: not what is recorded, not the entries or notes, not the date filter,
not the clock, not the window's place. The defaults are the look the window has always had.

Code: `chronicle/Appearance.lua` (settings, palette, typography, when a change is drawn), `chronicle/Window.lua`
(the surfaces it draws on), `chronicle/Style.lua` (the drawing helpers, shared with other windows),
`modules/MenuStyle.lua` (background and border, shared with the broker menus and the RestedXP skin),
`diag/ChronicleLook.lua` (report section). Nothing here has been seen in the game yet; see the checklist below.

## What it covers, and what it doesn't

| Surface | Follows the appearance |
| --- | --- |
| Chronicle window: frame, title band, title, details line, filter control, entry list, rows, scroll bar, buttons | yes |
| Note editor (`TwichUIChronicleNote`): same frame look, title, hint, buttons; the text you type follows the text face, size and outline (its color stays the game's) | yes |
| Date picker (`TwichUIChronicleDate`): accent and border colors, button and link labels use the text face and outline; its text keeps its size (its cells are fixed) | partly |
| Zone arrival card, Welcome Back card, Welcome dialog, training and friend cards, Auction House tab, refreshments panel, Mage menus | **no** |

`chronicle/Style.lua` is used by those other windows too, so its colors (`S.color`) and default palette
(`S.palette`) are never changed. A helper draws exactly as before unless a palette is passed to it as its last
argument; only the Chronicle windows pass theirs (`ChronicleAppearance.palette`, made by `S.NewPalette()`). A test
checks that `S.color`, `S.palette` and an ordinary `S.Button` are unchanged after appearance changes.

## Saved data

In the profile in use (`TwichUIDB.ui`; see `profiles.md`), like TwichUI's other looks; a profile change redraws an
open Chronicle once. The Chronicle's entries are per character in `TwichUIChronicleDB`, in no profile, which this
never reads or writes.

* `ui.chronicleLook`: a `MenuStyle` look: `bgTexture`, `bgColor`, `bgOpacity`, `borderTexture`, `borderColor`,
  `borderOpacity`, `borderSize`, and the optional `bgTiling`, `bgTileSize`, `bgInset`.
* `ui.chronicleAppearance`: everything else (see the table below).

Only values the player changed are saved. Reading goes through `Get`, which falls back to the default for anything
invalid **without erasing it**; `false` and `0` are values. Neither table is part of configuration sharing or
backups. Persist drops either one if it is not a table (`container-not-table`) and the owner rebuilds it.
Frames, fonts and media paths are never saved. No schema step was needed: both are new containers whose absence is
the default.

**Reset Chronicle appearance** clears those two tables and nothing else.

## Settings

| Group | Setting | Notes |
| --- | --- | --- |
| Background | Background texture | None, Solid color (default), the game's, EllesmereUI's (installed only), LibSharedMedia backgrounds and status bars (labelled with where they come from) |
| | Color, Opacity | the tint, and how solid the fill, header band and list are (98 is the default) |
| | Tiling, Tile size, Inset | shown only for an image background; Tiling is Automatic, Repeat or Stretch |
| | Overall window opacity | 40-100; multiplies everything, labelled as such; default 100 |
| Border | Style | Chronicle ledger (default), None, Solid line, the game's, EllesmereUI's, LibSharedMedia |
| | Color, Opacity | tint of the ledger's rim or of a single border; greyed for None |
| | Thickness | 0-16 pixels; greyed (with the reason in the tooltip) for the ledger, whose width is fixed, and for None |
| | Content padding | 0-12 pixels; separate from the border's thickness |
| Typography | Text font, Title and headline font | LibSharedMedia fonts: TwichUI's, EllesmereUI's (it registers its own), and any other addon's; "Same as text font" |
| | Title / Headline / Note / Date and detail color | four roles |
| | Text opacity | 30-100; only text |
| | Set text sizes here + four sizes | off follows the game's own (16, 12, 10, 10); on uses the sizes |
| | Line spacing | 0-8 |
| | Text outline | none, outline, thick outline |
| Controls and accents | Accent color | links, a note's frame, the main button, the picker's marks, scroll arrows, the rim's lit edge and corners |
| | Header band color, Entry list color | |
| | Entry highlight | strength of the accent tint under the pointer (0-40) |
| | Show dividers, Worn surface | |
| | Main button | Filled (default) or Outline |
| | Scroll bar thumb and track, Divider color | |

Minimums (text opacity 30, window opacity 40) keep the window findable. Colors that mean something are not
settings: the Delete link and warnings stay red, disabled controls stay muted, "today" in the picker stays the
accent.

## How it is drawn

* **Background and border** are a `MenuStyle` look applied to the window's `BackdropTemplate` frame
  (`MenuStyle.Apply`), so opacity is the backdrop's own alpha and never fades text, icons or buttons. The
  ledger is a border id the look's owner draws (`extraBorders`): `Apply` draws no edge for it and
  `Style.PaintFrame` shows the rim lines, corner pixels and the dark outer line, tinted by the border color
  (the inner line is the rim color at the same ratio as before, so the default is the original, exactly).
* **Layout:** the window keeps its anchor and its list keeps its size. The border thickness (or 4 px for the
  ledger) plus the padding is the inset; the window grows by twice the difference from the default inset, and by
  how much larger the title and details text are than the game's, so nothing is clipped or covered and the saved
  or dragged position is not touched. Row height is measured from the text as drawn (`GetStringHeight` wrapped at
  the row's width; the date line grows with its font). Buttons widen to fit their label, never narrower than
  before. The filter control widens for its label. The details line gives way to the played time.
* **Text:** every FontString is made through `ChronicleAppearance.Text` with the game's font object it started
  from and a role (title, heading, body, meta, control). A role with nothing chosen is given back to the font
  object (`SetFontObject`), so locale variants keep applying. A font that can't be used (missing, or the game
  refuses it) is drawn as the font object's and stays chosen; the report names the role.
* **Passes:** a change bumps a revision and requests one pass. Nothing open: nothing is scheduled and the pass
  runs as a window opens. Open: one `C_Timer.After(0.05)` folds every change that arrives meanwhile into one pass;
  a timer that fires after the window closed does nothing (token check, `A.Cancel`). A pass recolours and restyles
  what exists; it creates no frames, textures, font strings or hooks (a test counts them over 25 rounds of
  changes). Nothing runs per frame and nothing polls.
* **Media arriving later:** `LibSharedMedia_Registered` for the chosen background or border (MenuStyle) and for
  any font (`MenuStyle.Fonts`), `ADDON_LOADED` for EllesmereUI, and `UI_SCALE_CHANGED` / `DISPLAY_SIZE_CHANGED`
  (border thickness is in screen pixels) all request a pass. Font and texture lists are read when a dropdown opens
  and kept until a font is registered.
* **Combat:** none of these frames is protected, so nothing is deferred for combat.

## EllesmereUI media

* **Fonts:** EllesmereUI registers its bundled fonts with LibSharedMedia (`EllesmereUI_Fonts.lua`), the supported
  route, so they appear in the font lists (labelled "(EllesmereUI)" using its `FONT_FILES` / `FONT_BLIZZARD`
  tables, only to label them) with no integration code. TwichUI's own fonts (`modules/Media.lua`) are labelled
  "(TwichUI)".
* **Borders:** EllesmereUI's own border textures through `EllesmereUI.GetBorderTextureList` and `ApplyBorderStyle`,
  the integration the Food and Drink buttons and the Mage menus already use (`modules/Borders.lua`).
* **Backgrounds:** the textures it offers for its own backgrounds, from `EllesmereUI.BuildBarTextureTables`
  (already used by `MenuStyle`). Status bar textures from LibSharedMedia are listed as "(status bar)" and
  stretched, as EllesmereUI does; a few names that are icons are left out.
* Nothing is copied or bundled; the files are referenced by the path the provider gives. Nothing is read from
  EllesmereUI's saved variables or internal tables other than the ones named here, and it is not modified.
  Without EllesmereUI the Chronicle works with the game's media and LibSharedMedia's; a saved EllesmereUI choice is
  drawn as a plain color or line, stays chosen, and is drawn again when EllesmereUI is there.
* **Licensing:** TwichUI's fonts are SIL OFL (`licenses/`). EllesmereUI's and other addons' files are not
  redistributed; they are used from where their owners installed them, through the registrations they publish.
  The game's own textures are named by path, as Blizzard's UI does.

## Not covered

* The date picker's text keeps its size (fixed cells), and only its face and outline follow.
* The text you type in the editor follows face, size and outline but not color.
* There is no per-button styling, and no sample entries are created to preview: **Chronicle window** under the
  Appearance header shows the real window beside the settings window (drag it by its title).
* Appearance is per TwichUI profile (`profiles.md`); switching profile redraws an open Chronicle once.
* Rendering has not been looked at in the game.

## Manual checklist (in the game)

1. Default appearance: open the Chronicle with nothing saved; compare with a screenshot from before this change
   (rim, corner pixels, speckle, band, list, buttons, hover tint).
2. Background: each texture kind (solid, a game texture, an EllesmereUI one, a status bar), tint, opacity from
   0 to 100; text, icons and border stay solid; Tiling, Tile size and Inset only appear for an image.
3. Border: ledger, None, solid line at 1/4/16 pixels, a game border, an EllesmereUI border; color and opacity;
   the window grows, the list keeps its size, the window stays where it is, nothing is covered.
4. Fonts, sizes, outline, colors for title, headline, note and details; Text opacity.
5. Long entry text and a note that wraps to several lines at a large size and with line spacing; rows grow, none
   clips, the scroll range follows; the editor's box and buttons are not covered at a thick border.
6. Hover tint, Edit and Delete links, Delete stays red, a disabled Save, the picker's today/selected/range marks.
7. Scroll through many entries; open and close; add and delete entries; rows recycled keep the look.
8. Different UI scales (and a small game window): the border is the thickness chosen, the window fits the screen.
9. Switch EllesmereUI profiles: the Chronicle look does not change. Switch TwichUI profiles: it changes to that profile's look, once.
10. Reset Chronicle appearance: look is back; entries, notes, the date filter, the clock, the sound setting, and
    where you dragged the window are as they were.
11. EllesmereUI present, absent (disable it, reload), and a saved choice of one of its media with it disabled;
    a LibSharedMedia font pack added.
12. Open and close 20 times with settings changing; `/tui diagnostics` > Chronicle appearance counts steady
    ("holds" does not grow).
13. Arrival recording, visit counts, history and notes are as they were (add a note, change zone, reload).
14. `/tui welcome` (Welcome Back) and a zone arrival card look as before while the Chronicle is heavily restyled.
