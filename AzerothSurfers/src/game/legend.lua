---@type string, AzerothSurfers
local _, app = ...
-- The hotkey legend, built like the client's input legend: a dialog panel per run state (only
-- the current one shown), rows of key caps and what they do. The keys are the game's own
-- (keys.lua: Key 1, or Gamepad 1 since a gamepad was used, a row's keys side by side), and WoW's
-- move-forward binding.
local overlay = app.overlay

local ROW_HEIGHT = 24
local INDENT = 20
-- Room between a header row and the rows under it, for the trim.
local HEADER_EXTRA = 10
-- A key cap's height, its smallest width, and the room around its text.
local KEY_HEIGHT, KEY_WIDTH, KEY_PAD = 20, 22, 6
-- Between two keys of a row (they belong together, as A and D), and between the keys and the text.
local KEY_GAP, LABEL_GAP = 4, 8
-- The most keys a row shows.
local CAPS = 4
-- A gamepad's icon: drawn this big, centered on its cap; its art has room around the button, so
-- it takes less room in the row than that.
local ICON_SIZE, ICON_ROOM = 34, 24
local SIDE_SCALE = 0.75
local KEY_CAP = {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true,
    tileSize = 8,
    edgeSize = 8,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
}
local TRIM = "Interface\\Common\\UI-TooltipDivider"

-- `actions`: the game's actions (keys.lua) whose keys the row shows together, from the slot
-- shown (overlay:ShownSlot: Key 1, or Gamepad 1); `binding`: instead the WoW binding whose first
-- key it shows; `header`: a title row with trim; `observed`: only while `profile.capture` is off.
local GROUPS = {
    running = {
        { binding = "MOVEFORWARD", text = "Run (hold)", observed = true },
        { actions = { "left", "right" }, text = "Change lane" },
        { actions = { "jump" }, text = "Jump" },
        { actions = { "duck" }, text = "Duck / drop" },
        { actions = { "pause" }, text = "Pause" },
        { actions = { "restart" }, text = "Start over (hold)" },
    },
}

local function keyCap(parent)
    local cap = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    cap:SetBackdrop(KEY_CAP)
    cap:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
    cap:SetBackdropBorderColor(0.7, 0.7, 0.7, 1)
    cap:SetHeight(KEY_HEIGHT)
    cap.text = cap:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    cap.text:SetPoint("CENTER", 0, 0)
    cap.icon = cap:CreateTexture(nil, "OVERLAY")
    cap.icon:SetSize(ICON_SIZE, ICON_SIZE)
    cap.icon:SetPoint("CENTER", 0, 0)
    cap.icon:Hide()
    return cap
end

-- Returns the cap's width: the same for every one-character name, wider for longer ones. A
-- gamepad's icon (keys.lua's texture markup) is a button of its own: drawn as a texture, bigger
-- than the text and in the middle of its line, with no cap around it.
local function setKey(cap, key, text)
    text = text or GetBindingText(key) or key
    local atlas = overlay.IsIcon(text) and text:match("^|A:([^:|]+)")
    cap:SetBackdropColor(0.1, 0.1, 0.1, atlas and 0 or 0.9)
    cap:SetBackdropBorderColor(0.7, 0.7, 0.7, atlas and 0 or 1)
    cap.icon:SetShown(not not atlas)
    if atlas then
        cap.icon:SetAtlas(atlas)
        cap.text:SetText("")
        cap:SetWidth(ICON_ROOM)
        return ICON_ROOM
    end
    cap.text:SetText(text)
    -- Characters, not bytes: UTF-8 continuation bytes are not counted.
    local single = #text:gsub("[\128-\191]", "") == 1
    local w = single and KEY_WIDTH or math.max(KEY_WIDTH, cap.text:GetStringWidth() + 2 * KEY_PAD)
    cap:SetWidth(w)
    return w
end
overlay.KeyCap, overlay.SetKeyCap = keyCap, setKey

local function entry(parent, spec)
    local e = { spec = spec, caps = {} }
    for i = 1, CAPS do
        e.caps[i] = keyCap(parent)
    end
    e.label = parent:CreateFontString(nil, "OVERLAY", spec.header and "GameFontHighlight" or "GameFontNormal")
    e.label:SetJustifyH("LEFT")
    e.label:SetText(spec.text)
    return e
end

function overlay:CreateLegend(f)
    local legend = CreateFrame("Frame", nil, f)
    self:Stack(legend, "legend")
    legend:SetSize(1, 1)
    self.legend = legend
    self.legendGroups = {}
    for state, specs in pairs(GROUPS) do
        local panel = CreateFrame("Frame", nil, legend, "DialogBorderTemplate")
        -- The template fills its parent (setAllPoints); the panel is sized by its rows instead.
        panel:ClearAllPoints()
        panel:SetPoint("TOPLEFT")
        panel:Hide()
        local group = { panel = panel, entries = {} }
        for i, spec in ipairs(specs) do
            group.entries[i] = entry(panel, spec)
            if spec.header then
                group.trim = panel:CreateTexture(nil, "ARTWORK")
                group.trim:SetTexture(TRIM)
                group.trim:SetHeight(8)
            end
        end
        self.legendGroups[state] = group
    end
    legend:RegisterEvent("UPDATE_BINDINGS")
    legend:SetScript("OnEvent", function()
        self.legendState = nil
    end)
