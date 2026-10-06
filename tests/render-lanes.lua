local app = {}
assert(loadfile("Surfer/src/game/simulation.lua"))("Surfer", app)
assert(loadfile("Surfer/src/game/window.lua"))("Surfer", app)
app.db = { global = { bestScore = 0 } }
local r, g = app.runner, app.simulation
local function texture()
    return {
        ClearAllPoints = function() end,
        SetPoint = function(self, _, x, y)
            self.x, self.y = x, y
        end,
        SetSize = function() end,
        Show = function() end,
        Hide = function() end,
        SetColorTexture = function() end,
        SetVertexOffset = function() end,
    }
end
r.strips, r.props = {}, {}
r.markers = { { texture = texture(), top = texture() } }
r.playerOffset = 0
r.player = {
    GetScale = function()
        return 1
    end,
    SetPosition = function() end,
    SetAnimation = function() end,
}
r.score = { SetText = function() end }
r.message = r.score
r.hint = r.score
for _, kind in ipairs({ "coin", "obstacle" }) do
    for _, lane in ipairs({ -1, 1 }) do
        r.state = g.New()
        g.Start(r.state)
        -- Input mapping verified in game: left moves to positive simulation lane.
        r:Action(lane == 1 and "LEFT" or "RIGHT")
        r.state.lateral = r.state.lane
        local o = { kind = kind, lane = lane, at = 0 }
        r.state.objects = { o }
        r:Render()
        local x = r.markers[1].texture.x
        assert(
            (lane == 1 and x < 450) or (lane == -1 and x > 450),
            "rendered pickup/obstacle must follow input direction"
        )
        assert(g.Overlaps(r.state, o), "same visible lane must overlap")
        o.lane = -lane
        r:Render()
        local oppositeX = r.markers[1].texture.x
        assert((x - 450) * (oppositeX - 450) < 0, "opposite lane must render on the other side")
        assert(not g.Overlaps(r.state, o), "opposite visible lane must not collide or collect")
    end
end
print("PASS Render obstacle/coin positions agree with controls and collision lanes")
