-- Turns the page tree in Model.lua into frames.
--
-- The window is built once and kept. Page content is built the first time a page
-- is shown and then only ever reconfigured, because a WoW frame cannot be
-- destroyed: rebuilding rows on every refresh would grow the frame count for as
-- long as the session lasted. Lists that change length own a pool of rows and
-- reuse it.
--
-- Layout is a single top-down pass. Every block is anchored TOPLEFT at the
-- running cursor and reports how far it moved the cursor on, so nothing has to
-- know what sits above or below it.

local _, ns = ...

local CreateFrame = CreateFrame
local HideUIPanel = HideUIPanel
local Settings = Settings
local StaticPopup_Show = StaticPopup_Show
local StaticPopupDialogs = StaticPopupDialogs
local UISpecialFrames = UISpecialFrames

local Panel = {}
ns.Panel = Panel

local UI = ns.UI
local M = UI.METRICS

local HEADER_H = 46
local GAP_ROW = 2
local GAP_BLOCK = 8
local GAP_SECTION = 18
local BUTTON_W = 152
local CONTENT_W = M.PANEL_W - M.SIDEBAR_W - M.PAD * 2 - M.SCROLLBAR_W - 6

local addon
local model
local window, sidebar, scroll
local currentKey
local sidebarButtons = {}
local sidebarEntries = {}
local pages = {}

--------------------------------------------------------------------------------
-- Dialogs
--------------------------------------------------------------------------------

StaticPopupDialogs["BONUSROLLGATE_CONFIRM"] = {
    text = "%s",
    button1 = YES,
    button2 = NO,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    -- Above Blizzard's own dialogs, since the options window sits high too.
    preferredIndex = 3,
    OnAccept = function(_, action)
        action()
        Panel.Refresh()
    end,
}

local function CreateProfile(text)
    local name = ns.NormalizeProfileName(text)
    if name then
        -- A name AceDB has not seen creates an empty profile, which it then
        -- fills from the defaults. No copy of the current one.
        addon.db:SetProfile(name)
        Panel.Refresh()
    end
end

StaticPopupDialogs["BONUSROLLGATE_NEW_PROFILE"] = {
    text = "Name the new profile.",
    button1 = ACCEPT,
    button2 = CANCEL,
    hasEditBox = true,
    editBoxWidth = 200,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
    OnAccept = function(self)
        CreateProfile(self.editBox:GetText())
    end,
    EditBoxOnEnterPressed = function(self)
        CreateProfile(self:GetText())
        self:GetParent():Hide()
    end,
    EditBoxOnEscapePressed = function(self)
        self:GetParent():Hide()
    end,
}

function ns.PromptNewProfile()
    StaticPopup_Show("BONUSROLLGATE_NEW_PROFILE")
end

local function Act(spec)
    if spec.confirm then
        StaticPopup_Show("BONUSROLLGATE_CONFIRM", spec.confirm, nil, spec.func)
    else
        spec.func()
        Panel.Refresh()
    end
end

--------------------------------------------------------------------------------
-- Blocks
--
-- Each returns Run(y, width) -> the cursor after it has placed itself. A block
-- that has nothing to show hides its frames and hands the cursor back untouched.
--------------------------------------------------------------------------------

local function Disabled(section, row)
    if row and row.disabled and row.disabled() then
        return true
    end
    return section.disabled ~= nil and section.disabled()
end

local function Hidden(section)
    return section.hidden ~= nil and section.hidden()
end

local function SectionBlock(parent, section)
    local widget = UI.Section(parent)
    widget:SetLabel(section.title)

    return function(y, width)
        if Hidden(section) then
            widget:Hide()
            return y
        end
        widget:Show()
        widget:SetWidth(width)
        widget:ClearAllPoints()
        widget:SetPoint("TOPLEFT", 0, -y)
        return y + widget.height + 4
    end
end

local function ParagraphBlock(parent, section, get, color)
    local widget = UI.Paragraph(parent)

    return function(y, width)
        local text = get()
        if Hidden(section) or not text or text == "" then
            widget:Hide()
            return y
        end
        widget:Show()
        widget:Resize(width, color and ns.colored(text, color) or text)
        widget:ClearAllPoints()
        widget:SetPoint("TOPLEFT", 0, -y)
        return y + widget.height + GAP_BLOCK
    end
end

local function CheckBlock(parent, section, row)
    local widget = UI.Check(parent)
    widget:SetLabel(row.label)
    widget.tooltipTitle = row.label
    widget.tooltipDesc = row.desc
    widget.onClick = function(value)
        row.set(value)
        Panel.Refresh()
    end

    return function(y, width)
        if Hidden(section) then
            widget:Hide()
            return y
        end
        widget:Show()
        widget:SetWidth(width)
        widget:ClearAllPoints()
        widget:SetPoint("TOPLEFT", 0, -y)
        widget:SetChecked(row.get())
        widget:SetEnabled(not Disabled(section, row))
        return y + widget.height + GAP_ROW
    end
