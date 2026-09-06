-- The options panel described as data: pages, sections, rows.
--
-- No frames are created here, so this file runs under plain Lua and the test
-- suite asserts against it the way it used to assert against the Ace3 tree.
-- Panel.lua turns it into widgets and knows nothing about what the addon does.
--
-- Rebuilt each time the window opens, because "Seen in play" grows as the addon
-- meets difficulties it did not ship a switch for.

local _, ns = ...

local Model = {}
ns.Model = Model

--------------------------------------------------------------------------------
-- Row constructors
--------------------------------------------------------------------------------

local function Check(label, desc, get, set, disabled)
    return { kind = "check", label = label, desc = desc, get = get, set = set, disabled = disabled }
end

local function Text(get, color)
    return { kind = "text", get = get, color = color }
end

--------------------------------------------------------------------------------
-- Pages
--------------------------------------------------------------------------------

local function GeneralPage(addon)
    local colored, GOLD, GREY = ns.colored, ns.GOLD, ns.GREY
    local profile = function()
        return addon.db.profile
    end

    return {
        key = "general",
        title = "General",
        sections = {
            {
                title = "At a glance",
                rows = {
                    Text(function()
                        return addon:StatusText()
                    end),
                },
            },
            {
                title = "Behaviour",
                rows = {
                    Check("Enable filtering", "Turn the addon off without losing your settings.", function()
                        return profile().enabled
                    end, function(value)
                        profile().enabled = value
                    end),
                    Check(
                        "Announce hidden rolls in chat",
                        "Print a reminder that /brg show will bring the roll back.",
                        function()
                            return profile().announce
                        end,
                        function(value)
                            profile().announce = value
                        end,
                        function()
                            return not profile().enabled
                        end
                    ),
                },
            },
            {
                title = "Actions",
                rows = {
                    {
                        kind = "buttons",
                        buttons = {
                            {
                                label = "Show the current roll",
                                desc = "Same as typing /brg show. Brings back a roll that was hidden,"
                                    .. " as long as its timer is still running.",
                                func = function()
                                    addon:ShowRoll()
                                end,
                            },
                            {
                                label = "Clear every filter",
                                desc = "Unhide everything, on every difficulty. Your profile is kept.",
                                confirm = "Clear every filter on every difficulty?",
                                func = function()
                                    addon:ClearAllFilters()
                                end,
                            },
                        },
                    },
                },
            },
            {
                title = "Where rolls come from in Midnight",
                rows = {
                    Text(function()
                        return "Raid bosses, Mythic+ dungeons, Bountiful Delves and Nightmare Prey each offer a roll."
                            .. " Raid bosses are filtered one at a time under "
                            .. colored("Raids", GOLD)
                            .. "; everything else is filtered by content type under "
                            .. colored("Dungeons", GOLD)
                            .. " and "
                            .. colored("Other", GOLD)
                            .. ".\n\n"
                            .. colored("/brg show", GOLD)
                            .. "  bring back a hidden roll\n"
                            .. colored("/brg config", GOLD)
                            .. "  open this window"
                    end, GREY),
                },
            },
        },
    }
end

local function RaidPage(addon, difficultyID)
    local colored, GOLD, GREY, RED = ns.colored, ns.GOLD, ns.GREY, ns.RED

    local function cfg()
        return addon.db.profile.difficulty[difficultyID]
    end

    local function everythingHidden()
        return cfg().hide
    end

    return {
        key = "raid" .. difficultyID,
        title = ns.DifficultyName(difficultyID),
        color = ns.DIFFICULTY_COLOR[difficultyID],
        group = "Raids",
        difficultyID = difficultyID,
        badge = function()
            if cfg().hide then
                return colored("all", RED)
            end
            local n = addon:HiddenCount(difficultyID)
            return n > 0 and colored(tostring(n), GOLD) or ""
        end,
        sections = {
            {
                title = "This difficulty",
                rows = {
                    Check("Hide every bonus roll at this difficulty", "Overrides the per-boss list below.", function()
                        return cfg().hide
                    end, function(value)
                        cfg().hide = value
                    end),
                },
            },
            {
                title = "Per boss",
                disabled = everythingHidden,
                blurb = function()
                    if cfg().hide then
                        return colored("Every roll at this difficulty is hidden, so the list below is inactive.", GREY)
                    end
                    local n = addon:HiddenCount(difficultyID)
                    if n == 0 then
                        return colored("Tick a boss to stop its bonus roll appearing.", GREY)
                    end
                    return colored(("%d boss%s hidden."):format(n, n == 1 and "" or "es"), GOLD)
                end,
                rows = {
                    {
                        kind = "buttons",
                        disabled = everythingHidden,
                        buttons = {
                            {
                                label = "Check all",
                                desc = "Hide bonus rolls for every boss listed.",
                                func = function()
                                    for id in pairs(addon:GetEncounterChoices(difficultyID)) do
                                        cfg().encounters[id] = true
                                    end
                                end,
                            },
                            {
                                label = "Clear all",
                                desc = "Show bonus rolls for every boss listed.",
                                func = function()
                                    for id in pairs(addon:GetEncounterChoices(difficultyID)) do
                                        cfg().encounters[id] = false
                                    end
                                end,
                            },
                        },
                    },
                    {
                        kind = "checklist",
                        disabled = everythingHidden,
                        empty = "The Encounter Journal lists no bosses at this difficulty.",
                        values = function()
                            return addon:GetEncounterChoices(difficultyID)
                        end,
                        get = function(id)
                            return cfg().encounters[id]
                        end,
                        set = function(id, value)
                            cfg().encounters[id] = value
                        end,
                    },
                },
            },
        },
    }
