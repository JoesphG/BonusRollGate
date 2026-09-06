-- Widget factory for the options window.
--
-- Hand-drawn rather than AceGUI: flat fills, one-pixel borders, a single accent.
-- Nothing here uses the Backdrop API, so there is no BackdropTemplate
-- dependency and the borders stay a true pixel at any UI scale.
--
-- Widgets are built once and reconfigured, never rebuilt: a WoW frame cannot be
-- destroyed, so a panel that recreated its rows on every refresh would grow for
-- as long as the session lasted. Hence the setters -- SetLabel, Configure,
-- Resize -- rather than constructor arguments.
--
-- Each returns a frame carrying `height`, which the renderer in Panel.lua stacks
-- with a running cursor. No widget knows what sits above or below it.

local _, ns = ...

local CreateFrame = CreateFrame
local GameTooltip = GameTooltip
local GetCursorPosition = GetCursorPosition
local UIParent = UIParent

local max, min, floor = math.max, math.min, math.floor

local UI = {}
ns.UI = UI

--------------------------------------------------------------------------------
-- Palette
--------------------------------------------------------------------------------

-- Gold, because Core already colours its own status text with it and a second
-- accent would read as a second addon.
local ACCENT = { 1.0, 0.82, 0.0 }
UI.ACCENT = ACCENT

local COLOR = {
    panel = { 0.055, 0.055, 0.065, 0.97 },
    sidebar = { 0, 0, 0, 0.35 },
    border = { 0.20, 0.20, 0.23, 1 },
    divider = { 1, 1, 1, 0.07 },
    hover = { 1, 1, 1, 0.05 },
    fill = { 1, 1, 1, 0.04 },
}
UI.COLOR = COLOR

local TEXT = {
    bright = { 1, 1, 1 },
    normal = { 0.86, 0.86, 0.87 },
    dim = { 0.52, 0.52, 0.55 },
}
UI.TEXT = TEXT

UI.METRICS = {
    PANEL_W = 740,
    PANEL_H = 580,
    SIDEBAR_W = 180,
    PAD = 16,
    ROW_H = 24,
    SCROLLBAR_W = 6,
}
local ROW_H = UI.METRICS.ROW_H

--------------------------------------------------------------------------------
-- Primitives
--------------------------------------------------------------------------------

local function Fill(frame, layer, color)
    local t = frame:CreateTexture(nil, layer or "BACKGROUND")
    t:SetAllPoints(frame)
    t:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
    return t
end
UI.Fill = Fill

-- Four one-pixel edges. Separate textures rather than a nine-slice, so a line
-- never blurs when the frame lands on a half pixel.
local function Border(frame, color)
    local edges = {}

    local function Edge(p1, p2, horizontal)
        local line = frame:CreateTexture(nil, "BORDER")
        line:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
        line:SetPoint(p1)
        line:SetPoint(p2)
        if horizontal then
            line:SetHeight(1)
        else
            line:SetWidth(1)
        end
        edges[#edges + 1] = line
    end

    Edge("TOPLEFT", "TOPRIGHT", true)
    Edge("BOTTOMLEFT", "BOTTOMRIGHT", true)
    Edge("TOPLEFT", "BOTTOMLEFT", false)
    Edge("TOPRIGHT", "BOTTOMRIGHT", false)

    function edges:SetColor(r, g, b, a)
        for _, line in ipairs(self) do
            line:SetColorTexture(r, g, b, a or 1)
        end
    end

    return edges
end
UI.Border = Border

local function Text(parent, template, text)
    local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlight")
    fs:SetJustifyH("LEFT")
    fs:SetJustifyV("TOP")
    if text then
        fs:SetText(text)
    end
    return fs
end
UI.Text = Text

-- Reads `tooltipTitle` and `tooltipDesc` off the frame at hover time, so a
-- reconfigured widget carries the right text without rehooking.
local function Tooltip(frame)
    frame:HookScript("OnEnter", function(self)
        if not self.tooltipTitle or GameTooltip:IsForbidden() then
            return
        end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.tooltipTitle, 1, 1, 1)
        if self.tooltipDesc then
            GameTooltip:AddLine(self.tooltipDesc, 0.8, 0.8, 0.8, true)
        end
        GameTooltip:Show()
    end)
    frame:HookScript("OnLeave", function()
        GameTooltip:Hide()
    end)
