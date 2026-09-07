-- BonusRollGate -- hides the bonus roll prompt for content you have ruled out.
-- Boss lists come from the Encounter Journal at runtime, so a new tier needs no
-- addon update. Descended from BonusRollFilter by Chawan (public domain).

local ADDON_NAME, ns = ...

local BonusRollGate = LibStub("AceAddon-3.0"):NewAddon("BonusRollGate", "AceEvent-3.0", "AceConsole-3.0", "AceHook-3.0")

local GetAddOnMetadata = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata

-- DifficultyUtil.ID is Blizzard's table; the literals are a fallback.
local D = DifficultyUtil and DifficultyUtil.ID or {}
local DIFF = {
    RAID_LFR = D.PrimaryRaidLFR or 17,
    RAID_NORMAL = D.PrimaryRaidNormal or 14,
    RAID_HEROIC = D.PrimaryRaidHeroic or 15,
    RAID_MYTHIC = D.PrimaryRaidMythic or 16,
    RAID_STORY = D.RaidStory or 220,
    RAID_WORLD = D.RaidWorld or 250,
    -- Flexible-size Mythic. The client calls it "Mythic" too, so it gets no
    -- control of its own and is folded into Mythic at filter time.
    RAID_FLEX = D.RaidMythicFlexible or 233,
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
    DIFF.RAID_STORY,
}

local DUNGEON_DIFFICULTIES = {
    DIFF.DUNGEON_NORMAL,
    DIFF.DUNGEON_HEROIC,
    DIFF.DUNGEON_MYTHIC,
}

local OTHER_DIFFICULTIES = {
    DIFF.DELVE,
}

-- World Boss (172) gets a per-boss page of its own, drawn from the journal's
-- world boss pseudo-instance rather than the instanced raid list.
local WORLD_DIFFICULTIES = {
    [DIFF.WORLD_BOSS] = true,
}

-- Has a dedicated control somewhere; anything else lands in "Other content".
local KNOWN_DIFFICULTIES = {}
for _, list in ipairs({ RAID_DIFFICULTIES, DUNGEON_DIFFICULTIES, OTHER_DIFFICULTIES }) do
    for _, id in ipairs(list) do
        KNOWN_DIFFICULTIES[id] = true
    end
end
KNOWN_DIFFICULTIES[DIFF.MYTHIC_PLUS] = true
KNOWN_DIFFICULTIES[DIFF.RAID_FLEX] = true
KNOWN_DIFFICULTIES[DIFF.WORLD_BOSS] = true

-- World (250) has no page. The journal answers that real raid instances offer
-- it, so a page listed the whole tier over again beside Normal and Heroic; and
-- despite the name it is not where world bosses live. Left unknown, so a roll
-- at 250 raises a switch under "Seen in play" rather than being unfilterable.

-- The options window is built from these; it knows nothing else about the addon.
ns.addon = BonusRollGate
ns.DIFF = DIFF
ns.RAID_DIFFICULTIES = RAID_DIFFICULTIES
ns.DUNGEON_DIFFICULTIES = DUNGEON_DIFFICULTIES
ns.OTHER_DIFFICULTIES = OTHER_DIFFICULTIES
ns.KNOWN_DIFFICULTIES = KNOWN_DIFFICULTIES

function ns.Version()
    return "v" .. (GetAddOnMetadata(ADDON_NAME, "Version") or "?")
end

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

-- Current-tier bosses, split into `raid` and `world`, with the journal's own
-- order recorded so the boss lists read in pull order. Cached for the session.
local encounterCache

-- The world boss container has no instance map. Falls back to its habit of
-- carrying the expansion's name when the journal withholds the map id.
local function IsWorldBossInstance(instanceName, dungeonAreaMapID, tierName)
    if dungeonAreaMapID == 0 then
        return true
    end
    return tierName ~= nil and instanceName == tierName
end

-- Raid difficulties the selected instance offers. nil when the journal will not
-- say, which lists the instance everywhere rather than nowhere.
local function InstanceDifficulties()
    if not EJ_IsValidInstanceDifficulty then
        return nil
    end

    local valid, answered = {}, false
    for _, difficultyID in ipairs(RAID_DIFFICULTIES) do
        local ok, isValid = pcall(EJ_IsValidInstanceDifficulty, difficultyID)
        if ok and isValid then
            valid[difficultyID] = true
            answered = true
        end
    end

    return answered and valid or nil
end

local function CollectInstanceEncounters(instanceID, instanceName, into, list)
    -- EJ_GetEncounterInfoByIndex only answers for the selected instance.
    if EJ_SelectInstance then
        pcall(EJ_SelectInstance, instanceID)
    end

    local difficulties = InstanceDifficulties()

    local j = 1
    while true do
        local encounterName, _, encounterID = EJ_GetEncounterInfoByIndex(j, instanceID)
        if not encounterID then
            break
        end
        if encounterName and not into[encounterID] then
            into[encounterID] = instanceName and ("%s |cff808080(%s)|r"):format(encounterName, instanceName)
                or encounterName
            list.validAt[encounterID] = difficulties
            -- One counter across the whole walk: instances in journal order,
            -- bosses in pull order within each.
            list.n = list.n + 1
            list.order[encounterID] = list.n
        end
        j = j + 1
    end
