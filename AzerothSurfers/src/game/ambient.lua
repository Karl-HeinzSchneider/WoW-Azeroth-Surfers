---@type string, AzerothSurfers
local _, app = ...
local shapes = app.shapes
local random = app.random
-- Wildlife (a biome's `ambient`): actors of the world scene, only for the eye, moving in the
-- run's time. Which come and where follows from the seed's random.AMBIENT stream.
local overlay = app.overlay
local cam = overlay.camera
local ground = shapes.Ground
local value, choose, pick = overlay.Value, overlay.Choose, overlay.Pick

-- Yards off the middle a crosser must be past before the runner comes: the road's edge and its body.
local ROAD = 5
-- Yards a crosser needs clear of boxes and coins to either side of its line.
local CLEAR = 2
-- The run speeds up meanwhile: the runner may come this much sooner.
local SAFETY = 1.25
-- Yards between the lines of two of a group crossing each other the other way.
local PASS = 1.5
-- An item's `pace` when it has none: a character's run.
local PACE = 7
-- About where a creature comes into sight: that zone's creatures come.
local SEEN = 60
-- Yards a creature fades in and out over at the ends of its way.
local EDGE = 1.5
local VOICE_RANGE = 12

function overlay:CreateAmbient()
    self.critters, self.spareCritters = {}, {}
    self.ambientRandom = random.New(1, random.AMBIENT)
end

local function release(self, i)
    local list, c = self.critters, self.critters[i]
    self:ReleaseActor(c.model, c.actor)
    c.actor = nil
    self.spareCritters[#self.spareCritters + 1] = c
    list[i] = list[#list]
    list[#list] = nil
end

function overlay:ResetAmbient()
    for i = #self.critters, 1, -1 do
        release(self, i)
    end
    self.ambientState = nil
end

-- In every lane.
local function clear(s, at)
    for _, o in ipairs(s.objects) do
        if o.at - CLEAR < at and o.at + o.length + CLEAR > at then
            return false
        end
    end
    return true
end

-- A group's planned members (reused): side, offset from the first one's line, and delay.
local members = {}

local function clearFor(s, at, count)
    for k = 1, count do
        if not clear(s, at + members[k].offset) then
            return false
        end
    end
    return true
end

-- The nearest track distance within `far` where every member's line is clear and the last one
-- is off the road before the runner comes; nil when there is none.
local function crossing(s, base, count, from, speed, far)
    local difficulty = s.difficulty
    local run = math.min(difficulty.topSpeed, difficulty.startSpeed + base / difficulty.speedUp)
    local near, reach = 0, 0
    for k = 1, count do
        local m = members[k]
        near = math.max(near, run * ((from + ROAD) / speed + m.delay) * SAFETY + CLEAR - m.offset)
        reach = math.max(reach, m.offset)
    end
    for ahead = math.ceil(near), far - reach do
        if clearFor(s, base + ahead, count) then
            return base + ahead
        end
    end
end

local function plan(r, item, side, speed)
    local group = item.group
    local count = group and group.count or 1
    if type(count) == "table" then
        count = r(count[1], count[2])
    end
    local delay = 0
    for k = 1, count do
        local m = members[k] or {}
        members[k] = m
        if k == 1 then
            m.side, m.offset, m.delay = side, 0, 0
        else
            delay = delay + value(r, group.gap, 2) / speed
            m.side = r() < (group.opposite or 0) and -side or side
            m.offset = value(r, group.offset, 0) * (r() < 0.5 and -1 or 1)
            -- One the other way passes the first, not through it.
            if m.side ~= side and math.abs(m.offset) < PASS then
                m.offset = m.offset < 0 and -PASS or PASS
            end
            m.delay = delay
        end
    end
    return count
end

local function place(self, r, item, at, side, delay, speed, from)
    local model = -choose(r, item.creature)
    local actor = self:AcquireActor(model)
    local c = self.spareCritters[#self.spareCritters] or {}
    self.spareCritters[#self.spareCritters] = nil
    c.model, c.actor, c.item, c.at, c.delay = model, actor, item, at, delay
    c.start, c.x, c.to, c.step, c.speed = side * from, side * from, -side * from, -side * speed, speed
    c.z = item.move == "fly" and value(r, item.z, 10) or 0
    -- The scene's y points left: running left (from the right) is +y, a quarter turn.
    c.yaw = side > 0 and math.pi / 2 or -math.pi / 2
    c.height, c.scale = item.height and value(r, item.height, 1), value(r, item.scale, 1)
    c.fitted, c.shiftX, c.shiftY, c.alpha, c.moving, c.px = false, 0, 0, false, nil, nil
    c.distance = self.state.distance
    -- Drawing only for creatures with a `voice`.
    c.voice = item.voice and r() < (item.talks or 1) and choose(r, item.voice) or false
    actor:SetAlpha(0)
    actor:SetUseCenterForOrigin(false, false, false)
    actor:SetPitch(0)
    actor:SetYaw(c.yaw)
    self.critters[#self.critters + 1] = c
end

local function spawn(self, r, item, base)
    local s, fade = self.state, self.biome.ground.fade
    local speed, from = value(r, item.speed, 10), value(r, item.from, 9)
    local count = plan(r, item, r() < 0.5 and 1 or -1, speed)
    local at
    if item.move == "fly" then
        -- Start in the background at the configured speed; a full crossing is optional.
        -- Use current distance so a late frame does not spawn flyers near the camera.
        at = s.distance + value(r, item.ahead, 90)
    else
        -- A group without a way stays behind one by one, from its last, until one has.
        while count > 0 and not at do
            at = crossing(s, base, count, from, speed, fade.to - 4)
            if not at then
                count = count - 1
            end
        end
    end
    if not at then
        return
    end
    for k = 1, count do
        local m = members[k]
        place(self, r, item, at + m.offset, m.side, m.delay, speed, from)
    end
end

local function fit(self, c)
    local bounds = self:ModelBounds(c.actor, c.model)
    if not bounds then
        return false
    end
    if c.height then
        c.scale = c.height / math.max(bounds[6], 0.01)
    end
    c.actor:SetScale(c.scale)
    c.shiftX, c.shiftY = self.TurnShift(bounds, c.yaw)
    c.fitted = true
    return true
end

-- Once a frame: new creatures as the run comes far enough; each moved, faded and dropped.
function overlay:UpdateAmbient()
    local s, look = self.state, self.biome.ambient
    local r = self.ambientRandom
    if self.ambientState ~= s then
        self:ResetAmbient()
        self.ambientState = s
        r:Seed(s.seed, random.AMBIENT)
        self.ambientNext = s.distance + value(r, look.every, 100)
    end
    while self.ambientNext <= s.distance do
        local base = self.ambientNext
        local here = self:BiomeAt(base + SEEN).ambient
        if #here.creatures > 0 then
            spawn(self, r, pick(r, here.creatures), base)
        end
        self.ambientNext = base + value(r, here.every, 100)
    end
    local list = self.critters
    for i = #list, 1, -1 do
        local c = list[i]
        local ahead = c.at - s.distance
        local seconds = (s.distance - c.distance) / math.max(s.speed, 1)
        c.distance = s.distance
        -- A group's later members wait their turn, out of sight.
        if c.delay > 0 then
            c.delay = c.delay - seconds
            seconds = math.max(0, -c.delay)
        end
        c.x = c.x + c.step * seconds
        local left = (c.to - c.x) * (c.step > 0 and 1 or -1)
        if ahead < cam.x - 4 or left <= 0 then
            release(self, i)
        elseif c.delay > 0 then
            if c.alpha ~= 0 then
                c.actor:SetAlpha(0)
                c.alpha = 0
            end
        elseif c.fitted or fit(self, c) then
            -- By status, not this frame's seconds: a fast frame may have no simulation step, and
            -- each SetAnimation starts it over.
            local moving = s.status == "running"
            if moving ~= c.moving then
                c.moving = moving
                local item = c.item
                local rate = c.speed / ((item.pace or PACE) * c.scale) * (item.rate or 1)
                c.actor:SetAnimation(item.animation or 5, 0, moving and rate or 0)
            end
            local scale = c.scale
            self:MoveActor(
                c,
                ahead,
                scale,
                (ahead + self.sceneRunner) / scale + c.shiftX,
                -c.x / scale + c.shiftY,
                (ground(ahead) + c.z) / scale
            )
            local gone = math.abs(c.x - c.start)
            local edge = math.min(1, gone / EDGE, left / EDGE)
            local alpha = edge * self:FadeAlpha(ahead)
            if not c.alpha or math.abs(alpha - c.alpha) > 0.02 then
                c.actor:SetAlpha(alpha)
                c.alpha = alpha
            end
            if c.voice and ahead < VOICE_RANGE and moving then
                if app.db.profile.enemySound then
                    PlaySoundFile(c.voice, "SFX")
                end
                c.voice = false
            end
        end
    end
end
