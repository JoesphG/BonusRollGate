-- Options window smoke test. Run with: lua5.1 tests/ui.lua
--
-- Builds the real window against a stubbed frame API and walks every page
-- twice, so the layout pass, the pooled list rows and every get/disabled/badge
-- closure in the model are executed. It proves the window builds and redraws,
-- not that it looks right; the client is the only judge of that.
--
-- Separate from run.lua because loading the real UI replaces the fake Panel
-- that suite installs to watch Core reach for it.

package.path = "tests/?.lua;" .. package.path
local H = require("stubs")
local Frames = require("frames")

local passed, failed = 0, 0

local function ok(cond, label)
    if cond then
        passed = passed + 1
        print("  \27[32mpass\27[0m  " .. label)
    else
        failed = failed + 1
        print("  \27[31mFAIL\27[0m  " .. label)
    end
end

local function attempt(label, fn)
    local success, err = pcall(fn)
    ok(success, label .. (success and "" or ("  (" .. tostring(err) .. ")")))
end

Frames.install()

local addon = H.load("Core.lua")
local ns = H.ns

-- The real thing, over the top of the fake Panel run.lua's suite installs.
assert(loadfile("UI/Widgets.lua"))("BonusRollGate", ns)
assert(loadfile("UI/Panel.lua"))("BonusRollGate", ns)

print("\noptions window")

attempt("registers an entry in the Blizzard AddOns list", function()
    ns.Panel.RegisterSettingsCategory()
end)
ok(Frames.categoryRegistered, "and the category reached Settings")

attempt("opens", function()
    ns.Panel.Open()
end)
ok(ns.Panel.IsShown(), "and reports itself shown")

local pages = ns.Model.Build(addon).pages
ok(#pages == 13, "thirteen pages: General, five raid, World Bosses, two dungeon, Delves, Prey, Seen in play, Profiles")

-- Twice over: the first pass builds each page, the second re-lays it out, which
-- is where a pooled row that failed to reset would show up.
for pass = 1, 2 do
    for _, page in ipairs(pages) do
        attempt(("pass %d: %s lays out"):format(pass, page.key), function()
            ns.Panel.ShowPage(page.key)
            ns.Panel.Refresh()
        end)
    end
end

print("\nwith filters in force")

-- A whole-difficulty hide greys the boss list; a hidden section has to fold
-- away without leaving a hole. Both are layout paths the empty profile misses.
addon.db.profile.difficulty[16].hide = true
addon.db.profile.difficulty[14].encounters[2900] = true
addon.db.global.seenDifficulties[777] = true
addon.db.profile.mythicPlus.useMinLevel = true

for _, key in ipairs({ "raid16", "raid14", "world172", "delves", "seen", "mythicplus", "general" }) do
    attempt(key .. " redraws with filters set", function()
        ns.Panel.ShowPage(key)
        ns.Panel.Refresh()
    end)
end

attempt("closes", function()
    ns.Panel.Toggle()
end)
ok(not ns.Panel.IsShown(), "and reports itself hidden")
ok(select(2, pcall(ns.Panel.Refresh)) == nil, "refreshing a closed window is a no-op")

print(("\n%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
