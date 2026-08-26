-- Stub WoW client + Ace3 so Core.lua can be loaded and driven under plain
-- Lua 5.1. Only the surface BonusRollGate actually touches is emulated; the
-- AceDB stub reproduces the ["*"] wildcard-default semantics the real library
-- provides, because the filter relies on them.

local H = {}

--------------------------------------------------------------------------- WoW

DifficultyUtil = {
    ID = {
        DungeonNormal = 1,
        DungeonHeroic = 2,
        RaidLFR = 7,
        DungeonChallenge = 8,
        PrimaryRaidNormal = 14,
        PrimaryRaidHeroic = 15,
        PrimaryRaidMythic = 16,
        PrimaryRaidLFR = 17,
        DungeonMythic = 23,
        RaidStory = 220,
        RaidMythicFlexible = 233,
        RaidWorld = 250,
    },
}

local difficultyNames = {
    [1] = "Normal",
    [2] = "Heroic",
    [8] = "Mythic Keystone",
    [14] = "Normal",
    [15] = "Heroic",
    [16] = "Mythic",
    [17] = "Looking For Raid",
    [23] = "Mythic",
    [172] = "World Boss",
    [208] = "Delves",
    [220] = "Story",
    [233] = "Mythic",
    [250] = "World Raid",
}
function GetDifficultyInfo(id)
    return difficultyNames[id]
end

H.now = 1000
function time()
    return H.now
end

C_AddOns = {
    GetAddOnMetadata = function()
        return "test"
    end,
}

H.keystoneLevel = 0
C_ChallengeMode = {
    GetChallengeCompletionInfo = function()
        return { level = H.keystoneLevel }
    end,
    GetActiveKeystoneInfo = function()
        return H.keystoneLevel
    end,
}

H.openedCategory = nil
Settings = {
    OpenToCategory = function(id)
        H.openedCategory = id
    end,
}

-- Encounter Journal. The newest tier holds one raid, plus the pseudo-instance
-- the journal files world bosses under (no instance map, named after the
-- expansion); the tier before it holds a raid of its own. As on the live
-- client, EJ_GetEncounterInfoByIndex only answers for the selected instance.
local EJ_TIER, NEWEST_TIER = 1, 3
local EJ_INSTANCE = nil

local ejTiers = {
    [3] = {
        name = "Midnight",
        instances = {
            {
                id = 1300,
                name = "Voidscar Bastion",
                areaMapID = 2500,
                difficulties = { 17, 14, 15, 16 },
                bosses = {
                    { "Warden Kaelis", 2900 },
                    { "The Hollow Choir", 2901 },
                    { "Nal'thelun", 2902 },
                },
            },
            {
                -- A one-boss instance run at World, Normal, Heroic or Mythic,
                -- the way The Tidebound Grotto is. No LFR.
                id = 1302,
                name = "The Tidebound Grotto",
                areaMapID = 2501,
                difficulties = { 250, 14, 15, 16 },
                bosses = {
                    { "Nymrissa Wavecaller", 2960 },
                },
            },
            {
                id = 1301,
                name = "Midnight",
                areaMapID = 0,
                bosses = {
                    { "Dread Herald Vashj", 2950 },
                },
            },
        },
    },
    [2] = {
        name = "The War Within",
        instances = {
            {
                id = 1200,
                name = "Liberation of Undermine",
                areaMapID = 2400,
                difficulties = { 17, 14, 15, 16 },
                bosses = {
                    { "Vexie and the Geargrinders", 2800 },
                },
            },
        },
    },
}

local function ejInstanceByID(id)
    for _, tier in pairs(ejTiers) do
        for _, inst in ipairs(tier.instances) do
            if inst.id == id then
                return inst
            end
        end
    end
end

function EJ_GetNumTiers()
    return NEWEST_TIER
end
function EJ_GetCurrentTier()
    return EJ_TIER
end
function EJ_SelectTier(t)
    EJ_TIER = t
end
function EJ_GetTierInfo(t)
    return ejTiers[t] and ejTiers[t].name
end
function EJ_GetCurrentInstance()
    return EJ_INSTANCE
end
function EJ_SelectInstance(id)
    EJ_INSTANCE = id
end
function EJ_GetInstanceByIndex(i)
    local tier = ejTiers[EJ_TIER]
    local inst = tier and tier.instances[i]
    if not inst then
        return nil
    end
    return inst.id, inst.name, "desc", nil, nil, nil, nil, inst.areaMapID
end
function EJ_IsValidInstanceDifficulty(difficultyID)
    local inst = ejInstanceByID(EJ_INSTANCE)
    if not (inst and inst.difficulties) then
        return false
    end
    for _, id in ipairs(inst.difficulties) do
        if id == difficultyID then
            return true
        end
    end
    return false
