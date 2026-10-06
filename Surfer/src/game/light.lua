---@type string, Surfer
local _, app = ...
-- The world's light for everything the addon draws. The game's own light cannot be read, so it
-- follows the game's clock: white by day, the biome's night light at night, with dawn from 5
-- to 7 and dusk from 19 to 21 (`profile.overlay.dayNight` keeps it at day). 3D models register
-- their scene once with its colors by day and are relit on every change; anything else reads
-- `r`, `g`, `b` after `Update` reports a change.
local light = { r = 1, g = 1, b = 1, scenes = {} }
app.light = light

-- 1 by day, 0 at night, in between at dawn and dusk; `override` fixes it (Surfer_Dev).
local function daylight()
    if light.override then
        return light.override
    end
    if not app.db.profile.overlay.dayNight or not GetGameTime then
        return 1
    end
    local hour, minute = GetGameTime()
    local t = hour + minute / 60
    return math.min(1, math.max(0, (t - 5) / 2)) - math.min(1, math.max(0, (t - 19) / 2))
end

local function apply(entry)
    local scene, ambient, diffuse = entry.scene, entry.ambient, entry.diffuse
    scene:SetLightAmbientColor(ambient[1] * light.r, ambient[2] * light.g, ambient[3] * light.b)
    scene:SetLightDiffuseColor(diffuse[1] * light.r, diffuse[2] * light.g, diffuse[3] * light.b)
end

-- A ModelScene lit like the world: `ambient` and `diffuse` are its colors by day, {r, g, b}.
-- Adding a scene again changes its colors.
function light.AddScene(scene, ambient, diffuse)
    local entry
    for _, e in ipairs(light.scenes) do
        if e.scene == scene then
            entry = e
        end
    end
    if not entry then
        entry = { scene = scene }
        light.scenes[#light.scenes + 1] = entry
    end
    entry.ambient, entry.diffuse = ambient, diffuse
    apply(entry)
end

-- The biome's light at midnight, {r, g, b}; the next Update relights everything with it.
function light.SetNight(night)
    light.night, light.day = night, nil
end

-- Once a frame: relights the scenes and tells whether the light changed, at most once a game
-- minute.
function light.Update()
    local day, night = daylight(), light.night
    if day == light.day or not night then
        return false
    end
    light.day = day
    light.r = night[1] + (1 - night[1]) * day
    light.g = night[2] + (1 - night[2]) * day
    light.b = night[3] + (1 - night[3]) * day
    for _, entry in ipairs(light.scenes) do
        apply(entry)
    end
    return true
end
