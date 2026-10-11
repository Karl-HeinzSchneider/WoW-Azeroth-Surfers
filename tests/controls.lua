local app = {}
dofile("tests/load.lua")(app, {
    "game/random",
    "game/simulation",
    "game/challenges",
    "game/track",
    "patterns/patterns.xml",
    "game/autopilot",
    "game/light",
    "game/shapes",
    "game/overlay",
    "game/keys",
    "game/menus",
    "game/screens",
    "game/controls",
})
local r = app.overlay
app.logger = app.logger or { debug = function() end }
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
-- The view: whether the last key went on to WoW.
local propagates
r.frame = {
    SetPropagateKeyboardInput = function(_, value)
        propagates = value
    end,
}
r.state = app.simulation.New()
binding = "MOVEFORWARD"
r:OnKey("W")
assert(r.state.status == "running" and r.state.velocity == 0)
assert(propagates, "observed keys go on to WoW")
-- The run's keys (keys.lua), whatever they are bound to in WoW: WASD, the arrows, the gamepad.
binding = nil
r:OnKey("A")
assert(r.state.lane == 1 and propagates, "A: lane left, observed")
r:OnKey("RIGHT")
assert(r.state.lane == 0, "the right arrow: lane right")
r:OnKey("PADLSTICKRIGHT")
assert(r.state.lane == -1, "the left stick: lane right")
r:OnKey("PADDLEFT")
assert(r.state.lane == 0, "the D-pad mirrors it (Gamepad 2): lane left")
r:OnKey("PADDRIGHT")
assert(r.state.lane == -1)
assert(app.overlay.ActionKey("jump", 4) == nil, "Gamepad 2 is empty otherwise")
r:OnKey("LEFT")
-- The left stick's axis as buttons: one lane per push, held until it is let back.
r:OnStick("Left", -0.8, 0)
assert(r.state.lane == 1, "the stick pushed left: lane left")
r:OnStick("Left", -0.4, 0)
r:OnStick("Left", -0.9, 0.1)
assert(r.state.lane == 1, "held: no second lane")
r:OnStick("Left", 0, 0)
r:OnStick("Right", 0.9, 0)
assert(r.state.lane == 1, "the right stick is not the left")
r:OnStick("Left", 0.7, 0)
assert(r.state.lane == 0, "pushed right after it was let back")
r:OnStick("Left", 0, 0)
-- The keys shown: Key 1 side by side, or Gamepad 1 once a gamepad was used, a stick's or the
-- D-pad's directions as one cap.
local shown = {}
local function caps(actions, slot)
    return table.concat(app.overlay.ShownKeys(shown, actions, slot), " ")
end
assert(caps({ "up", "menuLeft", "down", "menuRight" }, 1) == "W A S D")
assert(caps({ "left", "right" }, 1) == "A D" and caps({ "left", "right" }, 3) == "L Stick")
assert(caps({ "up", "down" }, 4) == "D-Pad" and caps({ "jump" }, 4) == "", "one stick; an empty slot")
-- With the default UI's gamepad icons: a button's icon, one stick or D-pad icon for a group.
-- As the client has it: its texture states are local to its file, and the normal texture of a
-- key without icons is an error.
local ATLASES = { PAD1 = "button-a", PADLSTICKAXIS = "stick-l", DIRPADHORIZONTAL = "dpad-lr", DIRPAD = "dpad" }
InputIconTextureSetUtility = {
    GetActiveInputIconButtonTextures = function(key)
        return ATLASES[key] and { ATLASES[key] }
    end,
    GetNormalActiveInputIconButtonTexture = function(key)
        return InputIconTextureSetUtility.GetActiveInputIconButtonTextures(key)[1]
    end,
}
assert(caps({ "jump" }, 3) == "|A:button-a:22:22|a" and caps({ "left", "right" }, 3) == "|A:stick-l:22:22|a")
assert(caps({ "left", "right" }, 4) == "|A:dpad-lr:22:22|a", "the D-pad's left and right")
assert(caps({ "up", "menuLeft", "down", "menuRight" }, 4) == "|A:dpad:22:22|a", "all of the D-pad")
assert(app.overlay.IsIcon(caps({ "jump" }, 3)) and not app.overlay.IsIcon("W"))
InputIconTextureSetUtility = nil
r:OnKey("PAD2")
assert(r:ShownSlot() == 3, "a gamepad button shows the gamepad's keys")
r:OnKey("M")
assert(r:ShownSlot() == 1, "a key, the keyboard's again")
-- What a push sets on the Keys tab: the way a stick is pushed furthest, either stick.
local stickButton = app.overlay.StickButton
assert(stickButton("Left", -0.9, 0.2) == "PADLSTICKLEFT" and stickButton("Camera", 0.1, 0.8) == "PADRSTICKUP")
assert(stickButton("Left", 0.3, 0) == nil and stickButton("Trigger", 1, 0) == nil, "not far enough, or no stick")
r:OnKey("SPACE")
assert(r.state.lane == 0 and r.state.velocity > 0)
focused = {}
r:OnKey("D")
assert(r.state.lane == 0 and propagates, "typing goes to the focused box")
focused = nil
-- A key set with a modifier works only with it.
app.db = { profile = { keys = { right = { "SHIFT-Z", false, false } } } }
r:OnKey("Z")
assert(r.state.lane == 0, "Z alone is not SHIFT-Z")
function IsShiftKeyDown()
    return true
