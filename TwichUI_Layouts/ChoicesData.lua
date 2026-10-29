-- TwichUI Layouts: the Adventure package's choices (what the setup wizard asks, the TwichUI helper presets among them), as data.
-- Generated: do not edit by hand. tools/update_bundled_layout.sh --from-published writes it from a package published in game
-- (docs/layouts/presets.md); the profile recapture (the same script without --from-published) never touches it.
-- Source: package twichui-adventure revision 7 (fingerprint #4265506251:429773), published in game on 2026-10-29; imported by tools/import_published_layout.lua

local LY = TwichUI.Layouts
LY.ADVENTURE_CHOICES = {
  [1] = {
    default = "as-is",
    hint = "Which of TwichUI's own features the setup turns on or off, and how they behave and look. Features that act for you or talk to other players are never part of a preset.",
    id = "helpers",
    kind = "preset",
    label = "TwichUI helpers",
    mode = "settings",
    options = {
      [1] = {
        hint = "No TwichUI feature is turned on or off. The layout still styles and places the ones you already use.",
        id = "as-is",
        keep = true,
        label = "Leave them as they are",
      },
      [2] = {
        hint = "Turns on the class resource bars, the marker bar and the food and drink buttons, in the places the layout leaves for them.",
        id = "on-screen",
        label = "On-screen helpers",
        twichui = {
          groups = {
            classBars = {
              modules = {
                classBars = true,
              },
            },
            food = {
              modules = {
                foodDrink = true,
              },
            },
            markerBar = {
              modules = {
                markersBar = true,
              },
            },
          },
        },
      },
      [3] = {
        hint = "The same, and Navigation: a walking arrow to a place you pick. Its map data loads the first time you ask for a route.",
        id = "finding-my-way",
        label = "Helpers and navigation",
        twichui = {
          groups = {
            classBars = {
              modules = {
                classBars = true,
              },
            },
            food = {
              modules = {
                foodDrink = true,
              },
            },
            markerBar = {
              modules = {
                markersBar = true,
              },
            },
            navigation = {
              modules = {
                navigation = true,
              },
            },
          },
        },
      },
      [4] = {
        hint = "A curated selection of settings designed for the new player.",
        id = "curated",
        label = "Curated",
        twichui = {
          groups = {
            auction = {
              modules = {
                auctionPosting = true,
                mailGoldSummary = false,
              },
            },
            chatClean = {
              modules = {
                chatClean = true,
              },
            },
            chronicle = {
              modules = {
                chronicle = true,
                chronicleBosses = true,
                chronicleChat = false,
                chronicleDeaths = true,
                chronicleGold = true,
                chronicleLevels = true,
                chronicleProfessions = true,
                chronicleRiding = true,
                chronicleSound = true,
                chronicleZones = true,
                welcomeBack = true,
              },
            },
            classBars = {
              modules = {
                classBars = false,
              },
            },
            food = {
              modules = {
                foodDrink = true,
                foodDrinkDrink = true,
                foodDrinkFood = true,
              },
            },
            gear = {
              modules = {
                gearBagIcons = true,
                gearHints = true,
                gearRollIcons = true,
              },
            },
            general = {
              modules = {
                media = true,
                quietLogin = true,
              },
            },
            hazard = {
              modules = {
                hazardAlerts = true,
              },
            },
            healerWatch = {
              modules = {
                healerWatch = true,
              },
            },
            mage = {
              modules = {
                mageConjure = true,
                mageRefreshments = true,
                mageRefreshmentsTrade = true,
                mageTravel = true,
              },
            },
            markerBar = {
              modules = {
                markersBar = true,
              },
            },
            markers = {
              modules = {
                markersTarget = true,
                markersWorld = true,
              },
            },
            navigation = {
              modules = {
                navigation = true,
              },
            },
            notifications = {
              modules = {
                arrival = true,
                arrivalDungeons = true,
                arrivalReducedMotion = false,
                arrivalSubzones = true,
                friendLogin = true,
                friendLoginSound = true,
                trainingNotice = true,
              },
            },
            qol = {
              modules = {
                qolQuickKeybind = true,
              },
            },
            skins = {
              modules = {
                attuneSkin = true,
                auctionatorSkin = true,
                foreverDungeonJournalSkin = true,
                whatsTrainingSkin = true,
              },
            },
            speakstone = {
              modules = {
                speakstoneSkin = true,
              },
            },
            targetArt = {
              modules = {
                targetArt = true,
              },
            },
            worldMap = {
              modules = {
                mapExplore = false,
              },
            },
          },
        },
      },
    },
    retired = {
      [1] = "new-preset",
    },
  },
  [2] = {
    default = "gold",
    hint = "The colour EllesmereUI uses for highlights. Nothing else is recoloured.",
    id = "accent",
    kind = "enum",
    label = "Accent colour",
    options = {
      [1] = {
        ellesmereui = {
          root = {
            euiAccent = {
              custom = {
                b = 0.2901960784313725,
                g = 0.6352941176470588,
                r = 0.788235294117647,
              },
              useClass = false,
            },
          },
        },
        hint = "The layout's own.",
        id = "gold",
        label = "Aged gold",
        swatch = {
          [1] = 0.788235294117647,
          [2] = 0.6352941176470588,
          [3] = 0.2901960784313725,
        },
      },
      [2] = {
        ellesmereui = {
          root = {
            euiAccent = {
              useClass = true,
            },
          },
        },
        hint = "Follows the character you play.",
        id = "class",
        label = "Your class colour",
      },
      [3] = {
        ellesmereui = {
          root = {
            euiAccent = {
              custom = {
                b = 0.57,
                g = 0.58,
                r = 0.36,
              },
              useClass = false,
            },
          },
        },
        id = "verdigris",
        label = "Verdigris",
        swatch = {
          [1] = 0.36,
          [2] = 0.58,
          [3] = 0.57,
        },
      },
      [4] = {
        ellesmereui = {
          root = {
            euiAccent = {
              custom = {
                b = 0.3,
                g = 0.45,
                r = 0.8,
              },
              useClass = false,
            },
          },
        },
        id = "ember",
        label = "Ember",
        swatch = {
          [1] = 0.8,
          [2] = 0.45,
          [3] = 0.3,
        },
      },
      [5] = {
        ellesmereui = {
          root = {
            euiAccent = {
              custom = {
                b = 0.8,
                g = 0.6,
                r = 0.47,
              },
              useClass = false,
            },
          },
        },
        id = "dusk",
        label = "Dusk blue",
        swatch = {
          [1] = 0.47,
          [2] = 0.6,
          [3] = 0.8,
        },
      },
    },
    sets = {
      [1] = "ellesmereui:root.euiAccent",
    },
  },
  [3] = {
    default = "layout",
    hint = "Where the game's default tooltips appear. Follow mouse is an EllesmereUI setting shared by every character on this account.",
    id = "tooltip",
    kind = "enum",
    label = "Tooltip placement",
    options = {
      [1] = {
        ellesmereui = {
          tooltip = {
            cursor = false,
            fixed = {
              x = 900.83,
              y = -496.67,
            },
          },
        },
        hint = "Show tooltips at this layout's configured location.",
        id = "layout",
        label = "Layout position",
      },
      [2] = {
        ellesmereui = {
          tooltip = {
            cursor = true,
          },
        },
        hint = "Keep tooltips near your cursor.",
        id = "cursor",
        label = "Follow mouse",
      },
    },
    sets = {
      [1] = "ellesmereui:tooltip.cursor",
      [2] = "ellesmereui:tooltip.fixedPos",
    },
  },
  [4] = {
    default = "class",
    hint = "How friendly players' nameplates look. Enemy plates, friendly NPCs and your other frames are not touched.",
    id = "friendly-plates",
    kind = "enum",
    label = "Friendly player nameplates",
    options = {
      [1] = {
        ellesmereui = {
          fields = {
            ["nameplates.classColorFriendly"] = true,
            ["nameplates.showFriendlyPlayers"] = true,
          },
        },
        hint = "Use each friendly player's class color.",
        id = "class",
        label = "Class colors",
      },
      [2] = {
        ellesmereui = {
          fields = {
            ["nameplates.showFriendlyPlayers"] = false,
          },
        },
        hint = "Use the standard blue appearance for friendly players.",
        id = "blue",
        label = "Standard blue",
        swatch = {
          [1] = 0.667,
          [2] = 0.667,
          [3] = 1,
        },
      },
    },
    sets = {
      [1] = "ellesmereui:addons.EllesmereUINameplates.showFriendlyPlayers",
      [2] = "ellesmereui:addons.EllesmereUINameplates.classColorFriendly",
    },
  },
  [5] = {
    default = "standard",
    hint = "How large chat, the damage meter and the minimap are drawn, and the text in chat and the meter. Positions follow.",
    id = "size",
    kind = "density",
    label = "Size",
    options = {
      [1] = {
        density = "standard",
        hint = "The size the layout was made at.",
        id = "standard",
        label = "Standard",
      },
      [2] = {
        density = "larger",
        hint = "About 15 percent bigger where there is room. Nothing is made smaller than is readable.",
        id = "larger",
        label = "Larger",
      },
    },
  },
}
