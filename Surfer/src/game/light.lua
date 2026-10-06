---@type string, Surfer
local _, app = ...
-- The world's light for everything the addon draws. The game's own light cannot be read, so it
-- follows the game's clock: white by day, dimmed to a moonlit blue at night, with dawn from 5
-- to 7 and dusk from 19 to 21 (`profile.overlay.dayNight` keeps it at day). 3D models register
-- their scene once with its colors by day and are relit on every change; anything else reads
-- `r`, `g`, `b` after `Update` reports a change.
local light = { r = 1, g = 1, b = 1, scenes = {} }
app.light = light

local NIGHT = { 0.45, 0.5, 0.7 }

-- 1 by day, 0 at night, in between at dawn and dusk.
local function daylight()
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
function light.AddScene(scene, ambient, diffuse)
    local entry = { scene = scene, ambient = ambient, diffuse = diffuse }
    light.scenes[#light.scenes + 1] = entry
    apply(entry)
end

-- Once a frame: relights the scenes and tells whether the light changed, at most once a game
-- minute.
function light.Update()
    local day = daylight()
    if day == light.day then
        return false
    end
    light.day = day
    light.r = NIGHT[1] + (1 - NIGHT[1]) * day
    light.g = NIGHT[2] + (1 - NIGHT[2]) * day
    light.b = NIGHT[3] + (1 - NIGHT[3]) * day
    for _, entry in ipairs(light.scenes) do
        apply(entry)
    end
    return true
end