end
UI.Tooltip = Tooltip

--------------------------------------------------------------------------------
-- Window shell
--------------------------------------------------------------------------------

function UI.Window(name, width, height)
    local frame = CreateFrame("Frame", name, UIParent)
    frame:SetSize(width, height)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("HIGH")
    frame:SetToplevel(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:Hide()

    Fill(frame, "BACKGROUND", COLOR.panel)
    Border(frame, COLOR.border)

    return frame
end

-- A flat X. UIPanelCloseButton drags in Blizzard's raised gold frame, which is
-- the look this window is getting away from.
function UI.CloseButton(parent)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(22, 22)

    local label = Text(btn, "GameFontNormalLarge", "\195\151") -- U+00D7
    label:SetPoint("CENTER", 0, 1)
    label:SetJustifyH("CENTER")
    label:SetTextColor(unpack(TEXT.dim))

    btn:SetScript("OnEnter", function()
        label:SetTextColor(1, 0.35, 0.35)
    end)
    btn:SetScript("OnLeave", function()
        label:SetTextColor(unpack(TEXT.dim))
    end)
    btn:SetScript("OnClick", function()
        parent:Hide()
    end)

    return btn
end

--------------------------------------------------------------------------------
-- Sidebar
--------------------------------------------------------------------------------

function UI.SidebarHeader(parent, text)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetHeight(24)
    frame.height = 24

    local label = Text(frame, "GameFontNormalSmall", text:upper())
    label:SetPoint("LEFT", 10, -1)
    label:SetJustifyV("MIDDLE")
    label:SetTextColor(ACCENT[1] * 0.75, ACCENT[2] * 0.75, ACCENT[3] * 0.75)
    frame.label = label

    return frame
end

function UI.SidebarButton(parent)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetHeight(ROW_H)
    btn.height = ROW_H

    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(1, 1, 1, 0)

    -- The active marker: a two-pixel accent bar on the left edge.
    local marker = btn:CreateTexture(nil, "ARTWORK")
    marker:SetSize(2, 16)
    marker:SetPoint("LEFT")
    marker:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 1)
    marker:Hide()

    local label = Text(btn, "GameFontHighlight")
    label:SetPoint("LEFT", 14, 0)
    label:SetPoint("RIGHT", -36, 0)
    label:SetJustifyV("MIDDLE")
    label:SetWordWrap(false)
    btn.label = label

    -- Right-aligned count, so the sidebar alone says where the filters live.
    local badge = Text(btn, "GameFontHighlightSmall")
    badge:SetPoint("RIGHT", -8, 0)
    badge:SetJustifyH("RIGHT")
    badge:SetJustifyV("MIDDLE")
    btn.badge = badge

    btn:SetScript("OnEnter", function(self)
        if not self.active then
            bg:SetColorTexture(unpack(COLOR.hover))
        end
    end)
    btn:SetScript("OnLeave", function(self)
        if not self.active then
            bg:SetColorTexture(1, 1, 1, 0)
        end
    end)

    function btn:SetActive(active)
        self.active = active
        if active then
            bg:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.13)
            marker:Show()
        else
            bg:SetColorTexture(1, 1, 1, 0)
            marker:Hide()
        end
    end

    btn:SetActive(false)
    return btn
end

--------------------------------------------------------------------------------
-- Scrolling
--
-- A thin overlay bar rather than Blizzard's ScrollFrameTemplate furniture. The
-- OnUpdate exists only while the thumb is actually held.
--------------------------------------------------------------------------------

