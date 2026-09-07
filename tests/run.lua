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
describe("options pages")
reset()

--- First row of the given kind anywhere on a page.
local function row(pageKey, kind)
    for _, section in ipairs(H.page(pageKey).sections) do
        for _, candidate in ipairs(section.rows) do
            if candidate.kind == kind then
                return candidate
            end
        end
    end
end

local model = H.model()
ok(model.byKey.general ~= nil, "has a General page")
ok(model.byKey.mythicplus ~= nil, "has a Mythic+ page")
ok(model.byKey.dungeons ~= nil, "has a Dungeons page")
ok(model.byKey.other ~= nil, "has an Other content page")
ok(model.byKey.profiles ~= nil, "has a Profiles page")

local raidPages = 0
for _, page in ipairs(model.pages) do
    if page.group == "Raids" then
        raidPages = raidPages + 1
    end
end
eq(raidPages, 6, "one page per raid difficulty")
ok(model.byKey.raid233 == nil, "Mythic flexible has no page of its own")

local bosses = row("raid16", "checklist").values()
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
-- World Boss draws on the pseudo-instance and nothing else
for _, id in ipairs(H.encounterIDs) do
    ok(A:GetEncounterChoices(D.WORLD_BOSS)[id] == nil, "instanced boss " .. id .. " is not a world boss")
