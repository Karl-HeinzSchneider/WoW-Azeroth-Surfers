---@type string, Surfer
local _, app = ...
local sim = app.simulation
local shapes = app.shapes
local random = app.random
-- The track's boxes as the biome's 3D models, actors of the world scene.
local overlay = app.overlay
local cam = overlay.camera
local ground = shapes.Ground
local LANE, LAYER = sim.geometry.laneWidth, sim.LAYER
local value, choose, pick = overlay.Value, overlay.Choose, overlay.Pick
-- Yards from the runner at which a creature attacks and plays its `sound`.
local ATTACK_RANGE = 7

local fitting = {}

-- Seeded by each box (`o.seed`): it looks the same in whatever order it comes into sight.
local looks = random.New(1, random.LOOK)

-- A variant for the box's kind and height, picked once; false when there is none (flat). A
-- gate's boxes take the transition's `obstacles`.
function overlay:ObstacleLook(o)
    local look = o.surferLook
    if look == nil then
        look = false
        local obstacles = o.gate and app.biomes.Transition(self:BiomeAt(o.rim + 1).entrance).obstacles
            or self:BiomeAt(o.at).obstacles
        local variants = obstacles and obstacles[o.kind]
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
                look = pick(looks:Seed(o.seed or 1, random.LOOK), fitting)
            end
        end
        o.surferLook = look
    end
    return look
end

local function attach(self, o, item, along)
    local model = item.creature and -choose(looks, item.creature) or choose(looks, item.model)
    local actor = self:AcquireActor(model)
    local sound = item.sound
    if item.creature then
        actor:SetAnimation(item.animation or 0, 0, 1, 0)
        -- A table by display id.
        if type(sound) == "table" and not sound[1] then
            sound = sound[-model]
        end
    end
    -- A file, not a sound kit: a kit does not play again while it still plays.
    sound = sound and choose(looks, sound)
    -- Invisible until fitted; upright (a ramp's model may have been this actor before).
    actor:SetAlpha(0)
    actor:SetUseCenterForOrigin(false, false, false)
    actor:SetPitch(0)
    local yaw = math.rad(value(looks, item.yaw, 0))
    actor:SetYaw(yaw)
    o.surferActors[#o.surferActors + 1] = {
        model = model,
        actor = actor,
        item = item,
        along = along,
        yaw = yaw,
        x = value(looks, item.x, 0),
        z = (item.ground and 0 or o.layer * LAYER) + value(looks, item.z, 0),
        -- Rolled here like the rest, for `fit`.
        height = value(looks, item.height, nil),
        size = value(looks, item.scale, nil),
        alpha = false,
        attacking = false,
        sound = sound,
    }
end

-- Placed by their centers (each is turned up to the slope about it), fitted once loaded.
local function attachRamp(self, o, item)
    local count = item.across or 1
    local width = item.width or 2 * sim.geometry.halfWidth.platform
    local slope = math.sqrt(o.ramp ^ 2 + (o.layers * LAYER) ^ 2)
    local pieces = item.segment and math.max(1, math.floor(slope / item.segment + 0.5)) or 1
    for piece = 1, pieces do
        for k = 1, count do
            local model = choose(looks, item.model)
            local actor = self:AcquireActor(model)
            actor:SetAlpha(0)
            actor:SetUseCenterForOrigin(true, true, true)
            actor:SetYaw(0)
            o.surferActors[#o.surferActors + 1] = {
                model = model,
                actor = actor,
                item = item,
                ramp = true,
                piece = piece,
                pieces = pieces,
                yaw = 0,
                x = (k - (count + 1) / 2) * width / count,
                size = value(looks, item.scale, nil),
                alpha = false,
            }
        end
    end
end

local function attachAll(self, o, look)
    o.surferActors = {}
    -- Past the look's own pick.
    looks:Seed(o.seed or 1, random.LOOK)
    looks()
    if o.ramp and look.ramp then
        for _, item in ipairs(look.ramp) do
            attachRamp(self, o, item)
        end
    end
    for _, item in ipairs(look.items) do
        if item.every then
            local from = o.at + (o.ramp or 0)
            local length = o.at + o.length - from
            local count = math.max(1, math.floor(length / item.every + 0.5))
            for k = 1, count do
                attach(self, o, item, from + length * (k - 0.5) / count)
            end
        else
            attach(self, o, item, o.at + value(looks, item.d, o.length / 2))
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

-- Once loaded: to `scale`, or its top `height` yards above its origin. A ramp's model spans its
-- piece of the slope, its top on it.
local function fit(self, o, entry)
    local bounds = self:ModelBounds(entry.actor, entry.model)
    if not bounds then
        return false
    end
    local item = entry.item
    if entry.ramp then
        local rise = o.layers * LAYER
        local angle = math.atan2(rise, o.ramp)
        local length = math.sqrt(o.ramp ^ 2 + rise ^ 2) / entry.pieces
        entry.scale = entry.size or length / math.max(bounds[4] - bounds[1], 0.01)
        local thickness = (bounds[6] - bounds[3]) * entry.scale
        local middle = (entry.piece - 0.5) / entry.pieces
        entry.along = o.at + o.ramp * middle + thickness / 2 * math.sin(angle)
        entry.z = o.layer * LAYER + rise * middle - thickness / 2 * math.cos(angle)
        entry.actor:SetScale(entry.scale)
        -- Its far end up.
        entry.actor:SetPitch(-angle)
        entry.shiftX, entry.shiftY = 0, 0
        return true
    end
    entry.scale = entry.size or (entry.height or o.layers * LAYER) / math.max(bounds[6], 0.01)
    entry.actor:SetScale(entry.scale)
    entry.shiftX, entry.shiftY = self.TurnShift(bounds, entry.yaw)
    return true
end

-- Once a frame: models for every box in view; boxes gone from view give theirs back.
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
                            (d + self.sceneRunner) / scale + entry.shiftX,
                            (lane - entry.x) / scale + entry.shiftY,
                            (entry.z + ground(d)) / scale
                        )
                        local alpha = self:FadeAlpha(d)
                        if not entry.alpha or math.abs(alpha - entry.alpha) > 0.02 then
                            entry.actor:SetAlpha(alpha)
                            entry.alpha = alpha
                        end
                        local attack = entry.item.attack
                        if (attack or entry.sound) and not entry.attacking and d < ATTACK_RANGE then
                            if attack then
                                entry.actor:SetAnimation(attack, 0, 1, 0)
                            end
                            entry.attacking = true
                            -- Not when it comes into view already behind (a new biome).
                            if entry.sound and s.status == "running" and d > 0 and app.db.profile.enemySound then
                                PlaySoundFile(entry.sound, "SFX")
                            end
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

-- Whether face `f` is drawn by models instead.
function overlay:Modelled(f)
    local o = f.object
    if not self.worldScene or o.kind == "coin" then
        return false
    end
    local look = self:ObstacleLook(o)
    return look and (not f.ramp or look.ramp ~= nil) or false
end
