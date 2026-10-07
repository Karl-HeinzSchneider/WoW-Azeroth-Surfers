---@type string, table
local _, dev = ...
local app, log = dev.app, dev.log

-- The parts of a frame the overlay times with overlay:Lap while profiling.
local PARTS = {
    "simulation",
    "twin animation, models",
    "road placement",
    "twin",
    "ground scroll, decorations, obstacles",
    "boxes, coins",
    "texts",
}

-- /surfer profile: the first call starts timing each part of a frame, the second reports the
-- milliseconds per frame each took. Only the addon's own work: the cost of drawing what it shows
-- lands in the game's frame time, which the report sets beside it.
dev.Command("profile", "profile (twice): milliseconds per frame by part", function()
    local o = dev.Overlay()
    if not o then
        return
    end
    local timing = o.timing
    if not timing then
        o.timing = { frames = 0, started = debugprofilestop() }
        log:chat("Profiling: play for a while, then /surfer profile again.")
        return
    end
    o.timing = nil
    local frames = math.max(timing.frames, 1)
    local seconds = (debugprofilestop() - timing.started) / 1000
    local total = 0
    for _, part in ipairs(PARTS) do
        total = total + (timing[part] or 0)
    end
    log:chat(
        "%d frames in %.1f s: %.0f fps, %.2f ms per frame, of which the addon's Lua %.3f ms",
        frames,
        seconds,
        frames / seconds,
        seconds * 1000 / frames,
        total / frames
    )
    for _, part in ipairs(PARTS) do
        log:chat("  %-26s %.3f ms", part, (timing[part] or 0) / frames)
    end
    local scenes = (o.twin:IsShown() and 1 or 0) + (o.probeScene:IsShown() and 1 or 0)
    scenes = scenes + (o.worldScene:IsShown() and 1 or 0)
    log:chat(
        "Last frame: %d faces, %d 3D coins, %d decorations, %d boxes with models, %d model scenes shown, %d ground textures",
        o.faceCount or 0,
        o.coinCount or 0,
        #o.decor,
        #o.modelled,
        scenes,
        #o.ground
    )
end)

-- /surfer debug: the twin's camera and scene against the game's camera, the world scene's lens
-- against the road, and every model's measured bounds.
dev.Command("debug", "debug: cameras, lens calibration, model bounds", function()
    local o = dev.Overlay()
    if not o then
        return
    end
    local cam, ground = o.camera, app.shapes.Ground
    local settings, scene = app.db.profile.overlay, o.twin
    log:chat(
        "zoom %s (used %.2f), cameraFov %s, fov setting %d",
        tostring(GetCameraZoom and GetCameraZoom()),
        cam.distance or -1,
        tostring(GetCVar("cameraFov")),
        settings.fov
    )
    log:chat(
        "UI scale %.3f, scene scale %.3f, screen %.0f x %.0f, scene %.0f x %.0f",
        UIParent:GetEffectiveScale(),
        scene:GetEffectiveScale(),
        o.frame:GetWidth(),
        o.frame:GetHeight(),
        scene:GetWidth(),
        scene:GetHeight()
    )
    -- A point on the road's edge 20 yards ahead, the scene's in its own units.
    local lens = o.decorLens
    local x, y = o:Project(20, 4.3, ground(20))
    local px, py = o.worldScene:Project3DPointTo2D(o.sceneRunner + 20, -4.3, ground(20))
    log:chat(
        "world scene: span %s, calibrated %s, last ratio %s, scene scale %.3f, middle %s, %s",
        tostring(lens.span),
        tostring(lens.calibrated),
        tostring(lens.ratio),
        o.worldScene:GetEffectiveScale(),
        tostring(o.decorMiddleX),
        tostring(o.decorMiddleY)
    )
    log:chat(
        "road edge at 20 yd: road %.0f, %.0f (middle %.0f, %.0f), scene %s, %s",
        x or -1,
        y or -1,
        cam.cx,
        cam.cy,
        tostring(px),
        tostring(py)
    )
    -- Which way each model extends, as the client measured it (creatures as minus their display id).
    for model, b in pairs(o.modelBounds) do
        log:chat("model %d: x %.2f to %.2f, y %.2f to %.2f, z %.2f to %.2f", model, b[1], b[4], b[2], b[5], b[3], b[6])
    end
    local minX, minY, low, maxX, maxY, high = o.Extents(o.twinActor)
    log:chat(
        "twin loaded %s, bounds %s, scale %.2f; measured height %.2f, drawn at %.2f (reference %.2f), track %.2f times as big",
        tostring(o.twinActor:IsLoaded()),
        low and string.format("%.2f x %.2f x %.2f", maxX - minX, maxY - minY, high - low) or "none",
        o.twinActor:GetScale(),
        o.height,
        o.body,
        o.referenceHeight,
        o.bodyScale
    )
end)
