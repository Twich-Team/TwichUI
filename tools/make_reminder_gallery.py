#!/usr/bin/env python3
"""Builds the Reminders artwork library from the two painted sheets in docs/reminders-revision/ (icon-grid-1.png, icon-grid-2.png).

Standard library only, like the other make_*.py tools. The PNG reader and the premultiplied-alpha box filter are
tools/make_map_tool_icons.py's; the solid-part finder, the shape-based haze cleaning, the TGA writer and the colour bleed are
tools/make_settings_icons.py's, used as they are. Both sheets are 8-bit RGBA with real transparency (about half of each sheet is fully
clear) and a faint haze around some icons, so nothing is keyed out by colour: a pixel is kept by being solid artwork or within a few
pixels of it (its antialiased edge), exactly as for the settings, vendor and Guild Locations sheets. The sheets are never changed.

Finding each picture (nothing is cut on a nominal grid):
  Sheet 1 (1536 x 1024) is a dense 6-band sheet, 8 / 10 / 9 / 8 / 8 / 8 pictures, not on a uniform grid. Every picture is one
  8-connected solid part (a few fragments of a glow are separate parts and are attached to the picture whose bounds they touch).
  The parts are sorted into the six bands by their centre's height and into reading order by their centre's x, which is how the
  entries below name them (row, column). The bounds come from the parts themselves, so no neighbour leaks in and nothing is clipped.
  Sheet 2 (1024 x 1536) is a regular 4 x 6 sheet of 256 px cells; a part belongs to the cell that holds its centre, so a picture made of
  several pieces (the fishing rod, the arcane focus, the crumbling hourglass) stays whole.

Each accepted picture is cleaned, scaled with its aspect ratio kept and centred on a square canvas with a clear margin
(about 12 % each side, up to about 18 % for a heavy, compact picture: the optical balance of tools/make_npc_art.py, so a dense medallion does
not look bigger than a thin rod), and written three ways:
  assets/reminder-gallery/<id>.png                              the individual source, SOURCE px square, RGBA
  !!!TwichUI/media/reminders/gallery/<id>.tga                   LARGE px, for a reminder drawn above 64 units
  !!!TwichUI/media/reminders/gallery/<id>-small.tga             SMALL px, for 64 units and under and for the picker's thumbnails
plus assets/reminder-gallery/manifest.json (every field below, for tools and tests) and !!!TwichUI/reminders/ArtData.lua (what the game
needs: id, name, category, description, keywords, related). docs/reminders-art.md explains all of it, including how to add a picture.

    python3 tools/make_reminder_gallery.py [--check] [--contact-sheet PATH] [--out-root DIR]

--check builds nothing: it prints the parts found, the crops and the balance, and fails on anything it can't place.
--only ID... draws and writes just those pictures (the manifest and ArtData.lua are always whole), for a quick reproducibility check.
--out-root writes the three outputs (assets/, media/, ArtData.lua) under another folder instead of the repository (the test uses it).
"""
import argparse
import json
import os
import struct
import sys
import zlib

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from make_map_tool_icons import read_png, resample  # noqa: E402
import make_settings_icons as SI  # noqa: E402

SOURCE, LARGE, SMALL = 192, 128, 64     # square canvas sides: the source PNG, the runtime textures
FIT = 0.76                              # the longer side of the content, as a share of the canvas (12 % clear margin each side)
BALANCE = 0.5
BALANCE_MIN = 0.85                      # a heavy picture is shrunk at most this far (margin at most about 18 %)
SHEETS = {1: "icon-grid-1.png", 2: "icon-grid-2.png"}
SHEET_DIR = os.path.join("docs", "reminders-revision")
CATEGORIES = ("Equipment", "Buffs & Effects", "Supplies", "Character", "Adventure", "General")

# id, sheet, (row, column), name, category, description, keywords, related ids
# Sheet 1 rows hold 8, 10, 9, 8, 8, 8 pictures; sheet 2 is 6 rows of 4. Ids describe the picture, never its position.
E = []


def add(id, sheet, pos, name, category, description, keywords, related=()):
    E.append(dict(id=id, sheet=sheet, row=pos[0], col=pos[1], name=name, category=category,
                  description=description, keywords=keywords.split(), related=list(related)))


