-- Preview raid: a made-up raid for trying the Rosters tab and its split tools without a group (/nru preview).
-- RaidUtility.GetGroupMembers() returns it while it's on, so the tab runs its normal code. Nothing in preview
-- reaches the game: Arrange and Invite only report what they would do, and Arrange moves the fake members.
local _, RaidUtility = ...
local L = RaidUtility.L
local Preview = {}
RaidUtility.Preview = Preview

local DEFAULT_SIZE, MAX_SIZE = 20, 40

-- name, realm ("" = your realm), class, role, DPS, HPS (nil = no meter data), spec ID (nil = not seen, for the
-- melee/ranged option: Fenwick's damage shaman could be either). You are slot 1; these fill the rest
-- in order, so the first 19 make a 20-player raid with every edge case the tab handles.
-- stylua: ignore start
local FIXTURE = {
    { "Brannoc",  "",          "WARRIOR",     "TANK",    310000, nil,    73   },
    { "Ysolde",   "",          "PALADIN",     "HEALER",  60000,  410000, 65   },
    { "Twin",     "",          "MAGE",        "DAMAGER", 880000, nil,    63   }, -- same name as the next one,
    { "Twin",     "Stormrage", "HUNTER",      "DAMAGER", 860000, nil,    254  }, -- on another realm
    { "Kaelin",   "Draenor",   "ROGUE",       "DAMAGER", 905000, nil,    259  }, -- cross-realm
    { "Morwen",   "",          "PRIEST",      "HEALER",  40000,  395000, 257  },
    { "Thessaly", "",          "DEMONHUNTER", "TANK",    295000, nil,    581  },
    { "Quillon",  "",          "DRUID",       "NONE",    640000, 20000,  102  }, -- no role assigned
    { "Ashka",    "",          "SHAMAN",      "HEALER",  55000,  380000, 264  },
    { "Veyra",    "",          "WARLOCK",     "DAMAGER", 840000, nil,    265  },
    { "Doran",    "",          "DEATHKNIGHT", "DAMAGER", 790000, nil,    252  },
    { "Lirael",   "",          "EVOKER",      "DAMAGER", 870000, nil,    1467 },
    { "Tamsin",   "",          "MONK",        "HEALER",  45000,  360000, 270  },
    { "Corvin",   "",          "HUNTER",      "DAMAGER", 810000, nil,    253  },
    { "Elowen",   "",          "MAGE",        "DAMAGER", 830000, nil,    62   },
    { "Gorrak",   "",          "WARRIOR",     "DAMAGER", 760000, nil,    72   },
    { "Newcomer", "",          "PALADIN",     "DAMAGER", nil,    nil,    70   }, -- joined late: no meter data
    { "Sable",    "",          "ROGUE",       "DAMAGER", 800000, nil,    261  },
    { "Ithren",   "",          "DEMONHUNTER", "DAMAGER", 850000, nil,    577  },
    { "Orla",     "",          "PRIEST",      "DAMAGER", 780000, nil,    258  },
    { "Fenwick",  "",          "SHAMAN",      "DAMAGER", 770000, nil,    nil  }, -- damage shaman, spec not seen yet
    { "Marrow",   "",          "DEATHKNIGHT", "TANK",    300000, nil,    250  },
    { "Seren",    "",          "EVOKER",      "HEALER",  50000,  370000, 1468 },
    { "Halvard",  "Silvermoon","PALADIN",     "DAMAGER", 820000, nil,    70   },
    { "Wren",     "",          "DRUID",       "HEALER",  35000,  355000, 105  },
    { "Bastian",  "",          "WARLOCK",     "DAMAGER", 815000, nil,    266  },
    { "Nyx",      "",          "MONK",        "DAMAGER", 795000, nil,    269  },
    { "Calder",   "",          "HUNTER",      "DAMAGER", 805000, nil,    255  }, -- Survival: a melee hunter
    { "Rhiannon", "",          "MAGE",        "DAMAGER", 845000, nil,    64   },
    { "Tormund",  "",          "WARRIOR",     "DAMAGER", 750000, nil,    71   },
    { "Isolde",   "",          "SHAMAN",      "HEALER",  42000,  350000, 264  },
    { "Varric",   "",          "ROGUE",       "DAMAGER", 825000, nil,    260  },
    { "Ophira",   "",          "PRIEST",      "HEALER",  38000,  365000, 256  },
    { "Kestrel",  "",          "EVOKER",      "DAMAGER", 835000, nil,    1473 },
    { "Dunmore",  "",          "DEATHKNIGHT", "DAMAGER", 785000, nil,    251  },
    { "Saoirse",  "",          "DRUID",       "DAMAGER", 775000, nil,    103  }, -- Feral: a melee druid
    { "Thorne",   "",          "DEMONHUNTER", "DAMAGER", 855000, nil,    577  },
    { "Merrin",   "",          "WARLOCK",     "DAMAGER", 820000, nil,    267  },
    { "Pell",     "",          "MONK",        "TANK",    290000, nil,    268  },
}
-- stylua: ignore end

local active, size = false, DEFAULT_SIZE
local groups = {} -- raid index -> current preview subgroup

function Preview.IsActive() return active end

-- Shown on the Rosters tab while the preview is on, so fake members are never mistaken for the real raid
function Preview.Banner()
    if not active then return "" end
    return "|cFFFF9900"
        .. L["PREVIEW RAID: made-up players, nothing is sent to the game. /nru preview to leave."]
        .. "|r "
end

-- The preview raid as members (same shape as the live group); slot 1 is you
function Preview.Members()
    local home = GetNormalizedRealmName()
    local list = {}
    local name, realm = UnitFullName("player")
    local _, class = UnitClass("player")
    local role = RaidUtility.PlayerSpecRole() or "DAMAGER"
    list[1] = RaidUtility.NewMember(name, (realm and realm ~= "") and realm or home, {
        index = 1,
        name = name,
        class = class,
        role = role,
        subgroup = groups[1],
        online = true,
        previewDps = role == "HEALER" and 50000 or 800000,
        previewHps = role == "HEALER" and 390000 or nil,
    })
    for i = 2, size do
        local e = FIXTURE[i - 1]
        local r = e[2] ~= "" and e[2] or home
        list[i] = RaidUtility.NewMember(e[1], r, {
            index = i,
            name = r == home and e[1] or e[1] .. "-" .. r,
            class = e[3],
            role = e[4],
            subgroup = groups[i],
            online = true,
            previewDps = e[5],
            previewHps = e[6],
            specID = e[7],
        })
    end
    return list
end

-- Moves preview members as Arrange would; anyone left in an overfull group moves to a group with room.
-- placements: { member = member, group = n }. Returns how many members changed group.
function Preview.Apply(placements)
    local moved, placed = 0, {}
    for _, p in ipairs(placements) do
        local i = p.member.index
        if groups[i] ~= p.group then moved = moved + 1 end
        groups[i], placed[i] = p.group, true
    end
    local count = {}
    for i = 1, size do
        count[groups[i]] = (count[groups[i]] or 0) + 1
    end
    for i = 1, size do
        if not placed[i] and count[groups[i]] > 5 then
            for g = 1, 8 do
                if (count[g] or 0) < 5 then
                    count[groups[i]], count[g] = count[groups[i]] - 1, (count[g] or 0) + 1
                    groups[i], moved = g, moved + 1
                    break
                end
            end
        end
    end
    return moved
end

-- The tab shows different people now: drop the old meter reading and redraw with a fresh one
local function Refresh()
    RaidUtility.meter = nil
    if RaidUtility.ui then RaidUtility:RefreshUI(true) end
end

-- size: 2-40 players, default 20
function Preview.Start(newSize)
    if IsInGroup() then
        RaidUtility.Print(L["Leave your group to use the preview raid."])
        return
    end
    size = math.max(2, math.min(MAX_SIZE, math.floor(tonumber(newSize) or DEFAULT_SIZE)))
    for i = 1, MAX_SIZE do
        groups[i] = math.ceil(i / 5)
    end
    active = true
    RaidUtility.Print(
        L["Preview raid on (%d players). Sort groups and Invite only report what they would do."]:format(size)
    )
    Refresh()
    return true
end

-- reason: optional message instead of the default
function Preview.Stop(reason)
    if not active then return end
    active = false
    RaidUtility.Print(reason or L["Preview raid off."])
    Refresh()
end
