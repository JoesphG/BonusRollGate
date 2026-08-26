-- BonusRollGate
-- Hides the Blizzard bonus roll prompt for content you do not want to spend
-- Voidcores on. Boss lists are built from the Encounter Journal at runtime
-- rather than hard coded, so a new raid tier needs no addon update.
--
-- Descended from BonusRollFilter by Chawan (public domain), rebuilt for
-- Midnight 12.1.

local ADDON_NAME = ...

local BonusRollGate = LibStub("AceAddon-3.0"):NewAddon("BonusRollGate",
    "AceEvent-3.0", "AceConsole-3.0", "AceHook-3.0")

local GetAddOnMetadata = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata

-- Difficulty ids. DifficultyUtil.ID is Blizzard's own table; the literals are
-- only a fallback in case it ever moves.
local D = DifficultyUtil and DifficultyUtil.ID or {}
local DIFF = {
    RAID_LFR       = D.PrimaryRaidLFR or 17,
    RAID_NORMAL    = D.PrimaryRaidNormal or 14,
    RAID_HEROIC    = D.PrimaryRaidHeroic or 15,
    RAID_MYTHIC    = D.PrimaryRaidMythic or 16,
    RAID_STORY     = D.RaidStory or 220,
    RAID_FLEX      = D.RaidMythicFlexible or 233,
    RAID_WORLD     = D.RaidWorld or 250,
    DUNGEON_NORMAL = D.DungeonNormal or 1,
    DUNGEON_HEROIC = D.DungeonHeroic or 2,
    DUNGEON_MYTHIC = D.DungeonMythic or 23,
    MYTHIC_PLUS    = D.DungeonChallenge or 8,
    DELVE          = 208,
    WORLD_BOSS     = 172,
}

local RAID_DIFFICULTIES = {
    DIFF.RAID_LFR, DIFF.RAID_NORMAL, DIFF.RAID_HEROIC, DIFF.RAID_MYTHIC,
    DIFF.RAID_FLEX, DIFF.RAID_STORY, DIFF.RAID_WORLD,
}

local DUNGEON_DIFFICULTIES = {
    DIFF.DUNGEON_NORMAL, DIFF.DUNGEON_HEROIC, DIFF.DUNGEON_MYTHIC,
}

