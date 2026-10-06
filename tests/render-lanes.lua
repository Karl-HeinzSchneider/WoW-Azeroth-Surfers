local app = {}
for _, file in ipairs({ "simulation", "shapes", "window" }) do
    assert(loadfile("Surfer/src/game/" .. file .. ".lua"))("Surfer", app)
end
app.db = { global = { bestScore = 0 } }
local r, g = app.runner, app.simulation
local function texture()
    return {
        ClearAllPoints = function() end,
        SetPoint = function(self, _, x, y)
            self.x, self.y = x, y
        end,
        SetSize = function(self, w, h)
            self.w, self.h = w, h
        end,
        Show = function() end,
        Hide = function() end,
        SetColorTexture = function() end,
        SetVertexOffset = function() end,
        SetDrawLayer = function() end,
        SetText = function() end,
    }
end
r.strips = {}
r.faces = app.shapes.Pool({ CreateTexture = texture }, "OVERLAY")
r.playerOffset = 0
r.player = {
    GetScale = function()
        return 1
    end,
    SetPosition = function() end,
    SetAnimation = function() end,
}
r.score, r.message, r.hint = texture(), texture(), texture()
for _, kind in ipairs({ "coin", "obstacle" }) do
    for _, lane in ipairs({ -1, 1 }) do
        r.state = g.New()
        g.Start(r.state)
        -- Input mapping verified in game: left moves to positive simulation lane.
        r:Action(lane == 1 and "LEFT" or "RIGHT")
        r.state.lateral = r.state.lane
        local o = kind == "coin" and g.Box("coin", lane, -0.16, 0.32, 0, 1) or g.Box("obstacle", lane, -0.25, 0.5, 0, 1)
        r.state.objects = { o }
        r:Render()
        local x = r.faces[1].x + r.faces[1].w / 2
        assert(
            (lane == 1 and x < 450) or (lane == -1 and x > 450),
            "rendered pickup/obstacle must follow input direction"
        )
        assert(g.Overlaps(r.state, o), "same visible lane must overlap")
        o.lane = -lane
        r:Render()
        local opposite = r.faces[1].x + r.faces[1].w / 2
        assert((x - 450) * (opposite - 450) < 0, "opposite lane must render on the other side")
        assert(not g.Overlaps(r.state, o), "opposite visible lane must not collide or collect")
    end
end
print("PASS Render obstacle/coin positions agree with controls and collision lanes")
