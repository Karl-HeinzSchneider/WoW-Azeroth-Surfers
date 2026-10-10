---@type string, AzerothSurfers
local _, app = ...
-- The game's menus: a dialog window (the frame of the pause panel and the hotkey list) showing
-- one page of a stack, steered by four directions and two buttons. Up and down choose an item,
-- left and right change a choice, accept runs the item, back returns to the page before, and a
-- page may have one extra action of its own. Keys map to these actions in one place
-- (`MenuAction`); a gamepad would map to the same. The mouse works
-- too: an item is chosen by pointing at it and run by a click.
--
-- A page: { title = text or nil, items = { ... }, back = function(o) for back on the first page,
-- extra = { text = its hint, run = function(o, menu) } }.
-- An item:
--   text    its label, or function(o) returning it (shown anew when it changes)
--   run     function(o, menu): run on accept
--   back    true: accept goes back a page
--   choice  { get = function(o): the value's text, step = function(o, dir), can = function(o,
--           dir): whether it can step that way }; left and right (or its arrows) step it,
--           accept leaves it alone
--   info    function(o): a value shown on the right; the line cannot be chosen
--   note    a color { r, g, b }: the label alone, centered in it; cannot be chosen
--   input   { get = function(o): the box's text, set = function(o, text) }: a number box; accept
--           (or a click) types in it, Enter keeps the number, Escape the one before
local overlay = app.overlay

local FONT = "Fonts\\MORPHEUS.ttf"
local WIDTH, PAD, TOP = 400, 26, 24
local TITLE_SIZE, ITEM_SIZE, VALUE_SIZE = 28, 24, 22
local ROW, MARKER, VALUE_WIDTH, ARROW_SIZE = 38, 26, 110, 26
local TRIM, TRIM_HEIGHT = "Interface\\Common\\UI-TooltipDivider", 8
local HINT_HEIGHT, HINT_GAP, CAP_GAP, LABEL_GAP = 20, 18, 4, 6
local GOLD = { 1, 0.82, 0 }
local WHITE = { 1, 1, 1 }
local GRAY = { 0.8, 0.8, 0.8 }
-- The login screen's arrow in front of the chosen item; the spell book's page arrows around a
-- choice.
local MARKER_ART = "Interface\\Glues\\Common\\Glue-RightArrow-Button-Up"
local ARROWS = { "Interface\\Buttons\\UI-SpellbookIcon-PrevPage", "Interface\\Buttons\\UI-SpellbookIcon-NextPage" }

-- Accept, back and a page's extra action by the key itself, whatever it is bound to (E and Q
-- strafe by default); the directions by the movement bindings and the arrow keys.
local ACCEPT_KEY, BACK_KEY, EXTRA_KEY = "E", "Q", "R"
local DIRECTIONS = {
    UP = "up",
    DOWN = "down",
    LEFT = "left",
    RIGHT = "right",
    MOVEFORWARD = "up",
    MOVEBACKWARD = "down",
    TURNLEFT = "left",
    STRAFELEFT = "left",
    TURNRIGHT = "right",
    STRAFERIGHT = "right",
}

-- The menu action of `key` (bound to `binding`): "up", "down", "left", "right", "accept",
-- "back", "extra", or nil for a key the menu leaves to WoW.
function overlay.MenuAction(key, binding)
    if not IsModifierKeyDown() then
        if key == ACCEPT_KEY then
            return "accept"
        elseif key == BACK_KEY then
            return "back"
        elseif key == EXTRA_KEY then
            return "extra"
        end
    end
    return DIRECTIONS[key] or DIRECTIONS[binding]
end

-- The footer's hints: the keys of `bindings` (their first ones) or `key`, and what they do;
-- `choice`: only on a page with a choice; `extra`: the page's extra action, with its text.
local HINTS = {
    { bindings = { "MOVEFORWARD", "MOVEBACKWARD" }, text = "Select" },
    { bindings = { "TURNLEFT", "TURNRIGHT" }, text = "Change", choice = true },
    { key = ACCEPT_KEY, text = "Accept" },
    { key = BACK_KEY, text = "Back" },
    { key = EXTRA_KEY, extra = true },
}

local function text(parent, size, color)
    local t = parent:CreateFontString(nil, "OVERLAY")
    t:SetFontObject(GameFontNormalHuge)
    t:SetFont(FONT, size, "OUTLINE")
    t:SetShadowColor(0, 0, 0, 1)
    t:SetShadowOffset(2, -2)
    t:SetTextColor(color[1], color[2], color[3])
    return t