# ---- sheet 1 -------------------------------------------------------------------------------------------------------------------
add("reminder-lion-shield", 1, (1, 1), "Lion shield", "Equipment", "A bronze shield with a lion's head: protection and tank preparation.", "shield lion protection defense tank block armor bronze", ["reminder-broken-shield", "reminder-tank-preparation"])
add("reminder-enchanted-sword", 1, (1, 2), "Enchanted sword", "Equipment", "A sword wrapped in blue magic: a weapon enchantment.", "sword enchant enchantment weapon magic blue buff oil", ["reminder-sharpening-stone"])
add("reminder-sharpening-stone", 1, (1, 3), "Sharpening stone", "Equipment", "A whetstone on a wooden block: sharpening a weapon.", "sharpening stone whetstone weapon sharpen blade enhancement")
add("reminder-poisoned-dagger", 1, (1, 4), "Poisoned dagger", "Equipment", "A dagger dripping green poison.", "poison dagger rogue weapon coat lethal deadly", ["reminder-rogue-preparation"])
add("reminder-helmet", 1, (1, 5), "Helmet", "Equipment", "A riveted bronze helmet.", "helmet helm head armor equipment gear")
add("reminder-breastplate", 1, (1, 6), "Plate armor", "Equipment", "A plate breastplate with pauldrons.", "breastplate chest armor plate equipment gear")
add("reminder-broken-shield", 1, (1, 7), "Broken shield", "Equipment", "A shield split by a crack: damaged or broken equipment.", "broken cracked shield damaged durability repair equipment", ["reminder-lion-shield"])
add("reminder-combat-loadout", 1, (1, 8), "Combat loadout", "Equipment", "Crossed swords and a travel pack: ready for a fight.", "swords crossed loadout pack gear combat ready travel equipment")
add("reminder-arcane-sigil", 1, (2, 1), "Arcane sigil", "Buffs & Effects", "Two hands around a glowing sigil: a general magical effect.", "arcane sigil magic hands buff effect spell class")
add("reminder-hourglass", 1, (2, 2), "Golden hourglass", "Buffs & Effects", "A golden hourglass ringed with light: a timed effect.", "hourglass timer time expiring duration buff effect sand", ["reminder-expiring-buff"])
add("reminder-curse-skull", 1, (2, 3), "Cursed skull", "Buffs & Effects", "A purple skull: a curse or a harmful effect.", "skull curse debuff harmful death purple poison", ["reminder-harmful-debuff"])
add("reminder-arcane-ward", 1, (2, 5), "Arcane ward", "Buffs & Effects", "A shield with a violet rune: a magical ward.", "ward shield protection barrier absorb magic violet buff", ["reminder-missing-buff"])
add("reminder-blessing-hand", 1, (2, 6), "Blessing", "Buffs & Effects", "An open hand with a soft glow: a blessing.", "blessing hand bless glow holy buff beneficial paladin")
add("reminder-war-horn", 1, (2, 7), "War horn", "Buffs & Effects", "A bronze war horn: a shout, a call or a group buff.", "horn war shout call battle buff group raid")
add("reminder-open-spellbook", 1, (2, 8), "Open spellbook", "Buffs & Effects", "An open book with a glowing rune: magical knowledge.", "spellbook book open arcane intellect magic knowledge buff spell")
add("reminder-golden-rings", 1, (2, 9), "Golden rings", "Buffs & Effects", "Stacked golden rings of light: layered effects.", "rings stacks stacking layered aura gold buff", ["reminder-aura-stacks"])
add("reminder-stained-cloth", 1, (2, 10), "Stained cloth", "Buffs & Effects", "A cloth marked with a dark stain: a harmful effect to cleanse.", "cloth stain dirty cleanse dispel harmful debuff disease")
add("reminder-arrow-quiver", 1, (3, 1), "Arrow quiver", "Supplies", "A leather quiver of arrows.", "quiver arrows ammunition ammo ranged hunter low supplies", ["ammo"])
add("reminder-crystal-pouch", 1, (3, 2), "Crystal pouch", "Supplies", "An open pouch of blue crystals: reagents.", "pouch reagents crystals bag components spell materials", ["reminder-low-reagents"])
add("reminder-supply-pack", 1, (3, 3), "Supply pack", "Supplies", "A bundle of stores for the road: consumables.", "supplies pack consumables bundle provisions stores", ["reminder-full-inventory"])
add("reminder-health-potion", 1, (3, 4), "Health potion", "Supplies", "A red potion flask.", "potion health healing red flask bottle drink consumable")
add("reminder-mana-potion", 1, (3, 5), "Mana potion", "Supplies", "A blue potion flask.", "potion mana blue flask bottle drink consumable", ["reminder-low-mana"])
add("reminder-bread-and-cheese", 1, (3, 6), "Bread and cheese", "Supplies", "A loaf and a wedge of cheese: food.", "bread cheese food eat hunger supplies provisions", ["reminder-low-food", "wellfed"])
add("reminder-waterskin", 1, (3, 7), "Waterskin", "Supplies", "A leather waterskin, full: drink.", "waterskin water drink thirst supplies flask", ["reminder-low-drink"])
add("reminder-purple-elixir", 1, (3, 8), "Purple elixir", "Supplies", "A bottle of purple elixir: an elixir or a flask.", "elixir flask potion bottle purple buff consumable")
add("reminder-hammer-and-anvil", 1, (3, 9), "Hammer and anvil", "Equipment", "A hammer on an anvil: repairs and crafting.", "hammer anvil repair blacksmith crafting smith equipment durability")
add("reminder-red-crystal", 1, (4, 1), "Red crystal", "Character", "A red crystal in a bronze setting: health.", "crystal red health life gem resource hp", ["reminder-low-health"])
add("reminder-blue-crystal", 1, (4, 2), "Blue crystal", "Character", "A blue crystal in a bronze setting: mana or another magical resource.", "crystal blue mana gem resource magic", ["reminder-low-mana"])
add("reminder-lightning-rune", 1, (4, 3), "Lightning rune", "Character", "An amber lightning bolt on stone: energy.", "lightning rune energy amber bolt resource stone", ["reminder-low-energy"])
add("reminder-battle-emblem", 1, (4, 4), "Battle emblem", "Character", "A red horned battle emblem: rage and fury.", "emblem rage fury red battle warrior horned resource", ["reminder-low-rage"])
add("reminder-arcane-spellbook", 1, (4, 5), "Arcane spellbook", "Character", "A violet spellbook: a known ability or talent.", "spellbook book arcane violet spell ability talent known learned")
add("reminder-bandages", 1, (4, 8), "Bandages", "Supplies", "Rolled bandages and a small potion: recovery and rest.", "bandages first aid recovery rest heal potion supplies")
add("reminder-warrior-banner", 1, (5, 4), "Crossed swords banner", "Character", "Crossed swords on a blue banner: a warrior, or ready for combat.", "banner swords crossed warrior combat fight blue battle ready")
add("reminder-healing-light", 1, (5, 5), "Healing light", "Character", "An open hand holding a spark of light: a healer.", "hand light healer healing holy heal spark priest")
add("reminder-dungeon-entrance", 1, (5, 7), "Dungeon entrance", "Adventure", "A torchlit stone doorway: a dungeon.", "dungeon entrance door gate torch instance cave stone")
add("reminder-raid-gate", 1, (5, 8), "Raid gate", "Adventure", "A fortress gate hung with banners: a raid.", "raid gate fortress castle banners instance door")
add("reminder-marked-map", 1, (6, 1), "Marked map", "Adventure", "A parchment map with a red marker: a place.", "map location marker pin place parchment zone navigate where")
add("reminder-horse", 1, (6, 2), "Horse", "Adventure", "A horse's head in its bridle: mounted.", "horse mount mounted riding steed travel")
add("reminder-bedroll", 1, (6, 3), "Bedroll", "Adventure", "A rolled bedroll: rest and camping.", "bedroll rest camping sleep camp bed resting", ["reminder-camp-tent"])
add("reminder-companion-crests", 1, (6, 5), "Companion crests", "Adventure", "Three shields side by side: a group.", "crests shields group party companions team", ["reminder-group-preparation"])
add("reminder-leather-backpack", 1, (6, 6), "Leather backpack", "Supplies", "A buckled leather backpack: bags and inventory.", "backpack bag inventory space leather pack bags", ["reminder-full-inventory"])
add("reminder-bronze-bell", 1, (6, 7), "Bronze bell", "General", "A bronze bell with a ribbon: a general reminder.", "bell reminder alert ring notice general bronze")
add("reminder-camp-tent", 1, (6, 8), "Camp tent", "Adventure", "A lit tent: camping and travel.", "tent camp camping fire rest travel light", ["reminder-bedroll"])
# ---- sheet 2 -------------------------------------------------------------------------------------------------------------------
add("reminder-missing-buff", 2, (1, 1), "Missing buff", "Buffs & Effects", "A fading ivory sigil in a bronze medallion: a buff that is missing.", "missing buff fading sigil absent expired medallion aura", ["reminder-expiring-buff", "reminder-arcane-ward"])
add("reminder-expiring-buff", 2, (1, 2), "Expiring buff", "Buffs & Effects", "A crumbling hourglass medallion: a buff about to end.", "expiring buff hourglass ending crumbling timer aura medallion", ["reminder-hourglass", "reminder-missing-buff"])
add("reminder-harmful-debuff", 2, (1, 3), "Harmful debuff", "Buffs & Effects", "A green corrupted rune wrapped in dark energy: a harmful effect.", "debuff harmful corrupted rune curse poison disease green aura", ["reminder-curse-skull"])
add("reminder-aura-stacks", 2, (1, 4), "Aura stacks", "Buffs & Effects", "Overlapping bronze seals around a glowing star: stacks of an effect.", "aura stacks stacking seals layers medallion star buff", ["reminder-golden-rings"])
add("reminder-low-health", 2, (2, 1), "Low health", "Character", "A cracked red heart crystal in bronze.", "health low heart cracked hp life red crystal", ["reminder-red-crystal"])
add("reminder-low-mana", 2, (2, 2), "Low mana", "Character", "A nearly empty blue mana vessel.", "mana low empty vessel flask blue resource", ["reminder-mana-potion", "reminder-blue-crystal"])
add("reminder-low-energy", 2, (2, 3), "Low energy", "Character", "A fading amber lightning emblem.", "energy low lightning amber fading resource rogue", ["reminder-lightning-rune"])
add("reminder-low-rage", 2, (2, 4), "Low rage", "Character", "A worn red battle banner with crossed swords.", "rage low banner red swords warrior resource", ["reminder-battle-emblem"])
add("reminder-talent-specialization", 2, (3, 1), "Talent specialization", "Character", "A branching character-build diagram on parchment.", "talent specialization spec build tree parchment scroll roles")
add("reminder-talent-learned", 2, (3, 2), "Talent learned", "Character", "A glowing amber rune carved into a stone tablet.", "talent learned known rune stone tablet glowing amber chosen", ["reminder-talent-missing"])
add("reminder-talent-missing", 2, (3, 3), "Talent missing", "Character", "A dark, unlit rune carved into a stone tablet.", "talent missing unlearned rune stone tablet dark unlit", ["reminder-talent-learned"])
add("reminder-cooldown-ready", 2, (3, 4), "Cooldown ready", "Character", "A blue magical clock medallion: an ability, ready.", "cooldown ready ability clock blue medallion timer spell")
add("reminder-low-reagents", 2, (4, 1), "Low reagents", "Supplies", "A nearly empty leather pouch with a few crystals left.", "reagents low empty pouch crystals components materials bag", ["reminder-crystal-pouch", "reminder-missing-class-reagents"])
add("reminder-low-food", 2, (4, 2), "Low food", "Supplies", "A small food pouch with bread and crumbs.", "food low bread crumbs pouch eat hunger supplies", ["reminder-bread-and-cheese", "wellfed"])
add("reminder-low-drink", 2, (4, 3), "Low drink", "Supplies", "An almost empty worn waterskin.", "drink low water waterskin empty thirst supplies", ["reminder-waterskin"])
add("reminder-missing-class-reagents", 2, (4, 4), "Class reagents", "Supplies", "A nearly empty pouch marked with a rune: class reagents.", "reagents class rune pouch missing empty components mage rogue", ["reminder-low-reagents"])
add("reminder-full-inventory", 2, (5, 1), "Full inventory", "Supplies", "An overfilled leather adventuring backpack.", "inventory full bags backpack overfilled space stuffed pack", ["reminder-leather-backpack", "reminder-supply-pack"])
add("reminder-fishing-rod", 2, (5, 2), "Fishing rod", "Equipment", "A broken fishing rod with its line and bobber.", "fishing rod line bobber hook broken equipment fish")
add("reminder-group-preparation", 2, (5, 3), "Group preparation", "Adventure", "Three banners: healer, leader and fighter.", "group party preparation banners roles team healer tank damage", ["reminder-companion-crests"])
add("reminder-spell-not-learned", 2, (5, 4), "Spell not learned", "Character", "A dark closed spellbook with an unfinished rune.", "spell not learned unknown book closed unfinished rune missing ability talent")
add("reminder-healer-preparation", 2, (6, 1), "Healer preparation", "Character", "A healing hand with an ivory cross and laurel.", "healer preparation hand cross laurel heal holy support medallion", ["reminder-healing-light"])
add("reminder-tank-preparation", 2, (6, 2), "Tank preparation", "Character", "A reinforced shield with a lion crest.", "tank preparation shield lion crest defense protect role", ["reminder-lion-shield"])
add("reminder-caster-preparation", 2, (6, 3), "Caster preparation", "Character", "A blue crystalline arcane focus.", "caster preparation arcane focus crystal staff magic mage blue wizard")
add("reminder-rogue-preparation", 2, (6, 4), "Rogue preparation", "Character", "A poison vial beside a dagger.", "rogue preparation poison vial dagger stealth", ["reminder-poisoned-dagger"])