end

-- Dungeons and Other content filter by content type, so one checkbox per
-- difficulty is the whole page.
local function DifficultyCheck(addon, difficultyID)
    return Check(
        ns.DifficultyName(difficultyID),
        ("Hide bonus rolls offered at %s."):format(ns.DifficultyName(difficultyID)),
        function()
            return addon.db.profile.difficulty[difficultyID].hide
        end,
        function(value)
            addon.db.profile.difficulty[difficultyID].hide = value
        end
    )
end

local function MythicPlusPage(addon)
    local colored, GOLD, GREEN, RED = ns.colored, ns.GOLD, ns.GREEN, ns.RED

    local function mp()
        return addon.db.profile.mythicPlus
    end

    return {
        key = "mythicplus",
        title = "Mythic+",
        color = ns.DIFFICULTY_COLOR[ns.DIFF.MYTHIC_PLUS],
        group = "Dungeons",
        badge = function()
            if mp().hideAll then
                return colored("all", RED)
            elseif mp().useMinLevel then
                return colored("+" .. mp().minLevel, GOLD)
            end
            return ""
        end,
        sections = {
            {
                title = "Keystone dungeons",
                rows = {
                    Check("Hide bonus rolls in all Mythic+ dungeons", nil, function()
                        return mp().hideAll
                    end, function(value)
                        mp().hideAll = value
                        -- The two switches would otherwise contradict each other.
                        if value then
                            mp().useMinLevel = false
                        end
                    end),
                    Check("Only hide below a keystone level", nil, function()
                        return mp().useMinLevel
                    end, function(value)
                        mp().useMinLevel = value
                    end, function()
                        return mp().hideAll
                    end),
                    {
                        kind = "slider",
                        label = "Minimum keystone level",
                        desc = "Rolls are hidden when the key you finished was below this level.",
                        min = 2,
                        max = 40,
                        step = 1,
                        get = function()
                            return mp().minLevel
                        end,
                        set = function(value)
                            mp().minLevel = value
                        end,
                        disabled = function()
                            return mp().hideAll or not mp().useMinLevel
                        end,
                    },
                    Text(function()
                        if mp().hideAll then
                            return colored("Every Mythic+ bonus roll is hidden.", RED)
                        elseif mp().useMinLevel then
                            return colored(("Rolls below +%d are hidden."):format(mp().minLevel), GOLD)
                        end
                        return colored("Every Mythic+ bonus roll will show.", GREEN)
                    end),
                },
            },
        },
    }
end

