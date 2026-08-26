-- BonusRollGate
-- Hides the Blizzard bonus roll prompt for content you do not want to spend
-- Voidcores on. Boss lists are built from the Encounter Journal at runtime
-- rather than hard coded, so a new raid tier needs no addon update.
--
-- Descended from BonusRollFilter by Chawan (public domain), rebuilt for
-- Midnight 12.1.

local ADDON_NAME = ...

local BonusRollGate = LibStub("AceAddon-3.0"):NewAddon("BonusRollGate", "AceEvent-3.0", "AceConsole-3.0", "AceHook-3.0")

local GetAddOnMetadata = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata

-- Difficulty ids. DifficultyUtil.ID is Blizzard's own table; the literals are
-- only a fallback in case it ever moves.
local D = DifficultyUtil and DifficultyUtil.ID or {}
local DIFF = {
    RAID_LFR = D.PrimaryRaidLFR or 17,
    RAID_NORMAL = D.PrimaryRaidNormal or 14,
    RAID_HEROIC = D.PrimaryRaidHeroic or 15,
    RAID_MYTHIC = D.PrimaryRaidMythic or 16,
    RAID_STORY = D.RaidStory or 220,
    RAID_FLEX = D.RaidMythicFlexible or 233,
    RAID_WORLD = D.RaidWorld or 250,
    DUNGEON_NORMAL = D.DungeonNormal or 1,
    DUNGEON_HEROIC = D.DungeonHeroic or 2,
    DUNGEON_MYTHIC = D.DungeonMythic or 23,
    MYTHIC_PLUS = D.DungeonChallenge or 8,
    DELVE = 208,
    WORLD_BOSS = 172,
}

local RAID_DIFFICULTIES = {
    DIFF.RAID_LFR,
    DIFF.RAID_NORMAL,
    DIFF.RAID_HEROIC,
    DIFF.RAID_MYTHIC,
    DIFF.RAID_FLEX,
    DIFF.RAID_STORY,
    DIFF.RAID_WORLD,
}

local DUNGEON_DIFFICULTIES = {
    DIFF.DUNGEON_NORMAL,
    DIFF.DUNGEON_HEROIC,
    DIFF.DUNGEON_MYTHIC,
}

local OTHER_DIFFICULTIES = {
    DIFF.DELVE,
    DIFF.WORLD_BOSS,
}

-- Bosses fought out in the open world rather than inside a raid instance. The
-- journal files them together under a pseudo-instance in its raid list, so the
-- addon has to sort them back out again.
local WORLD_DIFFICULTIES = {
    [DIFF.RAID_WORLD] = true,
    [DIFF.WORLD_BOSS] = true,
}

-- Every difficulty that gets its own dedicated control somewhere in the
-- options tree; anything else the addon runs into lands in "Other content".
local KNOWN_DIFFICULTIES = {}
for _, list in ipairs({ RAID_DIFFICULTIES, DUNGEON_DIFFICULTIES, OTHER_DIFFICULTIES }) do
    for _, id in ipairs(list) do
        KNOWN_DIFFICULTIES[id] = true
    end
end
KNOWN_DIFFICULTIES[DIFF.MYTHIC_PLUS] = true

local DB_SCHEMA = 1

local defaults = {
    profile = {
        schema = DB_SCHEMA,
        enabled = true,
        announce = true,
        mythicPlus = {
            hideAll = false,
            useMinLevel = false,
            minLevel = 10,
        },
        difficulty = {
            ["*"] = {
                hide = false,
                encounters = { ["*"] = false },
            },
        },
    },
    global = {
        seenDifficulties = {},
        seenEncounters = {},
    },
}

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function DifficultyName(difficultyID)
    local name = GetDifficultyInfo and GetDifficultyInfo(difficultyID)
    if name and name ~= "" then
        return name
    end
    return ("Difficulty %d"):format(difficultyID)
end

