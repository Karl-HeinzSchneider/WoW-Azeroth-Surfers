-- Exercise the actual local normalizer without creating any client UI frames.
local app = {}
assert(loadfile("Surfer/src/game/simulation.lua"))("Surfer", app)
assert(loadfile("Surfer/src/game/shapes.lua"))("Surfer", app)
assert(loadfile("Surfer/src/game/window.lua"))("Surfer", app)
local normalize
for i = 1, 30 do
    local name, value = debug.getupvalue(app.runner.Render, i)
    if not name then
        break
    end
    if name == "normalize" then
        normalize = value
        break
    end
end
assert(normalize, "Render must use the tested normalizer")
local actor = { loaded = true }
function actor:IsLoaded()
    return self.loaded
end
function actor:GetActiveBoundingBox()
    return -0.646075, -0.395915, -0.006005, 0.164332, 0.383174, 1.336797
end
function actor:SetScale(scale)
    self.scale = scale
end
local offset = normalize(actor, 2)
assert(math.abs(actor.scale * (1.336797 + 0.006005) - 2) < 0.000001)
assert(math.abs(offset - 0.006005 * actor.scale) < 0.000001)
print("PASS six-scalar bounding box from Forever error report")
actor.loaded = false
actor.scale = nil
assert(normalize(actor, 2) == nil and actor.scale == nil)
print("PASS unloaded model waits without setting scale")
actor.loaded = true
function actor:GetActiveBoundingBox()
    return 0, 0, 0, 0, 0, 0
end
assert(normalize(actor, 2) == nil and actor.scale == nil)
print("PASS zero-height bounds wait without division by zero")
function actor:GetActiveBoundingBox()
    return nil
end
assert(normalize(actor, 2) == nil and actor.scale == nil)
print("PASS unavailable bounds wait without arithmetic errors")