local function ListPage(addon, key, title, group, difficulties, sectionTitle)
    local rows = {}
    for _, difficultyID in ipairs(difficulties) do
        rows[#rows + 1] = DifficultyCheck(addon, difficultyID)
    end

    return {
        key = key,
        title = title,
        group = group,
        badge = function()
            local n = 0
            for _, difficultyID in ipairs(difficulties) do
                if addon.db.profile.difficulty[difficultyID].hide then
                    n = n + 1
                end
            end
            return n > 0 and ns.colored(tostring(n), ns.GOLD) or ""
        end,
        sections = { { title = sectionTitle, rows = rows } },
    }
end

-- Difficulties the addon has been offered a roll on that it ships no switch
-- for. A checklist rather than a row each, so one met mid-session appears
-- without a reload; the section hides itself while there are none.
local function SeenInPlaySection(addon)
    local function seen()
        local values = {}
        for difficultyID in pairs(addon.db.global.seenDifficulties) do
            if not ns.KNOWN_DIFFICULTIES[difficultyID] then
                values[difficultyID] = ns.DifficultyName(difficultyID)
            end
        end
        return values
    end

    return {
        title = "Seen in play",
        hidden = function()
            return next(seen()) == nil
        end,
        rows = {
            Text(function()
                return ns.colored("Difficulties BonusRollGate has met that it did not ship a switch for.", ns.GREY)
            end),
            {
                kind = "checklist",
                values = seen,
                get = function(difficultyID)
                    return addon.db.profile.difficulty[difficultyID].hide
                end,
                set = function(difficultyID, value)
                    addon.db.profile.difficulty[difficultyID].hide = value
                end,
            },
        },
    }
end

local function ProfilesPage(addon)
    local db = addon.db

    local function others()
        local list = {}
        for _, name in ipairs(db:GetProfiles()) do
            if name ~= db:GetCurrentProfile() then
                list[#list + 1] = { key = name, label = name }
            end
        end
        table.sort(list, function(a, b)
            return a.label < b.label
        end)
        return list
    end

    return {
        key = "profiles",
        title = "Profiles",
        sections = {
            {
                title = "Active profile",
                rows = {
                    Text(function()
                        return "Settings are saved per profile. This character is using "
                            .. ns.colored(db:GetCurrentProfile(), ns.GOLD)
                            .. "."
                    end),
                    {
                        kind = "list",
                        values = function()
                            local list = {}
                            for _, name in ipairs(db:GetProfiles()) do
                                list[#list + 1] = { key = name, label = name }
                            end
                            table.sort(list, function(a, b)
                                return a.label < b.label
                            end)
                            return list
                        end,
                        selected = function()
                            return db:GetCurrentProfile()
                        end,
                        onSelect = function(name)
                            db:SetProfile(name)
                        end,
                    },
                    {
                        kind = "buttons",
                        buttons = {
                            {
                                label = "New profile",
                                desc = "Name a profile and switch to it.",
                                func = function()
                                    ns.PromptNewProfile()
                                end,
                            },
                            {
                                label = "Reset this profile",
                                desc = "Put the active profile back to defaults.",
                                confirm = "Reset the active profile to defaults?",
                                func = function()
                                    db:ResetProfile()
                                end,
                            },
                        },
                    },
                },
            },
            {
                title = "Copy from",
                rows = {
                    {
                        kind = "list",
                        empty = "There is no other profile to copy from.",
                        values = others,
                        confirm = function(name)
                            return ("Copy every setting from '%s' into the active profile?"):format(name)
                        end,
                        onSelect = function(name)
                            db:CopyProfile(name)
                        end,
                    },
                },
            },
            {
                title = "Delete",
                rows = {
                    {
                        kind = "list",
                        empty = "There is no other profile to delete.",
                        values = others,
                        confirm = function(name)
                            return ("Delete the profile '%s'? This cannot be undone."):format(name)
                        end,
                        onSelect = function(name)
                            db:DeleteProfile(name)
                        end,
                    },
                },
            },
        },
    }
end

--------------------------------------------------------------------------------
-- Assembly
--------------------------------------------------------------------------------

--- Every page, in sidebar order. Pages carrying the same `group` sit under one
--- header; ungrouped pages come first.
function Model.Build(addon)
    local pages = { GeneralPage(addon) }

    for _, difficultyID in ipairs(ns.RAID_DIFFICULTIES) do
        pages[#pages + 1] = RaidPage(addon, difficultyID)
    end

    pages[#pages + 1] = MythicPlusPage(addon)
    pages[#pages + 1] =
        ListPage(addon, "dungeons", "Other difficulties", "Dungeons", ns.DUNGEON_DIFFICULTIES, "Hide bonus rolls from")

    local other = ListPage(addon, "other", "Content types", "Other", ns.OTHER_DIFFICULTIES, "Hide bonus rolls from")
    other.sections[#other.sections + 1] = SeenInPlaySection(addon)
    pages[#pages + 1] = other

    pages[#pages + 1] = ProfilesPage(addon)

    local byKey = {}
    for _, page in ipairs(pages) do
        byKey[page.key] = page
    end

    return { pages = pages, byKey = byKey }
end
