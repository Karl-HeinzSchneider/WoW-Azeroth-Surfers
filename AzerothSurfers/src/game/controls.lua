---@type string, AzerothSurfers
local _, app = ...
local sim = app.simulation
-- Input, movement sampling, the per-frame step and scoring. Keys are only observed (WoW still
-- gets them) unless `profile.capture` stops the movement keys here; then the runner runs by
-- itself. In auto mode the game takes no keys at all.
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
-- Pressed once after a run, or held RESTART_HOLD seconds during one, it starts a new run.
local RESTART_KEY, RESTART_HOLD = "R", 0.75
local PAUSE_KEY = "Q"
overlay.GAME_KEYS = { pause = PAUSE_KEY, restart = RESTART_KEY }
-- Seconds a finished auto mode run stays on screen.
local AUTO_RESTART = 3

function overlay:SaveBest()
    if self.state.piloted then
        return
    end
    local score = sim.Score(self.state)
    if score > app.db.global.bestScore then
        app.db.global.bestScore = score
        self.state.newBest = true
    end
end

-- `lobby`: a run from the lobby (screens.lua); `seed`: kept instead of the profile's.
function overlay:NewState(lobby, seed)
    local zones = app.db.profile.biome == app.biomes.AUTO
    return sim.New(seed or app.db.profile.seed or nil, app.db.profile.difficulty, zones, lobby)
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
    local status, coins, streak = s.status, s.coins, s.streak
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
    if s.coins > coins and app.db.profile.coinSound then
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
    local chord = (IsAltKeyDown() and "ALT-" or "")
        .. (IsControlKeyDown() and "CTRL-" or "")
        .. (IsShiftKeyDown() and "SHIFT-" or "")
        .. key
    local binding = GetBindingAction(chord, true)
    if self:OnScreenKey(key, binding) then
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
