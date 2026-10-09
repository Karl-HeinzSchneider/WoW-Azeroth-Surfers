---@type string, AzerothSurfers
local _, app = ...
local shapes = app.shapes
-- The ground's depth. The ground is drawn flat (2D textures under the world scene), so nothing
-- would hide what a model has below it (a tree's roots, a tent's edge): it would show over the
-- road. The view's 3D scenes share the depth buffer: under the view's frame a scene of flat tiles
-- lying along the ground writes its depth first, the 2D ground paints over their color, and the
-- world scene, drawn after, fails the depth test below them.
--
-- The tiles lie SINK yards under the ground, so a model standing on it never meets them: close
-- under it in the lobby (the title, the menu, up to its portal), where the camera is near; deep
-- past it in a run, where nearer the bottoms of the boxes flicker (not understood yet). Only under the ground
-- that is fully opaque: its solid bands, short of the far fade, with full ground opacity.
local overlay = app.overlay
local cam = overlay.camera
local ground = shapes.Ground
local unchanged = overlay.Unchanged

-- human/passive doodads/rugs/stormwindrug01: flat and solid (it writes depth).
local MODEL = 198435
-- A tile's size, how far the tiles reach (yards ahead of the runner), and their overlap.
local TILE, AHEAD, OVERLAP = 4, 60, 1.2
-- How far under the ground the tiles lie (SINK), and from how far ahead of the runner (BEHIND,
-- yards; no tile reaches back past it): in the lobby, up to its portal, close under the ground
-- and from behind the runner (the camp's models it runs past stay covered); past it deep, so
-- from ahead of the runner only: seen from above, a tile deep under the ground is drawn lower,
-- and near the camera it would show below the ground's near edge (zoomed out).
local SINK = { lobby = 0.05, run = 3 }
local BEHIND = { lobby = -3, run = 5 }
-- Surfer_Dev's /surfers occluder changes the sinks, and turns it off (`occluderOff`).
overlay.OCCLUDER_SINK = SINK

function overlay:CreateOccluder()
    local scene = CreateFrame("ModelScene", nil, UIParent)
    scene:EnableMouse(false)
    scene:SetAllPoints(self.frame)
    scene:SetCameraNearClip(self.CLIP_NEAR)
    scene:SetCameraFarClip(self.CLIP_FAR)
    scene:Hide()
    -- Each tile's place (yards ahead, to the right), and once loaded its scale, its top and how far
    -- it reaches each way along the road and across.
    self.occluder = {
        scene = scene,
        actors = {},
        d = {},
        x = {},
        scale = {},
        top = {},
        along = {},
        across = {},
        count = 0,
        last = {},
    }
    self:PlaceOccluder()
end

-- Under the view's frame, in its strata; on every change of mode (Restack).
function overlay:PlaceOccluder()
    local scene, f = self.occluder.scene, self.frame
    scene:SetFrameStrata(f:GetFrameStrata())
    scene:SetFrameLevel(math.max(0, f:GetFrameLevel() - 1))
end

-- How far to each side the ground is fully opaque: the widest band without a fade.
local function halfWidth(biome)
    local w = 0
    for _, band in ipairs(biome.ground.bands) do
        if band.opacity[1] == 1 and band.opacity[2] == 1 then
            w = math.max(w, band.to)
        end
    end
    return w
end

-- The tiles for the biome's ground, in rows ahead and columns across.
function overlay:BuildOccluder()
    local occ = self.occluder
    if not occ then
        return
    end
    local w = halfWidth(self.biome)
    local across = math.max(1, math.ceil(2 * w / TILE))
    local count = 0
    local from = math.min(BEHIND.lobby, BEHIND.run)
    for i = 0, math.ceil((AHEAD - from) / TILE) - 1 do
        for k = 0, across - 1 do
            count = count + 1
            local actor = occ.actors[count]
            if not actor then
                actor = occ.scene:CreateActor()
                actor:SetUseCenterForOrigin(true, true, true)
                actor:SetModelByFileID(MODEL)
                occ.actors[count] = actor
            end
            occ.d[count] = from + (i + 0.5) * TILE
            occ.x[count] = -w + (k + 0.5) * (2 * w / across)
        end
    end
    for i = count + 1, #occ.actors do
        shapes.Hide(occ.actors[i])
    end
    occ.count, occ.width, occ.last.placed = count, w, nil
end

-- Its camera is the road's without the runner's distance: the ground lies relative to the
-- runner, so the tiles stay put and only follow a change of the ground's curve, of the sink or
-- of where the view fades. Once a frame; nothing changed, nothing is called.
function overlay:UpdateOccluder()
    local occ = self.occluder
    if not occ then
        return
    end
    local s = self.state
    -- See-through ground would show the tiles; the world scene's lens is not measured yet.
    local on = not self.occluderOff and self.groundLight and self.groundLight.opacity == 1 and self.decorLens.span
    if not on then
        shapes.Hide(occ.scene)
        return
    end
    shapes.Show(occ.scene)
    local last = occ.last
    local same = unchanged(last, "x", cam.x)
    same = unchanged(last, "offset", cam.offset) and same
    same = unchanged(last, "z", cam.z) and same
    same = unchanged(last, "pitch", cam.pitch) and same
    same = unchanged(last, "f", cam.f) and same
    same = unchanged(last, "span", self.decorLens.span) and same
    if not same then
        occ.scene:SetCameraPosition(cam.x, cam.offset, cam.z)
        occ.scene:SetCameraOrientationByYawPitchRoll(0, cam.pitch, 0)
        occ.scene:SetCameraFieldOfView(2 * math.atan(self.decorLens.span / 2 / cam.f))
    end
    -- The lobby's up to its portal (the run starts before it), the run's once through it.
    local where = (s.lobby and s.distance < s.lobby.rim) and "lobby" or "run"
    local sink, behind = SINK[where], BEHIND[where]
    local placed = unchanged(last, "sink", sink)
    placed = unchanged(last, "behind", behind) and placed
    placed = unchanged(last, "curve", self.lastRoad.curve) and placed
    placed = unchanged(last, "fade", self.fade.from) and placed
    if placed and last.placed then
        return
    end
    last.placed = true
    for i = 1, occ.count do
        local actor = occ.actors[i]
        if not occ.scale[i] then
            local minX, minY, minZ, maxX, maxY, maxZ = self.Extents(actor)
            if minX then
                -- Its shorter side a little longer than TILE; its other measures with it (the
                -- scene's x runs along the road).
                local scale = TILE * OVERLAP / math.max(math.min(maxX - minX, maxY - minY), 0.01)
                occ.scale[i], occ.top[i] = scale, (maxZ - minZ) / 2 * scale
                occ.along[i], occ.across[i] = (maxX - minX) / 2 * scale, (maxY - minY) / 2 * scale
                actor:SetScale(scale)
            else
                -- Placed once it has loaded.
                last.placed = nil
            end
        end
        local scale = occ.scale[i]
        -- Within its bounds: from `behind` on (a row wholly behind it is not needed), within the
        -- solid ground to each side.
        local half = scale and occ.along[i]
        local d = scale and math.max(occ.d[i], behind + half)
        if scale and occ.d[i] + half > behind and d + half < self.fade.from then
            local x, side = occ.x[i], math.max(0, occ.width - occ.across[i])
            x = math.max(-side, math.min(side, x))
            -- Flat, it lies wholly under the ground: the ground is highest under the runner and
            -- falls away both ways, so over the tile it is lowest at one of its ends. The
            -- scene's y points left; positions are scaled with the actor.
            local low = math.min(ground(d - half), ground(d + half)) - sink
            actor:SetPosition(d / scale, -x / scale, (low - occ.top[i]) / scale)
            shapes.Show(actor)
        else
            shapes.Hide(actor)
        end
    end
end
