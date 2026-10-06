local app = {}
for _, file in ipairs({ "random", "simulation", "light", "shapes", "overlay", "controls" }) do
    assert(loadfile("Surfer/src/game/" .. file .. ".lua"))("Surfer", app)
end
local r = app.overlay
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

local x, y, map, facing, speed = 0, 0, 1, 0, 7
function UnitPosition()
    return x, y, 0, map
end
function GetPlayerFacing()
    return facing
end
function GetUnitSpeed()
    return speed
end
assert(not r:IsMovingForward(0.1))
x = 0.7
assert(r:IsMovingForward(0.1))
x = 0
assert(not r:IsMovingForward(0.1))
y = 0.7
assert(not r:IsMovingForward(0.1))
assert(not r:IsMovingForward(0.1))
facing = math.pi
x = -0.7
assert(r:IsMovingForward(0.1))
x = 100
assert(not r:IsMovingForward(0.1))
map = 2
assert(not r:IsMovingForward(0.1))
speed = 0
x = 99.9
assert(not r:IsMovingForward(0.1))
print("PASS forward/backward/strafe/standing movement, facing, teleports and map changes")

-- Collecting a coin plays the money loot sound file once, unless the option is off.
local played = {}
function PlaySoundFile(file, channel)
    played[#played + 1] = file .. " " .. channel
end
local g = app.simulation
app.db = { global = { bestScore = 0 }, profile = { coinSound = true } }
r.state = g.New()
r.state.nextRow = math.huge
r.state.objects = { g.Box("coin", 0, 0.5, 0.32, 0, 1) }
g.Start(r.state)
speed, x, facing = 7, 0, 0
r:Step(0.01)
for _ = 1, 30 do
    x = x + 0.1
    r:Step(0.05)
end
assert(r.state.coins == 1 and #played == 1 and played[1] == "567428 SFX", "one coin, one clink")
app.db.profile.coinSound = false
r.state.objects = { g.Box("coin", 0, r.state.distance + 0.5, 0.32, 0, 1) }
for _ = 1, 30 do
    x = x + 0.1
    r:Step(0.05)
end
assert(r.state.coins == 2 and #played == 1, "the option silences it")
print("PASS coin pickup plays the loot sound once, unless switched off")

-- Motion relative to facing, for the twin: ahead and to the left are positive.
facing, speed, map = 0, 7, 1
x, y = 0, 0
r:IsMovingForward(0.1)
x = 0.7
r:IsMovingForward(0.1)
assert(math.abs(r.motion.forward - 7) < 1e-9 and math.abs(r.motion.left) < 1e-9 and r.motion.speed == 7)
y = 0.7
r:IsMovingForward(0.1)
assert(math.abs(r.motion.forward) < 1e-9 and math.abs(r.motion.left - 7) < 1e-9, "west of north is left")
facing = math.pi / 2
y = 1.4
r:IsMovingForward(0.1)
assert(math.abs(r.motion.forward - 7) < 1e-9 and math.abs(r.motion.left) < 1e-9, "facing west, west is ahead")
print("PASS motion relative to facing")
