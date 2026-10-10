---@type string, AzerothSurfers
local _, app = ...
local sim = app.simulation
-- Input, movement sampling, the per-frame step and scoring. The run's keys (keys.lua) steer it;
-- they and WoW's movement keys go on to WoW too unless `profile.capture` stops them here, and
-- then the runner runs by itself. Pause and start over always stop here. In auto mode the game
-- takes no keys at all.
local overlay = app.overlay
local autopilot = app.autopilot

-- The bindings a captured key may have: they move the character.
local MOVEMENT = {
    MOVEFORWARD = true,
    MOVEBACKWARD = true,
    TURNLEFT = true,
    TURNRIGHT = true,
    STRAFELEFT = true,
    STRAFERIGHT = true,
    JUMP = true,
    TOGGLEAUTORUN = true,
}
-- The twin's speed while captured: a character's normal run.
local RUN_SPEED = 7
-- The start-over key (keys.lua): pressed once after a run, or held RESTART_HOLD seconds during one.
local RESTART_HOLD = 0.75
-- Seconds a finished auto mode run stays on screen.
local AUTO_RESTART = 3

function overlay:SaveBest()
    if self.state.piloted or self.state.practice then
        return
    end
    local score = sim.Score(self.state)
    if score > app.db.global.bestScore then
        app.db.global.bestScore = score
        self.state.newBest = true
    end
end

-- `lobby`: a run from the lobby (screens.lua); `seed`: kept instead of the profile's. With a
-- fixed seed, a run not from the lobby starts `startAt` yards into it.
function overlay:NewState(lobby, seed)
    local profile = app.db.profile
    local s = sim.New(seed or profile.seed or nil, profile.difficulty, profile.biome == app.biomes.AUTO, lobby)
    if profile.seed and (profile.startAt or 0) > 0 then
        sim.Skip(s, profile.startAt)
    end
    return s
end

-- Yards into a fixed seed a restart begins; a run not started yet takes it at once.
function overlay:SetStartAt(yards)
    app.db.profile.startAt = math.max(0, math.min(sim.MAX_START, math.floor(yards or 0)))
    if app.options then
        app.options:Refresh()
    end
    if self.frame and self.state.status == "ready" and not self.state.lobby then
        self.state = self:NewState(nil, self.state.seed)
    end
end

function overlay:Restart()
    self:SaveBest()
    self.state = self:NewState()
    sim.Start(self.state)
end

-- A whole number, or false: every run draws its own. A run not started yet takes it at once.
function overlay:SetSeed(seed)
    app.db.profile.seed = seed and app.random.Normalize(seed) or false
    if app.options then
        app.options:Refresh()
    end
    if not self.frame then
        return
    end
    if self.state.status == "ready" then
        self.state = self:NewState(self.state.lobby)
    end
end

-- From the next run on; a run not started yet takes it at once, with its seed.
function overlay:SetDifficulty(id)
    if not sim.DIFFICULTIES[id] then
        return
    end
    app.db.profile.difficulty = id
    if app.options then
        app.options:Refresh()
    end
    if not self.frame then
        return
    end
    if self.state.status == "ready" then
        self.state = self:NewState(self.state.lobby, self.state.seed)
    end
end

function overlay:StepDifficulty(step)
    local current = sim.DIFFICULTIES[app.db.profile.difficulty] or sim.DIFFICULTIES.normal
    local other = sim.DIFFICULTIES[current.level + step]
    if other then
        self:SetDifficulty(other.id)
    end
end

-- On keeps the current run's seed for every run.
function overlay:SetFixedSeed(on)
    if on then
        self:SetSeed(self.state and self.state.seed or app.random.Seed())
    else
        self:SetSeed(false)
    end
end

function overlay:Action(key)
    local s = self.state
    -- Positive simulation lanes are on the screen's left.
    if key == "LEFT" or key == "A" then
        sim.Move(s, 1)
    elseif key == "RIGHT" or key == "D" then
        sim.Move(s, -1)
    elseif key == "SPACE" then
        if s.status == "ready" then
            sim.Start(s)
        else
            sim.Jump(s)
        end
    elseif key == "DOWN" or key == "S" then
        sim.Duck(s)
    elseif key == "P" then
        sim.Pause(s)
    elseif key == "ENTER" then
        if s.status == "ready" or s.status == "over" then
            self:Restart()
        else
            sim.Pause(s)
        end
    elseif key == "ESCAPE" then
        if s.status == "running" then
            sim.Pause(s)
        else
            self.frame:Hide()
        end
    end
