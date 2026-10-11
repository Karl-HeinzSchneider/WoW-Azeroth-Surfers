---@type string, AzerothSurfers
local _, app = ...
local sim = app.simulation
-- What the game shows in the middle of the view, over everything else:
-- * the status menu while a run is paused or over (menus.lua): the run's numbers, whether its
--   seed is kept, the next run's difficulty and what to do next (before a run: screens.lua's
--   main menu);
-- * announcements in zone-text style (`Announce`);
-- * a gate's flash and its portal's pull (the vortex: wind into the portal, edges closing in).
local overlay = app.overlay

local SIDE_SCALE = 0.8
local ANNOUNCE_SECONDS, FADE_IN, FADE_OUT = 2, 0.3, 0.7
local BANNER_SIDE_SCALE = 0.5
-- Full screen: the menus' top line (PlaceMessages). About half the pause menu's height, and the
-- room left for the buttons' row above it.
local MENU_RAISE, PAUSE_HALF, MENU_TOP = 0.12, 280, 48
local FLASH_ALPHA, FLASH_SECONDS = 0.85, 0.7
-- The pull, by the portal's distance from the camera (which goes through last): it builds from
-- VORTEX_FROM yards and fades over VORTEX_THROUGH after; in the last VORTEX_AROUND yards the
-- opening grows past the screen's edges.
local VORTEX_FROM, VORTEX_THROUGH, VORTEX_AROUND = 50, 14, 8
-- In screen sizes.
local VORTEX_AROUND_SIZE = 1.2
-- `approach` fades out over HUM_FADE milliseconds; `through` plays THROUGH_LEAD seconds early
-- (the teleport's whoosh builds up into it).
local HUM_FADE, THROUGH_LEAD = 1000, 0.4
local VORTEX_EDGES, VORTEX_EDGES_ALPHA = "Interface\\FullScreenTextures\\OutOfControl", 0.8
-- Radians a second, without pull and at the full pull.
local VORTEX_SPIN = { 1, 9 }
-- The wind's lines: count; from and to, length (at no and full pull) in opening sizes; head width
-- in pixels; trips a second (at no and full pull); the share of the spin they turn.
local WIND_LINES, WIND_FROM, WIND_TO = 28, 2.2, 0.15
local WIND_LENGTH, WIND_WIDTH, WIND_TRIPS, WIND_TWIST = { 0.25, 0.8 }, 3, { 0.5, 2.2 }, 0.12
-- Reused for the gradients (read only during the call).
local windTail, windHead
-- The zone text's colors: the zone's cream, a subzone's gold.
local CREAM = { 1, 0.9294, 0.7607 }
local GOLD = { 1, 0.82, 0 }

-- The status menu's pages (menus.lua describes pages and items), built anew for each pause and
-- each end of a run.
local GREEN = { 0.1, 1, 0.1 }
local GRAY = { 0.7, 0.7, 0.7 }

local function chosen()
    return sim.DIFFICULTIES[app.db.profile.difficulty] or sim.DIFFICULTIES.normal
end

-- The run's numbers.
local NUMBERS = {
    {
        text = function(o)
            local multiplier = o.state.multiplier
            return multiplier > 1 and string.format("Score  |cffff8c1ax%d|r", multiplier) or "Score"
        end,
        info = function(o)
            return tostring(sim.Score(o.state))
        end,
    },
    {
        text = "Coins",
        info = function(o)
            local s = o.state
            if s.coinTotal == 0 then
                return tostring(s.coins)
            end
            -- 100% only with every one.
            return string.format(
                "%d / %d  |cffaaaaaa%d%%|r",
                s.coins,
                s.coinTotal,
                math.floor(100 * s.coins / s.coinTotal)
            )
        end,
    },
    {
        text = "Distance",
        info = function(o)
            local s = o.state
            if s.finish then
                return string.format("%d / %d yd", math.floor(sim.Run(s)), s.finish - s.start)
            end
            return string.format("%d yd", math.floor(sim.Run(s)))
        end,
    },
    -- A challenge's: its own best.
    {
        text = "Best",
        info = function(o)
            local s = o.state
            if s.challenge then
                local best = app.challenges.Best(s.challenge)
                return best and tostring(best.score) or "0"
            end
            return tostring(app.db.global.bestScore)
        end,
    },
}

-- From the next run on: says so while it differs from the run's.
local DIFFICULTY = {
    text = function(o)
        return chosen() ~= o.state.difficulty and "Next run" or "Difficulty"
    end,
    choice = {
        get = function()
            return chosen().name
        end,
        can = function(_, dir)
            return sim.DIFFICULTIES[chosen().level + dir] ~= nil
        end,
        step = function(o, dir)
            o:StepDifficulty(dir)
        end,
    },
}

-- The seed: the kept one, else this run's. One typed in is kept for every run from now on.
local SEED = {
    text = "Seed",
    input = {
        get = function(o)
            return tostring(app.db.profile.seed or o.state.seed)
        end,
        set = function(o, typed)
            local seed = tonumber(typed)
            if seed then
                o:SetSeed(seed)
            end
        end,
    },
}
-- Keeps the seed above for every run from now on (the options' fixed seed), or a random one
-- each run.
local KEEP_SEED = {
    text = "Seed mode",
    choice = {
        get = function()
            return app.db.profile.seed and "Keep" or "Random each run"
        end,
        can = function(_, dir)
            return (dir > 0) ~= (app.db.profile.seed ~= false)
        end,
        step = function(o, dir)
            o:SetFixedSeed(dir > 0)
        end,
    },
}

-- Yards into the seed a run begins: one from the main menu (screens.lua) with its seed, and
-- with a fixed seed every restart.
local function startAt()
    return tostring(app.db.profile.startAt or 0)
end
local function setStartAt(o, typed)
    local yards = tonumber(typed)
    if yards then
        o:SetStartAt(yards)
    end
end
overlay.START_AT = { text = "Start at", input = { get = startAt, set = setStartAt } }
-- Here grayed out while every run draws a new seed: a restart begins there only with a kept one.
local START_AT = {
    text = "Start at",
    input = {
        get = startAt,
        set = setStartAt,
        can = function(o)
            return o:StartsAt()
        end,
    },
}

local function restart(o)
    if not InCombatLockdown() then
        o:Restart()
    end
end
local GO_ON = {
    text = "Go on",
    run = function(o)
        o:Action("P")
    end,
}
local AUTO = {
    text = "Auto mode",
    run = function(o)
        o:SetAuto(true)
    end,
}
local MENU = {
    text = "Main menu",
    run = function(o)
        o:OpenMenu()
    end,
}
local STOP = {
    text = "Stop auto mode",
    run = function(o)
        o:SetAuto(false)
    end,
}

local function page(title, ...)
    local items = {}
    for _, list in ipairs({ ... }) do
        for _, item in ipairs(list) do
            items[#items + 1] = item
        end
    end
    return { title = title, items = items }
end

-- A challenge's run (screens.lua's PlayChallenge): its seed, difficulty and where it begins are
-- the challenge's own; it ends at its last portal (or before).
local function challengePage(s)
    local name = s.challenge.kind.name .. " challenge"
    if s.status == "paused" then
        local p = page(name, NUMBERS, { GO_ON, { text = "Start over", run = restart }, MENU })
        p.back = GO_ON.run
        p.extra = { text = "Start over", run = restart }
        return p
    end
    local note = s.newBest and { text = "New best!", note = GREEN }
        or not s.finished and { text = "The last portal not reached", note = GRAY }
    local p = page(
        s.finished and "Challenge complete" or name,
        note and { note } or {},
        NUMBERS,
        { { text = "Try again", run = restart }, MENU }
    )
    p.back = MENU.run
    p.extra = { text = "Try again", run = restart }
    return p
end

-- The page for run `s`, or nil while it runs or is ready. In auto mode no key does anything:
-- only clicks.
local function statusPage(o, s)
    if s.challenge and not o.auto and (s.status == "paused" or s.status == "over") then
        return challengePage(s)
    elseif s.status == "paused" then
        if o.auto then
            return page("Paused", NUMBERS, { GO_ON, STOP })
        end
        local p = page(
            "Paused",
            NUMBERS,
            { GO_ON, { text = "Start over", run = restart }, SEED, KEEP_SEED, START_AT, DIFFICULTY, AUTO, MENU }
        )
        -- Q pauses and goes on in a run: here too.
        p.back = GO_ON.run
        p.extra = { text = "Start over", run = restart }
        return p
    elseif s.status == "over" then
        -- A run begun further into its seed ("Start at") saves no best score: says so.
        local best = s.newBest and { { text = "New best!", note = GREEN } }
            or s.practice and { { text = string.format("From %d yd: no best score", s.practice), note = GRAY } }
            or {}
        if o.auto then
            return page("Run complete", best, NUMBERS, { STOP })
        end
        local p = page(
            "Run complete",
            best,
            NUMBERS,
            { { text = "Run again", run = restart }, SEED, KEEP_SEED, START_AT, DIFFICULTY, AUTO, MENU }
        )
        p.back = MENU.run
        p.extra = { text = "Run again", run = restart }
        return p
    end
end

function overlay:CreateMessages(f)
    local holder = CreateFrame("Frame", nil, f)
    self:Stack(holder, "messages")
    holder:SetSize(1, 1)
    holder:Hide()
    self.statusMenu = self:CreateMenu(holder)
    self.statusHolder = holder

    local banner = CreateFrame("Frame", nil, f)
    self:Stack(banner, "messages")
    banner:SetSize(1, 1)
    banner:Hide()
    local small = banner:CreateFontString(nil, "OVERLAY", "SubZoneTextFont")
    small:SetPoint("BOTTOM", banner, "CENTER", 0, 4)
    small:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
    local text = banner:CreateFontString(nil, "OVERLAY", "ZoneTextFont")
    text:SetPoint("TOP", banner, "CENTER", 0, 0)
    text:SetTextColor(CREAM[1], CREAM[2], CREAM[3])
    self.banner = { frame = banner, text = text, small = small }

    local flash = CreateFrame("Frame", nil, f)
    self:Stack(flash, "flash")
    flash:SetAllPoints(f)
    flash:Hide()
    local glow = flash:CreateTexture(nil, "BACKGROUND")
    glow:SetAllPoints(flash)
    glow:SetColorTexture(1, 1, 1, 1)
    self.flash = { frame = flash, texture = glow }

    local vortex = CreateFrame("Frame", nil, f)
    self:Stack(vortex, "flash")
    vortex:SetAllPoints(f)
    vortex:Hide()
    local edges = vortex:CreateTexture(nil, "BACKGROUND")
    edges:SetAllPoints(vortex)
    edges:SetTexture(VORTEX_EDGES)
    -- Quads drawn by their corners (SetVertexOffset) from a point at the view's corner, so they
    -- can point any way.
    local lines, phases = {}, {}
    for i = 1, WIND_LINES do
        -- Scattered by a hash: a phase growing with the number would line them up in a spiral.
        local hash = math.sin(i * 12.9898) * 43758.5453
        phases[i] = hash - math.floor(hash)
        local line = vortex:CreateTexture(nil, "ARTWORK")
        line:SetColorTexture(1, 1, 1, 1)
        line:SetBlendMode("ADD")
        line:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
        line:SetSize(1, 1)
        lines[i] = line
    end
    windTail, windHead = CreateColor(1, 1, 1, 0), CreateColor(1, 1, 1, 1)
    self.vortex = {
        frame = vortex,
        parent = f,
        edges = edges,
        lines = lines,
        phases = phases,
        angle = 0,
        flow = 0,
    }
end

-- Full screen, the pause and end menus hang from one top line (the scorecard's beside them):
-- where the pause menu's top was when it was centred MENU_RAISE of the height above the
-- middle, at most MENU_TOP under the top (the buttons' row). The side window centres them.
function overlay:PlaceMessages(side, h, top)
    local panel, banner = self.statusHolder, self.banner.frame
    local menu = self.statusMenu.panel
    -- Offsets count in the frame's own scale.
    local scale = side and SIDE_SCALE or 1
    panel:SetScale(scale)
    panel:ClearAllPoints()
    panel:SetPoint("CENTER", self.frame, "CENTER", 0, (side and 0.05 or MENU_RAISE) * h / scale)
    menu:ClearAllPoints()
    if side then
        menu:SetPoint("CENTER", panel, "CENTER", 0, 0)
    else
        local y = math.min(MENU_RAISE * h + PAUSE_HALF, h / 2 + top - MENU_TOP)
        menu:SetPoint("TOP", self.frame, "CENTER", 0, y)
    end
    scale = side and BANNER_SIDE_SCALE or 1
    banner:SetScale(scale)
    banner:ClearAllPoints()
    banner:SetPoint("CENTER", self.frame, "CENTER", 0, (side and 0.25 or 0.3) * h / scale)
end

-- Once a frame: a new page when the run's status or the run changes; its values while shown.
function overlay:ShowStatus()
    local s = self.state
    if s.status == "running" and self.announced ~= s then
        self.announced = s
        -- A run from the lobby is welcomed through its portal.
        if not s.lobby then
            self:WelcomeBiome()
        end
    end
    if self.statusShown == s.status and self.statusState == s then
        if self.statusOpen then
            self.statusMenu:Show()
        end
        return
    end
    self.statusShown, self.statusState = s.status, s
    -- Auto mode's pause button: Go on while paused, nothing to pause between two runs.
    if self.auto then
        local pause = self.controlButtons[3]
        pause:SetText(s.status == "paused" and "Go on" or "Pause")
        pause:SetEnabled(s.status == "running" or s.status == "paused")
    end
    local page = statusPage(self, s)
    self.statusOpen = page ~= nil
    if page then
        self.statusMenu:Open(page)
    end
    self.statusHolder:SetShown(page ~= nil)
end

-- `small`: an optional line over it. Replaces an announcement still showing.
function overlay:Announce(text, seconds, small)
    local b = self.banner
    if not b then
        return
    end
    b.text:SetText(text)
    b.small:SetText(small or "")
    b.start, b.hold = GetTime(), seconds or ANNOUNCE_SECONDS
    b.frame:SetAlpha(0)
    b.frame:Show()
end

-- White when `color` is nil.
function overlay:Flash(color)
    local flash = self.flash
    if not flash then
        return
    end
    color = color or { 1, 1, 1 }
    flash.texture:SetColorTexture(color[1], color[2], color[3], 1)
    flash.start = GetTime()
    flash.frame:SetAlpha(FLASH_ALPHA)
    flash.frame:Show()
end

-- Once a frame, when the next gate (or the one just gone through) has a `vortex`: the wind
-- rushes into the opening, stronger as it nears, then spreads over the screen and fades.
function overlay:ShowVortex()
    local vortex = self.vortex
    if not vortex then
        return
    end
    local s = self.state
    local strips, looks = self.strips, self.stripLooks
    local look, ahead, transition, rim
    for i = 1, strips and #strips or 0 do
        local d = strips[i] - s.distance
        if d - self.camera.x < VORTEX_FROM and d - self.camera.x > -VORTEX_THROUGH and looks[i].vortex then
            look, ahead, transition, rim = looks[i].vortex, d, looks[i], strips[i]
            break
        end
    end
    self:PortalSounds(transition, rim, ahead and ahead - self.camera.x)
    local now = GetTime()
    local elapsed = now - (vortex.time or now)
    vortex.time = now
    if not look then
        if vortex.shown then
            vortex.frame:Hide()
            vortex.shown = false
        end
        return
    end
    if not vortex.shown then
        vortex.frame:Show()
        vortex.shown = true
    end

    local camera = self.camera.x
    local before = ahead - camera
    local pull = math.max(0, math.min(1, 1 - before / VORTEX_FROM)) ^ 1.4
    local past = math.max(0, math.min(1, -before / VORTEX_THROUGH))
    local fade = past * past * (3 - 2 * past)
    local around = math.max(0, math.min(1, 1 - before / VORTEX_AROUND))
    around = around * around * (3 - 2 * around)
    -- Also on the title, where the camera looks at the portal.
    if s.status == "running" or self.screen then
        vortex.angle = vortex.angle + elapsed * (VORTEX_SPIN[1] + (VORTEX_SPIN[2] - VORTEX_SPIN[1]) * pull)
        vortex.flow = vortex.flow + elapsed * (WIND_TRIPS[1] + (WIND_TRIPS[2] - WIND_TRIPS[1]) * pull)
    end
    -- Held where it still projects once the camera is nearly at it.
    local at = math.max(ahead, camera + VORTEX_AROUND / 2)
    local x, y, scale = self:Project(at, 0, app.shapes.Ground(at) + look.center)
    if not x then
        vortex.frame:Hide()
        vortex.shown = false
        return
    end
    local w, h = vortex.parent:GetSize()
    local size = 2 * look.radius * scale * (1 + 0.2 * pull)
    size = size + (VORTEX_AROUND_SIZE * math.max(w, h) - size) * around
    x, y = x + (w / 2 - x) * around, y + (h / 2 - y) * around
    local strength = pull * (1 - fade)
    -- Not on a screen: they would darken the whole view.
    vortex.edges:SetAlpha(self.screen and 0 or strength * VORTEX_EDGES_ALPHA)
    self:ShowWind(x, y, size, pull, strength, look.color)
end

-- Each once a gate and only while running; `through` when the portal is `before` yards ahead.
function overlay:PortalSounds(transition, rim, before)
    local vortex, s = self.vortex, self.state
    local sounds = transition and transition.sounds
    if not sounds or s.status ~= "running" then
        if vortex.hum then
            StopSound(vortex.hum, HUM_FADE)
            vortex.hum = nil
        end
        return
    end
    if vortex.soundState ~= s or vortex.soundRim ~= rim then
        vortex.soundState, vortex.soundRim, vortex.hummed, vortex.through = s, rim, false, false
    end
    local on = app.db.profile.portalSound
    if sounds.approach and not vortex.hummed then
        vortex.hummed = true
        if on then
            local _, handle = PlaySoundFile(sounds.approach, "SFX")
            vortex.hum = handle
        end
    end
    if sounds.through and not vortex.through and before < s.speed * THROUGH_LEAD then
        vortex.through = true
        if on then
            PlaySoundFile(sounds.through, "SFX")
        end
    end
end

-- The lines into the opening at (`x`, `y`), `size` across, the golden angle apart.
function overlay:ShowWind(x, y, size, pull, strength, color)
    local vortex = self.vortex
    local length = size * (WIND_LENGTH[1] + (WIND_LENGTH[2] - WIND_LENGTH[1]) * pull)
    local half = WIND_WIDTH / 2
    local r, g, b = (color[1] + 1) / 2, (color[2] + 1) / 2, (color[3] + 1) / 2
    for i, line in ipairs(vortex.lines) do
        local trip = (vortex.flow + vortex.phases[i]) % 1
        local angle = i * 2.399963 + vortex.angle * WIND_TWIST
        local ux, uy = math.cos(angle), math.sin(angle)
        local head = size * (WIND_FROM - (WIND_FROM - WIND_TO) * trip)
        local tail = head + length
        -- The tail (left of the texture) is a point.
        local tx, ty = x + ux * tail, y + uy * tail
        local hx, hy = x + ux * head, y + uy * head
        local nx, ny = -uy * half, ux * half
        -- From the 1 by 1 square at the view's corner: upper left, lower left, upper right,
        -- lower right.
        line:SetVertexOffset(1, tx, ty - 1)
        line:SetVertexOffset(2, tx, ty)
        line:SetVertexOffset(3, hx + nx - 1, hy + ny - 1)
        line:SetVertexOffset(4, hx - nx - 1, hy - ny)
        local alpha = strength * math.sin(math.pi * trip)
        windTail:SetRGBA(r, g, b, 0)
        windHead:SetRGBA(r, g, b, alpha)
        line:SetGradient("HORIZONTAL", windTail, windHead)
    end
end

function overlay:ShowFlash()
    local flash = self.flash
    if not flash or not flash.start then
        return
    end
    local t = GetTime() - flash.start
    if t >= FLASH_SECONDS then
        flash.start = nil
        flash.frame:Hide()
        return
    end
    flash.frame:SetAlpha(FLASH_ALPHA * (1 - t / FLASH_SECONDS))
end

function overlay:WelcomeBiome()
    self:Announce(self.biome.name, nil, "Welcome to")
end

function overlay:ShowBanner()
    local b = self.banner
    if not b.start then
        return
    end
    -- GetTime() is the frame's time: an announcement made this frame starts at 0, invisible.
    local t = GetTime() - b.start
    if t >= FADE_IN + b.hold + FADE_OUT then
        b.start = nil
        b.frame:Hide()
        return
    end
    local alpha
    if t < FADE_IN then
        alpha = t / FADE_IN
    elseif t < FADE_IN + b.hold then
        alpha = 1
    else
        alpha = 1 - (t - FADE_IN - b.hold) / FADE_OUT
    end
    b.frame:SetAlpha(alpha)
end