end
function EJ_GetEncounterInfoByIndex(j, instanceID)
    -- The bug from issue #1: without a matching EJ_SelectInstance this is nil.
    if EJ_INSTANCE ~= instanceID then
        return nil
    end
    local inst = ejInstanceByID(instanceID)
    local b = inst and inst.bosses[j]
    if not b then
        return nil
    end
    return b[1], "desc", b[2]
end
function EJ_GetEncounterInfo(id)
    for _, tier in pairs(ejTiers) do
        for _, inst in ipairs(tier.instances) do
            for _, b in ipairs(inst.bosses) do
                if b[2] == id then
                    return b[1]
                end
            end
        end
    end
end

H.encounterIDs = { 2900, 2901, 2902 }
H.worldRaidEncounterID = 2960
H.worldEncounterIDs = { 2950 }
H.previousTierEncounterIDs = { 2800 }
H.tierWhenLoaded = function()
    return EJ_TIER
end
H.selectedInstance = function()
    return EJ_INSTANCE
end

-- Loot container + bonus roll frame
GroupLootContainer = {}
local shown = false
BonusRollFrame = {
    PromptFrame = { RollButton = {}, PassButton = {} },
    state = "prompt",
    endTime = 2000,
    IsShown = function()
        return shown
    end,
}
function GroupLootContainer_RemoveFrame()
    shown = false
end
function GroupLootContainer_AddFrame()
    shown = true
    H._fireOnShow()
end

-------------------------------------------------------------------------- Ace3

local libs = {}
function LibStub(name)
    return libs[name]
end

H.printed = {}
local proto = {}
function proto:Print(...)
    local parts = {}
    for i = 1, select("#", ...) do
        parts[#parts + 1] = tostring((select(i, ...)))
    end
    H.printed[#H.printed + 1] = table.concat(parts, " ")
end
function proto:RegisterChatCommand() end
function proto:SecureHookScript(frame, script, method)
    if frame == BonusRollFrame and script == "OnShow" then
        H._fireOnShow = function()
            self[method](self, frame)
        end
    end
end

libs["AceAddon-3.0"] = {
    NewAddon = function(_, _name)
        local a = setmetatable({}, { __index = proto })
        H.addon = a
        return a
    end,
}

-- Mirrors AceDB's copyDefaults: a "*" table default installs an __index that
-- materialises a fresh copy per key on first access.
local function copyDefaults(dest, src)
    for k, v in pairs(src) do
        if k == "*" then
            if type(v) == "table" then
                setmetatable(dest, {
                    __index = function(t, k2)
                        if k2 == nil then
                            return nil
                        end
                        local sub = {}
                        copyDefaults(sub, v)
                        rawset(t, k2, sub)
                        return sub
                    end,
                })
            end
        elseif type(v) == "table" then
            if type(rawget(dest, k)) ~= "table" then
                rawset(dest, k, {})
            end
            copyDefaults(rawget(dest, k), v)
        elseif rawget(dest, k) == nil then
            rawset(dest, k, v)
        end
    end
    return dest
end

libs["AceDB-3.0"] = {
    New = function(_, _sv, defaults)
        local db = {
            profile = copyDefaults({}, defaults.profile),
            global = copyDefaults({}, defaults.global),
        }
        db.RegisterCallback = function() end
        return db
    end,
}

H.optionTables = {}
libs["AceConfigRegistry-3.0"] = {
    RegisterOptionsTable = function(_, name, t)
        H.optionTables[name] = (type(t) == "function") and t or function()
            return t
        end
    end,
}
libs["AceConfigDialog-3.0"] = {
    AddToBlizOptions = function(_, _app, _name, parent)
        return {}, parent and 42 or 41
    end,
}
libs["AceDBOptions-3.0"] = {
    GetOptionsTable = function()
        return { args = {} }
    end,
}

------------------------------------------------------------------------ driver

function H.load(corePath)
    local chunk = assert(loadfile(corePath))
    chunk("BonusRollGate")
    H.addon:OnInitialize()
    H.addon:OnEnable()
    return H.addon
end

--- Simulate Blizzard raising a bonus roll prompt. Returns true if it stayed up.
function H.roll(fields)
    shown = true
    for k, v in pairs(fields) do
        BonusRollFrame[k] = v
    end
    BonusRollFrame.state = fields.state or "prompt"
    H._fireOnShow()
    return shown
end

function H.isShown()
    return shown
end
function H.setShown(v)
    shown = v
end
function H.options(name)
    return H.optionTables[name or "BonusRollGate"]()
end

return H
