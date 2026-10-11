---@type string, table
local _, dev = ...
local app, log = dev.app, dev.log

dev.Command("minimap", "minimap (report the icon's persistent model state)", function()
    local module = app.minimapButton
    local button, gem = module.button, module.gem
    log:chat(
        "Minimap: enabled=%s button=%s visible=%s scene=%s texture=%s iconAlpha=%s",
        tostring(module.modelEnabled),
        tostring(button and button:GetName()),
        tostring(button and button:IsVisible()),
        tostring(gem ~= nil),
        tostring(button and button.icon:GetTexture()),
        tostring(button and button.icon:GetAlpha())
    )
    if gem then
        log:chat(
            "Gem: requested=%s result=%s loaded=%s file=%s ready=%s wait=%.2fs failure=%s visible=%s alpha=%.2f",
            tostring(gem.model),
            tostring(gem.requestResult),
            tostring(gem.actor:IsLoaded()),
            tostring(gem.actor:GetModelFileID()),
            tostring(gem.ready),
            gem.wait,
            tostring(gem.failure),
            tostring(gem.scene:IsVisible()),
            gem.scene:GetAlpha()
        )
    end
end)

-- Read-only snapshot; no UI is opened or restacked to collect it.
local UI_FRAMES = {
    "UIParent",
    "PlayerFrame",
    "TargetFrame",
    "FocusFrame",
    "PetFrame",
    "TargetFrameToT",
    "MainMenuBar",
    "MainActionBar",
    "MultiBarBottomLeft",
    "MultiBarBottomRight",
    "MultiBarLeft",
    "MultiBarRight",
    "MultiBar5",
    "MultiBar6",
    "MultiBar7",
    "PetActionBarFrame",
    "PetActionBar",
    "StanceBarFrame",
    "StanceBar",
    "OverrideActionBar",
    "ExtraActionBarFrame",
    "ActionButton1",
    "MultiBarBottomLeftButton1",
    "MicroButtonAndBagsBar",
    "BagsBar",
    "MainMenuBarBackpackButton",
    "CharacterBag0Slot",
    "ContainerFrameCombinedBags",
    "BankFrame",
    "GeneralDockManager",
    "ChatFrameMenuButton",
}
local STRATA = {
    WORLD = 0,
    BACKGROUND = 1,
    LOW = 2,
    MEDIUM = 3,
    HIGH = 4,
    DIALOG = 5,
    FULLSCREEN = 6,
    FULLSCREEN_DIALOG = 7,
    TOOLTIP = 8,
}

