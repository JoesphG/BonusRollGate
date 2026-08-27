-- BonusRollGate test suite. Run with: lua5.1 tests/run.lua
-- Drives Core.lua against a stubbed WoW client, the way Blizzard would.

package.path = "tests/?.lua;" .. package.path
local H = require("stubs")

local passed, failed = 0, 0

local function describe(name)
    print("\n" .. name)
end

local function ok(cond, label)
    if cond then
        passed = passed + 1
        print("  \27[32mpass\27[0m  " .. label)
    else
        failed = failed + 1
        print("  \27[31mFAIL\27[0m  " .. label)
    end
end

local function eq(got, want, label)
    if got ~= want then
        label = label .. ("  (expected %s, got %s)"):format(tostring(want), tostring(got))
    end
    ok(got == want, label)
end

local A = H.load("Core.lua")
local P = A.db.profile

local D = {
    LFR = 17,
    NORMAL = 14,
    HEROIC = 15,
    MYTHIC = 16,
    STORY = 220,
    FLEX = 233,
    MPLUS = 8,
    DUNGEON_MYTHIC = 23,
    DELVE = 208,
    WORLD_BOSS = 172,
    WORLD_RAID = 250,
    UNKNOWN = 999,
}
local BOSS = { A = 2900, B = 2901, C = 2902 }

local function reset()
    for _, id in pairs(D) do
        P.difficulty[id].hide = false
        for encounterID in pairs(P.difficulty[id].encounters) do
            P.difficulty[id].encounters[encounterID] = false
        end
    end
    P.enabled = true
    P.announce = true
    P.mythicPlus.hideAll = false
    P.mythicPlus.useMinLevel = false
    P.mythicPlus.minLevel = 10
    H.keystoneLevel = 0
    A.userAction = false
end

local spell = 0
local function roll(fields)
    spell = spell + 1
    fields.spellID = fields.spellID or spell
    return H.roll(fields)
end

--------------------------------------------------------------------------------
describe("defaults let everything through")
reset()
ok(roll({ difficultyID = D.MYTHIC, encounterID = BOSS.A }), "mythic raid boss shows")
ok(roll({ difficultyID = D.MPLUS, encounterID = 0 }), "mythic+ shows")
ok(roll({ difficultyID = D.DELVE, encounterID = 0 }), "delve shows")
ok(roll({ difficultyID = D.UNKNOWN, encounterID = 0 }), "unknown difficulty shows (no nil index)")
ok(roll({ difficultyID = nil, encounterID = nil }), "missing difficulty shows (no nil index)")

--------------------------------------------------------------------------------
describe("per-boss filtering is scoped to one difficulty")
reset()
P.difficulty[D.MYTHIC].encounters[BOSS.A] = true
ok(not roll({ difficultyID = D.MYTHIC, encounterID = BOSS.A }), "filtered boss is hidden on mythic")
ok(roll({ difficultyID = D.HEROIC, encounterID = BOSS.A }), "same boss still shows on heroic")
ok(roll({ difficultyID = D.MYTHIC, encounterID = BOSS.B }), "other boss still shows on mythic")

--------------------------------------------------------------------------------
describe("whole-difficulty switch")
reset()
P.difficulty[D.LFR].hide = true
ok(not roll({ difficultyID = D.LFR, encounterID = BOSS.C }), "every LFR boss is hidden")
ok(roll({ difficultyID = D.NORMAL, encounterID = BOSS.C }), "normal is unaffected")

--------------------------------------------------------------------------------
describe("mythic+ keystone threshold")
reset()
P.mythicPlus.useMinLevel = true
P.mythicPlus.minLevel = 10
H.keystoneLevel = 7
ok(not roll({ difficultyID = D.MPLUS }), "+7 hidden below a threshold of 10")
H.keystoneLevel = 10
ok(roll({ difficultyID = D.MPLUS }), "+10 shows at the threshold")
H.keystoneLevel = 12
ok(roll({ difficultyID = D.MPLUS }), "+12 shows above the threshold")

