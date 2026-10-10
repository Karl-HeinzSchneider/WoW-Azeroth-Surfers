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