end
r:OnKey("Z")
assert(chord == "SHIFT-Z" and r.state.lane == -1)
function IsShiftKeyDown()
    return false
end
app.db = nil
r.capture = true
r:OnKey("A")
assert(r.state.lane == 0 and propagates == false, "captured, the run's keys stop at the view")
binding = "MOVEFORWARD"
r:OnKey("W")
assert(propagates == false, "and WoW's movement keys, so the character stays put")
binding = "TOGGLEMINIMAP"
r:OnKey("M")
assert(propagates, "other keys go on while captured")
r.capture = nil
binding = nil
-- The game's own keys stop at the view: Q pauses and goes on, holding R starts over.
r:OnKey("Q")
assert(r.state.status == "paused" and propagates == false)
r:OnKey("Q")
assert(r.state.status == "running")
r:OnKey("R")
assert(r.holding == 0 and propagates == false, "R starts the hold")
r:OnKeyRelease("R")
assert(r.holding == nil)
-- In auto mode every key goes on to WoW, the game's own too, and none steers.
r.auto = true
local lane = r.state.lane
for _, k in ipairs({ "A", "Q", "R" }) do
    binding = k == "A" and "STRAFELEFT" or nil
    r:OnKey(k)
    assert(propagates and r.state.lane == lane and r.state.status == "running" and r.holding == nil, k)
end
r.auto = nil
-- Keys set in the options take their place, slot by slot: Q and P go on to WoW, O pauses, the
-- gamepad's Start still does; T starts over.
app.db = { profile = { keys = { pause = { "O", false }, restart = { "T", false, false } } } }
binding = nil
r:OnKey("Q")
r:OnKey("P")
assert(propagates and r.state.status == "running", "Q and P are WoW's again")
r:OnKey("O")
assert(r.state.status == "paused" and propagates == false, "O pauses")
r:OnKey("PADFORWARD")
assert(r.state.status == "running", "the gamepad's default stays")
r:OnKey("T")
assert(r.holding == 0 and propagates == false, "T starts the hold")
r:OnKeyRelease("T")
assert(r.holding == nil)
-- While the options show (a key being bound there), every key goes on and the game takes none.
app.options = {
    IsOpen = function()
        return true
    end,
}
r.capture = true
local still = r.state.lane
r:OnKey("A")
r:OnStick("Left", -0.9, 0)
assert(r.state.lane == still and propagates, "options open: the game takes no key")
app.options, r.capture = nil, nil
-- A profile as AceDB gives it, with nothing set: every default works.
app.db = { profile = { keys = {} } }
local before = r.state.lane
r:OnKey("A")
assert(r.state.lane == math.min(1, before + 1), "A: lane left by default")
assert(app.overlay.ActionKey("accept", 1) == "E" and app.overlay.ActionKey("accept", 2) == nil)
app.db = nil
print("PASS the game's keys, modifiers, forward start, jump, typing focus, capture, pause and restart keys, auto mode")

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

-- Through a challenge's last portal: its finish once, the run going on to its end past it.
local finishes = 0
function r:Finish(s)
    assert(s == self.state and s.status == "running")
    finishes = finishes + 1