end

local Menu = {}
Menu.__index = Menu

local function arrow(menu, parent, art, dir)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(ARROW_SIZE, ARROW_SIZE)
    button:SetNormalTexture(art .. "-Up")
    button:SetPushedTexture(art .. "-Down")
    button:SetDisabledTexture(art .. "-Disabled")
    button:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    button:SetScript("OnClick", function()
        menu:SelectRow(parent.index)
        menu:Input(dir)
    end)
    return button
end

-- A row of the page: a button for the mouse, its label, a choice's value between its arrows or
-- an info line's value.
function Menu:Row(i)
    local row = self.rows[i]
    if row then
        return row
    end
    row = CreateFrame("Button", nil, self.panel)
    row.index = i
    row:SetSize(WIDTH - 2 * PAD + MARKER, ROW)
    row.label = text(row, ITEM_SIZE, GOLD)
    row.label:SetPoint("LEFT", MARKER + 6, 0)
    row.easier = arrow(self, row, ARROWS[1], "left")
    row.harder = arrow(self, row, ARROWS[2], "right")
    row.harder:SetPoint("RIGHT", 0, 0)
    row.value = text(row, VALUE_SIZE, WHITE)
    row.value:SetWidth(VALUE_WIDTH)
    row.value:SetPoint("RIGHT", row.harder, "LEFT", -2, 0)
    row.easier:SetPoint("RIGHT", row.value, "LEFT", -2, 0)
    row.info = text(row, VALUE_SIZE, WHITE)
    row.info:SetJustifyH("RIGHT")
    row.info:SetPoint("RIGHT", 0, 0)
    -- An input's box (menu.lua's number box): Enter keeps the number, Escape the one before.
    local box = overlay.NumberBox(row)
    box:SetPoint("RIGHT", 0, 0)
    box:SetScript("OnEnterPressed", box.ClearFocus)
    box:SetScript("OnEditFocusGained", function()
        self:SelectRow(i)
        box:HighlightText()
    end)
    box:SetScript("OnEditFocusLost", function()
        box:HighlightText(0, 0)
        local item = self:Page().items[i]
        local typed = box:GetText()
        if item and item.input and typed ~= "" and typed ~= row.shownValue and not row.escaped then
            item.input.set(self.o, typed)
        end
        row.shownValue, row.escaped = nil, nil
        self:Show()
    end)
    box:SetScript("OnEscapePressed", function()
        row.escaped = true
        box:ClearFocus()
    end)
    row.box = box
    row:SetScript("OnEnter", function()
        self:SelectRow(i)
    end)
    row:SetScript("OnClick", function()
        if self:SelectRow(i) then
            self:Input("accept")
        end
    end)
    self.rows[i] = row
    return row
end

-- A hint of the footer: up to two key caps and their text.
function Menu:Hint(i)
    local hint = self.hints[i]
    if hint then
        return hint
    end
    hint = { caps = { overlay.KeyCap(self.panel), overlay.KeyCap(self.panel) } }
    hint.label = self.panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    self.hints[i] = hint
    return hint
end

-- A menu window in `parent`, placed by its owner (`menu.panel`); `o` is the overlay.
function overlay:CreateMenu(parent)
    local menu = setmetatable({ o = self, stack = {}, rows = {}, hints = {} }, Menu)
    -- The template fills its parent (setAllPoints): the panel is anchored anew and sized by its
    -- page.
    local panel = CreateFrame("Frame", nil, parent, "DialogBorderTemplate")
    panel:ClearAllPoints()
    panel:SetWidth(WIDTH)
    panel:EnableMouse(true)
    menu.panel = panel
    menu.title = text(panel, TITLE_SIZE, GOLD)
    menu.title:SetPoint("TOP", 0, -TOP)
    menu.trims = {}
    for i = 1, 2 do
        menu.trims[i] = panel:CreateTexture(nil, "ARTWORK")
        menu.trims[i]:SetTexture(TRIM)
        menu.trims[i]:SetHeight(TRIM_HEIGHT)
    end
    menu.marker = panel:CreateTexture(nil, "ARTWORK")
    menu.marker:SetTexture(MARKER_ART)
    menu.marker:SetSize(MARKER, MARKER)
    return menu
end

local function selectable(item)
    return item and not item.info and not item.note
end