reset()
P.mythicPlus.hideAll = true
H.keystoneLevel = 30
ok(not roll({ difficultyID = D.MPLUS }), "hide-all beats any keystone level")

--------------------------------------------------------------------------------
describe("mythic flexible obeys mythic")
reset()
P.difficulty[D.MYTHIC].hide = true
ok(not roll({ difficultyID = D.FLEX, encounterID = BOSS.A }), "flex follows a whole-difficulty mythic hide")
reset()
P.difficulty[D.MYTHIC].encounters[BOSS.A] = true
ok(not roll({ difficultyID = D.FLEX, encounterID = BOSS.A }), "flex follows a per-boss mythic hide")
ok(roll({ difficultyID = D.FLEX, encounterID = BOSS.B }), "an unfiltered boss still shows at flex")

--------------------------------------------------------------------------------
describe("master switch")
reset()
P.difficulty[D.MYTHIC].hide = true
P.enabled = false
ok(roll({ difficultyID = D.MYTHIC, encounterID = BOSS.A }), "disabled addon filters nothing")

--------------------------------------------------------------------------------
describe("/brg show restores a hidden roll")
reset()
P.difficulty[D.MYTHIC].hide = true
ok(not roll({ difficultyID = D.MYTHIC, encounterID = BOSS.A }), "roll starts hidden")
A:ShowRoll()
ok(H.isShown(), "show brings it back")

reset()
P.difficulty[D.MYTHIC].hide = true
roll({ difficultyID = D.MYTHIC, encounterID = BOSS.A })
A:OnUserAction()
A:ShowRoll()
ok(not H.isShown(), "show refuses after the user already rolled or passed")

reset()
P.difficulty[D.MYTHIC].hide = true
roll({ difficultyID = D.MYTHIC, encounterID = BOSS.A })
local realNow = H.now
H.now = 99999
A:ShowRoll()
ok(not H.isShown(), "show refuses once the prompt has expired")
H.now = realNow

--------------------------------------------------------------------------------
describe("a prompt re-issued after a loading screen keeps its identity")
reset()
P.difficulty[D.MYTHIC].encounters[BOSS.A] = true
ok(not roll({ spellID = 777, difficultyID = D.MYTHIC, encounterID = BOSS.A }), "first prompt hidden")
ok(
    not roll({ spellID = 777, difficultyID = 0, encounterID = 0, instanceID = 0 }),
    "re-prompt with blanked fields is still hidden"
)

--------------------------------------------------------------------------------
describe("the addon learns what it sees")
reset()
roll({ difficultyID = 777, encounterID = 4242 })
eq(A.db.global.seenDifficulties[777], true, "unseen difficulty is recorded")
ok(A.db.global.seenEncounters[4242] ~= nil, "unseen encounter is recorded")

--------------------------------------------------------------------------------
describe("options tree")
reset()
local opts = H.options()
local function count(t)
    local n = 0
    for _ in pairs(t) do
        n = n + 1
    end
    return n
end
eq(opts.type, "group", "root is a group")
ok(opts.args.general ~= nil, "has a General tab")
ok(opts.args.raids ~= nil, "has a Raids tab")
ok(opts.args.dungeons ~= nil, "has a Dungeons tab")
ok(opts.args.other ~= nil, "has an Other content tab")
eq(count(opts.args.raids.args), 6, "one group per raid difficulty")
ok(opts.args.raids.args["diff233"] == nil, "Mythic flexible has no group of its own")

local bosses = opts.args.raids.args["diff16"].args.perBoss.args.bosses.values()
for _, id in ipairs(H.encounterIDs) do
    ok(bosses[id] ~= nil, "journal boss " .. id .. " is offered as a choice")
end
eq(H.tierWhenLoaded(), 1, "the player's Encounter Journal tier was restored")

