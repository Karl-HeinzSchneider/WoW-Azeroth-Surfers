---@type string, AzerothSurfers
local _, app = ...
local track = app.track
local add, coins = track.Add, track.Coins

-- A gauntlet: two or three rows, each blocking every lane with something different, a tall
-- wall, a beam to run under and a crate to jump, shuffled per row. A jump's length apart at
-- the speed of the moment, so a runner who jumped is down again before the next beam. Coins
-- under every beam.
track.Register({
    name = "gauntlet",
    weight = { easy = 1, normal = 2, hard = 3, expert = 3 },
    from = 150,
    place = function(s, at, r)
        local rows = r(2, 3)
        local spacing = track.JumpLength(s) + 4
        for i = 0, rows - 1 do
            local row = at + i * spacing
            local wall = r(-1, 1)
            local beam = (wall + 1 + r(1, 2)) % 3 - 1
            local crate = -wall - beam
            add(s, "obstacle", wall, row, 0.8, 0, 4)
            add(s, "barrier", beam, row, 0.4, 3, 1)
            add(s, "obstacle", crate, row, 0.5, 0, r(1, 2))
            coins(s, beam, row - 3, 3, 0)
        end
        return (rows - 1) * spacing + 3
    end,
})
