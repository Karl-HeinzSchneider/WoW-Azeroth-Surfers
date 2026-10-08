---@type string, Surfer
local _, app = ...
-- The light for everything the addon draws, by the game's clock (the world's own light cannot be
-- read): white by day, the biome's night light at night, dawn 5-7, dusk 19-21. Model scenes
-- register once and are relit on a change; anything else reads `r`, `g`, `b` when `Update`
-- reports one.
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
