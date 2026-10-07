---@type string, Surfer
local _, app = ...
local shapes = app.shapes
local random = app.random
-- Wildlife: the biome's creatures that pass by now and then (biomes/default.lua describes them),
-- added to the view that overlay.lua creates. They are only for the eye: never part of the
-- simulation, never in the runner's way, and they leave the track as it is. A crosser runs
-- across the road at a spot ahead where it is clear of every box and coin, and is off the road
-- before the runner gets there; a flyer crosses high above it, anywhere. They may come in
-- groups: one after another, on lines side by side, some the other way. Actors of the world
-- scene like the decorations, moving in the run's time (still while it is paused). Which
-- creatures come and where follows from the run's seed (their own stream of it).
local overlay = app.overlay
local cam = overlay.camera
local ground = shapes.Ground
local value, choose, pick = overlay.Value, overlay.Choose, overlay.Pick

-- Yards off the road's middle a crosser must be past before the runner comes: the road's edge
-- (4.3) and room for its body.
local ROAD = 5
-- Yards of road along the track a crosser needs clear of boxes and coins, to either side of
-- its path.
local CLEAR = 2
-- How much sooner than the run's speed of the moment says the runner may come: the run speeds
-- up meanwhile.
local SAFETY = 1.25
-- Yards between the lines of two of a group crossing each other the other way.
local PASS = 1.5
-- Yards a creature fades in and out over at the ends of its way.
local EDGE = 1.5

function overlay:CreateAmbient()
    -- The creatures under way, and spare tables for them.
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

-- Clears the creatures, for a new run or biome; the next frame starts anew.
function overlay:ResetAmbient()
    for i = #self.critters, 1, -1 do
        release(self, i)
    end
    self.ambientState = nil
end

-- Whether the road is clear of boxes and coins CLEAR yards to either side of track distance
-- `at`, in every lane.
local function clear(s, at)
    for _, o in ipairs(s.objects) do
        if o.at - CLEAR < at and o.at + o.length + CLEAR > at then
            return false
        end
    end
    return true
end

-- A group's members as planned before they are placed (reused): each one's side (1 right, -1
-- left), its line, yards along the road from the first one's, and the seconds it starts after
-- the first.
local members = {}

-- Whether every member's line is clear, crossing at track distance `at`.
local function clearFor(s, at, count)
    for k = 1, count do
        if not clear(s, at + members[k].offset) then
            return false
        end
    end
    return true
end

-- The track distance a group of crossers coming up at run distance `base` crosses at (the first
-- one's line): the nearest one ahead where every member's line is clear and the last of them is
-- off the road before the runner comes, at most `far` yards ahead; nil when there is none.
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

-- Plans a group of `item`'s creatures: its count, and each member's side, line and start. The
-- first comes from `side`; each other one starts `gap` yards of its way after the one before,
-- `offset` yards to either side of the first one's line, and crosses the other way by chance
-- `opposite`.
local function plan(r, item, side, speed)
    local group = item.group
    -- A whole number, each of a range's as likely.
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

-- A creature crossing at track distance `at`, from `side` across to the other, after `delay`
-- seconds of the run.
local function place(self, r, item, at, side, delay, speed, from)
    local model = -choose(r, item.creature)
    local actor = self:AcquireActor(model)
    local c = self.spareCritters[#self.spareCritters] or {}
    self.spareCritters[#self.spareCritters] = nil
    c.model, c.actor, c.item, c.at, c.delay = model, actor, item, at, delay
    -- Its way across, in yards to the screen's right of the road's middle.
    c.start, c.x, c.to, c.step = side * from, side * from, -side * from, -side * speed
    c.z = item.move == "fly" and value(r, item.z, 10) or 0
    -- The scene's y points left: running left (from the right) is +y, a quarter turn.
    c.yaw = side > 0 and math.pi / 2 or -math.pi / 2
    c.height, c.scale = item.height and value(r, item.height, 1), value(r, item.scale, 1)
    c.fitted, c.shiftX, c.shiftY, c.alpha, c.moving = false, 0, 0, false, nil
    c.distance = self.state.distance
    actor:SetAlpha(0)
    actor:SetUseCenterForOrigin(false, false, false)
    actor:SetPitch(0)
    actor:SetYaw(c.yaw)
    self.critters[#self.critters + 1] = c
end

-- `item`'s creatures coming up at run distance `base`, one or a group, if they have a way.
local function spawn(self, r, item, base)
    local s, fade = self.state, self.biome.ground.fade
    local speed, from = value(r, item.speed, 10), value(r, item.from, 9)
    local count = plan(r, item, r() < 0.5 and 1 or -1, speed)
    local at
    if item.move == "fly" then
        at = base + value(r, item.ahead, 50)
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

-- Scales a creature once its model has loaded: to `height` yards (its top above its origin),
-- or by `scale`; and turns it about its origin.
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

-- Once a frame: a new creature whenever the run has come far enough, every creature moved along
-- its way in the run's time, faded in far ahead and at the ends of its way, and dropped at its
-- end or once behind the camera.
function overlay:UpdateAmbient()
    local s, look = self.state, self.biome.ambient
    local r = self.ambientRandom
    if self.ambientState ~= s then
        self:ResetAmbient()
        self.ambientState = s
        r:Seed(s.seed, random.AMBIENT)
        self.ambientNext = s.distance + value(r, look.every, 100)
    end
    local creatures = look.creatures
    if #creatures > 0 then
        while self.ambientNext <= s.distance do
            local base = self.ambientNext
            spawn(self, r, pick(r, creatures), base)
            self.ambientNext = base + value(r, look.every, 100)
        end
    end
    local fade = self.biome.ground.fade
    local list = self.critters
    for i = #list, 1, -1 do
        local c = list[i]
        local ahead = c.at - s.distance
        -- Seconds of the run since the last frame: none while it stands still.
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
            local moving = seconds > 0
            if moving ~= c.moving then
                c.moving = moving
                local item = c.item
                c.actor:SetAnimation(item.animation or 5, 0, moving and (item.rate or 1) or 0)
            end
            local scale = c.scale
            c.actor:SetPosition(ahead / scale + c.shiftX, -c.x / scale + c.shiftY, (ground(ahead) + c.z) / scale)
            local gone = math.abs(c.x - c.start)
            local edge = math.min(1, gone / EDGE, left / EDGE)
            local alpha = edge * math.min(1, math.max(0, (fade.to - ahead) / (fade.to - fade.from)))
            if not c.alpha or math.abs(alpha - c.alpha) > 0.02 then
                c.actor:SetAlpha(alpha)
                c.alpha = alpha
            end
        end
    end
end