function UI.ScrollArea(parent)
    local scroll = CreateFrame("ScrollFrame", nil, parent)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(1, 1)
    content.height = 0
    scroll:SetScrollChild(content)
    scroll.content = content

    local track = CreateFrame("Frame", nil, parent)
    track:SetWidth(UI.METRICS.SCROLLBAR_W)
    Fill(track, "BACKGROUND", { 1, 1, 1, 0.04 })
    track:Hide()
    scroll.track = track

    local thumb = CreateFrame("Button", nil, track)
    thumb:SetWidth(UI.METRICS.SCROLLBAR_W)
    local thumbFill = Fill(thumb, "ARTWORK", { 1, 1, 1, 0.22 })

    local function Range()
        return max(0, content.height - scroll:GetHeight())
    end

    local function UpdateThumb()
        local range = Range()
        if range <= 0 then
            track:Hide()
            return
        end
        track:Show()

        local viewH = scroll:GetHeight()
        local thumbH = max(28, floor(viewH * viewH / content.height))
        thumb:SetHeight(thumbH)
        thumb:ClearAllPoints()
        thumb:SetPoint("TOP", track, "TOP", 0, -(scroll:GetVerticalScroll() / range) * (viewH - thumbH))
    end

    local function ScrollTo(offset)
        scroll:SetVerticalScroll(min(max(0, offset), Range()))
        UpdateThumb()
    end

    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(_, delta)
        ScrollTo(scroll:GetVerticalScroll() - delta * 40)
    end)

    thumb:SetScript("OnEnter", function()
        thumbFill:SetColorTexture(1, 1, 1, 0.35)
    end)
    thumb:SetScript("OnLeave", function(self)
        if not self.dragging then
            thumbFill:SetColorTexture(1, 1, 1, 0.22)
        end
    end)

    thumb:SetScript("OnMouseDown", function(self)
        local _, cursorY = GetCursorPosition()
        self.dragging = true
        self.grabY = cursorY / self:GetEffectiveScale()
        self.grabScroll = scroll:GetVerticalScroll()
        self:SetScript("OnUpdate", function(s)
            local _, y = GetCursorPosition()
            local travel = scroll:GetHeight() - s:GetHeight()
            if travel > 0 then
                ScrollTo(s.grabScroll + (s.grabY - y / s:GetEffectiveScale()) * (Range() / travel))
            end
        end)
    end)

    thumb:SetScript("OnMouseUp", function(self)
        self.dragging = false
        self:SetScript("OnUpdate", nil)
        thumbFill:SetColorTexture(1, 1, 1, 0.22)
    end)

    --- Called by the renderer once it knows how tall the laid-out page came out.
    function scroll:SetContentHeight(h)
        content.height = h
        content:SetHeight(max(h, 1))
        ScrollTo(scroll:GetVerticalScroll())
    end

    function scroll:ResetScroll()
        ScrollTo(0)
    end

    return scroll
end

--------------------------------------------------------------------------------
-- Content widgets
--------------------------------------------------------------------------------

function UI.Section(parent)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetHeight(26)
    frame.height = 26

    local label = Text(frame, "GameFontNormal")
    label:SetPoint("TOPLEFT", 0, -4)
    label:SetTextColor(unpack(ACCENT))
    frame.label = label

    local rule = frame:CreateTexture(nil, "ARTWORK")
    rule:SetHeight(1)
    rule:SetPoint("BOTTOMLEFT", 0, 3)
    rule:SetPoint("BOTTOMRIGHT", 0, 3)
    rule:SetColorTexture(unpack(COLOR.divider))

    function frame:SetLabel(text)
        label:SetText(text)
    end

    return frame
end

-- A block of text that measures itself. Height is only right once the string has
-- laid out, so Resize must come before the caller reads `height`.
function UI.Paragraph(parent)
    local frame = CreateFrame("Frame", nil, parent)

    local label = Text(frame, "GameFontHighlight")
    label:SetPoint("TOPLEFT")
    label:SetSpacing(2)
    frame.label = label

    function frame:Resize(width, text, color)
        label:SetWidth(width)
        label:SetText(text or "")
        label:SetTextColor(unpack(color or TEXT.normal))
        local h = max(1, label:GetStringHeight())
        self:SetSize(width, h)
        self.height = h
    end

    return frame
end

local CHECK_BOX = 16

