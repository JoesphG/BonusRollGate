-- Every WoW global the addon reads is declared here, so real problems stand out.

local wow_api = {
    -- Libraries
    "LibStub",

    -- Addon metadata
    "C_AddOns",
    "GetAddOnMetadata",

    -- Difficulty
    "DifficultyUtil",
    "GetDifficultyInfo",

    -- Encounter Journal
    "EJ_GetCurrentInstance",
    "EJ_GetCurrentTier",
    "EJ_GetEncounterInfo",
    "EJ_GetEncounterInfoByIndex",
    "EJ_GetInstanceByIndex",
    "EJ_GetNumTiers",
    "EJ_GetTierInfo",
    "EJ_IsValidInstanceDifficulty",
    "EJ_SelectInstance",
    "EJ_SelectTier",

    -- Mythic+
    "C_ChallengeMode",

    -- Bonus roll UI
    "BonusRollFrame",
    "GroupLootContainer",
    "GroupLootContainer_AddFrame",
    "GroupLootContainer_RemoveFrame",

    -- Settings and misc
    "Settings",
    "time",
}

std = "lua51"
max_line_length = 120
codes = true
exclude_files = { "Libs/", "images/", ".release/" }

ignore = {
    "212/self", -- methods kept on the addon table for consistency
}

globals = {
    "BRG_Data", -- SavedVariables
}

read_globals = wow_api

-- The stubs define the client API, so there it is writable.
files["tests/"] = {
    globals = wow_api,
    ignore = { "212" }, -- stub signatures mirror Blizzard's, unused args and all
}
