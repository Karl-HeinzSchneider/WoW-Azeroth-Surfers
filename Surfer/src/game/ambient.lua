---@type string, Surfer
local _, app = ...
local shapes = app.shapes
local random = app.random
-- Wildlife: the biome's creatures that pass by now and then (biomes/default.lua describes them),
-- added to the view that overlay.lua creates. They are only for the eye: never part of the
-- simulation, never in the runner's way, and they leave the track as it is. A crosser runs
-- across the road at a spot ahead where it is clear of every box and coin, and is off the road
-- before the runner gets there; a flyer crosses high above it, anywhere. Actors of the world
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

-- The track distance a crosser of `item` coming up at run distance `base` crosses at: the
-- nearest clear one ahead that it gets off the road from before the runner comes, at most
-- `far` yards ahead; nil when there is none.
local function crossing(s, base, from, speed, far)
    local difficulty = s.difficulty
    local run = math.min(difficulty.topSpeed, difficulty.startSpeed + base / difficulty.speedUp)
    local near = run * (from + ROAD) / speed * SAFETY + CLEAR
    for ahead = math.ceil(near), far do
        if clear(s, base + ahead) then
            return base + ahead
        end
    end
end

-- A creature of `item` coming up at run distance `base`, if it has a way: from `side` (1 right,
-- -1 left) across to the other.
local function spawn(self, r, item, base)
    local s, fade = self.state, self.biome.ground.fade
    local side = r() < 0.5 and 1 or -1
    local speed, from = value(r, item.speed, 10), value(r, item.from, 9)
    local flying = item.move == "fly"
    local at
    if flying then
        at = base + value(r, item.ahead, 50)
    else
        at = crossing(s, base, from, speed, fade.to - 4)
    end
    if not at then
        return
    end
    local model = -choose(r, item.creature)
    local actor = self:AcquireActor(model)
    local c = self.spareCritters[#self.spareCritters] or {}
    self.spareCritters[#self.spareCritters] = nil
    c.model, c.actor, c.item, c.at = model, actor, item, at
    -- Its way across, in yards to the screen's right of the road's middle.
    c.x, c.to, c.step = side * from, -side * from, -side * speed
    c.z = flying and value(r, item.z, 10) or 0
    -- The scene's y points left: running left (from the right) is +y, a quarter turn.
    c.yaw = side > 0 and math.pi / 2 or -math.pi / 2
    c.height, c.scale = item.height and value(r, item.height, 1), value(r, item.scale, 1)
    c.fitted, c.shiftX, c.shiftY, c.alpha, c.moving = false, 0, 0, false, nil
    c.distance = s.distance
    actor:SetAlpha(0)
    actor:SetUseCenterForOrigin(false, false, false)
    actor:SetPitch(0)
    actor:SetYaw(c.yaw)
    self.critters[#self.critters + 1] = c
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
        c.x = c.x + c.step * seconds
        local left = (c.to - c.x) * (c.step > 0 and 1 or -1)
        if ahead < cam.x - 4 or left <= 0 then
            release(self, i)
        elseif c.fitted or fit(self, c) then
            local moving = seconds > 0
            if moving ~= c.moving then
                c.moving = moving
                local item = c.item
                c.actor:SetAnimation(item.animation or 5, 0, moving and (item.rate or 1) or 0)
            end
            local scale = c.scale
            c.actor:SetPosition(ahead / scale + c.shiftX, -c.x / scale + c.shiftY, (ground(ahead) + c.z) / scale)
            -- It starts at minus its end.
            local gone = math.abs(c.x + c.to)
            local edge = math.min(1, gone / EDGE, left / EDGE)
            local alpha = edge * math.min(1, math.max(0, (fade.to - ahead) / (fade.to - fade.from)))
            if not c.alpha or math.abs(alpha - c.alpha) > 0.02 then
                c.actor:SetAlpha(alpha)
                c.alpha = alpha
            end
        end
    end
end