end

local function SliderBlock(parent, section, row)
    local widget = UI.Slider(parent)
    widget:SetLabel(row.label)
    widget:Configure(row.min, row.max, row.step)
    widget.slider.tooltipTitle = row.label
    widget.slider.tooltipDesc = row.desc
    widget.onChange = function(value)
        row.set(value)
        Panel.Refresh()
    end

    return function(y, width)
        if Hidden(section) then
            widget:Hide()
            return y
        end
        widget:Show()
        widget:SetWidth(width)
        widget:ClearAllPoints()
        widget:SetPoint("TOPLEFT", 0, -y)
        widget:SetValue(row.get())
        widget:SetEnabled(not Disabled(section, row))
        return y + widget.height + GAP_ROW
    end
end

local function ButtonsBlock(parent, section, row)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetHeight(M.ROW_H)

    local buttons = {}
    for index, spec in ipairs(row.buttons) do
        local button = UI.Button(holder)
        button:SetLabel(spec.label)
        button.tooltipTitle = spec.label
        button.tooltipDesc = spec.desc
        button.onClick = function()
            Act(spec)
        end
        button:SetPoint("TOPLEFT", (index - 1) * (BUTTON_W + 8), 0)
        button:SetWidth(BUTTON_W)
        buttons[index] = button
    end

    return function(y, width)
        if Hidden(section) then
            holder:Hide()
            return y
        end
        holder:Show()
        holder:SetWidth(width)
        holder:ClearAllPoints()
        holder:SetPoint("TOPLEFT", 0, -y)

        local disabled = Disabled(section, row)
        for _, button in ipairs(buttons) do
            button:SetEnabled(not disabled)
        end
        return y + M.ROW_H + GAP_BLOCK
    end
end

