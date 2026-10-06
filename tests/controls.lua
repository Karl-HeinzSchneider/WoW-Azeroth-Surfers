local app = {}
assert(loadfile("Surfer/src/game/simulation.lua"))("Surfer", app)
assert(loadfile("Surfer/src/game/window.lua"))("Surfer", app)
local r = app.runner
local focused, binding, chord
function InCombatLockdown()
    return false
end
function GetCurrentKeyBoardFocus()
    return focused
end
function IsAltKeyDown()
    return false
end
function IsControlKeyDown()
    return false
end
function IsShiftKeyDown()
    return false
end
function GetBindingAction(key, overrides)
    chord = key
    assert(overrides)
    return binding
end
r.state = app.simulation.New()
binding = "MOVEFORWARD"
r:OnMovementKey("W")
assert(r.state.status == "running" and r.state.velocity == 0)
binding = "STRAFELEFT"
r:OnMovementKey("Q")
assert(r.state.lane == 1)
binding = "TURNRIGHT"
r:OnMovementKey("D")
assert(r.state.lane == 0)
binding = "JUMP"
r:OnMovementKey("SPACE")
assert(r.state.velocity > 0)
focused = {}
binding = "TURNRIGHT"
r:OnMovementKey("D")
assert(r.state.lane == 0)
focused = nil
function IsShiftKeyDown()
    return true
end
r:OnMovementKey("Z")
assert(chord == "SHIFT-Z" and r.state.lane == -1)
print("PASS movement bindings, modifiers, forward start, jump and typing focus")
for _, direction in ipairs({ -1, 1 }) do
    r.scene = {
        Transform3DPointTo2D = function(_, _, y)
            return 450 + y * direction * 40
        end,
    }
    r:CalibrateLanes()
    assert(r.laneSign == direction)
    assert(r.scene:Transform3DPointTo2D(0, -r.laneSign) < 450)
    assert(r.scene:Transform3DPointTo2D(0, r.laneSign) > 450)
end
print("PASS lane orientation for both native camera directions")