-- Bosses of the current tier, split by where they are fought: `raid` for
-- instanced bosses, `world` for the tier's world bosses. Cached for the session:
-- walking the journal is cheap but not free, and the data does not change while
-- you are logged in.
local encounterCache

-- A raid the journal lists with no instance map of its own is the world boss
-- container. Older builds do not hand back the map id, so fall back to the
-- container's habit of carrying the expansion's own name.
local function IsWorldBossInstance(instanceName, dungeonAreaMapID, tierName)
    if dungeonAreaMapID == 0 then
        return true
    end
    return tierName ~= nil and instanceName == tierName
end

local function CollectInstanceEncounters(instanceID, instanceName, into)
    -- EJ_GetEncounterInfoByIndex takes an instance id but only answers for the
    -- instance the journal currently has selected, so select it first.
    if EJ_SelectInstance then
        pcall(EJ_SelectInstance, instanceID)
    end

    local j = 1
    while true do
        local encounterName, _, encounterID = EJ_GetEncounterInfoByIndex(j, instanceID)
        if not encounterID then
            break
        end
        if encounterName and not into[encounterID] then
            into[encounterID] = instanceName and ("%s |cff808080(%s)|r"):format(encounterName, instanceName)
                or encounterName
        end
        j = j + 1
    end
end

local function BuildEncounterList()
    local list = { raid = {}, world = {} }

    if not (EJ_GetNumTiers and EJ_GetInstanceByIndex and EJ_GetEncounterInfoByIndex) then
        return list
    end

    -- Bonus rolls only come from current content, so the newest tier is the
    -- whole list; anything older would just be padding it out.
    local tier = EJ_GetNumTiers() or 0
    if tier < 1 then
        return list
    end

    -- EJ_GetInstanceByIndex reads from the selected tier and the boss walk moves
    -- the selected instance, so borrow both and hand them back afterwards.
    local savedTier = EJ_GetCurrentTier and EJ_GetCurrentTier() or nil
    local savedInstance = EJ_GetCurrentInstance and EJ_GetCurrentInstance() or nil

    if pcall(EJ_SelectTier, tier) then
        local tierName = EJ_GetTierInfo and EJ_GetTierInfo(tier) or nil

        local i = 1
        while true do
            local instanceID, instanceName, _, _, _, _, _, dungeonAreaMapID = EJ_GetInstanceByIndex(i, true)
            if not instanceID then
                break
            end

            local bucket = IsWorldBossInstance(instanceName, dungeonAreaMapID, tierName) and list.world or list.raid
            CollectInstanceEncounters(instanceID, instanceName, bucket)

            i = i + 1
        end
    end

    if savedTier and savedTier > 0 then
        pcall(EJ_SelectTier, savedTier)
    end
    if savedInstance and savedInstance > 0 and EJ_SelectInstance then
        pcall(EJ_SelectInstance, savedInstance)
    end

    return list
end

local function GetEncounterList()
    if not encounterCache then
        encounterCache = BuildEncounterList()
    end
    return encounterCache
end

-- Journal bosses for the difficulty being edited, plus anything we have been
-- offered a roll on that the journal does not place at all, so a boss the
-- journal misses still gets a checkbox. Passing no difficulty returns the lot.
function BonusRollGate:GetEncounterChoices(difficultyID)
    local journal = GetEncounterList()
    local choices = {}

    local sources
    if difficultyID == nil then
        sources = { journal.raid, journal.world }
    elseif WORLD_DIFFICULTIES[difficultyID] then
        sources = { journal.world }
    else
        sources = { journal.raid }
    end

    for _, source in ipairs(sources) do
        for id, name in pairs(source) do
            choices[id] = name
        end
    end

    for id, name in pairs(self.db.global.seenEncounters) do
        if not (choices[id] or journal.raid[id] or journal.world[id]) then
            choices[id] = name
        end
    end

    return choices
end

