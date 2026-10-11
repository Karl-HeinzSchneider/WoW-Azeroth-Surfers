---@type string, table
local _, dev = ...
local app, log = dev.app, dev.log
local TIMEOUT = 5
local rows, queue, current, elapsed, index = {}, {}, nil, 0, 0
local scene, actor, model, driver, window, soundHandle
local animationLoaded = false
local mode = "all"

-- These are the few assets/animations local to game code rather than biome data.
-- Keep in sync with overlay.lua, occluder.lua, controls.lua and messages.lua.
local PLAYER_ANIMATIONS = { 0, 4, 5, 13, 37, 38, 39, 666 }
local function each(value, callback)
    if type(value) == "table" then
        for _, entry in pairs(value) do
            each(entry, callback)
        end
    elseif type(value) == "number" or type(value) == "string" then
        callback(value)
    end
end

local function catalog(scope)
    local found, list = {}, {}
    local function add(kind, id, path, animation)
        local key = kind .. ":" .. tostring(id)
        local row = found[key]
        if not row then
            row = { kind = kind, id = id, sources = {}, animations = {}, status = "pending" }
            found[key], list[#list + 1] = row, row
        end
        row.sources[path] = true
        if animation then
            row.animations[animation] = true
        end
        return row
    end
    local function sounds(value, path)
        each(value, function(id)
            add("sound", id, path)
        end)
    end
    local function walk(value, path)
        if type(value) ~= "table" then
            return
        end
        each(value.model, function(id)
            add("model", id, path .. ".model")
        end)
        each(value.creature, function(id)
            local row = add(
                "creature",
                id,
                path .. ".creature",
                value.animation or (path:find(".ambient.", 1, true) and 5 or 0)
            )
            if value.attack then
                row.animations[value.attack] = true
            end
        end)
        for key, child in pairs(value) do
            local source = path .. "." .. tostring(key)
            if key == "sound" or key == "voice" or key == "finale" or key == "sounds" or key == "music" then
                sounds(child, source)
            elseif key == "footsteps" then
                sounds(child.ground, source .. ".ground")
                sounds(child.wood, source .. ".wood")
            elseif type(child) == "table" then
                walk(child, source)
            end
        end
    end
    for id in pairs(app.biomes.list) do
        if scope == "all" or scope == id then
            local biome = app.biomes.Get(id)
            walk(biome, "biomes." .. id)
            local transition = app.biomes.Transition(biome.entrance)
            if transition then
                walk(transition, "transitions." .. tostring(biome.entrance))
            end
        end
    end
    if scope == "all" then
        walk(app.biomes.transitions, "transitions")
        walk(app.lobby, "lobby")
    end
    for _, animation in ipairs(PLAYER_ANIMATIONS) do
        add("player", "player", "game.overlay", animation)
    end
    add("player", "player", "lobby.seat.sit", app.lobby.seat.sit)
    add("player", "player", "lobby.seat.standUp", app.lobby.seat.standUp)
    add("model", 198435, "game.occluder")
    add("sound", 567428, "game.controls.coinFallback")
    add("sound", 567431, "game.messages.finish")
    table.sort(list, function(a, b)
        if a.kind ~= b.kind then
            return a.kind < b.kind
        end
        return tostring(a.id) < tostring(b.id)
    end)
    return list
end

local function sources(row)
    local list = {}
    for path in pairs(row.sources) do
        list[#list + 1] = path
    end
    table.sort(list)
    return list
end

local function stop()
    if current then
        current.status, current.detail = "cancelled", "Scan stopped before this asset finished"
    end
    current = nil
    if driver then
        driver:Hide()
        actor:ClearModel()
        model:ClearModel()
        scene:Hide()
        model:Hide()
    end
    if soundHandle then
        StopSound(soundHandle)
        soundHandle = nil
    end
end

local function finish(status, detail)
    current.status, current.detail = status, detail
    if status ~= "ok" then
        log:chat("Assets: %s %s: %s (%s)", current.kind, tostring(current.id), detail, sources(current)[1])
    end
    current = nil
end

local function nextAsset()
    index = index + 1
    current, elapsed, animationLoaded = queue[index], 0, false
    if not current then
        local ok, suspect = 0, 0
        for _, row in ipairs(queue) do
            if row.status == "ok" then
                ok = ok + 1
            else
                suspect = suspect + 1
            end
        end
        stop()
        log:chat(
            "Assets complete: %d checked, %d accepted, %d need review. /surfers assets report",
            #queue,
            ok,
            suspect
        )
        return
    end
    current.status = "checking"
    if current.kind == "sound" then
        local success, accepted, handle = pcall(PlaySoundFile, current.id, "SFX")
        if success and handle then
            StopSound(handle)
        end
        finish(
            success and accepted and "ok" or "review",
            success and accepted and "Playback accepted (not an audibility check)"
                or "Playback failed: missing file, muted audio or channel limit; retry/listen"
        )
        return
    end
    actor:ClearModel()
    model:ClearModel()
    local success, accepted
    if current.kind == "model" then
        success, accepted = pcall(actor.SetModelByFileID, actor, current.id)
    elseif current.kind == "creature" then
        success, accepted = pcall(actor.SetModelByCreatureDisplayID, actor, current.id)
    else
        success, accepted = pcall(actor.SetModelByUnit, actor, "player", true, true, false, true)
    end
    if not success or accepted == false then
        finish("review", "Model request rejected: " .. tostring(accepted))
        return
    end
    if mode ~= "models" and next(current.animations) then
        local loaded, err
        if current.kind == "player" then
            loaded, err = pcall(model.SetUnit, model, "player")
        else
            loaded, err = pcall(model.SetDisplayInfo, model, current.id)
        end
        if not loaded then
            finish("review", "Animation probe failed: " .. tostring(err))
        end
    end
end

local function update(_, dt)
    if not current then
        nextAsset()
        return
    end
    elapsed = elapsed + dt
    if not actor:IsLoaded() then
        if elapsed >= TIMEOUT then
            finish("review", "Model load timed out after 5s; retry on a warm cache")
        end
        return
    end
    local file = actor:GetModelFileID()
    if current.kind == "model" and file ~= current.id then
        finish("review", "Requested file differs from loaded file " .. tostring(file) .. " (possible fallback model)")
        return
    end
    if mode ~= "models" and next(current.animations) then
        if not animationLoaded or model:GetModelFileID() ~= file then
            if elapsed >= TIMEOUT then
                finish("review", "Model loaded, but animation probe timed out or loaded a different file")
            end
            return
        end
        local missing = {}
        for animation in pairs(current.animations) do
            if not model:HasAnimation(animation) then
                missing[#missing + 1] = animation
            end
        end
        table.sort(missing)
        if #missing > 0 then
            finish("review", "Missing animation IDs: " .. table.concat(missing, ", "))
            return
        end
    end
    finish(
        "ok",
        "Model loaded; requested animations checked where applicable. Visual appearance/animation variations need preview."
    )
end

local function report(all)
    if window then
        window:Release()
    end
    local gui = LibStub("AceGUI-3.0")
    window = gui:Create("Frame")
    window:SetTitle("Azeroth Surfers asset audit")
    window:SetLayout("Fill")
    window:SetWidth(850)
    window:SetHeight(550)
    window:SetCallback("OnClose", function(widget)
        widget:Release()
        window = nil
    end)
    local text = gui:Create("MultiLineEditBox")
    text:SetLabel("Copy with Ctrl+A, Ctrl+C. /surfers assets report all includes accepted assets.")
    text:DisableButton(true)
    local version, build, _, interface = GetBuildInfo()
    local lines = { string.format("Client %s build %s interface %s", version, build, interface) }
    for i, row in ipairs(rows) do
        if all or (row.status ~= "ok" and row.status ~= "skipped") then
            lines[#lines + 1] = string.format(
                "#%d %s %s [%s]: %s",
                i,
                row.kind,
                tostring(row.id),
                row.status,
                row.detail or "Not checked yet"
            )
            for _, path in ipairs(sources(row)) do
                lines[#lines + 1] = "  " .. path
            end
        end
    end
    lines[#lines + 1] =
        "Loaded does not prove visible: error models, placement, scale and occlusion need visual inspection."
    lines[#lines + 1] =
        "HasAnimation checks IDs, not variations or appearance. Player checks cover only your current character."
    lines[#lines + 1] = "Sound failures are inconclusive. Enable SFX and use /surfers assets listen <report number>."
    text:SetText(table.concat(lines, "\n"))
    window:AddChild(text)
end

local USAGE = "assets [all|models|animations|sounds] [all|biome] | report [all] | listen <report number> | stop"
dev.Command("assets", USAGE, function(rest)
    local words = dev.Words(rest)
    local action, scope = words[1] or "all", words[2] or "all"
    if action == "stop" then
        stop()
        log:chat("Asset audit stopped; partial results: /surfers assets report")
        return
    elseif action == "report" then
        report(words[2] == "all")
        return
    elseif action == "listen" then
        local row = rows[tonumber(words[2]) or 0]
        if not row or row.kind ~= "sound" then
            log:chat("Use a sound's #number from /surfers assets report all.")
            return
        end
        stop()
        local ok, accepted, handle = pcall(PlaySoundFile, row.id, "SFX")
        soundHandle = ok and handle or nil
        log:chat(
            "Sound %s: %s. /surfers assets stop ends playback.",
            tostring(row.id),
            ok and accepted and "playing on SFX" or "playback failed"
        )
        return
    end
    if
        (action ~= "all" and action ~= "models" and action ~= "animations" and action ~= "sounds")
        or (scope ~= "all" and not app.biomes.list[scope])
    then
        log:chat("/surfers " .. USAGE)
        return
    end
    stop()
    mode, rows, queue, index = action, catalog(scope), {}, 0
    for _, row in ipairs(rows) do
        if
            action == "all"
            or (action == "sounds" and row.kind == "sound")
            or (action == "models" and row.kind ~= "sound")
            or (action == "animations" and next(row.animations))
        then
            queue[#queue + 1] = row
        else
            row.status, row.detail = "skipped", "Outside this scan's category"
        end
    end
    if not driver then
        scene = CreateFrame("ModelScene", nil, UIParent)
        scene:SetSize(1, 1)
        scene:SetPoint("BOTTOMLEFT")
        scene:SetAlpha(0)
        actor = scene:CreateActor()
        model = CreateFrame("PlayerModel", nil, UIParent)
        model:SetSize(1, 1)
        model:SetPoint("BOTTOMLEFT")
        model:SetAlpha(0)
        model:SetScript("OnModelLoaded", function()
            animationLoaded = true
        end)
        driver = CreateFrame("Frame")
        driver:SetScript("OnUpdate", update)
    end
    scene:Show()
    actor:Show()
    model:Show()
    driver:Show()
    log:chat("Auditing %d assets (%s/%s), up to 5s per model. /surfers assets stop cancels.", #queue, action, scope)
    if action == "all" or action == "sounds" then
        log:chat(
            "Sound probes briefly request playback on SFX, then stop it. Disabled audio can cause inconclusive failures."
        )
    end
end)
