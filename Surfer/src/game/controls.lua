---@type string, Surfer
local _, app = ...
local sim = app.simulation
-- The game's input, movement sampling, per-frame step and scoring, added to the view that
-- overlay.lua creates. Keys are only observed: WoW still gets them, so the real character
-- moves and jumps too, unless the game captures the movement keys (`profile.capture`): then
-- they stop here, the character stays put and the runner runs by itself. In auto mode the game
-- plays itself (autopilot.lua) and takes no keys at all: you can play on, or just watch.
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
-- Yards per second the twin runs at while captured, the character's normal running speed.
local RUN_SPEED = 7
-- The game's own key: pressed once after a run, or held this many seconds during one, it starts
-- a new run.
local RESTART_KEY, RESTART_HOLD = "R", 0.75
-- The game's pause key: pauses a run and goes on with it.
local PAUSE_KEY = "Q"
-- The game's own keys, for the hotkey legend (legend.lua).
overlay.GAME_KEYS = { pause = PAUSE_KEY, restart = RESTART_KEY }
-- Seconds a run auto mode finished stays on screen before the next one starts.
local AUTO_RESTART = 3

function overlay:SaveBest()
    -- A run auto mode played (a part of) is not the player's.
    if self.state.piloted then
        return
    end
    local score = sim.Score(self.state)
    if score > app.db.global.bestScore then
        app.db.global.bestScore = score
        -- For the status panel (messages.lua).
        self.state.newBest = true
    end
end

-- A run ready to start: from the fixed seed (`profile.seed`), or a new one, at the profile's
-- difficulty.
function overlay:NewState()
    return sim.New(app.db.profile.seed or nil, app.db.profile.difficulty)
end

function overlay:Restart()
    self:SaveBest()
    self.state = self:NewState()
    sim.Start(self.state)
end

-- Fixes the seed (a whole number) or lets every run draw its own (false). A run that has not
-- started yet takes it at once.
function overlay:SetSeed(seed)
    app.db.profile.seed = seed and app.random.Normalize(seed) or false
    -- The addon options show it too.
    if app.options then
        app.options:Refresh()
    end
    -- Before the view is created, only the setting.
    if not self.frame then
        return
    end
    if self.state.status == "ready" then
        self.state = self:NewState()
    end
    -- The status panel's seed option (messages.lua).
    if self.status.holder:IsShown() then
        self:FillStatus(self.state.status)
    end
end

-- Sets the difficulty (an id of simulation.lua's DIFFICULTIES) from the next run on; a run
-- that has not started yet takes it at once, with its seed.
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
        self.state = sim.New(self.state.seed, id)
    end
    -- The status panel's difficulty (messages.lua).
    if self.status.holder:IsShown() then
        self:FillStatus(self.state.status)
    end
end

-- One difficulty easier (-1) or harder (1), as far as there is one.
function overlay:StepDifficulty(step)
    local current = sim.DIFFICULTIES[app.db.profile.difficulty] or sim.DIFFICULTIES.normal
    local other = sim.DIFFICULTIES[current.level + step]
    if other then
        self:SetDifficulty(other.id)
    end
end

-- "Fixed seed" on keeps the current run's seed (or the last one's) for every run; off, every
-- run draws its own.
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

-- The money loot clink (sound/interface/lootcoinsmall.ogg). Its sound kit plays one instance at
-- a time; the file plays every time, so each coin of a trail clinks.
local COIN_SOUND_FILE = 567428

-- One frame of the game: movement, simulation, best score, coin sound.
function overlay:Step(elapsed)
    local s = self.state
    if self.capture or self.auto then
        s.forward = self:AutoRun()
    else
        s.forward = self:IsMovingForward(elapsed)
    end
    if s.forward and s.status == "ready" then
        sim.Start(s)
    end
    local status, coins = s.status, s.coins
    if self.auto then
        self:StepAuto(s, elapsed)
    else
        sim.Update(s, elapsed)
    end
    if status == "running" and s.status == "over" then
        self:SaveBest()
    end
    if s.coins > coins and app.db.profile.coinSound then
        -- The SFX channel follows the game's sound effects volume.
        if PlaySoundFile then
            PlaySoundFile(COIN_SOUND_FILE, "SFX")
        else
            PlaySound(SOUNDKIT and SOUNDKIT.LOOT_WINDOW_COIN_SOUND or 120, "SFX")
        end
    end