dev.Command("layers", "layers [FrameName]: UI strata and levels, or a named frame and its children", function(rest)
    local rows, seen = {}, {}
    local function add(frame, label)
        if not frame or not frame.GetFrameStrata or not frame.GetFrameLevel or seen[frame] then
            return
        end
        seen[frame] = true
        local parent = frame:GetParent()
        rows[#rows + 1] = {
            name = frame:GetName() or label,
            strata = frame:GetFrameStrata(),
            level = frame:GetFrameLevel(),
            visible = frame:IsVisible(),
            parent = parent and (parent:GetName() or "unnamed") or "none",
        }
    end
    local name = (rest or ""):match("^%s*(%S+)")
    if name then
        local frame = _G[name]
        if not frame or not frame.GetFrameStrata then
            log:chat("No frame named %s (names are case-sensitive).", name)
            return
        end
        add(frame, name)
        for i, child in ipairs({ frame:GetChildren() }) do
            add(child, name .. ".child" .. i)
        end
    else
        for _, frameName in ipairs(UI_FRAMES) do
            add(_G[frameName], frameName)
        end
        for i = 1, NUM_CONTAINER_FRAMES or 13 do
            local frameName = "ContainerFrame" .. i
            add(_G[frameName], frameName)
        end
        local function chat(frameName)
            for _, suffix in ipairs({ "", "Tab", "EditBox", "ButtonFrame" }) do
                add(_G[frameName .. suffix], frameName .. suffix)
            end
        end
        for _, frameName in ipairs(CHAT_FRAMES or {}) do
            chat(frameName)
        end
        for i = 1, NUM_CHAT_WINDOWS or 10 do
            chat("ChatFrame" .. i)
        end
        local o = app.overlay
        if o then
            add(o.frame, "Surfers.view")
            for frame, place in pairs(o.stacked or {}) do
                add(frame, "Surfers." .. place)
            end
        end
    end
    table.sort(rows, function(a, b)
        local ar, br = STRATA[a.strata] or -1, STRATA[b.strata] or -1
        if ar ~= br then
            return ar < br
        elseif a.level ~= b.level then
            return a.level < b.level
        end
        return a.name < b.name
    end)
    log:chat("UI layers, back to front (%d frames). Strata first, then level; ties have no guaranteed order.", #rows)
    for _, row in ipairs(rows) do
        log:chat(
            "%s %d | %s | %s | parent %s",
            row.strata,
            row.level,
            row.name,
            row.visible and "visible" or "hidden",
            row.parent
        )
    end
    log:chat("Only existing frames are listed. Open bags/chat panels and run again to include them.")
end)

-- The parts of a frame the overlay times with overlay:Lap while profiling.
local PARTS = {
    "simulation",
    "twin animation, models",
    "road placement",
    "ground scroll, decorations, obstacles, wildlife",
    "twin",
    "boxes, coins",
    "texts",
}

-- /surfers profile: the first call starts timing each part of a frame, the second reports the
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
        log:chat("Profiling: play for a while, then /surfers profile again.")
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
    local scenes = (o.worldScene:IsShown() and 1 or 0) + (o.probeScene:IsShown() and 1 or 0)
    scenes = scenes + (o.occluder and o.occluder.scene:IsShown() and 1 or 0)
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

-- /surfers debug: the road's camera against the game's camera, the world scene's lens against
-- the road, the twin's square on the screen, and every model's measured bounds.
dev.Command("debug", "debug: cameras, lens calibration, model bounds", function()
    local o = dev.Overlay()
    if not o then
        return
    end
    local cam, ground = o.camera, app.shapes.Ground
    local settings, scene = app.db.profile.overlay, o.twinAnchor
    log:chat(
        "zoom %s (used %.2f), cameraFov %s, fov setting %d",
        tostring(GetCameraZoom and GetCameraZoom()),
        cam.distance or -1,
        tostring(GetCVar("cameraFov")),
        settings.fov
    )
    log:chat(
        "UI scale %.3f, twin square scale %.3f, screen %.0f x %.0f, twin square %.0f x %.0f",
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

-- On-screen distance (UI units) between two points projected by `scene`, in the scene's own
-- coordinates; nil while it cannot project.
local function projected(scene, x1, y1, z1, x2, y2, z2)
    local ax, ay = scene:Project3DPointTo2D(x1, y1, z1)
    local bx, by = scene:Project3DPointTo2D(x2, y2, z2)
    if type(ax) ~= "number" or type(bx) ~= "number" then
        return nil
    end
    return math.sqrt((bx - ax) ^ 2 + (by - ay) ^ 2) / scene:GetEffectiveScale()
end

-- /surfers twinsize: how big the twin is drawn on the screen (its model's height at its scale, in
-- the world scene) against the road's projection of the body it stands for: overlay.lua's
-- TWIN_SIZE times the twin size setting. During a run (the twin is placed).
dev.Command("twinsize", "twinsize: the twin's size on the screen against the road's projection of its body", function()
    local o = dev.Overlay()
    if not o then
        return
    end
    if o.seated or not o.twinActor:IsShown() then
        log:chat("Start a run first: the twin is not placed while the character sits at the fire.")
        return
    end
    local _, _, low, _, _, high = o.Extents(o.twinActor)
    if not low then
        log:chat("The twin's model has not loaded yet.")
        return
    end
    local s, cam = o.state, o.camera
    local lane = app.simulation.geometry.laneWidth
    local tall = (high - low) * o.twinActor:GetScale()
    local feet = cam.feet
    -- The world scene: the runner at sceneRunner, its lane on the scene's y (pointing left).
    local x, y = o.sceneRunner, s.lateral * lane
    local drawn = projected(o.worldScene, x, y, feet, x, y, feet + tall)
    -- The road's projection of the body: screen-right of the middle.
    local _, footY = o:Project(0, -s.lateral * lane, feet)
    local _, topY = o:Project(0, -s.lateral * lane, feet + o.body)
    local road = footY and topY and math.abs(topY - footY)
    log:chat(
        "Twin drawn %.2f yards tall (model %.2f at scale %.3f), body %.2f; on the screen %s against %s (UI units)",
        tall,
        high - low,
        o.twinActor:GetScale(),
        o.body,
        drawn and string.format("%.1f", drawn) or "n/a",
        road and string.format("%.1f", road) or "n/a"
    )
    log:chat(
        "twin / body %s (expected about %.3f: sqrt(2) times the twin size setting %.2f)",
        (drawn and road and road > 0) and string.format("%.4f", drawn / road) or "n/a",
        math.sqrt(2) * app.db.profile.overlay.twinScale,
        app.db.profile.overlay.twinScale
    )
end)
