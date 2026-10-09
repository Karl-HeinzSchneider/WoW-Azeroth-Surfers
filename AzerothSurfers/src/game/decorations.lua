---@type string, AzerothSurfers
local _, app = ...
local shapes = app.shapes
local random = app.random
local light = app.light
-- The biome's roadside models: actors of one full-screen ModelScene with the road's camera, so
-- they cost one render pass however many there are.
local overlay = app.overlay
local cam = overlay.camera
local ground = shapes.Ground
local unchanged = overlay.Unchanged

-- A number, or a { min, max } range rolled with `r`.
local function value(r, v, default)
    if v == nil then
        return default
    end
    if type(v) == "table" then
        return v[1] + r() * (v[2] - v[1])
    end
    return v
end

local function choose(r, v)
    if type(v) == "table" then
        return v[r(#v)]
    end
    return v
end

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
    self.sceneRunner, self.sceneCamera = 0, {}
    -- Placed decorations, spare tables and spare actors by model.
    self.decor, self.spareDecor, self.spareActors = {}, {}, {}
    self.decorNext, self.decorLens, self.modelBounds = {}, {}, {}
    -- Each side draws from its own stream in road order: a seed decorates the same at any frame rate.
    self.decorRandom = { [-1] = random.New(1, random.LEFT), [1] = random.New(1, random.RIGHT) }
    self.gateRandom, self.gatesPlaced = random.New(1, random.LOOK), 0
end

-- `model`: a file id, or minus a creature display id. Placed by its origin, never its bounds'
-- center: an animated model's bounds change as it moves, so it would drift.
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

-- { minX, minY, minZ, maxX, maxY, maxZ } around the origin, once per model; nil until loaded.
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

-- The client turns a model about its bounds' center: the offset that turns it about its origin
-- instead, in the actor's own units.
function overlay.TurnShift(bounds, yaw)
    local sin, cos = math.sin(yaw), math.cos(yaw)
    local cx, cy = (bounds[1] + bounds[4]) / 2, (bounds[2] + bounds[5]) / 2
    return cx * (cos - 1) - cy * sin, cx * sin + cy * (cos - 1)
end

-- How the scene spreads its field of view is undocumented, so its lens is calibrated against the
-- road's: a road point is projected both ways and the distances from the middle compared; a
-- ratio r off corrects `span` by r. Nothing while the scene cannot project yet.
local function measure(self, scene, pitch)
    local c, s = math.cos(pitch), math.sin(pitch)
    local runner = self.sceneRunner
    local mx, my = scene:Project3DPointTo2D(runner + cam.x + 10 * c, cam.offset, cam.z - 10 * s)
    local px, py = scene:Project3DPointTo2D(runner + 20, -4.3, ground(20))
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
    -- Its middle, in its own units, for /surfers debug.
    self.decorMiddleX, self.decorMiddleY = mx, my
    return seen / road
end

-- Track distance repeats along the scene's x every REBASE yards, so its numbers stay small.
local REBASE = 16384

-- The scene stands still along the track and its camera runs along: moving the models instead
-- would trail their particles (a brazier's flames). Once a frame, before the models are placed.
function overlay:FollowWorldCamera(force)
    self.sceneRunner = self.state.distance % REBASE
    -- The scene's y points left: the road's lane offset moves its camera.
    local x, last = self.sceneRunner + cam.x, self.sceneCamera
    local same = unchanged(last, "x", x)
    same = unchanged(last, "y", cam.offset) and same
    same = unchanged(last, "z", cam.z) and same
    if force or not same then
        self.worldScene:SetCameraPosition(x, cam.offset, cam.z)
    end
end

-- The road's camera, and the lens calibrated once for this screen size and UI scale (in a few
-- rounds, should it not be a plain pinhole). The lens does not change with the camera's pitch
-- or field of view, so a screen's shot keeps it.
function overlay:AimDecorations()
    local scene, w, h = self.worldScene, self.frame:GetSize()
    local pitch = cam.pitch
    self:FollowWorldCamera(true)
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

-- The seed of the lobby's looks (its models' ranges), the same for every run.
local LOBBY_LOOK = 1
-- Yards of roadside left bare where a biome has no decorations.
local EMPTY = 10

function overlay:ResetDecorations()
    for i = #self.decor, 1, -1 do
        release(self, i)
    end
    self.decorState = nil
end

-- `side`: 1 right, -1 left; the left one's group is turned round about its middle.
local function place(self, r, length, item, at, side, clear)
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
    d.shiftX, d.shiftY, d.lift, d.raise, d.clear = 0, 0, item.lift, 0, clear
    d.z = value(r, item.z, 0)
    d.height = value(r, item.height, nil)
    d.y = -side * d.x
    d.yaw, d.scale = math.rad(value(r, item.yaw, 0)) + (side < 0 and math.pi or 0), value(r, item.scale, 1)
    actor:SetYaw(d.yaw)
    actor:SetScale(d.scale)
    self.decor[#self.decor + 1] = d
end

-- One of a transition's or the lobby's `items`, counted from `at`: not mirrored, never pushed
-- out.
local function placeFixed(self, r, item, at)
    local model = choose(r, item.model)
    local actor = self:AcquireActor(model)
    local d = self.spareDecor[#self.spareDecor] or {}
    self.spareDecor[#self.spareDecor] = nil
    d.model, d.actor, d.at, d.alpha = model, actor, at + value(r, item.d, 0), nil
    d.side, d.x, d.overhang, d.fitted = 1, value(r, item.x, 0), true, false
    d.shiftX, d.shiftY, d.lift, d.raise, d.clear = 0, 0, item.lift, 0, 0
    d.z = value(r, item.z, 0)
    d.y = -d.x
    d.yaw, d.scale = math.rad(value(r, item.yaw, 0)), value(r, item.scale, 1)
    -- Or scaled so its top is that many yards up, once its model has loaded (FitDecoration).
    d.height = value(r, item.height, nil)
    actor:SetYaw(d.yaw)
    actor:SetScale(d.scale)
    self.decor[#self.decor + 1] = d
end

-- Once its model has loaded: scales it to `height`, lifts it, and moves it out until its turned
-- bounds no longer reach in past `clear`.
function overlay:FitDecoration(d, clear)
    local bounds = self:ModelBounds(d.actor, d.model)
    if not bounds then
        return
    end
    d.fitted = true
    if d.height then
        d.scale = d.height / math.max(bounds[6], 0.01)
        d.actor:SetScale(d.scale)
    end
    -- In its own units.
    if d.lift then
        d.raise = math.max(0, -bounds[3])
    end
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

-- Once a frame: places new groups up to the far fade, fades them in and drops those behind.
function overlay:UpdateDecorations()
    local s, look = self.state, self.biome.decorations
    local fade = self.biome.ground.fade
    if not self.decorLens.calibrated then
        self:AimDecorations()
    end
    if self.decorState ~= s then
        self:ResetDecorations()
        self.decorState, self.gatesPlaced = s, 0
        -- From behind the camera, each side starting at its own place; past the lobby's gate in
        -- a run from the lobby, whose own models stand before it.
        for side = -1, 1, 2 do
            local r = self.decorRandom[side]:Seed(s.seed, side < 0 and random.LEFT or random.RIGHT)
            self.decorNext[side] = (s.lobby and s.lobby.rim or s.distance - 15) + r() * value(r, look.spacing, 0)
        end
        if s.lobby then
            -- The same camp whatever the run's seed: a new one in the menu changes nothing in view.
            local r = self.gateRandom:Seed(LOBBY_LOOK, random.LOOK)
            for _, item in ipairs(s.lobby.items) do
                placeFixed(self, r, item, 0)
            end
        end
    end
    for side = -1, 1, 2 do
        local r = self.decorRandom[side]
        while self.decorNext[side] < s.distance + fade.to do
            local at = self.decorNext[side]
            local here = self:BiomeAt(at).decorations
            local strip = self:StripEnd(at)
            if strip then
                self.decorNext[side] = strip
            elseif #here.groups == 0 then
                self.decorNext[side] = at + EMPTY
            else
                local group = pick(r, here.groups)
                local length = value(r, group.length, 0)
                -- None in a gate's strip; the roadside starts again past it.
                local into = self:StripEnd(at, at + length)
                if into then
                    self.decorNext[side] = into
                else
                    for _, item in ipairs(group.items) do
                        if not item.chance or r() < item.chance then
                            place(self, r, length, item, at, side, here.clear)
                        end
                    end
                    self.decorNext[side] = at + length + value(r, here.spacing, 0)
                end
            end
        end
    end
    -- Each gate's transition, once it comes into sight.
    local gates = s.gates
    while gates and self.gatesPlaced < #gates and gates[self.gatesPlaced + 1] < s.distance + fade.to do
        local k = self.gatesPlaced + 1
        self.gatesPlaced = k
        -- The lobby's portal as always (its camp's); every other one by the run's seed.
        local r = self.gateRandom:Seed((s.lobby and k == 1) and LOBBY_LOOK or s.seed + k, random.LOOK)
        local transition = app.biomes.Transition(self:BiomeAt(gates[k] + 1).entrance)
        for _, item in ipairs(transition.items) do
            placeFixed(self, r, item, gates[k])
        end
    end
    local list = self.decor
    -- Before a run, a screen's camera may look from far ahead: nothing is dropped.
    local behind = s.status == "ready" and -math.huge or cam.x - 4
    for i = #list, 1, -1 do
        local d = list[i]
        local ahead = d.at - s.distance
        if ahead < behind then
            release(self, i)
        else
            if not d.fitted then
                self:FitDecoration(d, d.clear)
            end
            -- An actor's position is scaled with it: divided out, so every size stands in place.
            local scale = d.scale
            d.actor:SetPosition(
                (ahead + self.sceneRunner) / scale + d.shiftX,
                d.y / scale + d.shiftY,
                (ground(ahead) + d.z) / scale + d.raise
            )
            local alpha = self:FadeAlpha(ahead)
            if not d.alpha or math.abs(alpha - d.alpha) > 0.02 then
                d.actor:SetAlpha(alpha)
                d.alpha = alpha
            end
        end
    end
end

-- Placed anew, unless `entering` a zone, where they already stand.
function overlay:ApplyDecorations(biome, entering)
    local look = biome.decorations
    light.AddScene(self.worldScene, look.ambient, look.diffuse)
    if not entering then
        self:ResetDecorations()
    end
end
