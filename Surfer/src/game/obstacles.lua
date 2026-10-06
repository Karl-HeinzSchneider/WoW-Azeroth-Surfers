---@type string, Surfer
local _, app = ...
local sim = app.simulation
local shapes = app.shapes
-- Obstacles as 3D models: for each box of the track (obstacle, barrier, platform) the biome's
-- models, actors of the world scene like the decorations (biomes/default.lua describes them).
-- A kind without models in the biome stays a flat box; so does a platform's ramp.
local overlay = app.overlay
local cam = overlay.camera
local ground = shapes.Ground
local LANE, LAYER = sim.geometry.laneWidth, sim.LAYER
local value, choose, pick = overlay.Value, overlay.Choose, overlay.Pick

-- Reused while picking a variant.
local fitting = {}

-- The biome's look for box `o`: one of its kind's variants for its height, picked once and kept
-- on the box; false when the biome has none, so it stays flat.
function overlay:ObstacleLook(o)
    local look = o.surferLook
    if look == nil then
        look = false
        local variants = self.biome.obstacles[o.kind]
        if variants then
            for i = #fitting, 1, -1 do
                fitting[i] = nil
            end
            for _, variant in ipairs(variants) do
                if not variant.layers or variant.layers == o.layers then
                    fitting[#fitting + 1] = variant
                end
            end
            if #fitting > 0 then
                look = pick(fitting)
            end
        end
        o.surferLook = look
    end
    return look
end

-- One actor of a box: `along` yards along the track, its item's other values picked.
local function attach(self, o, item, along)
    local model = choose(item.model)
    local actor = self:AcquireActor(model)
    -- Invisible until its model has loaded and been fitted.
    actor:SetAlpha(0)
    local yaw = math.rad(value(item.yaw, 0))
    actor:SetYaw(yaw)
    o.surferActors[#o.surferActors + 1] = {
        model = model,
        actor = actor,
        item = item,
        along = along,
        yaw = yaw,
        -- Yards to the screen's right of the lane's middle, and up from the box's bottom (or
        -- the road, for `ground` items).
        x = value(item.x, 0),
        z = (item.ground and 0 or o.layer * LAYER) + value(item.z, 0),
        alpha = false,
    }
end

-- The box's actors: each item once at its `d` (the box's middle when left out), or, with
-- `every`, repeated along the box's flat part (past a ramp) about every that many yards.
local function attachAll(self, o, look)
    o.surferActors = {}
    for _, item in ipairs(look.items) do
        if item.every then
            local from = o.at + (o.ramp or 0)
            local length = o.at + o.length - from
            local count = math.max(1, math.floor(length / item.every + 0.5))
            for k = 1, count do
                attach(self, o, item, from + length * (k - 0.5) / count)
            end
        else
            attach(self, o, item, o.at + value(item.d, o.length / 2))
        end
    end
    self.modelled[#self.modelled + 1] = o
end

local function release(self, o)
    for _, entry in ipairs(o.surferActors) do
        self:ReleaseActor(entry.model, entry.actor)
    end
    o.surferActors = nil
end

-- Drops every box's models and looks, for a new run or biome.
function overlay:ResetObstacles()
    local list = self.modelled
    for i = #list, 1, -1 do
        release(self, list[i])
        list[i] = nil
    end
    for _, o in ipairs(self.state.objects) do
        o.surferLook = nil
    end
    self.obstacleState = nil
end

-- Scales an entry's model once it has loaded: to its item's `scale`, or so its top above its
-- origin is `height` yards (the box's height when left out).
local function fit(self, o, entry)
    local bounds = self:ModelBounds(entry.actor, entry.model)
    if not bounds then
        return false
    end
    local item = entry.item
    entry.scale = item.scale or (item.height or o.layers * LAYER) / math.max(bounds[6], 0.01)
    entry.actor:SetScale(entry.scale)
    entry.shiftX, entry.shiftY = self.TurnShift(bounds, entry.yaw)
    return true
end

-- Once a frame: models for every box in view, moved with the run and faded in far ahead like the
-- ground; boxes gone from view give theirs back.
function overlay:UpdateObstacles()
    local s = self.state
    self.modelled = self.modelled or {}
    if self.obstacleState ~= s then
        self:ResetObstacles()
        self.obstacleState = s
    end
    local fade = self.biome.ground.fade
    local stamp = (self.obstacleStamp or 0) + 1
    self.obstacleStamp = stamp
    for _, o in ipairs(s.objects) do
        local near = o.at - s.distance
        if o.kind ~= "coin" and near + o.length > cam.x - 4 and near < fade.to then
            local look = self:ObstacleLook(o)
            if look then
                if not o.surferActors then
                    attachAll(self, o, look)
                end
                o.surferStamp = stamp
                -- The scene's y points left.
                local lane = o.lane * LANE
                for _, entry in ipairs(o.surferActors) do
                    if entry.scale or fit(self, o, entry) then
                        local d, scale = entry.along - s.distance, entry.scale
                        entry.actor:SetPosition(
                            d / scale + entry.shiftX,
                            (lane - entry.x) / scale + entry.shiftY,
                            (entry.z + ground(d)) / scale
                        )
                        local alpha = math.min(1, math.max(0, (fade.to - d) / (fade.to - fade.from)))
                        if not entry.alpha or math.abs(alpha - entry.alpha) > 0.02 then
                            entry.actor:SetAlpha(alpha)
                            entry.alpha = alpha
                        end
                    end
                end
            end
        end
    end
    local list = self.modelled
    for i = #list, 1, -1 do
        local o = list[i]
        if o.surferStamp ~= stamp then
            release(self, o)
            list[i] = list[#list]
            list[#list] = nil
        end
    end
end

-- Whether face `f` is drawn by models instead: every face of a box with a look, but its ramp.
function overlay:Modelled(f)
    return self.worldScene and not f.ramp and f.object.kind ~= "coin" and self:ObstacleLook(f.object) and true
end
