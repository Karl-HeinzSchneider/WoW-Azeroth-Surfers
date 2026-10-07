---@type string, Surfer
local _, app = ...
local shapes = app.shapes
local random = app.random
local light = app.light
-- Decorations: the biome's 3D models along both sides of the road (biomes/default.lua describes
-- them), added to the view that overlay.lua creates. All of them are actors in one ModelScene
-- covering the screen, with the road's camera, so they cost one render pass however many there
-- are, and the scene's depth buffer sorts them.
local overlay = app.overlay
local cam = overlay.camera
local ground = shapes.Ground
local unchanged = overlay.Unchanged

-- A value from a biome: a number, or a { min, max } range picked with generator `r`
-- (random.lua).
local function value(r, v, default)
    if v == nil then
        return default
    end
    if type(v) == "table" then
        return v[1] + r() * (v[2] - v[1])
    end
    return v
end

-- A model from a biome: a file id, or a list of them picked with `r`.
local function choose(r, v)
    if type(v) == "table" then
        return v[r(#v)]
    end
    return v
end

-- A group by weight, picked with `r`.
local function pick(r, groups)
    local total = 0
    for _, group in ipairs(groups) do
        total = total + (group.weight or 1)
    end
    local roll = r() * total
    for _, group in ipairs(groups) do
        roll = roll - (group.weight or 1)
        if roll <= 0 then
            return group
        end
    end
    return groups[#groups]
end
-- Shared with obstacles.lua.
overlay.Value, overlay.Choose, overlay.Pick = value, choose, pick

function overlay:CreateDecorations(f)
    local scene = CreateFrame("ModelScene", nil, f)
    scene:EnableMouse(false)
    self:Stack(scene, "world")
    scene:SetAllPoints(f)
    scene:SetCameraNearClip(overlay.CLIP_NEAR)
    scene:SetCameraFarClip(overlay.CLIP_FAR)
    self.worldScene = scene
    -- Placed decorations, and spare ones: their tables and, by model, their actors.
    self.decor, self.spareDecor, self.spareActors = {}, {}, {}
    self.decorNext, self.decorLens, self.modelBounds = {}, {}, {}
    -- Each side draws from its own stream of the run's seed, in order along the road, so the
    -- same seed decorates the same whatever the frame rate.
    self.decorRandom = { [-1] = random.New(1, random.LEFT), [1] = random.New(1, random.RIGHT) }
end

-- An actor of the world scene showing `model`: a spare one that showed it before, or a new one.
-- `model` is a file id, or minus a creature display id (a creature with its skin). Placed by
-- the model's own origin, the point it stands on in the world. Not its bounds' center: an
-- animated model's bounds change as it moves, so it would drift.
function overlay:AcquireActor(model)
    local spare = self.spareActors[model]
    if not spare then
        spare = {}
        self.spareActors[model] = spare
    end
    local actor = spare[#spare]
    if actor then
        spare[#spare] = nil
    else
        actor = self.worldScene:CreateActor()
        actor:SetUseCenterForOrigin(false, false, false)
        if model < 0 then
            actor:SetModelByCreatureDisplayID(-model)
        else
            actor:SetModelByFileID(model)
        end
    end
    actor:Show()
    return actor
end

function overlay:ReleaseActor(model, actor)
    actor:Hide()
    local spare = self.spareActors[model]
    spare[#spare + 1] = actor
end

-- A model's bounds once it has loaded, { minX, minY, minZ, maxX, maxY, maxZ } around its
-- origin, measured once per model; nothing before.
function overlay:ModelBounds(actor, model)
    local bounds = self.modelBounds[model]
    if not bounds then
        local minX, minY, minZ, maxX, maxY, maxZ = self.Extents(actor)
        if not minX then
            return nil
        end
        bounds = { minX, minY, minZ, maxX, maxY, maxZ }
        self.modelBounds[model] = bounds
    end
    return bounds
end

-- The client turns a model about its bounds' center, not its origin: the offset that makes it
-- turn about its origin, (turn - 1) * center, in the actor's own units (its position is scaled
-- with it).
function overlay.TurnShift(bounds, yaw)
    local sin, cos = math.sin(yaw), math.cos(yaw)
    local cx, cy = (bounds[1] + bounds[4]) / 2, (bounds[2] + bounds[5]) / 2
    return cx * (cos - 1) - cy * sin, cx * sin + cy * (cos - 1)
end

-- How the scene spreads its field of view is not documented (over its height, its width, or
-- what is left of it on the screen) and it projects in its own units, so its lens is
-- calibrated against the road's: a road point is projected both ways and their distances from
-- the view's middle compared. Every distance scales with 1 / tan(fov / 2), so with
-- tan(fov / 2) = span / 2 / focal, a ratio r off corrects `span` by r. Nothing when the scene
-- cannot project yet.
local function measure(self, scene, pitch)
    local c, s = math.cos(pitch), math.sin(pitch)
    local mx, my = scene:Project3DPointTo2D(cam.x + 10 * c, cam.offset, cam.z - 10 * s)
    local px, py = scene:Project3DPointTo2D(20, -4.3, ground(20))
    local rx, ry = self:Project(20, 4.3, ground(20))
    if type(mx) ~= "number" or type(px) ~= "number" or not rx then
        return nil
    end
    -- The scene's units are UI units times its effective scale.
    local road = math.sqrt((rx - cam.cx) ^ 2 + (ry - cam.cy) ^ 2)
    local seen = math.sqrt((px - mx) ^ 2 + (py - my) ^ 2) / scene:GetEffectiveScale()
    if road < 1 or seen <= 0 then
        return nil
    end
    -- Its middle, in its own units, for /surfer debug.
    self.decorMiddleX, self.decorMiddleY = mx, my
    return seen / road
end

-- The scene covers the screen and shows what the road's camera sees: its camera, and its lens,
-- calibrated once for this screen size and UI scale (in a few rounds, should it not be a plain
-- pinhole).
function overlay:AimDecorations()
    local scene, w, h = self.worldScene, self.frame:GetSize()
    local pitch = math.rad(app.db.profile.overlay.pitch)
    -- The scene's y points left: the road's lane offset moves its camera.
    scene:SetCameraPosition(cam.x, cam.offset, cam.z)
    scene:SetCameraOrientationByYawPitchRoll(0, pitch, 0)
    local last = self.decorLens
    local same = unchanged(last, "w", w)
    same = unchanged(last, "h", h) and same
    same = unchanged(last, "scale", scene:GetEffectiveScale()) and same
    if not same then
        last.span, last.calibrated = h, false
    end
    scene:SetCameraFieldOfView(2 * math.atan(last.span / 2 / cam.f))
    for _ = 1, 4 do
        if last.calibrated then
            return
        end
        local ratio = measure(self, scene, pitch)
        if not ratio then
            return
        end
        last.ratio = ratio
        if math.abs(ratio - 1) < 0.001 then
            last.calibrated = true
            return
        end
        last.span = last.span * ratio
        scene:SetCameraFieldOfView(2 * math.atan(last.span / 2 / cam.f))
    end
end

local function release(self, i)
    local list, d = self.decor, self.decor[i]
    self:ReleaseActor(d.model, d.actor)
    d.actor = nil
    self.spareDecor[#self.spareDecor + 1] = d
    list[i] = list[#list]
    list[#list] = nil
end

-- Clears the road's decorations, for a new run or biome; the next frame places new ones.
function overlay:ResetDecorations()
    for i = #self.decor, 1, -1 do
        release(self, i)
    end
    self.decorState = nil
end

-- One decoration of a group starting `at` yards along the run, on `side` (1 right, -1 left).
-- The left side's group is the right side's turned round about its middle: each model turned
-- round, and its place along the group reversed, so parts that join up on the right still do.
local function place(self, r, length, item, at, side)
    local model = choose(r, item.model)
    local actor = self:AcquireActor(model)
    local d = self.spareDecor[#self.spareDecor] or {}
    self.spareDecor[#self.spareDecor] = nil
    local along = value(r, item.d, 0)
    if side < 0 then
        along = length - along
    end
    d.model, d.actor, d.at, d.alpha = model, actor, at + along, nil
    d.side, d.x, d.overhang, d.fitted = side, value(r, item.x, 6), item.overhang, false
    d.shiftX, d.shiftY = 0, 0
    d.y = -side * d.x
    -- Built for the right side; the left side's are turned round to face the road too.
    d.yaw, d.scale = math.rad(value(r, item.yaw, 0)) + (side < 0 and math.pi or 0), value(r, item.scale, 1)
    actor:SetYaw(d.yaw)
    actor:SetScale(d.scale)
    self.decor[#self.decor + 1] = d
end

-- Moves a decoration out until none of it reaches closer to the road's middle than `clear`,
-- once its model has loaded: how far its bounds, turned, reach toward the road. Models are
-- measured once. Not for `overhang` items, which are meant to reach over the road.
function overlay:FitDecoration(d, clear)
    local bounds = self:ModelBounds(d.actor, d.model)
    if not bounds then
        return
    end
    d.fitted = true
    d.shiftX, d.shiftY = self.TurnShift(bounds, d.yaw)
    if d.overhang then
        return
    end
    -- The scene's y (left) of the turned bounds' corners: x sin + y cos.
    local sin, cos = math.sin(d.yaw), math.cos(d.yaw)
    local low, high = math.huge, -math.huge
    for i = 1, 4, 3 do
        for j = 2, 5, 3 do
            local y = bounds[i] * sin + bounds[j] * cos
            low, high = math.min(low, y), math.max(high, y)
        end
    end
    -- Toward the road is left (+y) on the right side, right (-y) on the left side.
    local reach = (d.side > 0 and high or -low) * d.scale
    d.x = math.max(d.x, clear + reach)
    d.y = -d.side * d.x
end

-- Once a frame: places new groups up to the far end of the ground, moves every decoration with
-- the run, fades it in far ahead and drops it once behind the camera.
function overlay:UpdateDecorations()
    local s, look = self.state, self.biome.decorations
    local fade = self.biome.ground.fade
    if not self.decorLens.calibrated then
        self:AimDecorations()
    end
    if self.decorState ~= s then
        self:ResetDecorations()
        self.decorState = s
        -- From behind the camera, each side starting at its own place.
        for side = -1, 1, 2 do
            local r = self.decorRandom[side]:Seed(s.seed, side < 0 and random.LEFT or random.RIGHT)
            self.decorNext[side] = s.distance - 15 + r() * value(r, look.spacing, 0)
        end
    end
    local groups = look.groups
    if #groups > 0 then
        for side = -1, 1, 2 do
            local r = self.decorRandom[side]
            while self.decorNext[side] < s.distance + fade.to do
                local group, at = pick(r, groups), self.decorNext[side]
                local length = value(r, group.length, 0)
                for _, item in ipairs(group.items) do
                    if not item.chance or r() < item.chance then
                        place(self, r, length, item, at, side)
                    end
                end
                self.decorNext[side] = at + length + value(r, look.spacing, 0)
            end
        end
    end
    local list = self.decor
    for i = #list, 1, -1 do
        local d = list[i]
        local ahead = d.at - s.distance
        if ahead < cam.x - 4 then
            release(self, i)
        else
            if not d.fitted then
                self:FitDecoration(d, look.clear)
            end
            -- An actor's position is scaled with it: divided out, so every size stands in place.
            local scale = d.scale
            d.actor:SetPosition(ahead / scale + d.shiftX, d.y / scale + d.shiftY, ground(ahead) / scale)
            local alpha = math.min(1, math.max(0, (fade.to - ahead) / (fade.to - fade.from)))
            if not d.alpha or math.abs(alpha - d.alpha) > 0.02 then
                d.actor:SetAlpha(alpha)
                d.alpha = alpha
            end
        end
    end
end

-- The biome's decorations and their light; called by ApplyBiome.
function overlay:ApplyDecorations(biome)
    local look = biome.decorations
    light.AddScene(self.worldScene, look.ambient, look.diffuse)
    self:ResetDecorations()
end