function UI.Check(parent)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetHeight(ROW_H)
    btn.height = ROW_H

    local hover = btn:CreateTexture(nil, "BACKGROUND")
    hover:SetAllPoints()
    hover:SetColorTexture(1, 1, 1, 0)

    local box = CreateFrame("Frame", nil, btn)
    box:SetSize(CHECK_BOX, CHECK_BOX)
    box:SetPoint("LEFT", 2, 0)
    local boxFill = Fill(box, "BACKGROUND", COLOR.fill)
    local boxBorder = Border(box, { 0.35, 0.35, 0.38, 1 })

    -- A filled square inset in the box. A tick glyph at 16 pixels is mush.
    local mark = box:CreateTexture(nil, "OVERLAY")
    mark:SetPoint("TOPLEFT", 4, -4)
    mark:SetPoint("BOTTOMRIGHT", -4, 4)
    mark:SetColorTexture(unpack(ACCENT))
    mark:Hide()

    local label = Text(btn, "GameFontHighlight")
    label:SetPoint("LEFT", box, "RIGHT", 8, 0)
    label:SetPoint("RIGHT", -4, 0)
    label:SetJustifyV("MIDDLE")
    label:SetWordWrap(false)
    btn.label = label

    local checked, enabled = false, true

    local function Refresh()
        mark:SetShown(checked)
        if enabled then
            boxBorder:SetColor(0.35, 0.35, 0.38, 1)
            boxFill:SetColorTexture(unpack(COLOR.fill))
            mark:SetVertexColor(1, 1, 1)
            label:SetTextColor(unpack(checked and TEXT.bright or TEXT.normal))
        else
            hover:SetColorTexture(1, 1, 1, 0)
            boxBorder:SetColor(0.25, 0.25, 0.27, 1)
            boxFill:SetColorTexture(1, 1, 1, 0.02)
            mark:SetVertexColor(0.45, 0.45, 0.45)
            label:SetTextColor(unpack(TEXT.dim))
        end
    end

    btn:SetScript("OnEnter", function()
        if enabled then
            hover:SetColorTexture(unpack(COLOR.hover))
            boxBorder:SetColor(ACCENT[1], ACCENT[2], ACCENT[3], 0.9)
        end
    end)
    btn:SetScript("OnLeave", function()
        hover:SetColorTexture(1, 1, 1, 0)
        Refresh()
    end)
    btn:SetScript("OnClick", function(self)
        if enabled and self.onClick then
            self.onClick(not checked)
        end
    end)

    function btn:SetLabel(text)
        label:SetText(text)
    end
    function btn:SetChecked(value)
        checked = value and true or false
        Refresh()
    end
    function btn:SetEnabled(value)
        enabled = value and true or false
        if enabled then
            self:Enable()
        else
            self:Disable()
        end
        Refresh()
    end

    Tooltip(btn)
    Refresh()
    return btn
end

function UI.Button(parent)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(150, ROW_H)
    btn.height = ROW_H

    local bg = Fill(btn, "BACKGROUND", COLOR.fill)
    local border = Border(btn, { 0.30, 0.30, 0.33, 1 })

    local label = Text(btn, "GameFontHighlight")
    label:SetPoint("CENTER")
    label:SetJustifyH("CENTER")
    label:SetJustifyV("MIDDLE")
    btn.label = label

    local enabled = true

    local function Refresh()
        if enabled then
            bg:SetColorTexture(unpack(COLOR.fill))
            border:SetColor(0.30, 0.30, 0.33, 1)
            label:SetTextColor(unpack(TEXT.normal))
        else
            bg:SetColorTexture(1, 1, 1, 0.015)
            border:SetColor(0.20, 0.20, 0.22, 1)
            label:SetTextColor(unpack(TEXT.dim))
        end
    end

    btn:SetScript("OnEnter", function()
        if enabled then
            bg:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.15)
            border:SetColor(ACCENT[1], ACCENT[2], ACCENT[3], 0.9)
            label:SetTextColor(unpack(TEXT.bright))
        end
    end)
    btn:SetScript("OnLeave", Refresh)
    btn:SetScript("OnClick", function(self)
        if enabled and self.onClick then
            self.onClick()
        end
    end)

    function btn:SetLabel(text)
        label:SetText(text)
    end
    function btn:SetEnabled(value)
        enabled = value and true or false
        if enabled then
            self:Enable()
        else
            self:Disable()
        end
        Refresh()
    end

    Tooltip(btn)
    Refresh()
    return btn
end

