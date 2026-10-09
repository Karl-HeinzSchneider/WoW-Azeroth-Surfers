---@type string, AzerothSurfers
local _, app = ...
local track = app.track
local add, coins, arc = track.Add, track.Coins, track.Arc

-- A corridor: two lanes walled off by lumber too high to climb, the third the only way. In it
-- a crate to jump (coins in an arc over it), then, a jump's length past it, a beam to run
-- under: the runner must be down again in time. Coins under the beam.
track.Register({
    name = "corridor",
    weight = { easy = 1, normal = 2, hard = 3, expert = 3 },
    from = 150,
    place = function(s, at, r)
        local open = r(-1, 1)
        local hurdle = at + 4
        local beam = hurdle + track.JumpLength(s) + 4
        local length = beam + 10 - at
        for lane = -1, 1 do
            if lane ~= open then
                add(s, "platform", lane, at, length, 0, r(4, 5))
            end
        end
        add(s, "obstacle", open, hurdle, 0.5, 0, r(1, 2))
        arc(s, open, hurdle + 0.25)
        add(s, "barrier", open, beam, 0.4, 3, 1)
        coins(s, open, beam - 3, 3, 0)
        return length
    end,
})