function BonusRollGate:GetKeystoneLevel()
    local cm = C_ChallengeMode
    if not cm then
        return nil
    end

    if cm.GetChallengeCompletionInfo then
        local info = cm.GetChallengeCompletionInfo()
        if info and info.level and info.level > 0 then
            return info.level
        end
    end

    if cm.GetActiveKeystoneInfo then
        local level = cm.GetActiveKeystoneInfo()
        if level and level > 0 then
            return level
        end
    end

    return nil
end

-- Remember what we have been offered rolls on so the options tree can list it.
function BonusRollGate:Learn(info)
    if info.difficultyID and info.difficultyID ~= 0 then
        self.db.global.seenDifficulties[info.difficultyID] = true
    end

    if info.encounterID and info.encounterID ~= 0 and not self.db.global.seenEncounters[info.encounterID] then
        local name = EJ_GetEncounterInfo and EJ_GetEncounterInfo(info.encounterID)
        self.db.global.seenEncounters[info.encounterID] = name or ("Encounter %d"):format(info.encounterID)
    end
end

--------------------------------------------------------------------------------
-- Options
--------------------------------------------------------------------------------

-- The item-quality ramp, which players already read as a difficulty ladder.
local DIFFICULTY_COLOR = {
    [DIFF.RAID_LFR] = "ff9d9d9d",
    [DIFF.RAID_NORMAL] = "ffffffff",
    [DIFF.RAID_HEROIC] = "ff0070dd",
    [DIFF.RAID_MYTHIC] = "ffa335ee",
    [DIFF.RAID_FLEX] = "ffa335ee",
    [DIFF.RAID_STORY] = "ff1eff00",
    [DIFF.RAID_WORLD] = "ffff8000",
    [DIFF.DUNGEON_NORMAL] = "ffffffff",
    [DIFF.DUNGEON_HEROIC] = "ff0070dd",
    [DIFF.DUNGEON_MYTHIC] = "ffa335ee",
    [DIFF.MYTHIC_PLUS] = "ffff8000",
    [DIFF.DELVE] = "ff1eff00",
    [DIFF.WORLD_BOSS] = "ffff8000",
}

local GREY, GOLD, GREEN, RED = "ff808080", "ffffd100", "ff40dd60", "ffff6060"

local function colored(text, hex)
    return ("|c%s%s|r"):format(hex, text)
end

local function ColoredDifficulty(difficultyID)
    return colored(DifficultyName(difficultyID), DIFFICULTY_COLOR[difficultyID] or "ffffffff")
end

-- Count of bosses explicitly hidden at a difficulty, for the tree labels.
function BonusRollGate:HiddenCount(difficultyID)
    local n = 0
    for _, hidden in pairs(self.db.profile.difficulty[difficultyID].encounters) do
        if hidden == true then
            n = n + 1
        end
    end
    return n
end

-- Tree label: coloured difficulty name plus what it is currently doing, so the
-- sidebar alone tells you where your filters live.
function BonusRollGate:DifficultyLabel(difficultyID)
    local cfg = self.db.profile.difficulty[difficultyID]
    local label = ColoredDifficulty(difficultyID)
    if cfg.hide then
        return label .. " " .. colored("(all)", RED)
    end
    local n = self:HiddenCount(difficultyID)
    if n > 0 then
        return label .. " " .. colored("(" .. n .. ")", GOLD)
    end
    return label
end