end

-- Auto mode's frame: the autopilot plays the run; a finished one stays a moment, then the next
-- one starts.
function overlay:StepAuto(s, elapsed)
    if s.status ~= "over" then
        autopilot.Play(s, elapsed)
        return
    end
    if self.autoEnded ~= s then
        self.autoEnded, self.autoWait = s, 0
        app.logger:debug(
            "Auto mode: over at %d yards, score %d (%s, seed %d)%s",
            math.floor(s.distance),
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

-- Turns auto mode on (the game plays the run, or the next one after a finished run) or off
-- (the run it played pauses, for you to go on with or start over).
function overlay:SetAuto(on)
    if not on == not self.auto then
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
    elseif s.status == "running" then
        sim.Pause(s)
    end
    -- The stop button, and no legend while no key does anything.
    self:Layout()
    self.legendState = nil
    -- The status panel's buttons (messages.lua).
    self.status.shownStatus = nil
end

-- Sample actual displacement, so autorun/mouse movement work and pushing a wall does not.
-- Also keeps `motion`: the character's velocity relative to its facing (yards per second
-- forward and to its left) and its speed, for the twin's animations.
function overlay:IsMovingForward(elapsed)
    local x, y, _, map = UnitPosition("player")
    local facing = GetPlayerFacing()
    -- Both tables are reused every frame.
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

-- Captured, the character stands still: the runner runs while the game runs, and the twin runs
-- with it.
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

function overlay:OnKey(key)
    -- In combat the view is closed, and whether a key reaches WoW cannot be changed.
    if InCombatLockdown() then
        return
    end
    -- Typing goes to the focused box; in auto mode every key goes on to WoW.
    if GetCurrentKeyBoardFocus() or self.auto then
        self.frame:SetPropagateKeyboardInput(true)
        return
    end
    if key == RESTART_KEY and not IsModifierKeyDown() then
        self.frame:SetPropagateKeyboardInput(false)
        local status = self.state.status
        if status == "over" then
            self:Restart()
        elseif status ~= "ready" then
            self.holding = self.holding or 0
        end
        return
    end
    if key == PAUSE_KEY and not IsModifierKeyDown() then
        self.frame:SetPropagateKeyboardInput(false)
        self:Action("P")
        return
    end
    local chord = (IsAltKeyDown() and "ALT-" or "")
        .. (IsControlKeyDown() and "CTRL-" or "")
        .. (IsShiftKeyDown() and "SHIFT-" or "")
        .. key
    local binding = GetBindingAction(chord, true)
    self.frame:SetPropagateKeyboardInput(not (self.capture and binding and MOVEMENT[binding]))
    if not binding then
        return
    end
    if binding == "TURNLEFT" or binding == "STRAFELEFT" then
        self:Action("LEFT")
    elseif binding == "TURNRIGHT" or binding == "STRAFERIGHT" then
        self:Action("RIGHT")
    elseif binding == "JUMP" then
        self:Action("SPACE")
    elseif binding == "MOVEFORWARD" and self.state.status == "ready" then
        sim.Start(self.state)
    end
end

function overlay:OnKeyRelease(key)
    if key == RESTART_KEY then
        self.holding = nil
    end
end

-- Counts how long the restart key is held, and restarts once it was held long enough.
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

-- /surfer and the minimap button: the game is created on first use, then shown and hidden.
function overlay:Toggle()
    if InCombatLockdown() then
        app.logger:chat("Surfer is available outside combat.")
        return
    end
    if not self.frame then
        self:Create()
    else
        self.frame:SetShown(not self.frame:IsShown())
    end
end