-- Sorted entries for a values() result. Checklists hand back a id -> name map,
-- lists hand back an array of { key, label }; which one is a property of the
-- block, never inferred from the data -- a map keyed by 1 would read as an array.
local function Entries(values, isArray, rank)
    local list = {}
    if isArray then
        for _, entry in ipairs(values) do
            list[#list + 1] = entry
        end
    else
        for key, label in pairs(values) do
            list[#list + 1] = { key = key, label = label }
        end
    end
    -- `rank` orders a boss list the way the Encounter Journal does; the label
    -- breaks ties and orders everything else.
    table.sort(list, function(a, b)
        if rank then
            local ra, rb = rank(a.key), rank(b.key)
            if ra ~= rb then
                return ra < rb
            end
        end
        return tostring(a.label) < tostring(b.label)
    end)
    return list
end

-- The two variable-length blocks. Rows are pooled: the pool only ever grows to
-- the longest list the session has shown, and never leaks per refresh.
local function PooledBlock(parent, section, row, isArray, make, configure)
    local holder = CreateFrame("Frame", nil, parent)
    local empty = UI.Paragraph(holder)
    local pool = {}

    return function(y, width)
        if Hidden(section) then
            holder:Hide()
            return y
        end
        holder:Show()
        holder:SetWidth(width)
        holder:ClearAllPoints()
        holder:SetPoint("TOPLEFT", 0, -y)

        local entries = Entries(row.values(), isArray, row.rank)
        local disabled = Disabled(section, row)

        if #entries == 0 then
            for _, widget in ipairs(pool) do
                widget:Hide()
            end
            if not row.empty then
                holder:Hide()
                return y
            end
            empty:Show()
            empty:Resize(width, ns.colored(row.empty, ns.GREY))
            empty:SetPoint("TOPLEFT", 0, 0)
            holder:SetHeight(empty.height)
            return y + empty.height + GAP_BLOCK
        end

        empty:Hide()

        local cursor = 0
        for index, entry in ipairs(entries) do
            local widget = pool[index]
            if not widget then
                widget = make(holder)
                pool[index] = widget
            end
            widget:Show()
            widget:SetWidth(width)
            widget:ClearAllPoints()
            widget:SetPoint("TOPLEFT", 0, -cursor)
            configure(widget, entry, disabled)
            cursor = cursor + widget.height + GAP_ROW
        end

        for index = #entries + 1, #pool do
            pool[index]:Hide()
        end

        holder:SetHeight(cursor)
        return y + cursor + GAP_BLOCK - GAP_ROW
    end
end

local function ChecklistBlock(parent, section, row)
    return PooledBlock(parent, section, row, false, UI.Check, function(widget, entry, disabled)
        widget.key = entry.key
        widget:SetLabel(entry.label)
        widget.tooltipTitle = entry.label
        widget:SetChecked(row.get(entry.key))
        widget:SetEnabled(not disabled)
        widget.onClick = function(value)
            row.set(widget.key, value)
            Panel.Refresh()
        end
    end)
end

local function ListBlock(parent, section, row)
    local selected = row.selected
    return PooledBlock(parent, section, row, true, UI.ListRow, function(widget, entry)
        widget.key = entry.key
        widget:SetLabel(entry.label)
        widget:SetSelected(selected ~= nil and selected() == entry.key)
        widget.onClick = function()
            local key = widget.key
            if row.confirm then
                Act({
                    confirm = row.confirm(key),
                    func = function()
                        row.onSelect(key)
                    end,
                })
            else
                row.onSelect(key)
                Panel.Refresh()
            end
        end
    end)
end

local BUILDERS = {
    check = CheckBlock,
    slider = SliderBlock,
    buttons = ButtonsBlock,
    checklist = ChecklistBlock,
    list = ListBlock,
}

--------------------------------------------------------------------------------
-- Pages
--------------------------------------------------------------------------------

-- A page can withdraw from the sidebar entirely: "Seen in play" has nothing to
-- show until the addon meets a difficulty it ships no switch for.
local function PageHidden(page)
    return page.hidden ~= nil and page.hidden()
end

local function BuildPage(page)
    local frame = CreateFrame("Frame", nil, scroll.content)
    frame:SetPoint("TOPLEFT")
    frame:SetSize(CONTENT_W, 1)
    frame:Hide()

    local blocks = {}
    for index, section in ipairs(page.sections) do
        -- The gap belongs to the section about to be drawn, so a hidden one
        -- leaves no hole behind it.
        if index > 1 then
            local upcoming = section
            blocks[#blocks + 1] = function(y)
                return Hidden(upcoming) and y or y + GAP_SECTION
            end
        end

        blocks[#blocks + 1] = SectionBlock(frame, section)

        if section.blurb then
            blocks[#blocks + 1] = ParagraphBlock(frame, section, section.blurb)
        end

        for _, row in ipairs(section.rows) do
            if row.kind == "text" then
                blocks[#blocks + 1] = ParagraphBlock(frame, section, row.get, row.color)
            else
                blocks[#blocks + 1] = BUILDERS[row.kind](frame, section, row)
            end
        end
    end

    return { frame = frame, blocks = blocks }
end

local function LayoutPage(key)
    local built = pages[key]
    if not built then
        return
    end

    local y = 0
    for _, run in ipairs(built.blocks) do
        y = run(y, CONTENT_W)
    end

    built.frame:SetHeight(math.max(y, 1))
    scroll:SetContentHeight(y)
end

local function ShowPage(key)
    local page = model.byKey[key]
    if not page or PageHidden(page) then
        key = model.pages[1].key
    end

    if not pages[key] then
        pages[key] = BuildPage(model.byKey[key])
    end

    if currentKey and pages[currentKey] then
        pages[currentKey].frame:Hide()
    end
    currentKey = key
    pages[key].frame:Show()

    for pageKey, button in pairs(sidebarButtons) do
        button:SetActive(pageKey == key)
    end

    scroll:ResetScroll()
    LayoutPage(key)
end

--------------------------------------------------------------------------------
-- Sidebar
--------------------------------------------------------------------------------

local function BuildSidebar()
    local group

    for _, page in ipairs(model.pages) do
        if page.group ~= group then
            group = page.group
            if group then
                sidebarEntries[#sidebarEntries + 1] = { kind = "header", widget = UI.SidebarHeader(sidebar, group) }
            end
        end

        local button = UI.SidebarButton(sidebar)
        button.label:SetText(page.color and ns.colored(page.title, page.color) or page.title)
        button:SetScript("OnClick", function()
            ShowPage(page.key)
        end)
        sidebarButtons[page.key] = button
        sidebarEntries[#sidebarEntries + 1] = { kind = "page", widget = button, page = page }
    end
end

-- A header belongs to the pages beneath it: it goes when they all do.
local function HeaderWanted(index)
    for i = index + 1, #sidebarEntries do
        local entry = sidebarEntries[i]
        if entry.kind == "header" then
            return false
        end
        if not PageHidden(entry.page) then
            return true
        end
    end
    return false
end

-- Re-run on every refresh, so a page that arrives mid-session takes its place
-- without the rest of the sidebar being rebuilt.
local function LayoutSidebar()
    local y = 8
    for index, entry in ipairs(sidebarEntries) do
        local visible
        if entry.kind == "header" then
            visible = HeaderWanted(index)
        else
            visible = not PageHidden(entry.page)
        end

        if visible then
            entry.widget:Show()
            entry.widget:ClearAllPoints()
            entry.widget:SetPoint("TOPLEFT", 0, -y)
            entry.widget:SetPoint("TOPRIGHT", 0, -y)
            y = y + entry.widget.height
        else
            entry.widget:Hide()
        end
    end
end

local function RefreshSidebar()
    for _, entry in ipairs(sidebarEntries) do
        if entry.kind == "page" then
            local page = entry.page
            sidebarButtons[page.key].badge:SetText(page.badge and page.badge() or "")
        end
    end
    LayoutSidebar()
end

--------------------------------------------------------------------------------
-- Window
--------------------------------------------------------------------------------

local function BuildWindow()
    window = UI.Window("BonusRollGateOptions", M.PANEL_W, M.PANEL_H)

    local title = UI.Text(window, "GameFontNormalLarge", "BonusRollGate")
    title:SetPoint("TOPLEFT", M.PAD, -14)
    title:SetTextColor(1, 1, 1)

    local version = UI.Text(window, "GameFontDisableSmall", ns.Version())
    version:SetPoint("LEFT", title, "RIGHT", 8, -1)

    local close = UI.CloseButton(window)
    close:SetPoint("TOPRIGHT", -8, -10)

    local rule = window:CreateTexture(nil, "ARTWORK")
    rule:SetHeight(1)
    rule:SetPoint("TOPLEFT", 1, -HEADER_H)
    rule:SetPoint("TOPRIGHT", -1, -HEADER_H)
    rule:SetColorTexture(unpack(UI.COLOR.divider))

    sidebar = CreateFrame("Frame", nil, window)
    sidebar:SetPoint("TOPLEFT", 1, -HEADER_H - 1)
    sidebar:SetPoint("BOTTOMLEFT", 1, 1)
    sidebar:SetWidth(M.SIDEBAR_W)
    UI.Fill(sidebar, "BACKGROUND", UI.COLOR.sidebar)

    local edge = sidebar:CreateTexture(nil, "ARTWORK")
    edge:SetWidth(1)
    edge:SetPoint("TOPRIGHT")
    edge:SetPoint("BOTTOMRIGHT")
    edge:SetColorTexture(unpack(UI.COLOR.divider))

    scroll = UI.ScrollArea(window)
    scroll:SetPoint("TOPLEFT", M.SIDEBAR_W + M.PAD, -HEADER_H - 6)
    scroll:SetPoint("BOTTOMRIGHT", -(M.PAD + M.SCROLLBAR_W + 6), M.PAD)
    scroll.content:SetWidth(CONTENT_W)

    scroll.track:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 6, 0)
    scroll.track:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 6, 0)

    -- Escape closes it, the way every other panel in the game does.
    UISpecialFrames[#UISpecialFrames + 1] = "BonusRollGateOptions"
end

--------------------------------------------------------------------------------
-- Public
--------------------------------------------------------------------------------

--- Re-read every value on the visible page and in the sidebar. Called after any
--- control writes, and after the addon itself changes the profile.
function Panel.Refresh()
    if not window or not window:IsShown() then
        return
    end
    RefreshSidebar()
    LayoutPage(currentKey)
end

function Panel.Open()
    if not window then
        addon = ns.addon
        model = ns.Model.Build(addon)
        BuildWindow()
        BuildSidebar()
    end

    window:Show()
    ShowPage(currentKey or model.pages[1].key)
    RefreshSidebar()
end

--- Switch the window to one page by key. Also how the smoke test walks them.
function Panel.ShowPage(key)
    if model and model.byKey[key] then
        ShowPage(key)
    end
end

function Panel.Toggle()
    if window and window:IsShown() then
        window:Hide()
    else
        Panel.Open()
    end
end

function Panel.IsShown()
    return window ~= nil and window:IsShown()
end

--- The entry in Blizzard's AddOns list. A single button: the panel proper is a
--- standalone window, and drawing it twice would be two panels to keep in step.
function Panel.RegisterSettingsCategory()
    local canvas = CreateFrame("Frame")
    canvas.name = "BonusRollGate"

    local title = UI.Text(canvas, "GameFontNormalLarge", "BonusRollGate")
    title:SetPoint("TOPLEFT", 16, -16)

    local blurb = UI.Paragraph(canvas)
    blurb:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
    blurb:Resize(
        480,
        "Bonus rolls you have decided against never appear, so the only prompts you see are ones worth reading."
    )

    local open = UI.Button(canvas)
    open:SetPoint("TOPLEFT", blurb, "BOTTOMLEFT", 0, -16)
    open:SetWidth(200)
    open:SetLabel("Open BonusRollGate")
    open.onClick = function()
        -- Blizzard's settings frame sits above ours; step out of it first.
        if SettingsPanel and SettingsPanel:IsShown() then
            HideUIPanel(SettingsPanel)
        end
        Panel.Open()
    end

    local category = Settings.RegisterCanvasLayoutCategory(canvas, "BonusRollGate")
    category.ID = "BonusRollGate"
    Settings.RegisterAddOnCategory(category)
    return category
end
