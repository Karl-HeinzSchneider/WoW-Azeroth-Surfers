---@type string, Surfer
local _, app = ...
local sim = app.simulation
-- The game's input, movement sampling, per-frame step and scoring, added to the view that
-- overlay.lua creates. Keys are only observed: WoW still gets them, so the real character
-- moves and jumps too.
local overlay = app.overlay

function overlay:SaveBest()
    app.db.global.bestScore = math.max(app.db.global.bestScore, sim.Score(self.state))
end

function overlay:Restart()
    self:SaveBest()
    self.state = sim.New()
    sim.Start(self.state)
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
    s.forward = self:IsMovingForward(elapsed)
    if s.forward and s.status == "ready" then
        sim.Start(s)
    end
    local status, coins = s.status, s.coins
    sim.Update(s, elapsed)
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

-- The next sample starts afresh, e.g. after the view was hidden.
function overlay:ForgetPosition()
    if self.lastPosition then
        self.lastPosition.valid = false
    end
end

local MESSAGES = { ready = "READY TO RUN?", paused = "PAUSED", over = "RUN COMPLETE" }

-- The score line and status message, rewritten only when they change, so a running game does
-- not build new strings every frame.
function overlay:ShowStatus()
    local s, shown = self.state, self.shown or {}
    self.shown = shown
    local score, best = sim.Score(s), app.db.global.bestScore
    local speed, layer = math.floor(s.speed + 0.5), math.floor(s.height / sim.LAYER + 0.01)
    if
        shown.score ~= score
        or shown.coins ~= s.coins
        or shown.best ~= best
        or shown.speed ~= speed
        or shown.layer ~= layer
    then
        shown.score, shown.coins, shown.best, shown.speed, shown.layer = score, s.coins, best, speed, layer
        self.score:SetText(
            string.format(
                "SCORE  %06d     COINS  %d     BEST  %06d     SPEED  %d     LAYER  %d",
                score,
                s.coins,
                best,
                speed,
                layer
            )
        )
    end
    if shown.status ~= s.status then
        shown.status = s.status
        self.message:SetText(MESSAGES[s.status] or "")
    end
end

function overlay:OnMovementKey(key)
    if InCombatLockdown() or GetCurrentKeyBoardFocus() then
        return
    end
    local chord = (IsAltKeyDown() and "ALT-" or "")
        .. (IsControlKeyDown() and "CTRL-" or "")
        .. (IsShiftKeyDown() and "SHIFT-" or "")
        .. key
    local binding = GetBindingAction(chord, true)
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