local function label(o, item)
    return type(item.text) == "function" and item.text(o) or item.text
end

-- Whether the page takes `action` (a page without an extra action leaves its key to WoW).
function Menu:Takes(action)
    local page = self:Page()
    return action ~= "extra" or (page ~= nil and page.extra ~= nil)
end

-- Shows `page` alone.
function Menu:Open(page)
    for i = #self.stack, 1, -1 do
        self.stack[i] = nil
    end
    self:Push(page)
end

-- Shows `page` over the current one, back returns from it.
function Menu:Push(page)
    local entry = { page = page, selected = 0 }
    self.stack[#self.stack + 1] = entry
    self.selected = nil
    self:Move(1)
    self:Layout()
end

function Menu:Back()
    if #self.stack > 1 then
        self.stack[#self.stack] = nil
        self:Layout()
    else
        local page = self:Page()
        if page and page.back then
            page.back(self.o, self)
        end
    end
end

function Menu:Page()
    local entry = self.stack[#self.stack]
    return entry and entry.page
end

-- The next item that can be chosen, `dir` (1 or -1) away, round the page.
function Menu:Move(dir)
    local entry = self.stack[#self.stack]
    local items = entry.page.items
    local i = entry.selected
    for _ = 1, #items do
        i = (i + dir - 1) % #items + 1
        if selectable(items[i]) then
            entry.selected = i
            return
        end
    end
end

-- Chooses row `i` if it can be chosen; true then.
function Menu:SelectRow(i)
    local entry = self.stack[#self.stack]
    if not entry or not selectable(entry.page.items[i]) then
        return false
    end
    entry.selected = i
    self:Show()
    return true
end

-- One of MenuAction's actions.
function Menu:Input(action)
    local entry = self.stack[#self.stack]
    if not entry then
        return
    end
    local item, o = entry.page.items[entry.selected], self.o
    if action == "up" or action == "down" then
        self:Move(action == "up" and -1 or 1)
    elseif action == "left" or action == "right" then
        local choice = item and item.choice
        local dir = action == "left" and -1 or 1
        if choice and choice.can(o, dir) then
            choice.step(o, dir)
        end
    elseif action == "back" then
        self:Back()
        return
    elseif action == "extra" then
        local extra = entry.page.extra
        if extra then
            extra.run(o, self)
        end
    elseif action == "accept" and item then
        if item.back then
            self:Back()
            return
        elseif item.choice then
            -- Only left and right (or its arrows) change it.
            return
        elseif item.input then
            -- Typed in from here; the keys go to the box until Enter or Escape.
            self.rows[entry.selected].box:SetFocus()
            return
        elseif item.run then
            item.run(o, self)
            return
        end
    end
    self:Show()
end

-- Lays the page out: its title and trim, a row per item, the hints under a trim.
function Menu:Layout()
    local page, panel = self:Page(), self.panel
    if not page then
        return
    end
    local y = -TOP
    self.title:SetShown(page.title ~= nil)
    if page.title then
        self.title:SetText(page.title)
        y = y - self.title:GetStringHeight() - 6
        self:PlaceTrim(self.trims[1], y)
        y = y - TRIM_HEIGHT - 6
    else
        self.trims[1]:Hide()
        y = y + 4
    end
    local hasChoice = false
    for i, item in ipairs(page.items) do
        local row = self:Row(i)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD - MARKER / 2, y)
        row.label:SetText(label(self.o, item))
        row.shownLabel = nil
        row.label:ClearAllPoints()
        if item.note then
            row.label:SetPoint("CENTER", MARKER / 2, 0)
        else
            row.label:SetPoint("LEFT", MARKER + 6, 0)
        end
        row.easier:SetShown(item.choice ~= nil)
        row.harder:SetShown(item.choice ~= nil)
        row.value:SetShown(item.choice ~= nil)
        row.info:SetShown(item.info ~= nil)
        row.box:SetShown(item.input ~= nil)
        row.shownValue = nil
        row:Show()
        hasChoice = hasChoice or item.choice ~= nil
        y = y - ROW
    end
    for i = #page.items + 1, #self.rows do
        self.rows[i]:Hide()
    end
    y = y - 6
    self:PlaceTrim(self.trims[2], y)
    y = y - TRIM_HEIGHT - 8
    y = self:LayoutHints(y, hasChoice, page.extra)
    panel:SetHeight(-y + PAD - 6)
    self.shownSelected = nil
    self:Show()
end

function Menu:PlaceTrim(trim, y)
    trim:ClearAllPoints()
    trim:SetPoint("TOPLEFT", self.panel, "TOPLEFT", PAD - 6, y)
    trim:SetPoint("TOPRIGHT", self.panel, "TOPRIGHT", -PAD + 6, y)
    trim:Show()
end

-- The hints in a row, centered, wrapped onto a second row should they not fit. Returns where the
-- next line would start.
function Menu:LayoutHints(y, hasChoice, extra)
    local shown, total = {}, 0
    for i, spec in ipairs(HINTS) do
        local hint = self:Hint(i)
        local on = (not spec.choice or hasChoice) and (not spec.extra or extra ~= nil)
        hint.label:SetShown(on)
        for _, cap in ipairs(hint.caps) do
            cap:Hide()
        end
        if on then
            local width = 0
            for k = 1, 2 do
                local key = spec.key
                if not key and spec.bindings[k] then
                    key = GetBindingKey(spec.bindings[k])
                end
                if key and (k == 1 or not spec.key) then
                    local cap = hint.caps[k]
                    cap.width = overlay.SetKeyCap(cap, key)
                    cap:Show()
                    width = width + cap.width + (k > 1 and CAP_GAP or 0)
                end
            end
            hint.label:SetText(spec.extra and extra.text or spec.text)
            hint.width = width + LABEL_GAP + hint.label:GetStringWidth()
            shown[#shown + 1] = hint
            total = total + hint.width
        end
    end
    -- One line, or two halves.
    local lines = { shown }
    if total + HINT_GAP * (#shown - 1) > WIDTH - 2 * PAD and #shown > 2 then
        local half = math.ceil(#shown / 2)
        lines = { {}, {} }
        for i, hint in ipairs(shown) do
            table.insert(lines[i <= half and 1 or 2], hint)
        end
    end
    for _, line in ipairs(lines) do
        local width = 0
        for i, hint in ipairs(line) do
            width = width + hint.width + (i > 1 and HINT_GAP or 0)
        end
        local x = (WIDTH - width) / 2
        for _, hint in ipairs(line) do
            for _, cap in ipairs(hint.caps) do
                if cap:IsShown() then
                    cap:ClearAllPoints()
                    cap:SetPoint("TOPLEFT", self.panel, "TOPLEFT", x, y)
                    x = x + cap.width + CAP_GAP
                end
            end
            x = x - CAP_GAP + LABEL_GAP
            hint.label:ClearAllPoints()
            hint.label:SetPoint("LEFT", self.panel, "TOPLEFT", x, y - HINT_HEIGHT / 2)
            x = x + hint.label:GetStringWidth() + HINT_GAP
        end
        y = y - HINT_HEIGHT - 6
    end
    return y
end

-- The chosen item white behind the marker, the others gold, a choice gray where it cannot step;
-- the values. Cheap enough once a frame while shown: only changes reach the client.
function Menu:Show()
    local entry = self.stack[#self.stack]
    if not entry then
        return
    end
    local o, items = self.o, entry.page.items
    if self.shownSelected ~= entry.selected or self.shownPage ~= entry.page then
        self.shownSelected, self.shownPage = entry.selected, entry.page
        for i, item in ipairs(items) do
            local color = item.note or item.info and GRAY or i == entry.selected and WHITE or GOLD
            self.rows[i].label:SetTextColor(color[1], color[2], color[3])
        end
        local row = self.rows[entry.selected]
        self.marker:SetShown(row ~= nil)
        if row then
            self.marker:ClearAllPoints()
            self.marker:SetPoint("LEFT", row, "LEFT", 0, 0)
        end
    end
    for i, item in ipairs(items) do
        local row = self.rows[i]
        if type(item.text) == "function" then
            local text = item.text(o)
            if row.shownLabel ~= text then
                row.shownLabel = text
                row.label:SetText(text)
            end
        end
        local value = item.choice and item.choice.get(o)
            or item.info and item.info(o)
            or item.input and item.input.get(o)
        -- Not while typing in it.
        if value and row.shownValue ~= value and not (item.input and row.box:HasFocus()) then
            row.shownValue = value
            if item.choice then
                row.value:SetText(value)
                row.easier:SetEnabled(item.choice.can(o, -1))
                row.harder:SetEnabled(item.choice.can(o, 1))
            elseif item.input then
                row.box:SetText(value)
            else
                row.info:SetText(value)
            end
        end
    end
end