local OTHER_DIFFICULTIES = {
    DIFF.DELVE, DIFF.WORLD_BOSS,
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

-- Bosses of the current and previous raid tier, keyed by journal encounter id.
-- Cached for the session: walking the journal is cheap but not free, and the
-- data does not change while you are logged in.
local encounterCache

local function BuildEncounterList()
    local list = {}

    if not (EJ_GetNumTiers and EJ_GetInstanceByIndex and EJ_GetEncounterInfoByIndex) then
        return list
    end

    local numTiers = EJ_GetNumTiers() or 0
    if numTiers < 1 then
        return list
    end

    -- EJ_GetInstanceByIndex reads from the selected tier, so borrow the
    -- selection and hand it back afterwards.
    local savedTier = EJ_GetCurrentTier and EJ_GetCurrentTier() or nil

    for tier = numTiers, math.max(1, numTiers - 1), -1 do
        if not pcall(EJ_SelectTier, tier) then
            break
        end

        local i = 1
        while true do
            local instanceID, instanceName = EJ_GetInstanceByIndex(i, true)
            if not instanceID then break end

            local j = 1
            while true do
                local encounterName, _, encounterID = EJ_GetEncounterInfoByIndex(j, instanceID)
                if not encounterID then break end
                if encounterName and not list[encounterID] then
                    list[encounterID] = instanceName
                        and ("%s |cff808080(%s)|r"):format(encounterName, instanceName)
                        or encounterName
                end
                j = j + 1
            end

            i = i + 1
        end
    end

    if savedTier and savedTier > 0 then
        pcall(EJ_SelectTier, savedTier)
    end

    return list
end

local function GetEncounterList()
    if not encounterCache then
        encounterCache = BuildEncounterList()
    end
    return encounterCache
end

-- Journal bosses plus anything we have actually been offered a roll on, so a
-- boss the journal does not list still gets a checkbox.
function BonusRollGate:GetEncounterChoices()
    local choices = {}
    for id, name in pairs(GetEncounterList()) do
        choices[id] = name
    end
    for id, name in pairs(self.db.global.seenEncounters) do
        if not choices[id] then
            choices[id] = name
        end
    end
    return choices
end

function BonusRollGate:GetKeystoneLevel()
    local cm = C_ChallengeMode
    if not cm then return nil end

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

    if info.encounterID and info.encounterID ~= 0
        and not self.db.global.seenEncounters[info.encounterID] then
        local name = EJ_GetEncounterInfo and EJ_GetEncounterInfo(info.encounterID)
        self.db.global.seenEncounters[info.encounterID] =
            name or ("Encounter %d"):format(info.encounterID)
    end
end

--------------------------------------------------------------------------------
-- Options
--------------------------------------------------------------------------------

local function RaidDifficultyGroup(self, difficultyID, order)
    local function cfg()
        return self.db.profile.difficulty[difficultyID]
    end

    return {
        name = DifficultyName(difficultyID),
        type = "group",
        order = order,
        args = {
            hide = {
                name = "Hide every bonus roll at this difficulty",
                desc = "Ignores the per-boss list below and hides all of them.",
                type = "toggle",
                width = "full",
                order = 1,
                set = function(_, val) cfg().hide = val end,
                get = function() return cfg().hide end,
            },
            bossHeader = {
                name = "Per boss",
                type = "header",
                order = 2,
            },
            hideAllBosses = {
                name = "Check all",
                desc = "Hide bonus rolls for every boss listed below.",
                type = "execute",
                order = 3,
                func = function()
                    local encounters = cfg().encounters
                    for id in pairs(self:GetEncounterChoices()) do
                        encounters[id] = true
                    end
                end,
            },
            showAllBosses = {
                name = "Clear all",
                desc = "Show bonus rolls for every boss listed below.",
                type = "execute",
                order = 4,
                func = function()
                    local encounters = cfg().encounters
                    for id in pairs(self:GetEncounterChoices()) do
                        encounters[id] = false
                    end
                end,
            },
            bosses = {
                name = "Bosses to hide bonus rolls on",
                type = "multiselect",
                order = 5,
                values = function() return self:GetEncounterChoices() end,
                set = function(_, key, val) cfg().encounters[key] = val end,
                get = function(_, key) return cfg().encounters[key] end,
            },
        },
    }
end

local function DifficultyToggle(self, difficultyID, order, nameOverride)
    return {
        name = nameOverride or DifficultyName(difficultyID),
        desc = ("Hide bonus rolls offered at difficulty %d."):format(difficultyID),
        type = "toggle",
        width = "full",
        order = order,
        set = function(_, val) self.db.profile.difficulty[difficultyID].hide = val end,
        get = function() return self.db.profile.difficulty[difficultyID].hide end,
    }
end

function BonusRollGate:BuildOptions()
    local options = {
        name = "BonusRollGate",
        type = "group",
        childGroups = "tab",
        args = {
            general = {
                name = "General",
                type = "group",
                order = 1,
                args = {
                    enabled = {
                        name = "Enable filtering",
                        desc = "Turn the whole addon off without losing your settings.",
                        type = "toggle",
                        width = "full",
                        order = 1,
                        set = function(_, val) self.db.profile.enabled = val end,
                        get = function() return self.db.profile.enabled end,
                    },
                    announce = {
                        name = "Announce hidden rolls in chat",
                        desc = "Print a reminder that /brg show will bring the roll back.",
                        type = "toggle",
                        width = "full",
                        order = 2,
                        set = function(_, val) self.db.profile.announce = val end,
                        get = function() return self.db.profile.announce end,
                    },
                    spacer = { name = "", type = "description", order = 3 },
                    show = {
                        name = "Show the current bonus roll",
                        desc = "Same as typing /brg show.",
                        type = "execute",
                        order = 4,
                        func = function() self:ShowRoll() end,
                    },
                    help = {
                        name = "\n|cffffd100Bonus rolls in Midnight|r\n"
                            .. "Raid bosses, Mythic+ dungeons, Bountiful Delves and Nightmare "
                            .. "Prey each offer a roll. Raid bosses are filtered individually "
                            .. "on the Raids tab; everything else is filtered by content type.",
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
                    mythicPlusHeader = {
                        name = "Mythic+",
                        type = "header",
                        order = 1,
                    },
                    hideAllMythicPlus = {
                        name = "Hide bonus rolls in all Mythic+ dungeons",
                        type = "toggle",
                        width = "full",
                        order = 2,
                        set = function(_, val)
                            self.db.profile.mythicPlus.hideAll = val
                            if val then
                                self.db.profile.mythicPlus.useMinLevel = false
                            end
                        end,
                        get = function() return self.db.profile.mythicPlus.hideAll end,
                    },
                    useMinLevel = {
                        name = "Hide below a keystone level",
                        type = "toggle",
                        width = "full",
                        order = 3,
                        disabled = function() return self.db.profile.mythicPlus.hideAll end,
                        set = function(_, val) self.db.profile.mythicPlus.useMinLevel = val end,
                        get = function() return self.db.profile.mythicPlus.useMinLevel end,
                    },
                    minLevel = {
                        name = "Minimum keystone level",
                        desc = "Rolls are hidden when the completed key was below this level.",
                        type = "range",
                        min = 2, max = 40, step = 1,
                        order = 4,
                        disabled = function()
                            local mp = self.db.profile.mythicPlus
                            return mp.hideAll or not mp.useMinLevel
                        end,
                        set = function(_, val) self.db.profile.mythicPlus.minLevel = val end,
                        get = function() return self.db.profile.mythicPlus.minLevel end,
                    },
                    otherHeader = {
                        name = "Other dungeon difficulties",
                        type = "header",
                        order = 10,
                    },
                },
            },
            other = {
                name = "Other content",
                type = "group",
                order = 4,
                args = {
                    header = {
                        name = "Hide bonus rolls from",
                        type = "header",
                        order = 1,
                    },
                },
            },
        },
    }

    for i, difficultyID in ipairs(RAID_DIFFICULTIES) do
        options.args.raids.args["diff" .. difficultyID] =
            RaidDifficultyGroup(self, difficultyID, i)
    end

    for i, difficultyID in ipairs(DUNGEON_DIFFICULTIES) do
        options.args.dungeons.args["diff" .. difficultyID] =
            DifficultyToggle(self, difficultyID, 10 + i)
    end

    for i, difficultyID in ipairs(OTHER_DIFFICULTIES) do
        options.args.other.args["diff" .. difficultyID] =
            DifficultyToggle(self, difficultyID, 10 + i)
    end

    -- Anything the addon has run into that has no dedicated control above.
    local extraOrder = 100
    for difficultyID in pairs(self.db.global.seenDifficulties) do
        if not KNOWN_DIFFICULTIES[difficultyID] then
            options.args.other.args["diff" .. difficultyID] =
                DifficultyToggle(self, difficultyID, extraOrder)
            extraOrder = extraOrder + 1
        end
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
    registry:RegisterOptionsTable("BonusRollGate_Profiles",
        LibStub("AceDBOptions-3.0"):GetOptionsTable(self.db))

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
        if not difficultyID or difficultyID == 0 then difficultyID = cached.difficultyID end
        if not encounterID or encounterID == 0 then encounterID = cached.encounterID end
        if not instanceID or instanceID == 0 then instanceID = cached.instanceID end
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

function BonusRollGate:ShowRoll()
    local frame = BonusRollFrame

    if not frame or frame.state ~= "prompt" or self.userAction
        or not frame.endTime or time() > frame.endTime then
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

function BonusRollGate:SlashCommand(command)
    command = (command or ""):lower():match("^%s*(.-)%s*$")

    if command == "show" then
        self:ShowRoll()
    elseif command == "config" or command == "options" then
        if self.optionsCategory then
            Settings.OpenToCategory(self.optionsCategory)
        else
            self:Print("Options are not available yet.")
        end
    else
        self:Print("Version: " .. (GetAddOnMetadata(ADDON_NAME, "Version") or "unknown"))
        self:Print("/brg show - shows the bonus roll if it was hidden")
        self:Print("/brg config - opens the configuration window")
    end
end
