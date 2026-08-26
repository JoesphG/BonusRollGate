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

-- Encounter Journal: newest tier holds one raid with three bosses.
local EJ_TIER, NEWEST_TIER = 1, 3
local ejRaid = {
    id = 1300,
    name = "Voidscar Bastion",
    bosses = {
        { "Warden Kaelis", 2900 },
        { "The Hollow Choir", 2901 },
        { "Nal'thelun", 2902 },
    },
}
function EJ_GetNumTiers()
    return NEWEST_TIER
end
function EJ_GetCurrentTier()
    return EJ_TIER
end
function EJ_SelectTier(t)
    EJ_TIER = t
end
function EJ_GetInstanceByIndex(i)
    if EJ_TIER ~= NEWEST_TIER or i ~= 1 then
        return nil
    end
    return ejRaid.id, ejRaid.name
end
function EJ_GetEncounterInfoByIndex(j, instanceID)
    if instanceID ~= ejRaid.id then
        return nil
    end
    local b = ejRaid.bosses[j]
    if not b then
        return nil
    end
    return b[1], "desc", b[2]
end
function EJ_GetEncounterInfo(id)
    for _, b in ipairs(ejRaid.bosses) do
        if b[2] == id then
            return b[1]
        end
    end
end
H.encounterIDs = { 2900, 2901, 2902 }
H.tierWhenLoaded = function()
    return EJ_TIER
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
