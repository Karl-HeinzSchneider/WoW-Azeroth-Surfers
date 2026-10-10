---@type string, AzerothSurfers
local _, app = ...
-- The game's controls: actions, each with two keys and two gamepad buttons, set on the options'
-- Keys tab (`profile.keys`; an action's `keys` where the player set none). They work only while
-- the game is open, whatever they are bound to in WoW. A run's actions and the menus' are apart:
-- a key may do one thing in a run and another in a menu.
local overlay = app.overlay

-- Per action: key 1 and key 2 (a key, or a chord such as "SHIFT-E"), then gamepad buttons 1 and
-- 2; false: none. The defaults: WASD and its neighbours, the arrow keys, and on the gamepad A to
-- jump, X to duck and the face buttons in the menus; the left stick (its axis read as buttons:
-- controls.lua's OnStick) and the D-pad mirror each other, for the lanes and the menus' moves.
-- `input`: the menus' name for it (menus.lua's Input).
overlay.KEY_SLOTS = 4
-- The slots that hold gamepad buttons.
overlay.GAMEPAD_SLOTS = { [3] = true, [4] = true }
overlay.ACTIONS = {
    { id = "left", context = "run", name = "Lane left", keys = { "A", "LEFT", "PADLSTICKLEFT", "PADDLEFT" } },
    {
        id = "right",
        context = "run",
        name = "Lane right",
        keys = { "D", "RIGHT", "PADLSTICKRIGHT", "PADDRIGHT" },
    },
    { id = "jump", context = "run", name = "Jump", keys = { "SPACE", "UP", "PAD1", false } },
    { id = "duck", context = "run", name = "Duck / drop", keys = { "S", "DOWN", "PAD3", false } },
    { id = "pause", context = "run", name = "Pause", keys = { "Q", "P", "PADFORWARD", false } },
    { id = "up", context = "menu", input = "up", name = "Up", keys = { "W", "UP", "PADLSTICKUP", "PADDUP" } },
    {
        id = "down",
        context = "menu",
        input = "down",
        name = "Down",
        keys = { "S", "DOWN", "PADLSTICKDOWN", "PADDDOWN" },
    },
    {
        id = "menuLeft",
        context = "menu",
        input = "left",
        name = "Left",
        keys = { "A", "LEFT", "PADLSTICKLEFT", "PADDLEFT" },
    },
    {
        id = "menuRight",
        context = "menu",
        input = "right",
        name = "Right",
        keys = { "D", "RIGHT", "PADLSTICKRIGHT", "PADDRIGHT" },
    },
    { id = "accept", context = "menu", input = "accept", name = "Accept", keys = { "E", false, "PAD1", false } },
    { id = "back", context = "menu", input = "back", name = "Back", keys = { "Q", false, "PAD2", false } },
    -- One key for both: in a run start over (held during one), in a menu its page's extra action
    -- (a new seed).
    {
        id = "restart",
        context = "both",
        input = "extra",
        name = "Start over / new seed",
        keys = { "R", false, "PAD4", false },
    },
}
local byId = {}
for _, action in ipairs(overlay.ACTIONS) do
    byId[action.id] = action
end
overlay.ACTION_BY_ID = byId

-- The key in `slot` of action `id`, or nil where there is none.
function overlay.ActionKey(id, slot)
    local saved = app.db and app.db.profile.keys
    local own = saved and saved[id]
    -- Only a slot set (a key, or false for unbound) replaces the default.
    if type(own) == "table" and own[slot] ~= nil then
        return own[slot] or nil
    end
    return byId[id].keys[slot] or nil
end

-- `key` with the modifiers held, as key bindings name it: "CTRL-SHIFT-E".
function overlay.Chord(key)
    return (IsAltKeyDown() and "ALT-" or "")
        .. (IsControlKeyDown() and "CTRL-" or "")
        .. (IsShiftKeyDown() and "SHIFT-" or "")
        .. key
end

-- Whether actions of contexts `a` and `b` ("run", "menu" or "both") can meet on one key press.
function overlay.SameContext(a, b)
    return a == b or a == "both" or b == "both"
end

-- The action of `context` ("run" or "menu") with `chord` in one of its slots; nil for none.
function overlay.KeyAction(context, chord)
    for _, action in ipairs(overlay.ACTIONS) do
        if overlay.SameContext(action.context, context) then
            for slot = 1, overlay.KEY_SLOTS do
                if overlay.ActionKey(action.id, slot) == chord then
                    return action.id
                end
            end
        end
    end
end

-- Whether `key` (released, without its modifiers) is the key of one of action `id`'s slots.
function overlay.IsActionKey(id, key)
    for slot = 1, overlay.KEY_SLOTS do
        local bound = overlay.ActionKey(id, slot)
        if bound and bound:match("[^-]+$") == key then
            return true
        end
    end
    return false
end

-- The keys the game shows (the legend, the menus' hints, the title's prompt): Key 1, or
-- Gamepad 1 since a gamepad's button or stick was used last.
local KEYBOARD_SLOT, GAMEPAD_SLOT = 1, 3

function overlay:ShownSlot()
    return self.usingGamepad and GAMEPAD_SLOT or KEYBOARD_SLOT
end

local function relayout(menu)
    if menu and menu.panel:IsShown() and menu.stack[1] then
        menu:Layout()
    end
end

-- Every key or button pressed: on a change of device, what shows the keys shows the other's.
function overlay:NoteDevice(key)
    local gamepad = key:sub(1, 3) == "PAD"
    if gamepad ~= (self.usingGamepad == true) then
        self.usingGamepad = gamepad
        self.legendState, self.screenPrompt = nil, nil
        relayout(self.mainMenu)
        relayout(self.statusMenu)
    end
end

-- Gamepad buttons as the default UI's gamepad mode shows them: the prompt icon of the controller's
-- style (Blizzard_SharedXML's InputIconTextureSetUtility; Xbox's while the game is not in gamepad
-- mode). Without one, the binding text's small icon (KEY_ABBR_...). Inline, as a texture markup.
local ICON, ICON_SIZE = "|A:%s:%d:%d|a", 22
local function gamepadIcon(key)
    local utility = InputIconTextureSetUtility
    -- Its texture states are its own: only the function that picks the normal one sees them. It
    -- fails for a key without icons, so those are asked for first.
    if not (utility and utility.GetActiveInputIconButtonTextures(key)) then
        return nil
    end
    local atlas = utility.GetNormalActiveInputIconButtonTexture(key)
    return type(atlas) == "string" and ICON:format(atlas, ICON_SIZE, ICON_SIZE) or nil
end

-- Whether `text` (from KeyText or ShownKeys) is an icon, not a name: shown without a key cap.
function overlay.IsIcon(text)
    return text:sub(1, 3) == "|A:"
end

-- Several keys shown as one: all directions of a stick, or of the D-pad (the default UI's whole
-- stick and D-pad icons; one way only, its left-right or up-down icon). `text` without an icon.
local GROUPED = {
    { prefix = "PADLSTICK", icon = "PADLSTICKAXIS", text = "L Stick" },
    { prefix = "PADRSTICK", icon = "PADRSTICKAXIS", text = "R Stick" },
    { prefix = "PADD", icon = "DIRPAD", text = "D-Pad" },
}
local DPAD_WAYS = { PADDLEFT = "DIRPADHORIZONTAL", PADDRIGHT = "DIRPADHORIZONTAL" }

-- A key's text on a key cap: a gamepad button's icon, else the key's name.
function overlay.KeyText(key)
    if key:sub(1, 3) == "PAD" then
        local icon = gamepadIcon(key)
        if icon then
            return icon
        end
        local short = _G["KEY_ABBR_" .. key]
        if type(short) == "string" and short ~= "" then
            return short
        end
    end
    return GetBindingText and GetBindingText(key) or key
end

local function within(keys, prefix)
    for _, key in ipairs(keys) do
        if key:sub(1, #prefix) ~= prefix then
            return false
        end
    end
    return true
end

-- Into `out` (reused): the cap texts of `actions`' keys in `slot` (those without one left out),
-- in their order; directions of one stick or of the D-pad as one cap.
function overlay.ShownKeys(out, actions, slot)
    for i = #out, 1, -1 do
        out[i] = nil
    end
    for _, id in ipairs(actions) do
        out[#out + 1] = overlay.ActionKey(id, slot)
    end
    if #out > 1 then
        for _, group in ipairs(GROUPED) do
            if within(out, group.prefix) then
                local icon = group.icon
                -- The D-pad's left and right only, or its up and down only.
                if icon == "DIRPAD" then
                    local horizontal = DPAD_WAYS[out[1]]
                    local same = true
                    for _, key in ipairs(out) do
                        same = same and DPAD_WAYS[key] == horizontal
                    end
                    if same then
                        icon = horizontal or "DIRPADVERTICAL"
                    end
                end
                for i = #out, 2, -1 do
                    out[i] = nil
                end
                out[1] = gamepadIcon(icon) or group.text
                return out
            end
        end
    end
    for i, key in ipairs(out) do
        out[i] = overlay.KeyText(key)
    end
    return out
end
