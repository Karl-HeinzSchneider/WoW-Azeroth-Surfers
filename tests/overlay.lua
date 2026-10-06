-- Exercise the full-screen projection and cutout rules without creating client UI frames.
local app = {}
assert(loadfile("Surfer/src/game/simulation.lua"))("Surfer", app)
assert(loadfile("Surfer/src/game/window.lua"))("Surfer", app)
assert(loadfile("Surfer/src/game/overlay.lua"))("Surfer", app)
app.db = {
    global = { bestScore = 0 },
    profile = { overlay = { pitch = 20, focus = 0.9, distance = 12, fov = 55, opacity = 0.85, cutout = 0.8 } },
}
local o, g = app.overlay, app.simulation
local W, H = 1600, 900
local function texture()
    return {
        ClearAllPoints = function() end,
        SetPoint = function(self, _, a, b, c, d)
            self.x, self.y = c or a, d or b
        end,
        SetSize = function(self, w, h)
            self.w, self.h = w, h
        end,
        Show = function(self)
            self.shown = true
        end,
        Hide = function(self)
            self.shown = false
        end,
        SetShown = function(self, shown)
            self.shown = shown
        end,
        SetColorTexture = function() end,
        SetVertexOffset = function() end,
        AddMaskTexture = function() end,
        RemoveMaskTexture = function() end,
        SetText = function() end,
    }
end
o.frame = {
    GetSize = function()
        return W, H
    end,
}
o.height, o.width = 2, 0.8
o.strips = { { texture(), texture(), texture(), texture(), texture() } }
o.markers = { { texture = texture(), top = texture() } }
o.cutout, o.feet = texture(), texture()
o.coins = {}
o.score, o.message, o.hint = texture(), texture(), texture()

o.state = g.New()
g.Start(o.state)
o:Render()
assert(o.feet.x == W / 2, "the character stays at the screen's horizontal center")
assert(o.feet.y < H / 2, "the feet sit below the camera's focus at the screen center")
assert(o.cutout.y < o.feet.y and o.cutout.y + o.cutout.h > o.feet.y, "the cutout covers the feet")
print("PASS character anchor and cutout placement")

for _, lane in ipairs({ -1, 1 }) do
    local obj = { kind = "obstacle", lane = lane, at = 10 }
    o.state.objects = { obj }
    o:Render()
    local x = o.markers[1].texture.x
    -- Positive simulation lanes are on the screen's left, as in the window view.
    assert((lane == 1 and x < W / 2) or (lane == -1 and x > W / 2), "obstacle lane follows the controls")
    assert(o.markers[1].texture.surferBehind, "an obstacle ahead is behind the character")
end
o.state.objects = { { kind = "obstacle", lane = 0, at = -1 } }
o:Render()
assert(not o.markers[1].texture.surferBehind, "a passed obstacle is drawn over the character")
print("PASS lane sides and behind/in-front masking")

-- Changing lanes moves the road under the character, which stays centered.
o.state.objects = { { kind = "coin", lane = 0, at = 10 } }
o:Render()
local centered = o.markers[1].texture.x
o.state.lateral = 1
o:Render()
assert(o.markers[1].texture.x > centered, "moving left slides the world to the right")
assert(o.feet.x == W / 2, "the character stays centered while changing lanes")
print("PASS road follows the character's lane")

-- 3D coins cannot be masked: one behind the body hides, one beside it or passed stays visible.
function GetTime()
    return 0
end
local function stub()
    local t = texture()
    t.SetYaw = function() end
    t.SetCameraPosition = function() end
    t.SetCameraOrientationByYawPitchRoll = function() end
    return t
end
o.coins = { { scene = stub(), actor = stub() } }
o.coinReady = true
o.state.lateral = 0
for _, case in ipairs({
    { lane = 0, at = 1, shown = false },
    { lane = 1, at = 1, shown = true },
    { lane = 0, at = -1, shown = true },
}) do
    o.state.objects = { { kind = "coin", lane = case.lane, at = case.at } }
    o:Render()
    assert(o.coins[1].actor.shown == case.shown, "3D coin visibility around the character")
    assert(not o.markers[1].texture.shown, "a loaded coin model replaces the flat coin")
end
o.state.objects = {}
o:Render()
assert(not o.coins[1].actor.shown, "unused coin scenes hide their model")
print("PASS 3D coins hide behind the character and replace flat coins")

-- Jumping: the camera rises with the character, so it keeps its place and the road drops.
o.coinReady = false
o.state.objects = { { kind = "coin", lane = 1, at = 10 } }
o.state.height = 0
o:Render()
local feetY, coinY = o.feet.y, o.markers[1].texture.y
o.state.height = 1.5
o:Render()
assert(math.abs(o.feet.y - feetY) < 0.001, "the character keeps its place on screen")
assert(o.markers[1].texture.y < coinY, "the road and its objects drop while jumping")
print("PASS jumping drops the road beneath the character")
