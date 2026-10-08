---@type string, Surfer
local _, app = ...
local sim = app.simulation
local shapes = app.shapes
local random = app.random
-- Obstacles as 3D models: for each box of the track (obstacle, barrier, platform) the biome's
-- models, actors of the world scene like the decorations (biomes/default.lua describes them).
-- A kind without models in the biome stays a flat box; so does a ramp without ramp models.
local overlay = app.overlay
local cam = overlay.camera
local ground = shapes.Ground
local LANE, LAYER = sim.geometry.laneWidth, sim.LAYER
local value, choose, pick = overlay.Value, overlay.Choose, overlay.Pick
-- A creature switches to its item's `attack` animation, and plays its `sound` (one without an
-- attack only that), once the runner is this many yards away.
local ATTACK_RANGE = 7

-- Reused while picking a variant.
local fitting = {}

-- Picks a box's looks, seeded by the box (`o.seed`): it looks the same whenever and in whatever
-- order it comes into sight.
local looks = random.New(1, random.LOOK)

-- The biome's look for box `o`: one of its kind's variants for its height, picked once and kept
-- on the box; false when the biome has none, so it stays flat. A gate's boxes
-- (patterns/gate.lua) take the looks of the transition into the next zone (its `obstacles`).
function overlay:ObstacleLook(o)
    local look = o.surferLook
    if look == nil then
        look = false
        -- The zone's it stands in (auto), so the next zone's boxes come into sight.
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

-- One actor of a box: `along` yards along the track, its item's other values picked.
local function attach(self, o, item, along)
    -- A creature by its display id, kept as minus the id (AcquireActor).
    local model = item.creature and -choose(looks, item.creature) or choose(looks, item.model)
    local actor = self:AcquireActor(model)
    local sound = item.sound
    if item.creature then
        actor:SetAnimation(item.animation or 0, 0, 1, 0)
        if type(sound) == "table" then
            sound = sound[-model]
        end
    end
    -- Invisible until its model has loaded and been fitted; by its own origin, upright (a ramp's
    -- model may have been this actor before).
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
        -- Yards to the screen's right of the lane's middle, and up from the box's bottom (or
        -- the road, for `ground` items).
        x = value(looks, item.x, 0),
        z = (item.ground and 0 or o.layer * LAYER) + value(looks, item.z, 0),
        -- Its size, picked here like the rest (a range draws, a number does not): `fit` uses them.
        height = value(looks, item.height, nil),
        size = value(looks, item.scale, nil),
        alpha = false,
        attacking = false,
        sound = sound,
    }
end

-- A ramp's models, `across` of them side by side over its `width` (the platform's when left
-- out) and, with
-- `segment`, as many end to end up the slope as make each about that many yards long (one
-- otherwise): placed by their centers (each is turned up to the slope about it), scaled and
-- turned once loaded (`fit`).
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
                -- Which piece up the slope, of how many.
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

-- The box's actors: each item once at its `d` (the box's middle when left out), or, with
-- `every`, repeated along the box's flat part (past a ramp) about every that many yards; and
-- its ramp's models.
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
-- origin is `height` yards (the box's height when left out). A ramp's model spans its piece of
-- the slope: as long as it, turned up to its angle, its top on it (its center half its
-- thickness below), its middle at the piece's.
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
                            -- Heard only as the runner passes it, not when it comes into view
                            -- already behind (a new biome).
                            if entry.sound and s.status == "running" and d > 0 and app.db.profile.enemySound then
                                -- The SFX channel follows the game's sound effects volume.
                                PlaySound(entry.sound, "SFX")
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

-- Whether face `f` is drawn by models instead: every face of a box with a look, and its ramp's
-- when the look has ramp models.
function overlay:Modelled(f)
    local o = f.object
    if not self.worldScene or o.kind == "coin" then
        return false
    end
    local look = self:ObstacleLook(o)
    return look and (not f.ramp or look.ramp ~= nil) or false
end