end

-- sound/interface/lootcoinsmall.ogg, for a coin model without a `sound` and the flat coins: the
-- file, not its kit, so each coin of a trail clinks.
local COIN_SOUND_FILE = 567428

-- Distance drives cadence, so standing still is silent and faster runs step faster.
-- Simulation contacts also catch jumps made by the autopilot and landing after a dive.
function overlay:Footsteps()
    local s = self.state
    if self.footState ~= s then
        self.footState, self.footContacts = s, 0
        self.footDistance, self.footTravel, self.footIndex = s.distance, 0, 0
    end
    local contact = s.contacts ~= self.footContacts
    local distance = math.max(0, s.distance - self.footDistance)
    self.footContacts, self.footDistance = s.contacts, s.distance
    if not app.db.profile.footstepSound or s.status ~= "running" or self.screen then
        self.footTravel = 0
        return
    end
    local look = self:BiomeAt(contact and s.contactAt or s.distance).footsteps
    local floor = contact and s.contactFloor or s.floor
    if contact then
        self.footTravel = 0
    elseif s.velocity ~= 0 or s.height > s.floor or s.duck > 0 then
        self.footTravel = 0
        return
    else
        self.footTravel = self.footTravel + distance
        if self.footTravel < look.stride then
            return
        end
        self.footTravel = self.footTravel % look.stride
    end
    local sounds = floor > 0 and look.wood or look.ground
    if #sounds > 0 and PlaySoundFile then
        self.footIndex = self.footIndex + 1
        PlaySoundFile(sounds[(self.footIndex - 1) % #sounds + 1], "SFX")
    end
end

function overlay:Step(elapsed)
    local s = self.state
    -- A run from the lobby runs by itself up to the portal, as when captured.
    if self.capture or self.auto or autopilot.InIntro(s) then
        s.forward = self:AutoRun()
    else
        s.forward = self:IsMovingForward(elapsed)
    end
    self:StepApproach(elapsed)
    -- Not before a screen has let the run begin (screens.lua).
    if s.forward and s.status == "ready" and not self.screen then
        sim.Start(s)
    end
    local status, collected, streak = s.status, s.collected, s.streak
    if autopilot.Intro(s, elapsed) then
        -- Up to the portal it plays itself; in auto mode the run is the autopilot's (no best
        -- score).
        if self.auto then
            s.piloted = true
        end
    elseif self.auto then
        self:StepAuto(s, elapsed)
    else
        sim.Update(s, elapsed)
    end
    if status == "running" and s.status == "over" then
        self:SaveBest()
    end
    self:Footsteps()
    -- Every coin picked up clinks, also those before the run counts (a run from the lobby).
    if s.collected > collected and app.db.profile.coinSound then
        local entry = self.coinReady and self.biome.coin.models[self.coinModel]
        local sound = entry and entry.sound or COIN_SOUND_FILE
        -- A ladder: the streak's step, the last one from there on; its finale once, on the
        -- coin that takes the streak past the last step.
        if type(sound) == "table" then
            local top = #sound
            if entry.finale and streak <= top and s.streak > top then
                sound = entry.finale
            else
                sound = sound[math.max(1, math.min(s.streak, top))]
            end
        end
        if PlaySoundFile then
            PlaySoundFile(sound, "SFX")
        else
            PlaySound(SOUNDKIT and SOUNDKIT.LOOT_WINDOW_COIN_SOUND or 120, "SFX")
        end
    end
end

function overlay:StepAuto(s, elapsed)
    if s.status ~= "over" then
        autopilot.Play(s, elapsed)
        return
    end
    if self.autoEnded ~= s then
        self.autoEnded, self.autoWait = s, 0
        app.logger:debug(
            "Auto mode: over at %d yards, score %d (%s, seed %d)%s",
            math.floor(sim.Run(s)),
            sim.Score(s),
            s.difficulty.name,
            s.seed,
            autopilot.lost and string.format(", found no way through from %d yards on", autopilot.lost) or ""
        )
    end
    self.autoWait = self.autoWait + elapsed
    if self.autoWait >= AUTO_RESTART then
        self:Restart()
    end
end

-- A run it played is never yours to go on with: off, it gives way to the main menu. On from the
-- title or the menu, it starts from the lobby like Watch.
function overlay:SetAuto(on)
    if not on == not self.auto then
        return
    end
    if on and self.screen then
        self:Play(true)
        return
    end
    self.auto = on or nil
    local s = self.state
    if on then
        if s.status == "paused" then
            sim.Pause(s)
        elseif s.status == "over" then
            self:Restart()
        end
    else
        self:OpenMenu()
    end
    self:Layout()
    self.legendState = nil
    self.statusShown = nil
end

-- Sample actual displacement, so autorun/mouse movement work and pushing a wall does not.
-- Also keeps `motion` (velocity relative to facing, and speed) for the twin's animations.
function overlay:IsMovingForward(elapsed)
    local x, y, _, map = UnitPosition("player")
    local facing = GetPlayerFacing()
    local last = self.lastPosition or {}
    self.lastPosition = last
    self.motion = self.motion or {}
    self.motion.forward, self.motion.left, self.motion.speed = 0, 0, 0
    if type(x) ~= "number" or type(y) ~= "number" or type(facing) ~= "number" then
        last.valid = false
        return false
    end
    local lastX, lastY, lastMap, valid = last.x, last.y, last.map, last.valid
    last.x, last.y, last.map, last.valid = x, y, map, true
    if not valid or lastMap ~= map or elapsed <= 0 then
        return false
    end
    local speed = GetUnitSpeed("player") or 0
    if speed <= 0 then
        return false
    end
    local dx, dy = x - lastX, y - lastY
    -- Reject teleports and large discontinuities instead of advancing the track.
    local limit = math.max(1, speed * elapsed * 3)
    if dx * dx + dy * dy > limit * limit then
        return false
    end
    local forward = dx * math.cos(facing) + dy * math.sin(facing)
    local left = dy * math.cos(facing) - dx * math.sin(facing)
    self.motion.forward, self.motion.left, self.motion.speed = forward / elapsed, left / elapsed, speed
    return forward > 0.05 * elapsed
end

function overlay:AutoRun()
    self:ForgetPosition()
    local running = self.state.status == "running"
    local motion = self.motion or {}
    self.motion = motion
    motion.forward, motion.left, motion.speed = running and RUN_SPEED or 0, 0, running and RUN_SPEED or 0
    return running
end

-- The next sample starts afresh, e.g. after the view was hidden.
function overlay:ForgetPosition()
    if self.lastPosition then
        self.lastPosition.valid = false
    end
end

-- Whether a key (`chord`, bound in WoW to `binding`) stays with the game whatever screen or menu
-- shows: with `profile.capture` on, every key of the game's (keys.lua, a run's or the menus') and
-- WoW's movement keys, so the character never moves or jumps while the game is open.
function overlay:Captures(chord, binding)
    if not self.capture then
        return false
    end
    return (overlay.KeyAction("run", chord) or overlay.KeyAction("menu", chord) or MOVEMENT[binding]) ~= nil
end

function overlay:OnKey(key)
    -- In combat the view is closed, and whether a key reaches WoW cannot be changed.
    if InCombatLockdown() then
        return
    end
    -- The keys shown follow the device last used (keys.lua).
    self:NoteDevice(key)
    -- Typing goes to the focused box; in auto mode, or while the options show (a key being bound
    -- there), every key goes on to WoW and the game takes none.
    if GetCurrentKeyBoardFocus() or self.auto or (app.options and app.options:IsOpen()) then
        self.frame:SetPropagateKeyboardInput(true)
        return
    end
    local chord = overlay.Chord(key)
    local binding = GetBindingAction(chord, true)
    if self:OnScreenKey(key, binding, chord) then
        return
    end
    local action = overlay.KeyAction("run", chord)
    if action == "restart" then
        self.frame:SetPropagateKeyboardInput(false)
        local status = self.state.status
        if status == "over" then
            self:Restart()
        elseif status ~= "ready" then
            self.holding = self.holding or 0
        end
        return
    elseif action == "pause" then
        self.frame:SetPropagateKeyboardInput(false)
        self:Action("P")
        return
    end
    -- Captured, the game's keys and WoW's own movement keys stop here; else WoW gets them too.
    self.frame:SetPropagateKeyboardInput(not self:Captures(chord, binding))
    if action == "left" then
        self:Action("LEFT")
    elseif action == "right" then
        self:Action("RIGHT")
    elseif action == "jump" then
        self:Action("SPACE")
    elseif action == "duck" then
        self:Action("DOWN")
    elseif binding == "MOVEFORWARD" and self.state.status == "ready" then
        sim.Start(self.state)
    end
end

-- Letting go of a start-over key, whatever modifiers are still held.
function overlay:OnKeyRelease(key)
    if overlay.IsActionKey("restart", key) then
        self.holding = nil
    end
end

-- WoW reports the sticks only as axes (the left one moves the character): pushed past
-- STICK_PRESS a direction is a button of its own (PADLSTICKLEFT, PADRSTICKUP, ...: the names
-- keys.lua's slots hold), pressed until the stick is back under STICK_RELEASE.
local STICK_PRESS, STICK_RELEASE = 0.5, 0.3
-- By the names the client gives a stick (the device's, or its config's): its buttons per axis,
-- toward minus and plus.
local LEFT = { x = { "PADLSTICKLEFT", "PADLSTICKRIGHT" }, y = { "PADLSTICKDOWN", "PADLSTICKUP" } }
local RIGHT = { x = { "PADRSTICKLEFT", "PADRSTICKRIGHT" }, y = { "PADRSTICKDOWN", "PADRSTICKUP" } }
local STICKS = { Left = LEFT, Movement = LEFT, Right = RIGHT, Camera = RIGHT }

-- The way (1: minus, 2: plus) an axis at `value` is pushed, `held` kept until it is let back.
local function pushed(value, held)
    if value <= -STICK_PRESS then
        return 1
    elseif value >= STICK_PRESS then
        return 2
    elseif (held == 1 and value < -STICK_RELEASE) or (held == 2 and value > STICK_RELEASE) then
        return held
    end
end

-- The button of the way `stick` is pushed furthest, nil while it is not pushed far enough: what
-- a push sets on the options' Keys tab.
function overlay.StickButton(stick, x, y)
    local buttons = STICKS[stick]
    if not buttons then
        return nil
    end
    local axis, value = "x", x
    if math.abs(y) > math.abs(x) then
        axis, value = "y", y
    end
    local way = pushed(value)
    return way and buttons[axis][way]
end

local function stickAxis(self, buttons, axis, value)
    local held = self.stickHeld[buttons[axis]]
    local want = pushed(value, held)
    if want ~= held then
        if held then
            self:OnKeyRelease(buttons[axis][held])
        end
        self.stickHeld[buttons[axis]] = want
        if want then
            self:OnKey(buttons[axis][want])
        end
    end
end

-- Each stick name logged once at DEBUG, to see what the client calls them.
local sticksSeen = {}

function overlay:OnStick(stick, x, y)
    if not sticksSeen[stick] then
        sticksSeen[stick] = true
        app.logger:debug("Gamepad stick: %s", tostring(stick))
    end
    local buttons = STICKS[stick]
    if not buttons then
        return
    end
    -- The options take a push to bind it; the game none.
    if app.options and app.options:IsOpen() then
        if not InCombatLockdown() then
            self.frame:SetPropagateKeyboardInput(true)
        end
        return
    end
    self.stickHeld = self.stickHeld or {}
    stickAxis(self, buttons, "x", x)
    stickAxis(self, buttons, "y", y)
    -- Captured, the left stick stays with the game, so the character does not walk off.
    if buttons == LEFT and not InCombatLockdown() and not self.auto then
        self.frame:SetPropagateKeyboardInput(not self.capture)
    end
end

function overlay:UpdateHold(elapsed)
    if self.holding then
        self.holding = self.holding + elapsed
        if self.holding >= RESTART_HOLD then
            self.holding = nil
            self:Restart()
        end
    end
    self:ShowHold(self.holding and self.holding / RESTART_HOLD)
end

-- The game is created on first use.
function overlay:Toggle()
    if InCombatLockdown() then
        app.logger:chat("%s is available outside combat.", app.TITLE)
        return
    end
    if not self.frame then
        self:Create()
    else
        self.frame:SetShown(not self.frame:IsShown())
    end
end
