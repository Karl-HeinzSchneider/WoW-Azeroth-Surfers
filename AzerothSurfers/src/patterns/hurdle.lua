---@type string, AzerothSurfers
local _, app = ...
local track = app.track
local add, arc = track.Add, track.Arc

-- A hurdle under an arc of coins that only a jump collects.
track.Register({
    name = "hurdle",
    weight = 3,
    place = function(s, at, r)
        local lane = r(-1, 1)
        add(s, "obstacle", lane, at, 0.5, 0, 1)
        arc(s, lane, at + 0.25)
        return 8
    end,
})