# Pictures looked at and not catalogued, each with the reason. They stay on the sheets; nothing else refers to them.
REJECTED = [
    dict(sheet=1, row=2, col=4, name="Empty plate", reason="Same subject as the existing Plate and cutlery (wellfed), which saved reminders already use.", duplicate_of="wellfed"),
    dict(sheet=1, row=4, col=6, name="Hourglass medallion", reason="Near-identical to Expiring buff (sheet 2) and to Golden hourglass.", duplicate_of="reminder-expiring-buff"),
    dict(sheet=1, row=4, col=7, name="Crossed-out spellbook", reason="Same idea as Spell not learned (sheet 2), which is the stronger version.", duplicate_of="reminder-spell-not-learned"),
    dict(sheet=1, row=5, col=1, name="Talent tree parchment", reason="Same subject as Talent specialization (sheet 2), which is more detailed.", duplicate_of="reminder-talent-specialization"),
    dict(sheet=1, row=5, col=2, name="Lit rune stone", reason="Same subject as Talent learned (sheet 2).", duplicate_of="reminder-talent-learned"),
    dict(sheet=1, row=5, col=3, name="Unlit rune stone", reason="Same subject as Talent missing (sheet 2).", duplicate_of="reminder-talent-missing"),
    dict(sheet=1, row=5, col=6, name="Plain steel shield", reason="Same subject as the existing Shield (shield), which saved reminders already use.", duplicate_of="shield"),
    dict(sheet=1, row=6, col=4, name="Crossed weapons banner", reason="Near-identical to Crossed swords banner, one row above.", duplicate_of="reminder-warrior-banner"),
]

