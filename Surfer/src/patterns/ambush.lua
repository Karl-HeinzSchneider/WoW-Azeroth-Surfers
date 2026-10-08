---@type string, Surfer
local _, app = ...
local track = app.track
local add, arc = track.Add, track.Arc

-- Enemies behind crates. The way through: a crate with a wolf (or boar) right behind it, one
-- early jump clears both, coins in an arc over them. Beside it a tall wall, and a trap: a
-- crate with a tall enemy waiting behind it (jump the crate there and strafe out in the air).
track.Register({
    name = "ambush",
    weight = { easy = 1, normal = 2, hard = 3, expert = 3 },
    from = 100,
    place = function(s, at, r)
        local path = r(-1, 1)
        local wall = (path + 1 + r(1, 2)) % 3 - 1
        local trap = -path - wall
        add(s, "obstacle", path, at, 0.5, 0, 1)
        add(s, "enemy", path, at + 2.5, 1.2, 0, 2)
        arc(s, path, at + 1.85)
        add(s, "obstacle", wall, at, 0.8, 0, 4)
        add(s, "obstacle", trap, at, 0.5, 0, r(1, 2))
        add(s, "enemy", trap, at + 3, 0.8, 0, 4)
        return track.Landing(s)
    end,
})