--- One-line summary of everything currently being filtered.
function BonusRollGate:StatusText()
    if not self.db.profile.enabled then
        return colored("Filtering is off.", RED) .. " Nothing is being hidden."
    end

    local lines, total = {}, 0
    local all = {}
    for _, id in ipairs(RAID_DIFFICULTIES) do
        all[#all + 1] = id
    end
    for _, id in ipairs(DUNGEON_DIFFICULTIES) do
        all[#all + 1] = id
    end
    for _, id in ipairs(OTHER_DIFFICULTIES) do
        all[#all + 1] = id
    end

    for _, id in ipairs(all) do
        local cfg = self.db.profile.difficulty[id]
        if cfg.hide then
            lines[#lines + 1] = ColoredDifficulty(id) .. colored(" - every roll", GREY)
            total = total + 1
        else
            local n = self:HiddenCount(id)
            if n > 0 then
                local suffix = (" - %d boss%s"):format(n, n == 1 and "" or "es")
                lines[#lines + 1] = ColoredDifficulty(id) .. colored(suffix, GREY)
                total = total + 1
            end
        end
    end

    local mp = self.db.profile.mythicPlus
    if mp.hideAll then
        lines[#lines + 1] = colored("Mythic+", DIFFICULTY_COLOR[DIFF.MYTHIC_PLUS]) .. colored(" - every roll", GREY)
        total = total + 1
    elseif mp.useMinLevel then
        lines[#lines + 1] = colored("Mythic+", DIFFICULTY_COLOR[DIFF.MYTHIC_PLUS])
            .. colored((" - below +%d"):format(mp.minLevel), GREY)
        total = total + 1
    end

    if total == 0 then
        return colored("Nothing is filtered yet.", GREEN)
            .. " Every bonus roll will show. Pick bosses on the Raids tab,"
            .. " or use the switches under Dungeons and Other content."
    end

    return colored("Currently hiding:", GOLD) .. "\n" .. table.concat(lines, "\n")
end

function BonusRollGate:ClearAllFilters()
    for _, cfg in pairs(self.db.profile.difficulty) do
        cfg.hide = false
        for id in pairs(cfg.encounters) do
            cfg.encounters[id] = false
        end
    end
    self.db.profile.mythicPlus.hideAll = false
    self.db.profile.mythicPlus.useMinLevel = false
end

local function RaidDifficultyGroup(self, difficultyID, order)
    local function cfg()
        return self.db.profile.difficulty[difficultyID]
    end

    return {
        name = function()
            return self:DifficultyLabel(difficultyID)
        end,
        type = "group",
        order = order,
        args = {
            intro = {
                name = function()
                    return ("Bonus rolls at %s difficulty.\n"):format(ColoredDifficulty(difficultyID))
                end,
                type = "description",
                fontSize = "medium",
                order = 1,
            },
            sweeping = {
                name = " ",
                type = "group",
                inline = true,
                order = 2,
                args = {
                    hide = {
                        name = "Hide every bonus roll at this difficulty",
                        desc = "Overrides the per-boss list below.",
                        type = "toggle",
                        width = "full",
                        order = 1,
                        set = function(_, val)
                            cfg().hide = val
                        end,
                        get = function()
                            return cfg().hide
                        end,
                    },
                },
            },
            perBoss = {
                name = "Per boss",
                type = "group",
                inline = true,
                order = 3,
                disabled = function()
                    return cfg().hide
                end,
                args = {
                    blurb = {
                        name = function()
                            local n = self:HiddenCount(difficultyID)
                            if cfg().hide then
                                return colored(
                                    "Every roll at this difficulty is hidden, so the list below is inactive.",
                                    GREY
                                )
                            elseif n == 0 then
                                return colored("Tick a boss to stop its bonus roll appearing.", GREY)
                            end
                            return colored(("%d boss%s hidden."):format(n, n == 1 and "" or "es"), GOLD)
                        end,
                        type = "description",
                        order = 1,
                    },
                    hideAllBosses = {
                        name = "Check all",
                        desc = "Hide bonus rolls for every boss listed.",
                        type = "execute",
                        order = 2,
                        func = function()
                            local encounters = cfg().encounters
                            for id in pairs(self:GetEncounterChoices(difficultyID)) do
                                encounters[id] = true
                            end
                        end,
                    },
                    showAllBosses = {
                        name = "Clear all",
                        desc = "Show bonus rolls for every boss listed.",
                        type = "execute",
                        order = 3,
                        func = function()
                            local encounters = cfg().encounters
                            for id in pairs(self:GetEncounterChoices(difficultyID)) do
                                encounters[id] = false
                            end
                        end,
                    },
                    bosses = {
                        name = "",
                        type = "multiselect",
                        order = 4,
                        values = function()
                            return self:GetEncounterChoices(difficultyID)
                        end,
                        set = function(_, key, val)
                            cfg().encounters[key] = val
                        end,
                        get = function(_, key)
                            return cfg().encounters[key]
                        end,
                    },
                },
            },
        },
    }
end

local function DifficultyToggle(self, difficultyID, order)
    return {
        name = function()
            return ColoredDifficulty(difficultyID)
        end,
        desc = function()
            return ("Hide bonus rolls offered at %s."):format(DifficultyName(difficultyID))
        end,
        type = "toggle",
        width = "full",
        order = order,
        set = function(_, val)
            self.db.profile.difficulty[difficultyID].hide = val
        end,
        get = function()
            return self.db.profile.difficulty[difficultyID].hide
        end,
    }
end

function BonusRollGate:BuildOptions()
    local options = {
        name = function()
            return "BonusRollGate  " .. colored("v" .. (GetAddOnMetadata(ADDON_NAME, "Version") or "?"), GREY)
        end,
        type = "group",
        childGroups = "tab",
        args = {
            general = {
                name = "General",
                type = "group",
                order = 1,
                args = {
                    banner = {
                        name = colored("Spend your Voidcores where you meant to.", GOLD)
                            .. "\nBonus rolls you have decided against never appear,"
                            .. " so the only prompts you see are ones worth reading.\n",
                        type = "description",
                        fontSize = "medium",
                        image = "Interface\\AddOns\\BonusRollGate\\icon",
                        imageWidth = 48,
                        imageHeight = 48,
                        order = 1,
                    },
                    switches = {
                        name = "Behaviour",
                        type = "group",
                        inline = true,
                        order = 2,
                        args = {
                            enabled = {
                                name = "Enable filtering",
                                desc = "Turn the addon off without losing your settings.",
                                type = "toggle",
                                width = "full",
                                order = 1,
                                set = function(_, val)
                                    self.db.profile.enabled = val
                                end,
                                get = function()
                                    return self.db.profile.enabled
                                end,
                            },
                            announce = {
                                name = "Announce hidden rolls in chat",
                                desc = "Print a reminder that /brg show will bring the roll back.",
                                type = "toggle",
                                width = "full",
                                order = 2,
                                disabled = function()
                                    return not self.db.profile.enabled
                                end,
                                set = function(_, val)
                                    self.db.profile.announce = val
                                end,
                                get = function()
                                    return self.db.profile.announce
                                end,
                            },
                        },
                    },
                    status = {
                        name = "At a glance",
                        type = "group",
                        inline = true,
                        order = 3,
                        args = {
                            text = {
                                name = function()
                                    return self:StatusText()
                                end,
                                type = "description",
                                fontSize = "medium",
                                order = 1,
                            },
                        },
                    },
                    actions = {
                        name = "Actions",
                        type = "group",
                        inline = true,
                        order = 4,
                        args = {
                            show = {
                                name = "Show the current bonus roll",
                                desc = "Same as typing /brg show. Brings back a roll that was hidden,"
                                    .. " as long as its timer is still running.",
                                type = "execute",
                                order = 1,
                                func = function()
                                    self:ShowRoll()
                                end,
                            },
                            clear = {
                                name = "Clear every filter",
                                desc = "Unhide everything, on every difficulty. Your profile is kept.",
                                type = "execute",
                                confirm = true,
                                confirmText = "Clear every filter on every difficulty?",
                                order = 2,
                                func = function()
                                    self:ClearAllFilters()
                                end,
                            },
                        },
                    },
                    help = {
                        name = colored("\nWhere rolls come from in Midnight\n", GOLD)
                            .. "Raid bosses, Mythic+ dungeons, Bountiful Delves and Nightmare Prey each offer a roll. "
                            .. "Raid bosses are filtered individually on the "
                            .. colored("Raids", GOLD)
                            .. " tab; everything else is filtered by content type under "
                            .. colored("Dungeons", GOLD)
                            .. " and "
                            .. colored("Other content", GOLD)
                            .. ".\n\n"
                            .. colored("/brg show", GOLD)
                            .. "  bring back a hidden roll\n"
                            .. colored("/brg config", GOLD)
                            .. "  open this panel",
                        type = "description",
                        order = 5,
                    },
                },
            },
            raids = {
                name = "Raids",
                type = "group",
                childGroups = "tree",
                order = 2,
                args = {},
            },
            dungeons = {
                name = "Dungeons",
                type = "group",
                order = 3,
                args = {
                    mythicPlus = {
                        name = colored("Mythic+", DIFFICULTY_COLOR[DIFF.MYTHIC_PLUS]),
                        type = "group",
                        inline = true,
                        order = 1,
                        args = {
                            hideAllMythicPlus = {
                                name = "Hide bonus rolls in all Mythic+ dungeons",
                                type = "toggle",
                                width = "full",
                                order = 1,
                                set = function(_, val)
                                    self.db.profile.mythicPlus.hideAll = val
                                    if val then
                                        self.db.profile.mythicPlus.useMinLevel = false
                                    end
                                end,
                                get = function()
                                    return self.db.profile.mythicPlus.hideAll
                                end,
                            },
                            useMinLevel = {
                                name = "Only hide below a keystone level",
                                type = "toggle",
                                width = "full",
                                order = 2,
                                disabled = function()
                                    return self.db.profile.mythicPlus.hideAll
                                end,
                                set = function(_, val)
                                    self.db.profile.mythicPlus.useMinLevel = val
                                end,
                                get = function()
                                    return self.db.profile.mythicPlus.useMinLevel
                                end,
                            },
                            minLevel = {
                                name = "Minimum keystone level",
                                desc = "Rolls are hidden when the key you finished was below this level.",
                                type = "range",
                                min = 2,
                                max = 40,
                                step = 1,
                                width = "full",
                                order = 3,
                                disabled = function()
                                    local mp = self.db.profile.mythicPlus
                                    return mp.hideAll or not mp.useMinLevel
                                end,
                                set = function(_, val)
                                    self.db.profile.mythicPlus.minLevel = val
                                end,
                                get = function()
                                    return self.db.profile.mythicPlus.minLevel
                                end,
                            },
                            summary = {
                                name = function()
                                    local mp = self.db.profile.mythicPlus
                                    if mp.hideAll then
                                        return colored("Every Mythic+ bonus roll is hidden.", RED)
                                    elseif mp.useMinLevel then
                                        return colored(("Rolls below +%d are hidden."):format(mp.minLevel), GOLD)
                                    end
                                    return colored("Every Mythic+ bonus roll will show.", GREEN)
                                end,
                                type = "description",
                                order = 4,
                            },
                        },
                    },
                    others = {
                        name = "Other dungeon difficulties",
                        type = "group",
                        inline = true,
                        order = 2,
                        args = {},
                    },
                },
            },
            other = {
                name = "Other content",
                type = "group",
                order = 4,
                args = {
                    known = {
                        name = "Hide bonus rolls from",
                        type = "group",
                        inline = true,
                        order = 1,
                        args = {},
                    },
                },
            },
        },
    }

    for i, difficultyID in ipairs(RAID_DIFFICULTIES) do
        options.args.raids.args["diff" .. difficultyID] = RaidDifficultyGroup(self, difficultyID, i)
    end

    for i, difficultyID in ipairs(DUNGEON_DIFFICULTIES) do
        options.args.dungeons.args.others.args["diff" .. difficultyID] = DifficultyToggle(self, difficultyID, i)
    end

    for i, difficultyID in ipairs(OTHER_DIFFICULTIES) do
        options.args.other.args.known.args["diff" .. difficultyID] = DifficultyToggle(self, difficultyID, i)
    end

    -- Anything the addon has run into that has no dedicated control above.
    local extra, extraOrder = {}, 100
    for difficultyID in pairs(self.db.global.seenDifficulties) do
        if not KNOWN_DIFFICULTIES[difficultyID] then
            extra["diff" .. difficultyID] = DifficultyToggle(self, difficultyID, extraOrder)
            extraOrder = extraOrder + 1
        end
    end

    if next(extra) then
        extra.blurb = {
            name = colored(
                "Difficulties BonusRollGate has been offered a roll on that it did not ship a switch for.",
                GREY
            ),
            type = "description",
            order = 1,
        }
        options.args.other.args.learned = {
            name = "Seen in play",
            type = "group",
            inline = true,
            order = 2,
            args = extra,
        }
    end

    return options
end

--------------------------------------------------------------------------------
-- Addon lifecycle
--------------------------------------------------------------------------------

function BonusRollGate:OnInitialize()
    self.db = LibStub("AceDB-3.0"):New("BRG_Data", defaults)
    self.rollCache = {}

    local registry = LibStub("AceConfigRegistry-3.0")
    local dialog = LibStub("AceConfigDialog-3.0")

    registry:RegisterOptionsTable("BonusRollGate", function()
        return self:BuildOptions()
    end)
    registry:RegisterOptionsTable("BonusRollGate_Profiles", LibStub("AceDBOptions-3.0"):GetOptionsTable(self.db))

    local _, categoryID = dialog:AddToBlizOptions("BonusRollGate", "BonusRollGate")
    self.optionsCategory = categoryID
    dialog:AddToBlizOptions("BonusRollGate_Profiles", "Profiles", "BonusRollGate")

    self:RegisterChatCommand("brg", "SlashCommand")
    self:RegisterChatCommand("bonusrollgate", "SlashCommand")
end

function BonusRollGate:OnEnable()
    if not BonusRollFrame then
        self:Print("BonusRollFrame is missing -- BonusRollGate cannot hook the bonus roll UI.")
        return
    end

    self:SecureHookScript(BonusRollFrame, "OnShow", "BonusRollFrame_OnShow")
    self:SecureHookScript(BonusRollFrame.PromptFrame.RollButton, "OnClick", "OnUserAction")
    self:SecureHookScript(BonusRollFrame.PromptFrame.PassButton, "OnClick", "OnUserAction")
end

--------------------------------------------------------------------------------
-- Filtering
--------------------------------------------------------------------------------

function BonusRollGate:OnUserAction()
    self.userAction = true
end

-- Reads the roll off the frame, filling in anything Blizzard left blank from
-- the first time we saw the same spell. A prompt re-issued after a loading
-- screen can come back without instance data.
function BonusRollGate:CaptureRollInfo(frame)
    local spellID = frame.spellID
    local difficultyID = frame.difficultyID
    local encounterID = frame.encounterID
    local instanceID = frame.instanceID

    local cached = spellID and self.rollCache[spellID]
    if cached then
        if not difficultyID or difficultyID == 0 then
            difficultyID = cached.difficultyID
        end
        if not encounterID or encounterID == 0 then
            encounterID = cached.encounterID
        end
        if not instanceID or instanceID == 0 then
            instanceID = cached.instanceID
        end
    end

    local info = {
        spellID = spellID,
        difficultyID = difficultyID,
        encounterID = encounterID,
        instanceID = instanceID,
    }

    if spellID then
        self.rollCache[spellID] = info
    end

    return info
end

function BonusRollGate:ShouldHide(info)
    local profile = self.db.profile
    local difficultyID = info.difficultyID or 0

    if difficultyID == DIFF.MYTHIC_PLUS then
        local mp = profile.mythicPlus
        if mp.hideAll then
            return true
        end
        if mp.useMinLevel then
            local level = self:GetKeystoneLevel()
            if level and level < mp.minLevel then
                return true
            end
        end
    end

    local cfg = profile.difficulty[difficultyID]
    if cfg.hide then
        return true
    end

    if info.encounterID and info.encounterID ~= 0 and cfg.encounters[info.encounterID] then
        return true
    end

    return false
end

function BonusRollGate:BonusRollFrame_OnShow(frame)
    local info = self:CaptureRollInfo(frame)
    self.currentRoll = info
    self:Learn(info)

    -- This OnShow came from our own /brg show.
    if self.restoring then
        self.restoring = false
        return
    end

    self.userAction = false

    if not self.db.profile.enabled then
        return
    end

    if self:ShouldHide(info) then
        self:HideRoll()
    end
end

function BonusRollGate:HideRoll()
    GroupLootContainer_RemoveFrame(GroupLootContainer, BonusRollFrame)

    if self.db.profile.announce then
        self:Print('Bonus roll hidden, type "/brg show" to open it again.')
    end
end

--- /brg hide: dismiss whatever prompt is on screen, without touching settings.
function BonusRollGate:HideCurrentRoll()
    local frame = BonusRollFrame

    if not frame or not frame:IsShown() then
        self:Print("There is no bonus roll on screen to hide.")
        return
    end

    if frame.state ~= "prompt" then
        self:Print("That roll is already under way and cannot be hidden now.")
        return
    end

    GroupLootContainer_RemoveFrame(GroupLootContainer, frame)
    self:Print('Bonus roll hidden, type "/brg show" to open it again.')
end

function BonusRollGate:ShowRoll()
    local frame = BonusRollFrame

    if not frame or frame.state ~= "prompt" or self.userAction or not frame.endTime or time() > frame.endTime then
        self:Print("No active bonus roll to show.")
        return
    end

    if frame:IsShown() then
        self:Print("The bonus roll is already showing.")
        return
    end

    self.restoring = true
    GroupLootContainer_AddFrame(GroupLootContainer, frame)
end

--------------------------------------------------------------------------------
-- Slash command
--------------------------------------------------------------------------------

local function cmd(text)
    return "|cffffd100" .. text .. "|r"
end

function BonusRollGate:PrintCommands()
    self:Print("Commands:")
    self:Print("  " .. cmd("/brg") .. "         open this list and the options panel")
    self:Print("  " .. cmd("/brg config") .. "  open the options panel")
    self:Print("  " .. cmd("/brg show") .. "    bring back a roll that was hidden")
    self:Print("  " .. cmd("/brg hide") .. "    hide the bonus roll showing right now")
    self:Print("  " .. cmd("/brg toggle") .. "  turn filtering on or off")
    self:Print("  " .. cmd("/brg status") .. "  list what is currently filtered")
    self:Print("  " .. cmd("/bonusrollgate") .. " works anywhere /brg does")
end

function BonusRollGate:OpenOptions()
    if not self.optionsCategory then
        self:Print("Options are not available yet.")
        return false
    end
    Settings.OpenToCategory(self.optionsCategory)
    return true
end

function BonusRollGate:PrintStatus()
    -- StatusText is written for the options panel, where a leading colour code
    -- and embedded newlines are fine; chat needs it line by line.
    for line in (self:StatusText() .. "\n"):gmatch("(.-)\n") do
        if line ~= "" then
            self:Print(line)
        end
    end
end

function BonusRollGate:SlashCommand(input)
    local command = (input or ""):lower():match("^%s*(.-)%s*$")

    if command == "" then
        self:Print("Version " .. (GetAddOnMetadata(ADDON_NAME, "Version") or "unknown"))
        self:PrintCommands()
        self:OpenOptions()
    elseif command == "config" or command == "options" or command == "opt" then
        self:OpenOptions()
    elseif command == "show" then
        self:ShowRoll()
    elseif command == "hide" then
        self:HideCurrentRoll()
    elseif command == "toggle" then
        self.db.profile.enabled = not self.db.profile.enabled
        self:Print(self.db.profile.enabled and "Filtering enabled." or "Filtering disabled.")
    elseif command == "status" then
        self:PrintStatus()
    elseif command == "help" or command == "?" then
        self:PrintCommands()
    else
        self:Print(("Unknown command '%s'."):format(command))
        self:PrintCommands()
    end
end