# The pictures that were already in Reminders: kept, with the ids saved reminders use. `art` ids have a texture of their own
# (reminders/Config.lua's ART table); `icon` ids are TwichUI icons (R.Icons) a reminder could already show. The picker lists them in the
# same gallery, so the player never has to know which kind a picture is. (category, name, description, keywords)
LEGACY = [
    dict(kind="art", id="shield", name="Steel shield", category="Equipment", description="A plain steel shield with a bronze rim.", keywords="shield steel protection defense equipment off hand"),
    dict(kind="art", id="ammo", name="Arrows", category="Supplies", description="A bundle of arrows.", keywords="arrows ammunition ammo ranged hunter bow supplies"),
    dict(kind="art", id="wellfed", name="Plate and cutlery", category="Supplies", description="An empty plate with a fork and knife.", keywords="plate cutlery food well fed eat meal hunger supplies"),
    dict(kind="art", id="enchant", name="Weapon oil", category="Equipment", description="A bottle of amber weapon oil.", keywords="oil weapon enchant enchantment poison bottle equipment"),
    dict(kind="icon", id="reminderShow", name="Framed shield", category="General", description="A framed shield: the reminders icon.", keywords="shield framed reminders icon general"),
    dict(kind="icon", id="reminders", name="Bell", category="General", description="A bell: a general reminder.", keywords="bell reminder alert ring general icon"),
    dict(kind="icon", id="reminderTest", name="Checklist", category="General", description="A checklist.", keywords="checklist list tasks check test general icon"),
    dict(kind="icon", id="hazardAlerts", name="Warning shield", category="General", description="A shield with a warning mark.", keywords="warning hazard danger alert shield general icon"),
    dict(kind="icon", id="ammunition", name="Quiver", category="Supplies", description="A quiver.", keywords="quiver ammunition ammo arrows supplies icon"),
    dict(kind="icon", id="foodAndDrink", name="Bread and cup", category="Supplies", description="Bread and a cup: food and drink.", keywords="bread cup food drink eat supplies icon"),
    dict(kind="icon", id="gearComparison", name="Breastplate", category="Equipment", description="A breastplate.", keywords="breastplate armor gear equipment chest icon"),
    dict(kind="icon", id="mage", name="Arcane staff", category="Character", description="A staff with an arcane crystal.", keywords="staff arcane mage magic crystal focus icon"),
]