--------------------------------------------------------------------------------
describe("the journal walk keeps world bosses off the raid difficulties")
reset()
local mythicBosses = A:GetEncounterChoices(D.MYTHIC)
for _, id in ipairs(H.worldEncounterIDs) do
    ok(mythicBosses[id] == nil, "world boss " .. id .. " is not listed under a raid difficulty")
end
local worldBosses = A:GetEncounterChoices(D.WORLD_BOSS)
for _, id in ipairs(H.worldEncounterIDs) do
    ok(worldBosses[id] ~= nil, "world boss " .. id .. " is listed under World Boss")
end
for _, id in ipairs(H.encounterIDs) do
    ok(worldBosses[id] == nil, "raid boss " .. id .. " is not listed under World Boss")
end
-- World is a difficulty of real raid instances, not of the world boss container
ok(
    A:GetEncounterChoices(D.WORLD_RAID)[H.worldRaidEncounterID] ~= nil,
    "World Raid lists the instanced boss that offers World"
)
ok(
    A:GetEncounterChoices(D.WORLD_RAID)[H.worldEncounterIDs[1]] == nil,
    "World Raid does not list the world boss container"
)

-- a world boss we have actually rolled on must not leak back into the raid list
reset()
roll({ difficultyID = D.WORLD_BOSS, encounterID = H.worldEncounterIDs[1] })
ok(
    A:GetEncounterChoices(D.MYTHIC)[H.worldEncounterIDs[1]] == nil,
    "a world boss seen in play still stays off the raid list"
)
ok(A:GetEncounterChoices(D.MYTHIC)[4242] ~= nil, "a boss the journal does not place at all is still offered everywhere")

--------------------------------------------------------------------------------
describe("each difficulty lists only the bosses it is offered at")
reset()
local N = H.worldRaidEncounterID
for _, id in ipairs({ D.WORLD_RAID, D.NORMAL, D.HEROIC, D.MYTHIC }) do
    ok(A:GetEncounterChoices(id)[N] ~= nil, "Nymrissa is listed at difficulty " .. id)
end
ok(A:GetEncounterChoices(D.LFR)[N] == nil, "Nymrissa is not listed at LFR, which her instance does not offer")
ok(A:GetEncounterChoices(D.STORY)[N] == nil, "nor at Story")

for _, id in ipairs(H.encounterIDs) do
    ok(A:GetEncounterChoices(D.LFR)[id] ~= nil, "the LFR raid still lists boss " .. id)
    ok(A:GetEncounterChoices(D.WORLD_RAID)[id] == nil, "the LFR raid is not listed at World")
end

-- filtering is unchanged: the list only decides what gets a checkbox
reset()
P.difficulty[D.NORMAL].encounters[N] = true
ok(not roll({ difficultyID = D.NORMAL, encounterID = N }), "Nymrissa hides on normal")
ok(roll({ difficultyID = D.WORLD_RAID, encounterID = N }), "and still shows at World until ticked there")

--------------------------------------------------------------------------------
describe("boss lists cover the current tier only")
reset()
for _, id in ipairs(H.previousTierEncounterIDs) do
    ok(A:GetEncounterChoices(D.MYTHIC)[id] == nil, "previous tier boss " .. id .. " is not listed")
    ok(A:GetEncounterChoices(D.WORLD_BOSS)[id] == nil, "previous tier boss " .. id .. " is not listed as a world boss")
end
for _, id in ipairs(H.encounterIDs) do
    ok(A:GetEncounterChoices(D.MYTHIC)[id] ~= nil, "current tier boss " .. id .. " is listed")
end
eq(H.tierWhenLoaded(), 1, "the journal tier is still the player's own")

