---@type string, table
local _, dev = ...
local app, log = dev.app, dev.log
-- /surfers preview: a model or creature standing in the middle lane a few yards ahead, at its own
-- size, to judge it for a biome: its measured size in chat, turned at will, and a creature
-- cycling through dev.ANIMATIONS unless one is asked for. `player`: your own character, with your
-- gear, cycling through dev.CROUCH.

local AHEAD, CYCLE = 8, 2.5
-- The one being shown: its pool key (a file id, minus a creature display id, or "player"), actor,
-- name, turn, and the animations it cycles through (none: it holds one).
local shown
-- Your character's actor, kept apart from the pool: loaded from the unit, not an id.
local playerActor

local function stop()
    if shown then
        if shown.key == "player" then
            shown.actor:Hide()
        else
            app.overlay:ReleaseActor(shown.key, shown.actor)
        end
        shown = nil
    end
end

local function play(index)
    local animation = shown.cycle[index]
    shown.actor:SetAnimation(animation[1], 0, 1, 0)
    log:chat("%s: animation %d (%s)", shown.name, animation[1], animation[2])
end

local function turn(degrees)
    shown.yaw = math.rad(degrees)
    shown.actor:SetYaw(shown.yaw)
    shown.measured = false
end

local function acquire(key)
    if key ~= "player" then
        return app.overlay:AcquireActor(key)
    end
    if not playerActor then
        playerActor = app.overlay.worldScene:CreateActor()
    end
    -- Again each time: the gear may have changed since.
    playerActor:SetModelByUnit("player", true, true, false, true)
    playerActor:Show()
    return playerActor
end

local function show(key, name, animation, degrees, cycle)
    stop()
    local actor = acquire(key)
    -- A pooled actor keeps what its last owner set.
    actor:SetUseCenterForOrigin(false, false, false)
    actor:SetScale(1)
    actor:SetAlpha(1)
    actor:SetPitch(0)
    shown = { key = key, actor = actor, name = name, clock = 0, index = 1 }
    turn(degrees)
    if animation then
        actor:SetAnimation(animation, 0, 1, 0)
        log:chat("%s: animation %d", name, animation)
    elseif cycle then
        shown.cycle = cycle
        play(1)
    end
end

local frame = CreateFrame("Frame")
frame:SetScript("OnUpdate", function(_, elapsed)
    local o = app.overlay
    if not shown or not o.frame or not o.frame:IsShown() then
        return
    end
    local bounds = o:ModelBounds(shown.actor, shown.key)
    if not bounds then
        return
    end
    if not shown.measured then
        shown.measured = true
        shown.shiftX, shown.shiftY = o.TurnShift(bounds, shown.yaw)
        log:chat(
            "%s: %.2f long (x), %.2f wide (y), %.2f tall (z %.2f to %.2f)",
            shown.name,
            bounds[4] - bounds[1],
            bounds[5] - bounds[2],
            bounds[6] - bounds[3],
            bounds[3],
            bounds[6]
        )
    end
    -- The world scene's camera runs along the track (FollowWorldCamera): ahead of it.
    shown.actor:SetPosition(app.overlay.sceneRunner + AHEAD + shown.shiftX, shown.shiftY, app.shapes.Ground(AHEAD))
    if shown.cycle then
        shown.clock = shown.clock + elapsed
        if shown.clock > CYCLE then
            shown.clock = 0
            shown.index = shown.index % #shown.cycle + 1
            play(shown.index)
        end
    end
end)

local USAGE = "preview creature <display id> [animation] | model <file id> [animation] | player [animation]"
    .. " | turn <degrees> | off"

dev.Command("preview", USAGE, function(rest)
    local words = dev.Words(rest)
    local what, id, animation = words[1], words[2], words[3]
    if what == "off" then
        stop()
    elseif what == "turn" and shown and type(id) == "number" then
        turn(id)
    elseif what == "player" then
        if not dev.Overlay() then
            return
        end
        -- Side on, as it would pass under an obstacle; `turn` shows it from elsewhere.
        show("player", "your character", type(id) == "number" and id or nil, 90, dev.CROUCH)
    elseif what == "creature" and type(id) == "number" then
        -- Facing the runner, as enemies do.
        show(-id, "creature " .. id, animation, 180, dev.ANIMATIONS)
    elseif what == "model" and type(id) == "number" then
        show(id, "model " .. id, animation, 0)
    else
        log:chat("/surfers " .. USAGE)
    end
end)