def png_rgba(path, w, h, rows):
    raw = b"".join(b"\x00" + bytes(r) for r in rows)

    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xffffffff)

    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
                + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


def png_rgb(path, w, h, rows):
    SI.write_png(path, w, h, rows)


def find_pictures(root):
    """{sheet: {(row, col): (ids, box, parts)}} from the sheets' solid parts."""
    found = {}
    for sheet, name in SHEETS.items():
        w, h, pixels, has_alpha = read_png(os.path.join(root, SHEET_DIR, name))
        if not has_alpha:
            raise SystemExit("%s: no alpha channel" % name)
        alpha = [[row[x * 4 + 3] for x in range(w)] for row in pixels]
        lab, parts = SI.solid_parts(w, h, alpha)
        parts = [p for p in parts if p[1] >= 10]            # a lone pixel is not artwork
        big = [p for p in parts if p[1] >= 400]
        small = [p for p in parts if p[1] < 400]
        groups = {}
        if sheet == 1:
            bands = [(0, 190), (190, 360), (360, 520), (520, 680), (680, 835), (835, 1024)]
            rows = {}
            for p in big:
                band = next(i for i, (a, b) in enumerate(bands) if a <= p[3] < b)
                rows.setdefault(band, []).append(p)
            for band in range(len(bands)):
                for ci, p in enumerate(sorted(rows[band], key=lambda q: q[2])):
                    groups[(band + 1, ci + 1)] = [p]
            # a fragment of a glow joins the picture whose bounds, grown a little, hold its centre
            for s in small:
                for key, ps in groups.items():
                    b = ps[0][4]
                    if b[0] - 30 <= s[2] <= b[2] + 30 and b[1] - 30 <= s[3] <= b[3] + 30:
                        ps.append(s)
                        break
                else:
                    raise SystemExit("sheet 1: a fragment at (%d, %d) belongs to no picture" % (s[2], s[3]))
        else:
            cell = 256
            for p in parts:
                key = (int(p[3] // cell) + 1, int(p[2] // cell) + 1)
                groups.setdefault(key, []).append(p)
        found[sheet] = (w, h, pixels, alpha, lab, groups)
    return found


def union(ps):
    return (min(p[4][0] for p in ps), min(p[4][1] for p in ps), max(p[4][2] for p in ps), max(p[4][3] for p in ps))


def build(root, out_root, check=False, only=None, keep_all=False):
    found = find_pictures(root)
    expect = {s: set() for s in SHEETS}
    for e in E:
        expect[e["sheet"]].add((e["row"], e["col"]))
    for r in REJECTED:
        expect[r["sheet"]].add((r["row"], r["col"]))
    for s, (w, h, _px, _a, _l, groups) in found.items():
        have = set(groups)
        if have != expect[s]:
            raise SystemExit("sheet %d: pictures found %s but accounted for %s (missing %s, unexpected %s)" % (
                s, len(have), len(expect[s]), sorted(expect[s] - have), sorted(have - expect[s])))

    prepared = []
    for e in E:
        w, h, pixels, alpha, lab, groups = found[e["sheet"]][0:6]
        ps = groups[(e["row"], e["col"])]
        ids = {p[0] for p in ps}
        box = union(ps)
        rows, (cw, ch), holes = SI.clean_icon(pixels, alpha, lab, ids, box)
        cbox, area = SI.content_and_area(rows, cw, ch)
        longest = max(cbox[2] - cbox[0], cbox[3] - cbox[1])
        prepared.append((e, rows, cbox, area, longest, box, len(ps)))
    fills = sorted((a ** 0.5) / lg for _e, _r, _c, a, lg, _b, _n in prepared)
    median = fills[len(fills) // 2]

    manifest, built, ids_seen = [], [], set()
    for e, rows, cbox, area, longest, box, nparts in prepared:
        if e["id"] in ids_seen:
            raise SystemExit("duplicate id " + e["id"])
        ids_seen.add(e["id"])
        balance = max(BALANCE_MIN, min(1.0, (median / ((area ** 0.5) / longest)) ** BALANCE))
        canvases = {}
        draw = not check and (not only or e["id"] in only)   # the balance above needs every picture; drawing one only needs itself
        if draw or keep_all:
            for side in (SOURCE, LARGE, SMALL):
                canvases[side], _ = SI.place(rows, cbox, side * FIT / float(longest) * balance, side)
            built.append((e["id"], canvases))
        entry = dict(
            id=e["id"], name=e["name"], category=e["category"], description=e["description"], keywords=e["keywords"],
            sheet=e["sheet"], position=dict(row=e["row"], column=e["col"]),
            crop=dict(x=box[0], y=box[1], width=box[2] - box[0], height=box[3] - box[1]), parts=nparts,
            source="assets/reminder-gallery/%s.png" % e["id"],
            texture="media/reminders/gallery/%s" % e["id"], textureSizes=dict(large=LARGE, small=SMALL),
            related=e["related"], balance=round(balance, 3))
        manifest.append(entry)
        print("%-34s sheet %d r%dc%d parts %d crop %-22s balance %.2f" % (
            e["id"], e["sheet"], e["row"], e["col"], nparts, "%d,%d %dx%d" % (box[0], box[1], box[2] - box[0], box[3] - box[1]), balance))
        if draw:
            SI_dir = os.path.join(out_root, "assets", "reminder-gallery")
            TGA_dir = os.path.join(out_root, "!!!TwichUI", "media", "reminders", "gallery")
            os.makedirs(SI_dir, exist_ok=True)
            os.makedirs(TGA_dir, exist_ok=True)
            png_rgba(os.path.join(SI_dir, e["id"] + ".png"), SOURCE, SOURCE, canvases[SOURCE])
            SI.write_tga(os.path.join(TGA_dir, e["id"] + ".tga"), canvases[LARGE], LARGE)
            SI.write_tga(os.path.join(TGA_dir, e["id"] + "-small.tga"), canvases[SMALL], SMALL)

    known = ids_seen | {l["id"] for l in LEGACY}
    for e in E:
        for r in e["related"]:
            if r not in known:
                raise SystemExit("%s: related id %s is not in the catalogue" % (e["id"], r))
    for l in LEGACY:
        if l["category"] not in CATEGORIES:
            raise SystemExit("%s: unknown category" % l["id"])
    for e in E:
        if e["category"] not in CATEGORIES:
            raise SystemExit("%s: unknown category" % e["id"])

    if not check:
        doc = dict(version=1, categories=list(CATEGORIES), canvas=dict(source=SOURCE, large=LARGE, small=SMALL, fit=FIT),
                   sheets={str(k): "docs/reminders-revision/" + v for k, v in SHEETS.items()},
                   artwork=manifest, legacy=LEGACY, rejected=REJECTED)
        with open(os.path.join(out_root, "assets", "reminder-gallery", "manifest.json"), "w") as f:
            json.dump(doc, f, indent=1, sort_keys=False)
            f.write("\n")
        write_lua(os.path.join(out_root, "!!!TwichUI", "reminders", "ArtData.lua"), manifest)
    return built, manifest


def lua_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def write_lua(path, manifest):
    lines = [
        "-- TwichUI: Reminders, the artwork library's data",
        "-- GENERATED by tools/make_reminder_gallery.py from assets/reminder-gallery/manifest.json: do not edit by hand (edit the tool, run it).",
        "-- One entry per picture in media/reminders/gallery/ (<id>.tga at LARGE px, <id>-small.tga at SMALL px, both square, content centred with a clear",
        "-- margin), and the pictures that were already in Reminders with the names and categories the picker lists them under.",
        "-- Nothing here touches a frame or saved data; reminders/Gallery.lua reads it.",
        "",
        "local R = TwichUI",
        "R.ReminderArtData = {",
        "    categories = { %s }," % ", ".join(lua_str(c) for c in CATEGORIES),
        "    large = %d, small = %d," % (LARGE, SMALL),
        "    -- id, name, category, description, keywords, related",
        "    gallery = {",
    ]
    for m in manifest:
        lines.append("        { %s, %s, %s, %s, %s, { %s } }," % (
            lua_str(m["id"]), lua_str(m["name"]), lua_str(m["category"]), lua_str(m["description"]),
            lua_str(" ".join(m["keywords"])), ", ".join(lua_str(r) for r in m["related"])))
    lines += ["    },", "    -- kind (\"art\": a texture of its own in Config.lua's ART; \"icon\": an R.Icons id), id, name, category, description, keywords", "    legacy = {"]
    for l in LEGACY:
        lines.append("        { %s, %s, %s, %s, %s, %s }," % (
            lua_str(l["kind"]), lua_str(l["id"]), lua_str(l["name"]), lua_str(l["category"]), lua_str(l["description"]), lua_str(l["keywords"])))
    lines += ["    },", "}", ""]
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        f.write("\n".join(lines))


def contact_sheet(path, built, cols=9):
    """Every picture at 64, 48, 32 and 24 on a dark then a light surface, so crops, fringes and small-size legibility can be inspected."""
    surfaces = [(30, 26, 22), (226, 220, 206)]
    cell_w = 64 + 48 + 32 + 24 + 5 * 6
    cell_h = 70
    rows_n = (len(built) + cols - 1) // cols
    W = 8 + cell_w * cols
    H = (8 + cell_h * rows_n) * len(surfaces)
    img = [bytearray(W * 3) for _ in range(H)]
    for si, bg in enumerate(surfaces):
        top = si * (8 + cell_h * rows_n)
        for y in range(top, top + 8 + cell_h * rows_n):
            img[y][:] = bytes(bg) * W
        for i, (_id, canvases) in enumerate(built):
            x = 8 + (i % cols) * cell_w
            y0 = top + 8 + (i // cols) * cell_h
            for show in (64, 48, 32, 24):
                canvas = canvases[LARGE]
                if show != LARGE:
                    canvas = resample(canvas, (0, 0, LARGE, LARGE), show, show)
                for yy in range(show):
                    row = canvas[yy]
                    out = img[y0 + yy + (64 - show) // 2]
                    for xx in range(show):
                        r, g, b, a = row[xx * 4:xx * 4 + 4]
                        al = a / 255.0
                        o = (x + xx) * 3
                        out[o:o + 3] = bytes(int(round(c * al + k * (1 - al))) for c, k in zip((r, g, b), bg))
                x += show + 6
    png_rgb(path, W, H, img)


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--contact-sheet")
    ap.add_argument("--out-root", default=root)
    ap.add_argument("--only", nargs="+", help="draw and write only these picture ids (the manifest and ArtData.lua are always written whole)")
    args = ap.parse_args()
    built, manifest = build(root, args.out_root, args.check, set(args.only) if args.only else None, bool(args.contact_sheet))
    print("%d pictures, %d rejected, %d kept from before" % (len(manifest), len(REJECTED), len(LEGACY)))
    if args.contact_sheet:
        contact_sheet(args.contact_sheet, built)
    return 0


if __name__ == "__main__":
    sys.exit(main())