-- round-trip a boss checkbox through the options handlers
local bossArg = opts.args.raids.args["diff16"].args.perBoss.args.bosses
bossArg.set(nil, BOSS.B, true)
eq(P.difficulty[16].encounters[BOSS.B], true, "options set writes through")
eq(bossArg.get(nil, BOSS.B), true, "options get reads back")
bossArg.set(nil, BOSS.B, false)

--------------------------------------------------------------------------------
describe("options labels reflect state")
reset()
eq(A:HiddenCount(D.MYTHIC), 0, "no bosses hidden to start")
P.difficulty[D.MYTHIC].encounters[BOSS.A] = true
P.difficulty[D.MYTHIC].encounters[BOSS.B] = true
eq(A:HiddenCount(D.MYTHIC), 2, "counts hidden bosses")
ok(A:DifficultyLabel(D.MYTHIC):find("(2)", 1, true) ~= nil, "tree label shows the count")
P.difficulty[D.LFR].hide = true
ok(A:DifficultyLabel(D.LFR):find("(all)", 1, true) ~= nil, "tree label marks a whole-difficulty hide")
ok(A:StatusText():find("Currently hiding") ~= nil, "status lists active filters")

-- a tick for a boss this difficulty does not list must not inflate the count
reset()
P.difficulty[D.LFR].encounters[H.worldRaidEncounterID] = true
eq(A:HiddenCount(D.LFR), 0, "a tick with no checkbox beside it is not counted")
ok(A:StatusText():find("Nothing is filtered yet") ~= nil, "nor does it reach the status line")
ok(
    not roll({ difficultyID = D.LFR, encounterID = H.worldRaidEncounterID }),
    "but it still filters, should a roll somehow arrive"
)
eq(A:HiddenCount(D.NORMAL), 0, "and it stays scoped to its own difficulty")

reset()
ok(A:StatusText():find("Nothing is filtered yet") ~= nil, "status says so when nothing is filtered")
P.enabled = false
ok(A:StatusText():find("Filtering is off") ~= nil, "status calls out the master switch")

--------------------------------------------------------------------------------
describe("clear every filter")
reset()
P.difficulty[D.MYTHIC].encounters[BOSS.A] = true
P.difficulty[D.LFR].hide = true
P.mythicPlus.hideAll = true
A:ClearAllFilters()
eq(P.difficulty[D.MYTHIC].encounters[BOSS.A], false, "boss filters cleared")
eq(P.difficulty[D.LFR].hide, false, "difficulty filters cleared")
eq(P.mythicPlus.hideAll, false, "mythic+ filters cleared")

--------------------------------------------------------------------------------
describe("slash commands")
reset()
H.printed, H.openedCategory = {}, nil
A:SlashCommand("")
ok(#H.printed >= 2, "bare command prints the command list")
eq(H.openedCategory, 41, "bare command also opens the options panel")

H.openedCategory = nil
A:SlashCommand("config")
eq(H.openedCategory, 41, "config opens the settings category")

H.printed = {}
A:SlashCommand("help")
ok(#H.printed >= 2, "help lists commands")

reset()
P.enabled = true
A:SlashCommand("toggle")
eq(P.enabled, false, "toggle turns filtering off")
A:SlashCommand("toggle")
eq(P.enabled, true, "toggle turns filtering back on")

reset()
H.printed = {}
A:SlashCommand("status")
ok(#H.printed >= 1, "status prints something")

-- /brg hide on a live prompt, and on nothing
reset()
roll({ difficultyID = D.NORMAL, encounterID = BOSS.C })
ok(H.isShown(), "roll is on screen")
A:SlashCommand("hide")
ok(not H.isShown(), "hide dismisses the live prompt")

H.printed = {}
A:SlashCommand("hide")
ok(#H.printed == 1 and H.printed[1]:find("no bonus roll") ~= nil, "hide reports when there is nothing to hide")

H.printed = {}
A:SlashCommand("wat")
ok(H.printed[1]:find("Unknown command") ~= nil, "unknown command is reported")

--------------------------------------------------------------------------------
print(("\n%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