end
ok(
    A:GetEncounterChoices(D.WORLD_BOSS)[H.worldRaidEncounterID] == nil,
    "nor is the instanced boss whose raid offers World"
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
for _, id in ipairs({ D.NORMAL, D.HEROIC, D.MYTHIC }) do
    ok(A:GetEncounterChoices(id)[N] ~= nil, "Nymrissa is listed at difficulty " .. id)
end
ok(A:GetEncounterChoices(D.LFR)[N] == nil, "Nymrissa is not listed at LFR, which her instance does not offer")
ok(A:GetEncounterChoices(D.STORY)[N] == nil, "nor at Story")

for _, id in ipairs(H.encounterIDs) do
    ok(A:GetEncounterChoices(D.LFR)[id] ~= nil, "the LFR raid still lists boss " .. id)
end

-- filtering is unchanged: the list only decides what gets a checkbox
reset()
P.difficulty[D.NORMAL].encounters[N] = true
ok(not roll({ difficultyID = D.NORMAL, encounterID = N }), "Nymrissa hides on normal")
ok(roll({ difficultyID = D.HEROIC, encounterID = N }), "and still shows on heroic until ticked there")

--------------------------------------------------------------------------------
describe("World is not a page")
reset()
-- The journal answers that real raid instances offer 250, so a page for it
-- listed the whole tier a second time. It is left unknown instead.
ok(H.page("raid" .. D.WORLD_RAID) == nil, "World Raid has no page of its own")
ok(H.page("world" .. D.WORLD_BOSS) ~= nil, "World Boss does")

local contentTypes = H.page("other")
eq(#contentTypes.sections[1].rows, 1, "Content types is down to one switch")
eq(contentTypes.sections[1].rows[1].label, "Delves", "and it is Delves")

-- Unknown, so a roll at 250 still becomes filterable rather than being lost.
roll({ difficultyID = D.WORLD_RAID, encounterID = N })
eq(A.db.global.seenDifficulties[D.WORLD_RAID], true, "a roll at World is recorded")
local learned = H.page("other").sections[2]
eq(learned.hidden(), false, "which raises the Seen in play section")
ok(learned.rows[2].values()[D.WORLD_RAID] ~= nil, "with a switch for it")

--------------------------------------------------------------------------------
describe("boss lists read in pull order")
reset()
local bossList = row("raid14", "checklist")
ok(bossList.rank ~= nil, "the boss list carries the journal's order")

local ids = {}
for id in pairs(bossList.values()) do
    ids[#ids + 1] = id
end
table.sort(ids, function(a, b)
    return bossList.rank(a) < bossList.rank(b)
end)

local names = {}
for _, id in ipairs(ids) do
    names[#names + 1] = bossList.values()[id]:match("^[^|]+"):gsub("%s+$", "")
end
eq(names[1], "Warden Kaelis", "first boss of the first raid comes first")
eq(names[2], "The Hollow Choir", "then the second")
eq(names[3], "Nal'thelun", "then the third -- alphabetical would have put it first")
eq(names[4], "Nymrissa Wavecaller", "and the next instance follows")

eq(A:EncounterOrder(4242), math.huge, "a boss the journal never placed sorts last")

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
local bossRow = row("raid16", "checklist")
bossRow.set(BOSS.B, true)
eq(P.difficulty[16].encounters[BOSS.B], true, "the boss list writes through")
eq(bossRow.get(BOSS.B), true, "and reads back")
bossRow.set(BOSS.B, false)

--------------------------------------------------------------------------------
describe("sidebar badges reflect state")
reset()
eq(A:HiddenCount(D.MYTHIC), 0, "no bosses hidden to start")
P.difficulty[D.MYTHIC].encounters[BOSS.A] = true
P.difficulty[D.MYTHIC].encounters[BOSS.B] = true
eq(A:HiddenCount(D.MYTHIC), 2, "counts hidden bosses")
ok(H.page("raid16").badge():find("2", 1, true) ~= nil, "the badge shows the count")
P.difficulty[D.LFR].hide = true
ok(H.page("raid17").badge():find("all", 1, true) ~= nil, "and marks a whole-difficulty hide")
reset()
eq(H.page("raid16").badge(), "", "no badge while nothing is hidden")

P.mythicPlus.useMinLevel = true
P.mythicPlus.minLevel = 12
ok(H.page("mythicplus").badge():find("+12", 1, true) ~= nil, "the Mythic+ badge carries the cutoff")
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
eq(H.panel.registered, 1, "the Blizzard AddOns entry was registered at load")

H.printed, H.panel.opened = {}, 0
A:SlashCommand("")
ok(#H.printed >= 2, "bare command prints the command list")
eq(H.panel.opened, 1, "bare command also opens the options window")

A:SlashCommand("config")
eq(H.panel.opened, 2, "config opens the options window")

H.printed = {}
A:SlashCommand("help")
ok(#H.printed >= 2, "help lists commands")

reset()
P.enabled = true
H.panel.refreshed = 0
A:SlashCommand("toggle")
eq(P.enabled, false, "toggle turns filtering off")
eq(H.panel.refreshed, 1, "and tells an open options window to redraw")
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
describe("profiles page")
reset()
local profileList = row("profiles", "list")
eq(#profileList.values(), 1, "one profile to start")
eq(profileList.selected(), "Default", "and it is the active one")
profileList.onSelect("Raiding")
eq(A.db:GetCurrentProfile(), "Raiding", "picking a name switches to it")
eq(#profileList.values(), 2, "and the new profile joins the list")

-- Copy and delete list only the profiles that are not the active one.
local others = H.page("profiles").sections[2].rows[1]
eq(#others.values(), 1, "copy-from offers every other profile")
eq(others.values()[1].key, "Default", "which is the one not in use")
ok(others.confirm("Default"):find("Default", 1, true) ~= nil, "and asks before copying")

-- AceDB r35 raises on these rather than returning, so they never reach it.
local Name = H.ns.NormalizeProfileName
eq(Name("  Raiding  "), "Raiding", "a typed name is trimmed")
eq(Name(""), nil, "an empty name is refused")
eq(Name("   "), nil, "so is one of only spaces")
eq(Name(nil), nil, "and so is nothing at all")
eq(Name(string.rep("x", 50)), string.rep("x", 50), "50 characters is allowed")
eq(Name(string.rep("x", 51)), nil, "51 is not")

--------------------------------------------------------------------------------
print(("\n%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
