---@type string, AzerothSurfers
local _, app = ...
local sim = app.simulation
local shapes = app.shapes
local light = app.light
local bounds = sim.geometry
local LANE = bounds.laneWidth
-- Where the ground's pieces start and end, from behind the runner to past the view's end. A
-- texture bends without perspective where a piece's two triangles meet, which shimmers as it
-- scrolls and grows with the piece's size on screen: pieces are half a yard deep near the camera,
-- up to 4 yards far ahead.
local function edges(scale)
    local list = { -7 }
    while list[#list] < sim.VIEW + 2 do
        local d = list[#list]
        list[#list + 1] = d + scale * (d < 6 and 0.5 or d < 20 and 1 or d < 44 and 2 or 4)
    end
    return list
end
-- For the same reason, nearer than COLUMN_NEAR yards wide bands are cut into lane-wide columns.
local COLUMN, COLUMN_NEAR = 2.4, 12
-- A band's pieces by its `segments`.
local SEGMENTS = { [1] = edges(1), [2] = edges(2), [4] = edges(4) }
local EDGES = SEGMENTS[1]
-- Levels relative to the configured base, shared by both display modes.
local ORDER = {
    world = 2,
    flash = 12,
    hud = 15,
    legend = 15,
    window = 20,
    controls = 21,
    screens = 23,
    messages = 24,
    menu = 25,
}
-- The 3D scenes share the depth buffer: with the same clip planes and camera, their depths
-- compare as in one scene (the world scene with the twin, and the occluder's, occluder.lua).
local CLIP_NEAR, CLIP_FAR = 0.2, 250
local COIN_SIZE = 0.5 -- a coin model's largest side
-- Flat boxes are cut this far ahead of the camera: a face with a corner nearer is not drawn.
local BOX_NEAR = 1
-- The twin's animations, and the speeds walking, running and backpedalling are animated for. A
-- normal jump (about 0.83 seconds) plays JUMP_START throughout; JUMP loops after AIR_LOOP.
local STAND, WALK, RUN, BACKWARDS, JUMP_START, JUMP, JUMP_END = 0, 4, 5, 13, 37, 38, 39
-- Ducking (simulation.Duck): the roll's loop.
local ROLL = 666
local WALK_SPEED, RUN_SPEED, BACKWARDS_SPEED = 2.5, 7, 4.5
local AIR_LOOP = 1.1
-- Jump-start choices by UnitRace's file token, then UnitSex (2 male, 3 female).
-- Each choice is { animation, variation }; missing races/sexes keep the standard jump.
local ALTERNATE_JUMPS = { { JUMP_START, 0 }, { JUMP_START, 1 } }
local JUMP_ANIMATIONS = {
    NightElf = { [2] = ALTERNATE_JUMPS, [3] = ALTERNATE_JUMPS },
    BloodElf = { [3] = ALTERNATE_JUMPS },
    VoidElf = { [3] = ALTERNATE_JUMPS },
    Worgen = { [2] = ALTERNATE_JUMPS, [3] = ALTERNATE_JUMPS },
    Vulpera = { [2] = ALTERNATE_JUMPS, [3] = ALTERNATE_JUMPS },
}
local jumpRandom = app.random.New(1, app.random.JUMPS)
-- Changing lanes, the twin turns this far toward the next lane (WoW's diagonal), for at least
-- STRAFE_HOLD seconds, STRAFE_TURN times quicker than otherwise.
local STRAFE_YAW, STRAFE_HOLD, STRAFE_TURN = math.pi / 4, 0.08, 3.5
-- The tallest a character is drawn in the track's world, as `Measure` measures it (hair and
-- all), so its head clears a bar to run under; fitted with a female troll (2.68 measured). A
-- taller one is drawn this tall with the road's camera nearer (`bodyScale`): it still covers
-- the real one, and the track is drawn bigger around it.
local REFERENCE_HEIGHT = 1.7
-- The twin's square on the screen (`twinAnchor`) spans this many character heights, room for
-- arms and turns.
local TWIN_FRAME = 1.6
-- How much bigger the twin is drawn than the real character: the size it had in a square scene
-- of its own, where a field of view spans the frame's diagonal, not its side as that code assumed
-- (`/surfers twinsize` measured it). Kept as the twin's look.
local TWIN_SIZE = math.sqrt(2)
-- The runner's own camera: a close shoulder view through a wide overview.
local ZOOM_MIN, ZOOM_MAX = 2, 24
local GROUND_OVERLAP = 32 -- UI pixels below the viewport, including while jumping

-- The view: the road, boxes and coins, and a twin (a copy of the character) running on it that
-- covers the real one. This file draws; controls.lua adds input, the per-frame step and scoring.
local overlay = {}
app.overlay = overlay
-- AzerothSurfers_Dev's /surfers reference changes it.
overlay.referenceHeight = REFERENCE_HEIGHT
overlay.CLIP_NEAR, overlay.CLIP_FAR = CLIP_NEAR, CLIP_FAR

local ground = shapes.Ground

-- WoW's follow camera orbits a focus point on the character and keeps it at the screen's
-- center; zoom, pitch and the focus height decide where the feet land below it.
local cam = {}
overlay.camera = cam
-- A camera shot: `at` yards ahead of the runner, `side` yards to the screen's right of the
-- road's middle, `height` yards up, `pitch` degrees down, `fov` the vertical field of view in
-- degrees. The run's follows the character; the screens have their own (screens.lua).
local runShot = {}
-- Stores `value` under `name`; true if it was already there.
local function unchanged(last, name, value)
    if last[name] == value then
        return true
    end
    last[name] = value
    return false
end
overlay.Unchanged = unchanged

function overlay:Zoom(delta)
    local settings = app.db.profile.overlay
    local distance = math.max(ZOOM_MIN, math.min(ZOOM_MAX, settings.distance))
    settings.distance = math.max(ZOOM_MIN, math.min(ZOOM_MAX, distance - delta))
end

-- The game's follow camera, independent of WoW's camera.
function overlay:RunShot(zoom)
    local settings = app.db.profile.overlay
    local pitch = math.rad(settings.pitch)
    -- Nearer for a tall character, so the track is drawn bigger around it (referenceHeight).
    local k = self.bodyScale
    runShot.at = -math.max(zoom, 0.5) * math.cos(pitch) / k
    -- The camera follows the character, so the world shifts by its lane offset and, while it
    -- jumps, drops away beneath it: the character keeps its place on screen.
    runShot.height = self.state.height + (settings.focus * self.height + math.max(zoom, 0.5) * math.sin(pitch)) / k
    runShot.side = -self.state.lateral * LANE
    runShot.pitch, runShot.fov = settings.pitch, settings.fov
    return runShot
end

function overlay:UpdateCamera()
    local settings = app.db.profile.overlay
    local w, h = self.frame:GetSize()
    local zoom = math.max(ZOOM_MIN, math.min(ZOOM_MAX, settings.distance))
    cam.distance = zoom
    -- A screen's shot, or the way to or from one.
    local shot = self:ViewShot(self:RunShot(zoom))
    cam.f = h / 2 / math.tan(math.rad(shot.fov) / 2)
    cam.pitch = math.rad(shot.pitch)
    cam.cos, cam.sin = math.cos(cam.pitch), math.sin(cam.pitch)
    cam.cx, cam.cy = w / 2, h / 2
    cam.x, cam.z, cam.offset = shot.at, shot.height, -shot.side
    cam.feet = self.state.height
    -- Intersect a ray just below the viewport with the flat ground behind the runner.
    -- Extend the first strip instead of moving the camera to hide the foreground edge.
    -- Recomputed for jumps, platforms, window sizes and camera settings alike.
    local slope = -(cam.cy + GROUND_OVERLAP) / cam.f
    local denominator = cam.sin - slope * cam.cos
    cam.groundNear = EDGES[1]
    if denominator > 0 then
        cam.groundNear = math.min(EDGES[1], cam.x + cam.z * (cam.cos + slope * cam.sin) / denominator)
    end
    -- Compared value by value, without building a key, so an unchanged frame allocates nothing.
    local last = self.lastRoad
    local same = unchanged(last, "x", cam.x)
    same = unchanged(last, "z", cam.z) and same
    same = unchanged(last, "offset", cam.offset) and same
    same = unchanged(last, "w", w) and same
    same = unchanged(last, "h", h) and same
    same = unchanged(last, "pitch", cam.pitch) and same
    same = unchanged(last, "f", cam.f) and same
    local curve = settings.fixedCurve and settings.curve or self:GroundCurve()
    if not unchanged(last, "curve", curve) then
        shapes.SetCurve(curve)
        same = false
    end
    return not same
end

-- Screen point of (distance ahead, screen-right world offset, height) and yards to pixels there.
local function project(d, x, z)
    local vd, vz = d - cam.x, z - cam.z
    local depth = vd * cam.cos - vz * cam.sin
    if depth < 0.2 then
        return nil
    end
    local scale = cam.f / depth
    return cam.cx + (x + cam.offset) * scale, cam.cy + (vd * cam.sin + vz * cam.cos) * scale, scale
end

function overlay:Project(d, x, z)
    return project(d, x, z)
end

-- Ground piece `t`'s quad from a bottom edge at (d1, z1) to a top edge at (d2, z2), between left
-- and right; `onScreen` false, and nothing placed, past the horizon or outside the view's frame
-- (it clips in the side window and fills the screen otherwise; the ground reaches GROUND_OVERLAP
-- below it). SkinPiece shows it or not.
local function face(t, left, right, d1, z1, d2, z2)
    local bl, by, scale = project(d1, left, z1)
    local tl, ty = project(d2, left, z2)
    if not bl or not tl or ty <= by or ty < -GROUND_OVERLAP or by > 2 * cam.cy then
        t.onScreen = false
        return
    end
    local br, tr = project(d1, right, z1), project(d2, right, z2)
    if br < 0 and tr < 0 or bl > 2 * cam.cx and tl > 2 * cam.cx then
        t.onScreen = false
        return
    end
    t.onScreen = true
    t:SetPoint("BOTTOMLEFT", bl, by)
    -- The same size while the camera only moves sideways, as it does changing lanes.
    local w, h = math.max((right - left) * scale, 0.01), ty - by
    if w ~= t.placedWidth or h ~= t.placedHeight then
        t.placedWidth, t.placedHeight = w, h
        t:SetSize(w, h)
    end
    t:SetVertexOffset(1, tl - bl, 0)
    t:SetVertexOffset(3, tr - br, 0)
end

-- Ground piece `t`'s surface from `look` (one it lacks from `fallback`): the texture, or its
-- color without one or until it loads.
local function skin(t, look, fallback)
    local surface = look.surfaces[t.kind] or fallback.surfaces[t.kind]
    if surface.texture and t:SetTexture(surface.texture, "REPEAT", "REPEAT", "TRILINEAR") then
        t.tile = surface.tile or look.tile or fallback.tile
    else
        local color = surface.color
        t:SetColorTexture(color[1], color[2], color[3], 1)
        t.tile = false
    end
end

function overlay:AddGroundPieces(band, left, right, alphaLeft, alphaRight)
    local look = self.biome.ground
    local surface = look.surfaces[band.surface]
    local segments = SEGMENTS[band.segments]
    assert(surface, "AzerothSurfers biome: unknown ground surface " .. tostring(band.surface))
    assert(segments, "AzerothSurfers biome: a band's segments are 1, 2 or 4")
    local list, pool = self.ground, self.groundPool
    for i = 1, #segments - 1 do
        local near = segments[i]
        local columns = near < COLUMN_NEAR and math.ceil((right - left) / COLUMN - 1e-9) or 1
        for c = 1, columns do
            local n = #list + 1
            local t = pool[n]
            if not t then
                t = self.groundParent:CreateTexture(nil, "BACKGROUND", nil, band.layer)
                t.groundLayer, t.seam = band.layer, false
                pool[n] = t
            end
            if t.groundLayer ~= band.layer then
                t:SetDrawLayer("BACKGROUND", band.layer)
                t.groundLayer = band.layer
            end
            -- A column's share of the band, and of its opacity gradient.
            local a, b = (c - 1) / columns, c / columns
            t.kind, t.near, t.far = band.surface, near, segments[i + 1]
            t.foreground = i == 1
            t.fullFar, t.cut, t.v1 = false, false, false
            -- Placed by the next frame's camera (Render).
            t.onScreen = false
            if t.seam then
                shapes.Hide(t.seam)
            end
            t.left, t.right = left + (right - left) * a, left + (right - left) * b
            t.alphaLeft = alphaLeft + (alphaRight - alphaLeft) * a
            t.alphaRight = alphaLeft + (alphaRight - alphaLeft) * b
            skin(t, look, look)
            -- The runner's biome's; ScrollGround gives it its zone's.
            t.skin = self.biomeId
            list[n] = t
        end
    end
end

-- The biome's bands, mirrored to both sides of the road.
function overlay:BuildGround()
    local list = self.ground
    for i = #list, 1, -1 do
        list[i] = nil
    end
    for _, band in ipairs(self.biome.ground.bands) do
        local from, to, inner, outer = band.from, band.to, band.opacity[1], band.opacity[2]
        if from == 0 then
            self:AddGroundPieces(band, -to, to, outer, outer)
        else
            self:AddGroundPieces(band, -to, -from, outer, inner)
            self:AddGroundPieces(band, from, to, inner, outer)
        end
    end
    for i = #list + 1, #self.groundPool do
        local t = self.groundPool[i]
        shapes.Hide(t)
        if t.seam then
            shapes.Hide(t.seam)
        end
    end
    -- Placed anew: ScrollGround cuts them again.
    self.groundPlaced = true
end

function overlay:CreateGround(f)
    self.groundParent, self.groundPool, self.ground = f, {}, {}
    -- Reused for the gradients: colors are only read during the call.
    self.groundColors = { CreateColor(1, 1, 1, 1), CreateColor(1, 1, 1, 1) }
    if self.biome then
        self:BuildGround()
    end
end

-- Whether the light, brightness or opacity changed since the last call. The side window has
-- nothing to see through to.
function overlay:UpdateGroundLight()
    local settings = app.db.profile.overlay
    local last = self.groundLight or {}
    self.groundLight = last
    local same = unchanged(last, "day", light.day)
    same = unchanged(last, "brightness", settings.brightness) and same
    same = unchanged(last, "opacity", self.side and 1 or settings.opacity) and same
    return not same
end

-- The opacity setting, the far fade and the soft edges, in the light of the moment.
function overlay:ShadePiece(t)
    local left, right = self.groundColors[1], self.groundColors[2]
    local brightness, opacity = self.groundLight.brightness, self.groundLight.opacity
    local r, g, b = light.r * brightness, light.g * brightness, light.b * brightness
    t.fadeAlpha = self:FadeAlpha(t.near)
    local alpha = opacity * t.fadeAlpha
    if t.alphaLeft == t.alphaRight then
        t:SetVertexColor(r, g, b, alpha * t.alphaLeft)
    else
        left:SetRGBA(r, g, b, alpha * t.alphaLeft)
        right:SetRGBA(r, g, b, alpha * t.alphaRight)
        t:SetGradient("HORIZONTAL", left, right)
    end
end

-- A hidden piece is shaded once it shows again (SkinPiece).
local function shadeShown(self, t)
    if t.surferShown then
        self:ShadePiece(t)
    else
        t.fadeAlpha = false
    end
end

function overlay:ShadeGround()
    for _, t in ipairs(self.ground) do
        shadeShown(self, t)
        if t.seam then
            shadeShown(self, t.seam)
        end
    end
end

-- This frame's ground, in yards ahead: the nearest zone and the next one by where each ends, and
-- where the look changes (`cuts`, nearest first: zone ends, gate strips' edges).
local onGround = { distance = 0, firstEnd = math.huge, nextEnd = math.huge, cuts = {} }

local function addCut(d)
    local cuts = onGround.cuts
    local i = #cuts + 1
    while i > 1 and cuts[i - 1] > d do
        cuts[i] = cuts[i - 1]
        i = i - 1
    end
    cuts[i] = d
end

-- The look `d` yards ahead: a biome id, or a gate strip's transition with a ground of its own
-- (twice: as key and look).
function overlay:GroundLookAt(d)
    local at = onGround.distance + d
    local strips, gate = self.strips, app.track.GATE
    for i = 1, #strips do
        local look = self.stripLooks[i]
        if look.ground and at > strips[i] - gate.before and at < strips[i] + gate.after then
            return look, look
        end
    end
    if d < onGround.firstEnd then
        return onGround.firstId
    elseif d < onGround.nextEnd then
        return onGround.nextId
    end
    return self:BiomeIdAt(at)
end

-- Gives ground piece (or seam) `t` the look `key` and its texture coordinates, and shows it
-- where there is something to see: on the screen (`face`) and not faded out. A hidden one costs
-- no calls; it is shaded and its texture placed once it shows again.
function overlay:SkinPiece(t, key, look)
    if t.skin ~= key then
        t.skin = key
        skin(t, look and look.ground or app.biomes.Get(key).ground, self.biome.ground)
        t.fadeAlpha, t.v1 = false, false
    end
    if not t.onScreen then
        shapes.Hide(t)
        if self.fade.moved then
            t.fadeAlpha = false
        end
        return
    end
    -- The view's end moves while a gate comes nearer: its rows fade anew.
    if
        self.groundLight
        and (self.fade.moved or not t.fadeAlpha)
        and math.abs(self:FadeAlpha(t.near) - (t.fadeAlpha or -1)) > 0.01
    then
        self:ShadePiece(t)
    end
    if t.fadeAlpha == 0 then
        shapes.Hide(t)
        return
    end
    local tile = t.tile
    if tile then
        local base = onGround.distance % tile
        local v1, v2 = -(t.far + base) / tile, -(t.near + base) / tile
        -- Unchanged while the runner stands, as on the title screen during a glide.
        if v1 ~= t.v1 or v2 ~= t.v2 then
            t.v1, t.v2 = v1, v2
            t:SetTexCoord(t.left / tile, t.right / tile, v1, v2)
        end
    end
    shapes.Show(t)
end

-- A second texture that takes over a piece from where the look changes in it, so the change
-- stays where it is on the ground instead of jumping from piece edge to piece edge.
local function seamOf(t, parent)
    local seam = t.seam
    if not seam then
        seam = parent:CreateTexture(nil, "BACKGROUND", nil, t.groundLayer)
        seam.groundLayer, seam.onScreen = t.groundLayer, false
        t.seam = seam
    elseif seam.groundLayer ~= t.groundLayer then
        seam:SetDrawLayer("BACKGROUND", t.groundLayer)
        seam.groundLayer = t.groundLayer
    end
    if seam.left ~= t.left or seam.right ~= t.right then
        seam.left, seam.right, seam.v1 = t.left, t.right, false
    end
    seam.kind = t.kind
    seam.alphaLeft, seam.alphaRight = t.alphaLeft, t.alphaRight
    return seam
end

local function uncut(t)
    if t.cut then
        t.cut, t.far = false, t.fullFar
        face(t, t.left, t.right, t.near, ground(t.near), t.far, ground(t.far))
        shapes.Hide(t.seam)
    end
end

-- The textures slide toward the runner; offsets wrap at a tile.
function overlay:ScrollGround()
    local distance = self.state.distance
    if self.scrolled == distance and not self.groundPlaced then
        return
    end
    self.scrolled, self.groundPlaced = distance, nil
    onGround.distance = distance
    local cuts = onGround.cuts
    for i = #cuts, 1, -1 do
        cuts[i] = nil
    end
    -- The zones by where each ends: once a frame, not once a piece.
    onGround.firstId, onGround.firstEnd, onGround.nextId, onGround.nextEnd = self.biomeId, math.huge, nil, math.huge
    local lobby = self.state.lobby
    if lobby and distance + cam.groundNear < lobby.rim then
        -- The lobby's biome up to its gate, the first zone's past it (BiomeIdAt).
        onGround.firstId, onGround.firstEnd = lobby.biome, lobby.rim - distance
        onGround.nextId = self:BiomeIdAt(lobby.rim + 1)
        addCut(onGround.firstEnd)
    elseif app.db.profile.biome == app.biomes.AUTO then
        local biomes, route = app.biomes, self:Route()
        local zone = biomes.Zone(route, distance + cam.groundNear)
        onGround.firstId, onGround.firstEnd = zone.id, zone.to - distance
        if onGround.firstEnd < sim.AHEAD then
            local following = biomes.Zone(route, zone.to)
            onGround.nextId, onGround.nextEnd = following.id, following.to - distance
            addCut(onGround.firstEnd)
            if onGround.nextEnd < sim.AHEAD then
                addCut(onGround.nextEnd)
            end
        end
    end
    local gate = app.track.GATE
    for _, rim in ipairs(self.strips) do
        addCut(rim - gate.before - distance)
        addCut(rim + gate.after - distance)
    end
    for _, t in ipairs(self.ground) do
        local near, far = t.near, t.fullFar or t.far
        t.fullFar = far
        local key, look = self:GroundLookAt(near + 0.01)
        local cut, seamKey, seamLook
        for i = 1, #cuts do
            local d = cuts[i]
            if d >= far then
                break
            elseif d > near then
                seamKey, seamLook = self:GroundLookAt(d + 0.01)
                if seamKey ~= key then
                    cut = d
                    break
                end
            end
        end
        if cut then
            t.cut, t.far = cut, cut
            face(t, t.left, t.right, near, ground(near), cut, ground(cut))
            local seam = seamOf(t, self.groundParent)
            seam.near, seam.far = cut, far
            face(seam, seam.left, seam.right, cut, ground(cut), far, ground(far))
            self:SkinPiece(seam, seamKey, seamLook)
        else
            uncut(t)
        end
        self:SkinPiece(t, key, look)
    end
end

-- Puts `frame` at its place in ORDER for the current mode, and again whenever it changes.
function overlay:Stack(frame, place)
    self.stacked = self.stacked or {}
    self.stacked[frame] = place
    local strata, level = app.db.profile.drawStrata or "HIGH", ORDER[place]
    frame:SetFixedFrameStrata(false)
    frame:SetFixedFrameLevel(false)
    frame:SetFrameStrata(strata)
    frame:SetFixedFrameStrata(true)
    frame:SetFrameLevel(self.frame:GetFrameLevel() + level)
    frame:SetFixedFrameLevel(true)
end

function overlay:Restack()
    self.frame:SetFixedFrameStrata(false)
    self.frame:SetFixedFrameLevel(false)
    self.frame:SetFrameStrata(app.db.profile.drawStrata or "HIGH")
    self.frame:SetFrameLevel(app.db.profile.drawLevel or 1)
    self.frame:SetFixedFrameStrata(true)
    self.frame:SetFixedFrameLevel(true)
    for frame, place in pairs(self.stacked) do
        self:Stack(frame, place)
    end
    if self.occluder then
        self:PlaceOccluder()
    end
end

-- Forever returns six scalars; the API docs describe two vectors. Accepts both.
local function extents(actor)
    if not actor:IsLoaded() then
        return nil
    end
    local a, b, c, d, e, f = actor:GetActiveBoundingBox()
    if type(a) == "table" and type(b) == "table" then
        a, b, c, d, e, f = a.x, a.y, a.z, b.x, b.y, b.z
    end
    if type(a) ~= "number" or type(f) ~= "number" then
        return nil
    end
    return a, b, c, d, e, f
end
overlay.Extents = extents

-- Character height in yards from a copy without weapons; a human-sized guess until it loads.
-- `body` is its height in the track's world, `bodyScale` how much smaller than the real one.
function overlay:Measure()
    if self.measured then
        return
    end
    local _, _, low, _, _, high = extents(self.probe)
    if not low or high - low < 0.1 then
        return
    end
    self.height = math.min(math.max(high - low, 0.8), 4)
    self.measured = true
    self:ApplyBodyScale()
    -- Every shown scene costs a render pass, even an empty one.
    shapes.Hide(self.probeScene)
end

-- The twin's scale: the twin size setting, a tall character at the track's size
-- (referenceHeight), and TWIN_SIZE. The character at the lobby's fire too (screens.lua).
function overlay:TwinScale()
    return app.db.profile.overlay.twinScale / self.bodyScale * TWIN_SIZE
end

function overlay:ApplyBodyScale()
    self.bodyScale = math.max(1, self.height / self.referenceHeight)
    self.body = self.height / self.bodyScale
    -- Everything is placed again.
    self.lastRoad = {}
    app.logger:debug(
        "Character %.2f yards tall: drawn at %.2f in the track's world, the track %.2f times as big",
        self.height,
        self.body,
        self.bodyScale
    )
end

function overlay:LoadPlayer()
    self.measured = false
    shapes.Show(self.probeScene)
    self.probe:SetModelByUnit("player", true, true, true, true)
    self.twinActor:SetModelByUnit("player", true, true, false, true)
    self.twinLow, self.twinAnimation = nil, nil
    if self.seat then
        self:LoadSeat()
    end
end

function overlay:Route()
    local s = self.state
    if self.routeState ~= s then
        -- A run without zones (begun before auto was picked) stays in its first one, or the
        -- first past the lobby's gate.
        self.routeState, self.route = s, app.biomes.Route(s.seed, s.gates or {}, s.lobby or s.fromLobby)
    end
    return self.route
end

-- How far the view's far fade has come at `ahead` yards: 1 near, 0 past its end.
function overlay:FadeAlpha(ahead)
    local fade = self.fade
    return math.min(1, math.max(0, (fade.to - ahead) / (fade.to - fade.from)))
end

-- Yards over which the view ends just past a gate's strip.
local CUT_SOFT = 3

-- Once a frame: where the view ends (`fade`, which every part of the view fades by), the
-- biome's far fade or, while a gate is ahead, just past its strip, so nothing of the next zone
-- shows early. And the gate strips in sight (`strips`, their rims; `stripLooks`, transitions).
function overlay:UpdateView()
    local s, own = self.state, self.biome.ground.fade
    local view = self.fade or {}
    self.fade = view
    local from, to = view.from, view.to
    view.from, view.to = own.from, own.to
    local strips, looks = self.strips or {}, self.stripLooks or {}
    self.strips, self.stripLooks = strips, looks
    for i = #strips, 1, -1 do
        strips[i], looks[i] = nil, nil
    end
    local gates = s.gates
    if not gates then
        view.moved = view.from ~= from or view.to ~= to
        return
    end
    if self.viewState ~= s then
        self.viewState, self.gateIndex = s, 1
    end
    local biomes, gate = app.biomes, app.track.GATE
    local k = self.gateIndex
    while gates[k] and gates[k] + gate.after < s.distance - 10 do
        k = k + 1
    end
    self.gateIndex = k
    local ahead
    for i = k, #gates do
        local rim = gates[i]
        if rim - gate.before > s.distance + sim.AHEAD then
            break
        end
        strips[#strips + 1] = rim
        looks[#strips] = biomes.Transition(self:BiomeAt(rim + 1).entrance)
        if not ahead and rim > s.distance then
            ahead = rim
        end
    end
    if ahead then
        local cut = ahead + gate.after - s.distance
        if cut < view.to then
            view.to = cut
            view.from = math.min(view.from, cut - CUT_SOFT)
        end
    end
    -- Whether the ground's rows have to fade anew (ScrollGround).
    view.moved = view.from ~= from or view.to ~= to
end

-- The end of a gate strip reaching into `from` to `to` (or at `from`), where decorations may
-- stand again; nil when none does.
function overlay:StripEnd(from, to)
    local strips, gate = self.strips, app.track.GATE
    to = to or from
    for i = 1, #strips do
        if from < strips[i] + gate.after and to > strips[i] - gate.before then
            return strips[i] + gate.after
        end
    end
end

-- The profile's biome, or in auto the zone's at `at`: everything along the track looks like the
-- zone it stands in, so the next zone comes into sight on the horizon.
function overlay:BiomeIdAt(at)
    local id, biomes = app.db.profile.biome, app.biomes
    -- Before the lobby's gate the lobby's own, and everywhere until its run starts: the title and
    -- the menu look the same whatever the run's seed (and so its first zone).
    local s = self.state
    local lobby = s and s.lobby
    if lobby and (at < lobby.rim or s.status == "ready") then
        return lobby.biome
    end
    if id ~= biomes.AUTO then
        return id
    end
    return biomes.ZoneAt(self:Route(), at)
end

function overlay:BiomeAt(at)
    return app.biomes.Get(self:BiomeIdAt(at))
end

-- The biome the runner is in: its sky, light and ground bands.
function overlay:BiomeId()
    -- Before the first run (the tests), at its start.
    return self:BiomeIdAt(self.state and self.state.distance or 0)
end

-- Once a frame in auto: entering the next zone changes only what is the runner's own.
function overlay:UpdateZone()
    if self:BiomeId() ~= self.biomeId then
        self:ApplyBiome(true)
        -- Through a gate, not a new run's first zone: a restart begins past its lobby's portal.
        local s = self.state
        local from = s.gates and app.biomes.Zone(self:Route(), s.distance).from
        -- Not through a challenge's last portal: its run ends there.
        local through = from and from > -math.huge and (s.lobby ~= nil or from > s.start) and from ~= s.finish
        if s.status == "running" and through then
            self:WelcomeBiome()
            local flash = app.biomes.Transition(self.biome.entrance).flash
            if flash then
                self:Flash(flash)
            end
        end
    end
end

-- In auto, blended toward the next zone's as it nears, so the far ground does not jump.
function overlay:GroundCurve()
    local curve = self.biome.ground.curve
    -- Before the lobby's gate, from the lobby's own at the start to the first zone's at the rim:
    -- the camp looks the same whatever the run's seed (and so its first zone).
    local s, lobby = self.state, self.state.lobby
    if lobby and s.distance < lobby.rim then
        local next = app.biomes.Get(self:BiomeIdAt(lobby.rim + 1)).ground.curve
        return curve + (next - curve) * math.max(0, s.distance / lobby.rim)
    end
    if app.db.profile.biome ~= app.biomes.AUTO then
        return curve
    end
    local biomes = app.biomes
    local zone = biomes.Zone(self:Route(), s.distance)
    local nearer = math.min(1, math.max(0, 1 - (zone.to - s.distance) / sim.AHEAD))
    if nearer == 0 then
        return curve
    end
    local next = biomes.Get(biomes.ZoneAt(self.route, zone.to)).ground.curve
    return curve + (next - curve) * nearer
end

-- `entering` a zone in auto: what stands on the track already looks like it and stays;
-- otherwise everything is redrawn.
function overlay:ApplyBiome(entering)
    local old = self.biome
    self.biomeId = self:BiomeId()
    local biome = app.biomes.Get(self.biomeId)
    self.biome = biome
    shapes.colors = biome.shapes
    light.SetNight(biome.light.night)
    if self.groundParent then
        self:BuildGround()
    end
    self:BuildOccluder()
    if self.worldScene then
        if not entering or not old or biome.coin ~= old.coin then
            self:LoadCoinModel(1)
        end
        self:ApplyDecorations(biome, entering)
        if not entering then
            self:ResetObstacles()
            self:ResetAmbient()
        end
    end
    self.lastRoad, self.groundLight, self.scrolled = {}, nil, nil
end

-- A coin actor more in the world scene, with the current coin model, out of sight until placed.
function overlay:NewCoinActor()
    local actor = self.worldScene:CreateActor()
    actor:SetUseCenterForOrigin(true, true, true)
    actor:SetPosition(-1000, 0, 0)
    actor.surferAlpha = false
    local entry = self.biome.coin.models[self.coinModel]
    if entry then
        actor:SetModelByFileID(entry.model)
    end
    if self.coinReady then
        actor:SetScale(self.coinScale)
        actor:SetPitch(self.coinPitch)
    end
    self.coinActors[#self.coinActors + 1] = actor
    return actor
end

-- Tried in order until one loads; measured on the first actor.
function overlay:LoadCoinModel(index)
    self.coinModel, self.coinWait, self.coinReady = index, 0, false
    if #self.coinActors == 0 then
        self:NewCoinActor()
    end
    local entry = self.biome.coin.models[index]
    for _, actor in ipairs(self.coinActors) do
        if entry and not actor:SetModelByFileID(entry.model) then
            return self:LoadCoinModel(index + 1)
        end
    end
end

-- Fits the coin model into its entry's size (COIN_SIZE if none) once it has loaded, or moves on
-- to the next entry.
function overlay:UpdateCoinModel(elapsed)
    local entry = self.biome.coin.models[self.coinModel]
    if self.coinReady or not self.worldScene or not entry then
        return
    end
    local minX, minY, minZ, maxX, maxY, maxZ = extents(self.coinActors[1])
    local size = minX and math.max(maxX - minX, maxY - minY, maxZ - minZ) or 0
    if size > 0.001 then
        -- A coin lying flat (as doodads do) is stood up to face the camera, then spun.
        local flat = maxZ - minZ < 0.3 * math.max(maxX - minX, maxY - minY)
        self.coinSize = entry.size or COIN_SIZE
        self.coinScale, self.coinPitch = self.coinSize / size, flat and math.pi / 2 or 0
        for _, actor in ipairs(self.coinActors) do
            actor:SetScale(self.coinScale)
            actor:SetPitch(self.coinPitch)
        end
        self.coinReady = true
        app.logger:debug("Coin model %d loaded", entry.model)
        return
    end
    self.coinWait = self.coinWait + elapsed
    if self.coinWait > 3 then
        app.logger:debug("Coin model %d did not load", entry.model)
        self:LoadCoinModel(self.coinModel + 1)
    end
end

function overlay:Create()
    self.state = self:NewState()
    self.height, self.body, self.bodyScale, self.lastRoad = 2, 2, 1, {}
    local f = CreateFrame("Frame", "AzerothSurfersOverlay", UIParent)
    self.frame = f
    f:SetAllPoints(UIParent)
    -- Above the 3D world, below the rest of the UI (full screen, ORDER).
    f:SetFrameStrata(app.db.profile.drawStrata or "HIGH")
    f:SetFrameLevel(app.db.profile.drawLevel or 1)
    f:EnableMouse(true)
    -- The ground; the boxes on it draw on BORDER.
    self:CreateGround(f)
    self.faces = shapes.Pool(f, "BORDER")
    -- Where a challenge's best ended (bestmarker.lua), on the ground under the boxes.
    self:CreateBestMarker(f)
    local probe = CreateFrame("ModelScene", nil, f)
    probe:SetSize(1, 1)
    probe:SetPoint("TOPLEFT")
    probe:SetAlpha(0)
    self.probeScene, self.probe = probe, probe:CreateActor()
    -- Where the twin is on the screen: a square around its body (the streak's panel stands beside
    -- it, hud.lua).
    local anchor = CreateFrame("Frame", nil, f)
    anchor:SetSize(1, 1)
    anchor:SetPoint("CENTER")
    self.twinAnchor = anchor
    -- The world scene: 3D decorations, coins and the twin, one render pass for all of them.
    self:CreateDecorations(f)
    -- The twin is one of its actors: one camera and one depth with everything else in it.
    self.twinActor = self.worldScene:CreateActor()
    self.twinActor:SetUseCenterForOrigin(true, true, false)
    self.twinActor:SetYaw(0)

    self:LoadPlayer()
    -- Under the view's frame: it needs a level above the lowest.
    self:CreateOccluder()
    self:CreateAmbient()
    self.coinActors, self.modelled = {}, {}
    self:ApplyBiome()

    self:CreateHud(f)
    self:CreateLegend(f)
    self:CreateMessages(f)
    self:CreateScreens(f)
    local controls = CreateFrame("Frame", nil, f)
    self.controls = controls
    self:Stack(controls, "controls")
    controls:SetHeight(24)
    -- Minimize and Close without the window frame (it has its own); Pause and Stop auto mode in
    -- auto mode (the side window passes keys on to WoW). window.lua lays the row out.
    local buttons = {
        {
            "Minimize",
            function()
                self:SetMode(self.side and "full" or "side")
            end,
        },
        {
            "Close",
            function()
                f:Hide()
            end,
        },
        {
            "Pause",
            function()
                self:Action("P")
            end,
        },
        {
            "Stop auto mode",
            function()
                self:SetAuto(false)
            end,
            120,
        },
    }
    self.controlButtons = {}
    for i, spec in ipairs(buttons) do
        local b = CreateFrame("Button", nil, controls, "UIPanelButtonTemplate")
        b:SetSize(spec[3] or 84, 24)
        b:SetText(spec[1])
        b:SetScript("OnClick", spec[2])
        self.controlButtons[i] = b
    end
    self:CreateHoldBar(f)

    f:EnableKeyboard(true)
    f:SetPropagateKeyboardInput(true)
    -- Keys pass on to WoW, except the restart key and, while captured, the movement keys.
    f:SetScript("OnKeyDown", function(_, key)
        self:OnKey(key)
    end)
    f:SetScript("OnKeyUp", function(_, key)
        self:OnKeyRelease(key)
    end)
    -- Gamepad buttons ("PAD1", "PADDLEFT", ...) as keys: they pass on to WoW the same way.
    if f.EnableGamePadButton then
        f:EnableGamePadButton(true)
        f:SetScript("OnGamePadButtonDown", function(_, button)
            self:OnKey(button)
        end)
        f:SetScript("OnGamePadButtonUp", function(_, button)
            self:OnKeyRelease(button)
        end)
    end
    -- The left stick, as buttons of its directions (controls.lua's OnStick).
    if f.EnableGamePadStick then
        f:EnableGamePadStick(true)
        f:SetScript("OnGamePadStick", function(_, stick, x, y)
            self:OnStick(stick, x, y)
        end)
    end
    f:SetScript("OnHide", function()
        -- Closing the game ends auto mode.
        self:SetAuto(false)
        self.holding, self.stickHeld = nil, nil
        self:ForgetPosition()
        self.state.forward = false
        if self.state.status == "running" then
            sim.Pause(self.state)
        end
        self:SaveBest()
        self:PlayTitleMusic(false)
    end)
    f:SetScript("OnShow", function()
        self:SyncCombat()
        -- A paused run goes on where it was; otherwise the game opens on its title screen.
        if self.state.status ~= "paused" then
            self:OpenTitle()
        end
        self:LoadPlayer()
        self.lastRoad = {}
    end)
    f:RegisterEvent("PLAYER_REGEN_DISABLED")
    f:RegisterEvent("PLAYER_REGEN_ENABLED")
    f:RegisterEvent("PLAYER_LOGOUT")
    f:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    f:RegisterUnitEvent("UNIT_MODEL_CHANGED", "player")
    f:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
            self:SyncCombat()
        elseif event == "PLAYER_LOGOUT" then
            self:SaveBest()
        else
            self:LoadPlayer()
        end
    end)
    self:CreateWindow(f)
    self:CreateInputHud()
    f:SetScript("OnUpdate", function(_, elapsed)
        local lap = self.timing and debugprofilestop()
        self:Step(elapsed)
        self:UpdateZone()
        self:UpdateHold(elapsed)
        lap = self:Lap("simulation", lap)
        self:AnimateTwin(elapsed)
        self:Measure()
        self:UpdateCoinModel(elapsed)
        lap = self:Lap("twin animation, models", lap)
        self:Render(lap)
        -- A hidden HUD cannot update itself; use the final game handler, after screens change.
        self:SyncInputHudVisibility()
    end)
    self:ApplyMode()
    -- Created shown: OnShow does not run the first time.
    self:OpenTitle()
    self:Render()
end

-- The twin: an actor of the world scene, at the runner, its lowest point on the runner's floor;
-- it shares the scene's camera and depth with everything else there, and the scene's lens is
-- measured against the road. Drawn TWIN_SIZE times as big as the real character. `twinAnchor` follows it on the
-- screen. Half see-through while not running full screen, to line it up. On the title and the
-- menu the character sits at the lobby's fire instead (screens.lua). After FollowWorldCamera:
-- with the camera of the same frame.
function overlay:PlaceTwin()
    local s = self.state
    local actor = self.twinActor
    if not actor:IsLoaded() or self.seated then
        actor:Hide()
        return
    end
    if not self.twinLow then
        local _, _, low = extents(actor)
        if not low then
            actor:Hide()
            return
        end
        self.twinLow = low
    end
    -- The runner's place to the screen's right.
    local runner = -s.lateral * LANE
    -- The scene's y points left; its position counts in its scale.
    local scale = self:TwinScale()
    actor:SetScale(scale)
    local offsets = app.biomes.playerAnimationOffsets
    local visualZ = 0
    if offsets and not self.screen and s.status == "running" and s.duck > 0 and self.twinAnimation == ROLL then
        visualZ = (offsets[app.biomes.PlayerAnimation(self.twinAnimation)] or 0) * self.bodyScale
    end
    actor:SetPosition((self.sceneRunner or 0) / scale, -runner / scale, (cam.feet + visualZ) / scale - self.twinLow)
    actor:SetAlpha((s.status == "running" or self.side or self.screen == "start") and 1 or 0.5)
    actor:Show()
    local x, y, size = project(0, runner, cam.feet + self.body / 2)
    if x then
        local side = TWIN_FRAME * self.body * size
        local anchor = self.twinAnchor
        anchor:ClearAllPoints()
        anchor:SetPoint("CENTER", self.frame, "BOTTOMLEFT", x, y)
        anchor:SetSize(side, side)
    end
end

-- The real character's animation cannot be read, so the twin mirrors its movement; a lane
-- change turns it like a strafe. In auto mode it follows only the run.
function overlay:AnimateTwin(elapsed)
    local actor, s, motion = self.twinActor, self.state, self.motion or {}
    if self.jumpState ~= s then
        self.jumpState = s
        jumpRandom:Seed(s.seed, app.random.JUMPS)
        self.wasAirborne, self.airTime, self.landTime = false, 0, nil
    end
    local airborne = s.height > s.floor or (not self.auto and IsFalling("player"))
    if airborne and not self.wasAirborne then
        local _, race = UnitRace("player")
        local bySex = JUMP_ANIMATIONS[race]
        local choices = bySex and bySex[UnitSex("player")]
        local choice = choices and choices[jumpRandom(#choices)]
        self.jumpAnimation = choice and choice[1] or JUMP_START
        self.jumpVariation = choice and choice[2] or 0
        -- A new takeoff must restart even if it follows the same animation.
        self.twinAnimation = nil
    end
    self.airTime = airborne and (self.airTime or 0) + elapsed or 0
    if self.wasAirborne and not airborne then
        self.landTime = 0
    elseif self.landTime then
        self.landTime = self.landTime + elapsed
    end
    self.wasAirborne = airborne
    -- The direction comes from one frame's step, which is noisy: smooth it.
    local k = math.min(1, elapsed * 12)
    self.towardForward = (self.towardForward or 0) + ((motion.forward or 0) - (self.towardForward or 0)) * k
    self.towardLeft = (self.towardLeft or 0) + ((motion.left or 0) - (self.towardLeft or 0)) * k
    local speed = motion.speed or 0
    -- 0 straight ahead, positive to the left; pushing against a wall runs on the spot.
    local direction = math.atan2(self.towardLeft, self.towardForward)
    local animation, rate, yaw, variation = STAND, 1, self.twinYaw or 0, 0
    if airborne then
        animation = self.airTime < AIR_LOOP and self.jumpAnimation or JUMP
        variation = self.airTime < AIR_LOOP and self.jumpVariation or 0
        -- Turned toward its way through the air; a jump backwards keeps its turn.
        if speed > 0 and self.towardForward >= 0 then
            yaw = direction
        end
    elseif s.duck > 0 and s.status == "running" then
        animation, yaw = ROLL, 0
    elseif speed > 0 then
        if self.towardForward < -0.1 and math.abs(direction) > math.pi * 0.6 then
            animation, rate = BACKWARDS, speed / BACKWARDS_SPEED
            yaw = direction - (direction > 0 and math.pi or -math.pi)
        else
            animation = speed < 4 and WALK or RUN
            rate, yaw = speed / (animation == WALK and WALK_SPEED or RUN_SPEED), direction
            -- As the run speeds up the track, the legs speed up with it, or the twin glides.
            if animation == RUN and s.status == "running" then
                -- Speeding up from the lobby's launch speed, a normal run's at least.
                local pace = s.speed / sim.RUN_PACE
                rate = rate * (s.launch and math.max(pace, 1) or pace)
                -- A tall character is drawn smaller in the track's world: shorter strides.
                rate = rate * self.bodyScale
            end
        end
    elseif self.landTime and self.landTime < 0.3 then
        animation = JUMP_END
    else
        yaw = 0
    end
    -- Held a little past the lane change, which is quicker than the turn.
    local toward = s.lane - s.lateral
    if s.status == "running" and math.abs(toward) > 0.01 then
        -- Positive lanes are on the left, as is a positive yaw.
        self.strafeYaw, self.strafeTime = toward > 0 and STRAFE_YAW or -STRAFE_YAW, STRAFE_HOLD
    elseif self.strafeTime then
        self.strafeTime = self.strafeTime - elapsed
        if self.strafeTime <= 0 or s.status ~= "running" then
            self.strafeTime = nil
        end
    end
    -- Turn the body smoothly, the short way round; into a strafe and back out of it quickly.
    local quick = self.strafeTime ~= nil or self.strafeBack
    if self.strafeTime then
        yaw = self.strafeYaw
    end
    -- Turned toward the road on the way into a run from the lobby (screens.lua).
    if self.twinFace then
        yaw = self.twinFace
    end
    local turn = (yaw - (self.twinYaw or 0) + math.pi) % (2 * math.pi) - math.pi
    self.twinYaw = (self.twinYaw or 0) + turn * math.min(1, elapsed * 10 * (quick and STRAFE_TURN or 1))
    -- Back out of a strafe: quick until the body faces its way again.
    self.strafeBack = self.strafeTime ~= nil or quick and math.abs(turn) > 0.05
    actor:SetYaw(self.twinYaw)
    -- Setting an animation restarts it: only when it or its speed really changes.
    if
        animation ~= self.twinAnimation
        or variation ~= self.twinVariation
        or math.abs(rate - (self.twinRate or 1)) > 0.1
    then
        actor:SetAnimation(app.biomes.PlayerAnimation(animation), variation, rate, 0)
        self.twinVariation = variation
        self.twinAnimation, self.twinRate = animation, rate
    end
end

-- Spinning with its own phase, fading in far ahead like the ground. In the middle of its layer,
-- or resting on the layer's floor when larger.
function overlay:PlaceCoin(i, o)
    local actor = self.coinActors[i] or self:NewCoinActor()
    local d = o.at + o.length / 2 - self.state.distance
    -- The scene's y points left; an actor's position is scaled with it.
    local scale = self.coinScale
    local lift = math.max(sim.LAYER, self.coinSize) / 2
    actor:SetPosition(
        (d + self.sceneRunner) / scale,
        o.lane * LANE / scale,
        (o.layer * sim.LAYER + lift + ground(d)) / scale
    )
    actor:SetYaw(GetTime() * 3 + o.at)
    local alpha = self:FadeAlpha(d)
    if not actor.surferAlpha or math.abs(alpha - actor.surferAlpha) > 0.02 then
        actor:SetAlpha(alpha)
        actor.surferAlpha = alpha
    end
    shapes.Show(actor)
end

function overlay:Render(lap)
    local s = self.state
    self:UpdateView()
    if self:UpdateCamera() then
        for _, t in ipairs(self.ground) do
            if t.foreground then
                t.near = cam.groundNear
            end
            local near, far = t.near, t.fullFar or t.far
            face(t, t.left, t.right, near, ground(near), far, ground(far))
        end
        -- Cut pieces and their seams again (ScrollGround), even with the runner standing.
        self.groundPlaced = true
        if self.worldScene then
            self:AimDecorations()
        end
        if self.side then
            self:PlaceBackdrop()
        end
    end
    light.Update()
    if self:UpdateGroundLight() then
        self:ShadeGround()
        if self.side then
            self:ShadeBackdrop()
        end
    end
    lap = self:Lap("road placement", lap)
    self:ScrollGround()
    self:UpdateOccluder()
    if self.worldScene then
        -- The scene's camera runs along; its models stand still (decorations.lua).
        self:FollowWorldCamera()
        self:UpdateDecorations()
        self:UpdateObstacles()
        self:UpdateAmbient()
    end
    lap = self:Lap("ground scroll, decorations, obstacles, wildlife", lap)
    self:PlaceTwin()
    lap = self:Lap("twin", lap)
    -- Boxes and flat coins from the shared faces; coins are 3D models in the world scene once
    -- their model has loaded, flat until then.
    local faces, count = shapes.Collect(s, -cam.offset, self.fade.to, cam.x + BOX_NEAR, cam.x - COIN_SIZE)
    local coins = 0
    local real = self.worldScene and self.coinReady
    for i = 1, count do
        local f = faces[i]
        if f.kind == "coin" and real then
            coins = coins + 1
            self:PlaceCoin(coins, f.object)
        elseif not (self.worldScene and self:Modelled(f)) then
            shapes.Draw(shapes.Acquire(self.faces, shapes.Sublevel(f)), project, f)
        end
    end
    self.faceCount, self.coinCount = self.faces.used, coins
    shapes.Release(self.faces)
    if self.worldScene then
        -- The first coin stays out of sight but shown while the model loads.
        for i = coins + 1, #self.coinActors do
            if self.coinReady or i > 1 then
                shapes.Hide(self.coinActors[i])
            end
        end
        -- Never empty: the twin (or the seated character) is always in it.
        shapes.Show(self.worldScene)
    end
    self:ShowBestMarker()
    lap = self:Lap("boxes, coins", lap)
    self:ShowScreens()
    self:ShowStatus()
    self:ShowBanner()
    self:ShowFlash()
    self:ShowVortex()
    self:ShowHud()
    self:ShowLegend()
    self:Lap("texts", lap)
    if self.timing then
        self.timing.frames = self.timing.frames + 1
    end
end

-- Adds the time since `since` to `part` of a frame and starts the next lap, into `timing` while
-- AzerothSurfers_Dev's /surfers profile runs; nothing otherwise.
function overlay:Lap(part, since)
    if not since then
        return nil
    end
    local now = debugprofilestop()
    self.timing[part] = (self.timing[part] or 0) + now - since
    return now
end
