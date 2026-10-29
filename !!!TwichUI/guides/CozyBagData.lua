-- TwichUI: Cozy Sleeping Bag guide, the data
-- The quest chain behind the Cozy Sleeping Bag on WoW: Forever, as a list of guide steps. No frames, no game calls.
--
-- Where the facts come from: the quest IDs, map IDs, coordinates and the order of the chain were read from
-- NaowhForever_Discovery's SleepingBag.lua and Data/SleepingBag.lua (a reference only: nothing of it is loaded, called or
-- copied; its code and text are all rights reserved, so only these facts are used and every word below is our own). That
-- addon in turn cites Wowhead Forever's quests and guide. Nothing here has been checked in the game.
-- What the reference does not say, this file does not claim: no reward values, no experience amounts and no quest
-- prerequisites beyond the order it lists. See docs/cozy-sleeping-bag.md.
--
-- Four things are kept apart:
--   step      one thing the player does, in order (this list). It has a title, instructions and an id that never changes.
--   quest     the quest the step starts or finishes: `quest`, read from the character's own quest data.
--   objective the game's own objective line of a quest. Not modelled: these quests are a single click.
--   place     where to do it: `places`, each a map ID and a position in percent (0 to 100) of that map, with a label.
-- One quest can need two steps (the first two steps of each side share one quest), and one step can have several places.
--
-- A step's `kind` says what its quest proves:
--   "start"   the step is done once the quest is in the quest log or turned in (you cannot have turned in a quest you never
--             took, so a turned-in quest proves its start: this inference needs no other quest).
--   "finish"  the step is done once the quest is turned in, and not before.
-- `provedBy` lists the ids of later steps whose completion proves this step done too. It is empty everywhere below: the
-- reference lists the steps in order but does not establish that each quest requires the one before, so no step is
-- assumed done because a later one is. (The evaluator supports it; tests/test_cozy_bag.lua exercises it with a made-up
-- chain.)

local R = TwichUI
local D = {}
R.CozyBagData = D

D.id = "cozybag"
D.title = "Cozy Sleeping Bag"
D.item = 211527        -- the Cozy Sleeping Bag
D.level = 14           -- the level the reference says the chain needs. The guide shows it and never enforces it; the launcher and
                       -- the unlock notice (CozyBagOffer.lua, through CozyBagState.Offer) wait for it, and nothing else reads it

D.intro = "A hidden chain of quests across Azeroth. Each step is a thing in the world to click; the last one holds the Cozy Sleeping Bag."

-- Alliance and Horde start at opposite ends of the same two spots; from Stonetalon on the steps are shared.
local REMAINS_WESTFALL = { map = 1436, x = 37.5, y = 50.7, label = "Alexston Farmstead, Westfall" }
local REMAINS_BARRENS = { map = 1413, x = 46.4, y = 73.9, label = "Burnt tower south of Camp Taurajo, The Barrens" }

D.steps = {
    { id = "a-westfall", faction = "Alliance", kind = "start", quest = 79008,
      title = "Burned-Out Remains in Westfall",
      text = "Search the wrecked cart in the rubble of Alexston Farmstead. This starts the chain.",
      places = { REMAINS_WESTFALL } },
    { id = "a-barrens", faction = "Alliance", kind = "finish", quest = 79008,
      title = "Burned-Out Remains in The Barrens",
      text = "Follow the road south of Camp Taurajo to the burnt tower and search the remains there.",
      places = { REMAINS_BARRENS } },

    { id = "h-barrens", faction = "Horde", kind = "start", quest = 79007,
      title = "Burned-Out Remains in The Barrens",
      text = "Follow the road south of Camp Taurajo to the burnt tower and search the remains there. This starts the chain.",
      places = { REMAINS_BARRENS } },
    { id = "h-westfall", faction = "Horde", kind = "finish", quest = 79007,
      title = "Burned-Out Remains in Westfall",
      text = "Search the wrecked cart in the rubble of Alexston Farmstead.",
      places = { REMAINS_WESTFALL } },

    { id = "litter", kind = "finish", quest = 79192,
      title = "Pocket Litter",
      text = "Take the path northeast of Sun Rock Retreat to an abandoned camp. The litter lies on top of a box.",
      places = { { map = 1442, x = 40.8, y = 52.6, label = "Abandoned camp, Stonetalon Mountains" } } },
    { id = "mound", kind = "finish", quest = 79980,
      title = "Mound of Dirt",
      text = "Climb the hill straight north of the camp, then jump across to the ledge from its edge.",
      places = { { map = 1442, x = 39.6, y = 49.9, label = "Ledge north of the camp, Stonetalon Mountains" } } },
    { id = "figurine", kind = "finish", quest = 79974,
      title = "Carved Figurine",
      text = "On the Stonewrought Dam, jump onto the carved heads that face the Wetlands.",
      places = { { map = 1432, x = 49.5, y = 12.8, label = "Stonewrought Dam, Loch Modan" } } },
    { id = "bag", kind = "finish", quest = 79975,
      title = "Messenger Bag",
      text = "Climb into Thoradin's Wall from the cart on the Hillsbrad side. The bag hangs outside, to the right.",
      places = {
          { map = 1417, x = 22.5, y = 24.2, label = "Messenger Bag, Thoradin's Wall" },
          { map = 1424, x = 87.3, y = 49.6, label = "Cart to climb from, Hillsbrad Foothills" },
      } },
    { id = "satchel", kind = "finish", quest = 79976,
      title = "Hastily Rolled-Up Satchel",
      text = "It lies right below the Messenger Bag, and it holds the Cozy Sleeping Bag.",
      places = { { map = 1417, x = 22.5, y = 24.2, label = "Below the Messenger Bag, Thoradin's Wall" } } },

    -- A side step the bag does not need: not counted, never the current step.
    { id = "firepit", kind = "finish", quest = 80001, optional = true,
      title = "Firepit (optional)",
      text = "Light the firepit at the abandoned camp with the Simple Wood and the Flint and Tinder from the Pocket Litter. The bag does not need it.",
      places = { { map = 1442, x = 40.6, y = 52.4, label = "Abandoned camp, Stonetalon Mountains" } } },
}