end

-- Into `texts` (reused): the row's key caps.
function overlay:RowKeys(texts, spec)
    if spec.actions then
        return overlay.ShownKeys(texts, spec.actions, self:ShownSlot())
    end
    for i = #texts, 1, -1 do
        texts[i] = nil
    end
    local key = GetBindingKey(spec.binding)
    texts[1] = key and overlay.KeyText(key)
    return texts
end

-- Returns their width.
local function placeKeys(e, texts, x, y)
    local width = 0
    for i, cap in ipairs(e.caps) do
        local text = texts[i]
        cap:SetShown(text ~= nil)
        if text then
            local w = setKey(cap, nil, text)
            if i > 1 then
                width = width + KEY_GAP
            end
            cap:ClearAllPoints()
            cap:SetPoint("TOPLEFT", x + width, y)
            width = width + w
        end
    end
    -- An action without a key shows that it has none.
    if not texts[1] then
        local cap = e.caps[1]
        cap:Show()
        width = setKey(cap, nil, NOT_BOUND or "Not bound")
        cap:ClearAllPoints()
        cap:SetPoint("TOPLEFT", x, y)
    end
    return width
end

local keys = {}

-- The texts in one column after the widest keys, the panel sized around them.
function overlay:LayoutLegend(group)
    local row, keysWidth, textWidth, headerWidth, header = 0, 0, 0, 0, false
    for _, e in ipairs(group.entries) do
        local spec = e.spec
        e.shown = not (spec.observed and self.capture)
        e.label:SetShown(e.shown)
        if not e.shown or spec.header then
            for _, cap in ipairs(e.caps) do
                cap:Hide()
            end
        end
        if e.shown then
            local y = -INDENT - ROW_HEIGHT * row - (header and HEADER_EXTRA or 0)
            e.y = y
            if spec.header then
                header = true
                e.label:ClearAllPoints()
                e.label:SetPoint("TOPLEFT", INDENT, y - 3)
                headerWidth = math.max(headerWidth, e.label:GetStringWidth())
            else
                self:RowKeys(keys, spec)
                keysWidth = math.max(keysWidth, placeKeys(e, keys, INDENT, y))
                textWidth = math.max(textWidth, e.label:GetStringWidth())
            end
            row = row + 1
        end
    end
    for _, e in ipairs(group.entries) do
        if e.shown and not e.spec.header then
            e.label:ClearAllPoints()
            e.label:SetPoint("LEFT", group.panel, "TOPLEFT", INDENT + keysWidth + LABEL_GAP, e.y - KEY_HEIGHT / 2)
        end
    end
    local width = 2 * INDENT + math.max(headerWidth, keysWidth + LABEL_GAP + textWidth)
    -- Without the last row's extra room, so the bottom margin matches the top.
    local height = ROW_HEIGHT * row + 2 * INDENT - (ROW_HEIGHT - KEY_HEIGHT) + (header and HEADER_EXTRA or 0)
    group.panel:SetSize(width, height)
    if group.trim then
        group.trim:ClearAllPoints()
        group.trim:SetPoint("TOPLEFT", INDENT, -INDENT - ROW_HEIGHT + 2)
        group.trim:SetPoint("TOPRIGHT", -INDENT, -INDENT - ROW_HEIGHT + 2)
    end
end

-- Without arguments: again where it was last placed (the challenge card under the scorecard came
-- or went).
function overlay:PlaceLegend(side, top)
    if top == nil then
        if self.legendTop == nil then
            return
        end
        side, top = self.legendSide, self.legendTop
    end
    self.legendSide, self.legendTop = side, top
    local legend, scale = self.legend, side and SIDE_SCALE or 1
    legend:ClearAllPoints()
    legend:SetScale(scale)
    -- Offsets count in the legend's own scale. Match the side window's scorecard padding.
    local x, y = 5, top - 5
    if side then
        x, y = 8, top - (self.framed and 8 or 40)
    elseif self.framed then
        x, y = 12, top - 10
    end
    if not side and self.hudPosition == "topleft" then
        -- Below the scorecard (its extra info and the challenge card) in the same corner.
        y = y - 130 - self:HudInfoRoom() - self:ChallengeCardRoom()
    end
    legend:SetPoint("TOPLEFT", self.frame, "TOPLEFT", x / scale, y / scale)
end

-- Laid out again only when the state, bindings or mode changed. None in auto mode, on the title
-- and the menu (screens.lua), and on the way into a run.
function overlay:ShowLegend()
    local state = app.db.profile.legend and not self.auto and (self.screen or self.state.status) or "off"
    if self.legendState == state then
        return
    end
    self.legendState = state
    for name, group in pairs(self.legendGroups) do
        if name == state then
            self:LayoutLegend(group)
            group.panel:Show()
        else
            group.panel:Hide()
        end
    end
end
