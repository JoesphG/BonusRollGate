-- BonusRollGate test suite. Run with: lua5.1 tests/run.lua
--
-- Loads Core.lua against a stubbed WoW client and drives the filter the way
-- Blizzard would, so the decision table stays honest across API changes.

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
    MPLUS = 8,
    DUNGEON_MYTHIC = 23,
    DELVE = 208,
    UNKNOWN = 999,
}
local BOSS = { A = 2900, B = 2901, C = 2902 }

local function reset()
    for _, id in pairs(D) do
        P.difficulty[id].hide = false
        for _, b in pairs(BOSS) do
            P.difficulty[id].encounters[b] = false
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
eq(count(opts.args.raids.args), 7, "one group per raid difficulty")

local bosses = opts.args.raids.args["diff16"].args.perBoss.args.bosses.values()
for _, id in ipairs(H.encounterIDs) do
    ok(bosses[id] ~= nil, "journal boss " .. id .. " is offered as a choice")
end
eq(H.tierWhenLoaded(), 1, "the player's Encounter Journal tier was restored")

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