end
r.state = g.New()
r.state.nextRow = math.huge
r.state.objects = {}
g.Start(r.state)
r.state.finish = r.state.distance + 1
while r.state.distance < r.state.finish do
    x = x + 0.1
    r:Step(0.05)
end
assert(finishes == 1 and r.state.status == "running", "once, past it")
for _ = 1, 100 do
    x = x + 0.1
    r:Step(0.05)
end
assert(finishes == 1 and r.state.finished and r.state.status == "over", "and not again at its end")
r.Finish = nil
print("PASS a challenge's last portal: its finish once")

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

-- Exercise surface contacts through the real physics, including a dive onto wood.
dofile("tests/load.lua")(app, { "game/biomes", "biomes/default", "biomes/elwynn", "biomes/teldrassil" })
app.db.profile.footstepSound, app.db.profile.biome = true, "default"
app.db.profile.coinSound = false
r.capture, r.screen = true, nil
local function freshFeet()
    r.state = g.New(42)
    r.state.nextRow = math.huge
    g.Start(r.state)
    r:Footsteps()
    played = {}
end
freshFeet()
for _ = 1, 10 do
    r:Step(0.05)
end
assert(#played > 0 and played[1] == "540227 SFX", "running uses dirt contacts")
g.Jump(r.state)
r:Step(0.01)
local takeoff = #played
assert(takeoff > 1, "jump takeoff sounds")
for _ = 1, 4 do
    r:Step(0.05)
end
assert(#played == takeoff, "airborne feet are silent")
-- Put a wooden platform beneath the descending runner.
r.state.objects = { g.Box("platform", 0, r.state.distance - 1, 20, 0, 1) }
g.Duck(r.state)
for _ = 1, 5 do
    r:Step(0.05)
end
assert(#played == takeoff + 1 and played[#played] == "540105 SFX", "dive lands once on wood")
assert(r.state.duck > 0, "the landing starts a roll")
r:Step(0.05)
assert(#played == takeoff + 1, "no running steps during the roll")
g.Pause(r.state)
r:Step(0.1)
assert(#played == takeoff + 1, "paused feet are silent")
freshFeet()
g.Duck(r.state)
r:Step(0.01)
assert(#played == 1, "grounded roll makes one contact")
g.Duck(r.state)
r:Step(0.01)
assert(#played == 1, "repeating duck does not spam contacts")
freshFeet()
app.db.profile.biome = "teldrassil"
g.Jump(r.state)
r:Footsteps()
assert(played[1] == "540160 SFX", "biome changes select leafy contacts immediately")
local n = #played
for _ = 1, 20 do
    g.Update(r.state, 0.05)
    r:Footsteps()
end
assert(#played == n + 1, "stationary jump still lands audibly")
app.db.profile.footstepSound = false
g.Jump(r.state)
r:Footsteps()
assert(#played == n + 1, "footstep option silences contacts")
app.db.profile.footstepSound = true
r:Footsteps()
assert(#played == n + 1, "reenabling does not replay muted contacts")
print("PASS footsteps, biome materials, wooden dive landing, rolling, pause and sound option")

-- Restarts as a player makes them: a seed lays out one track, from the menu, a restart, or a
-- restart once it is kept from the pause menu; with "Start at", the same track from there.
dofile("tests/load.lua")(app, { "scenes/lobby" })
local function layout(s)
    local lines = {}
    for _, o in ipairs(s.objects) do
        lines[#lines + 1] = string.format("%s %d %.6f %d %d", o.kind, o.lane, o.at, o.layer, o.seed)
    end
    return table.concat(lines, "\n")
end
-- The track of `s` from `at` on, run high above it so nothing stops it.
local function ahead(s, at)
    s.status, s.forward = "running", true
    local lines = {}
    while s.distance < at + 400 do
        s.height = 1e6
        g.Update(s, 1 / 120)
        for _, o in ipairs(s.objects) do
            if o.at >= at then
                lines[string.format("%s %d %.6f %d %d", o.kind, o.lane, o.at, o.layer, o.seed)] = true
            end
        end
    end
    return lines
end
local function same(a, b)
    for k in pairs(a) do
        assert(b[k], "the same box: " .. k)
    end
    for k in pairs(b) do
        assert(a[k], "the same box: " .. k)
    end
end
app.db = { global = { bestScore = 0 }, profile = { seed = false, startAt = 0, biome = "auto" } }
r.frame = r.frame or {}
r.state = r:NewState(app.lobby, 777)
local menu = ahead(r.state, 1000)
-- A restart with a new seed each run: kept from the pause menu, then restarted twice.
r.state.seed = 777
r:SetFixedSeed(true)
assert(app.db.profile.seed == 777)
r:Restart()
local first = r.state
r:Restart()
assert(layout(first) == layout(r.state) and r.state.seed == 777, "every restart the same")
same(menu, ahead(r.state, 1000))
-- Started 3000 yards in: the menu's track from its first pattern on.
app.db.profile.startAt = 3000
r:Restart()
local skipped = r.state
assert(skipped.practice == 3000 and skipped.distance >= 3000)
local cut = math.huge
for _, o in ipairs(skipped.objects) do
    cut = math.min(cut, o.at)
end
local fromMenu = r:NewState(app.lobby, 777)
same(ahead(fromMenu, cut), ahead(skipped, cut))
print("PASS a seed's track is the same from the menu, a restart and a later start")

-- "Start at" from the main menu: the run shown there (any seed) begins that far in; a restart
-- only with a kept seed.
app.db.profile.seed, app.db.profile.startAt = false, 2000
assert(not r:StartsAt())
r:Restart()
assert(r.state.distance < 2000, "a new seed restarts past the portal")
assert(not r.state.practice)
local menuRun = r:NewState(nil, 777, 2000)
assert(menuRun.seed == 777 and menuRun.practice == 2000 and menuRun.distance >= 2000)
r:SetFixedSeed(true)
assert(r:StartsAt())
print("PASS the start point from the main menu, and for restarts only with a kept seed")

-- A challenge: its seed and difficulty through zones to its goal, whatever the profile's seed,
-- difficulty and start; every restart the same; the best saved once over.
app.db.global.challenges = {}
function GetServerTime()
    return 20736 * 86400 + 12 * 3600
end
local period = app.challenges.Period("daily", 20736 * 86400 + 12 * 3600)
app.db.profile.biome = "elwynn"
app.db.profile.difficulty = period.difficulty == "easy" and "expert" or "easy"
r.challenge = period
r.state = r:NewState(app.lobby)
local challenge = r.state
assert(challenge.seed == period.seed and challenge.zones and challenge.finish == challenge.start + period.goal)
assert(challenge.difficulty.id == period.difficulty, "the challenge's difficulty")
r:Restart()
assert(r.state.challenge == period and not r.state.practice, "a restart ignores Start at")
assert(r.state.finish - r.state.start == period.goal and r.state.seed == period.seed)
assert(r.state.difficulty.id == period.difficulty)
same(ahead(r:NewState(app.lobby), 1500), ahead(r.state, 1500))
r.state.status, r.state.finished, r.state.distance = "over", true, r.state.finish + 20
r.state.points, r.state.coins = 6000, 42
r:SaveBest()
local best = app.challenges.Best(period)
assert(best and best.score == 6000 and best.coins == 42 and best.finished and best.distance == period.goal)
assert(best.difficulty == period.difficulty and best.goal == period.goal)
assert(r.state.newBest and app.db.global.bestScore ~= 6000, "not the endless best")
assert(r.state.lastBest == nil, "no best before it")
r:Restart()
r:SaveBest()
assert(app.challenges.Best(period).score == 6000, "a run left before its end saves nothing")
r.state.status, r.state.finished, r.state.distance = "over", true, r.state.finish + 20
r.state.points = 5000
r:SaveBest()
assert(not r.state.newBest and r.state.lastBest.score == 6000, "the best before it, kept")
r:SaveBest()
assert(r.state.lastBest.score == 6000, "saved once")
r:Restart()
r.state.status, r.state.finished, r.state.distance = "over", true, r.state.finish + 20
r.state.points = 7000
r:SaveBest()
assert(r.state.newBest and r.state.lastBest.score == 6000 and app.challenges.Best(period).score == 7000)
r:SaveBest()
assert(r.state.lastBest.score == 6000, "not the best it just set")
print("PASS a challenge's runs: its seed to its goal, restarts, its best")