end

local function BuildEncounterList()
    local list = { raid = {}, world = {}, validAt = {}, order = {}, n = 0 }

    if not (EJ_GetNumTiers and EJ_GetInstanceByIndex and EJ_GetEncounterInfoByIndex) then
        return list
    end

    -- Rolls only come from current content, so the newest tier is the whole list.
    local tier = EJ_GetNumTiers() or 0
    if tier < 1 then
        return list
    end

    -- The walk moves the selected tier and instance; borrow both, hand them back.
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
            CollectInstanceEncounters(instanceID, instanceName, bucket, list)

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

-- Bosses for one difficulty, plus any the journal does not place at all. No
-- difficulty returns the lot.
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
            local validAt = journal.validAt[id]
            if difficultyID == nil or validAt == nil or validAt[difficultyID] then
                choices[id] = name
            end
        end
    end

    for id, name in pairs(self.db.global.seenEncounters) do
        if not (choices[id] or journal.raid[id] or journal.world[id]) then
            choices[id] = name
        end
    end

    return choices
end

--- Where a boss sits in the Encounter Journal. Bosses the journal does not
--- place at all sort after the ones it does.
function BonusRollGate:EncounterOrder(encounterID)
    return GetEncounterList().order[encounterID] or math.huge
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
-- State the options window reads
--
-- The window itself lives in UI/. Everything here is plain data or a string, so
-- the same functions answer /brg status in chat.
--------------------------------------------------------------------------------

-- The item-quality ramp, which players already read as a difficulty ladder.
local DIFFICULTY_COLOR = {
    [DIFF.RAID_LFR] = "ff9d9d9d",
    [DIFF.RAID_NORMAL] = "ffffffff",
    [DIFF.RAID_HEROIC] = "ff0070dd",
    [DIFF.RAID_MYTHIC] = "ffa335ee",
    [DIFF.RAID_STORY] = "ff1eff00",
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

ns.DIFFICULTY_COLOR = DIFFICULTY_COLOR
ns.DifficultyName = DifficultyName
ns.ColoredDifficulty = ColoredDifficulty
ns.colored = colored
ns.GREY, ns.GOLD, ns.GREEN, ns.RED = GREY, GOLD, GREEN, RED

-- Bosses hidden at a difficulty, counting only the ones it lists. A tick left by
-- an older, wider list is unreachable, but stays in the profile as a safety net.
function BonusRollGate:HiddenCount(difficultyID)
    local encounters = self.db.profile.difficulty[difficultyID].encounters
    local n = 0
    for id in pairs(self:GetEncounterChoices(difficultyID)) do
        if encounters[id] == true then
            n = n + 1
        end
    end
    return n
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
            .. " Every bonus roll will show. Pick bosses under Raids,"
            .. " or use the switches under Dungeons and Other."
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

--------------------------------------------------------------------------------
-- Addon lifecycle
--------------------------------------------------------------------------------

function BonusRollGate:OnInitialize()
    self.db = LibStub("AceDB-3.0"):New("BRG_Data", defaults)
    self.rollCache = {}

    -- Switching, copying or resetting a profile swaps the table every control
    -- reads from, so the window has to be told.
    self.db.RegisterCallback(self, "OnProfileChanged", "RefreshOptions")
    self.db.RegisterCallback(self, "OnProfileCopied", "RefreshOptions")
    self.db.RegisterCallback(self, "OnProfileReset", "RefreshOptions")

    if ns.Panel then
        ns.Panel.RegisterSettingsCategory()
    end

    self:RegisterChatCommand("brg", "SlashCommand")
    self:RegisterChatCommand("bonusrollgate", "SlashCommand")
end

function BonusRollGate:RefreshOptions()
    if ns.Panel then
        ns.Panel.Refresh()
    end
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

-- Reads the roll off the frame, filling blanks from the first sighting of the
-- same spell: a prompt re-issued after a loading screen loses its instance data.
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

    -- Flexible-size Mythic has no controls of its own; it obeys Mythic's.
    if difficultyID == DIFF.RAID_FLEX then
        difficultyID = DIFF.RAID_MYTHIC
    end

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
    self:Print("Support: " .. cmd("https://discord.gg/zHT3bGEQ52"))
end

function BonusRollGate:OpenOptions()
    if not ns.Panel then
        self:Print("Options are not available yet.")
        return false
    end
    ns.Panel.Open()
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
        self:RefreshOptions()
    elseif command == "status" then
        self:PrintStatus()
    elseif command == "help" or command == "?" then
        self:PrintCommands()
    else
        self:Print(("Unknown command '%s'."):format(command))
        self:PrintCommands()
    end
end