function UI.Slider(parent)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetHeight(44)
    frame.height = 44

    local label = Text(frame, "GameFontHighlight")
    label:SetPoint("TOPLEFT", 0, -1)
    frame.label = label

    local valueText = Text(frame, "GameFontHighlightSmall")
    valueText:SetPoint("TOPRIGHT", 0, -1)
    valueText:SetJustifyH("RIGHT")

    local slider = CreateFrame("Slider", nil, frame)
    slider:SetPoint("TOPLEFT", 0, -24)
    slider:SetPoint("TOPRIGHT", 0, -24)
    slider:SetHeight(16)
    slider:SetOrientation("HORIZONTAL")
    slider:SetObeyStepOnDrag(true)
    frame.slider = slider

    local track = slider:CreateTexture(nil, "BACKGROUND")
    track:SetHeight(3)
    track:SetPoint("LEFT")
    track:SetPoint("RIGHT")
    track:SetColorTexture(1, 1, 1, 0.10)

    -- The filled portion, redrawn whenever the value moves.
    local progress = slider:CreateTexture(nil, "ARTWORK")
    progress:SetHeight(3)
    progress:SetPoint("LEFT", track, "LEFT")

    local thumb = slider:CreateTexture(nil, "OVERLAY")
    thumb:SetSize(10, 16)
    thumb:SetColorTexture(1, 1, 1, 0.95)
    slider:SetThumbTexture(thumb)

    local enabled = true

    local function Refresh()
        local current = slider:GetValue() or 0
        local low, high = slider:GetMinMaxValues()
        valueText:SetText(tostring(floor(current + 0.5)))

        local span = (high or 0) - (low or 0)
        local fraction = span > 0 and ((current - low) / span) or 0
        progress:SetWidth(max(1, fraction * max(1, slider:GetWidth())))

        if enabled then
            label:SetTextColor(unpack(TEXT.normal))
            valueText:SetTextColor(unpack(ACCENT))
            progress:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.85)
            thumb:SetColorTexture(1, 1, 1, 0.95)
        else
            label:SetTextColor(unpack(TEXT.dim))
            valueText:SetTextColor(unpack(TEXT.dim))
            progress:SetColorTexture(0.40, 0.40, 0.40, 0.5)
            thumb:SetColorTexture(0.50, 0.50, 0.50, 0.7)
        end
    end

    slider:SetScript("OnValueChanged", function(_, newValue, byUser)
        Refresh()
        if byUser and enabled and frame.onChange then
            frame.onChange(floor(newValue + 0.5))
        end
    end)
    slider:SetScript("OnSizeChanged", Refresh)

    function frame:SetLabel(text)
        label:SetText(text)
    end
    function frame:Configure(minValue, maxValue, step)
        slider:SetMinMaxValues(minValue, maxValue)
        slider:SetValueStep(step)
    end
    function frame:SetValue(value)
        slider:SetValue(value)
        Refresh()
    end
    function frame:SetEnabled(value)
        enabled = value and true or false
        if enabled then
            slider:Enable()
        else
            slider:Disable()
        end
        Refresh()
    end

    Tooltip(slider)
    return frame
end

-- One row of a selectable list: no box, the whole row is the hit area and the
-- current entry carries the accent.
function UI.ListRow(parent)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetHeight(ROW_H)
    btn.height = ROW_H

    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(1, 1, 1, 0)

    local label = Text(btn, "GameFontHighlight")
    label:SetPoint("LEFT", 8, 0)
    label:SetPoint("RIGHT", -8, 0)
    label:SetJustifyV("MIDDLE")
    label:SetWordWrap(false)
    btn.label = label

    local selected = false

    local function Refresh()
        if selected then
            bg:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.13)
            label:SetTextColor(unpack(TEXT.bright))
        else
            bg:SetColorTexture(1, 1, 1, 0)
            label:SetTextColor(unpack(TEXT.normal))
        end
    end

    btn:SetScript("OnEnter", function()
        if not selected then
            bg:SetColorTexture(unpack(COLOR.hover))
        end
    end)
    btn:SetScript("OnLeave", Refresh)
    btn:SetScript("OnClick", function(self)
        if self.onClick then
            self.onClick()
        end
    end)

    function btn:SetLabel(text)
        label:SetText(text)
    end
    function btn:SetSelected(value)
        selected = value and true or false
        Refresh()
    end

    Refresh()
    return btn
end
