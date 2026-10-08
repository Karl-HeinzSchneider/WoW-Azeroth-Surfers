---@type string, Surfer
local _, app = ...
local track = app.track
local add, arc = track.Add, track.Arc

-- The strip around the rim, in yards before and after it, which the next zone's transition
-- dresses (overlay.lua): no other pattern reaches into it.
-- `clear`: seconds of empty road before the rim and after it at the speed of the moment (at
-- least the strip): at full speed a runner sees the gate coming with nothing left to dodge, and
-- after the flash has time to see what the next zone brings before it has to react.
track.GATE = { before = 10, after = 18, clear = { 1, 1.5 } }

-- The gate between two zones (simulation.lua's `zones`: in auto, the biome changes there),
-- dressed as the next zone's entrance (a biome's `entrance`). Empty road leads to it and away
-- from it (`clear`); walls block the lanes beside the middle one, the middle one runs straight
-- through, an arc of coins over it for a jump. Never picked by weight: the track lays it out
-- where a zone ends (track.lua). Its walls are marked `gate` (and their `rim`), so the views
-- dress them with the transition's `wall` look, if it has one; it adds where the next zone
-- starts, at the rim, to the run's `gates`.
track.Register({
    name = "gate",
    weight = 0,
    place = function(s, at)
        local gate = track.GATE
        local before = math.max(gate.before, s.speed * gate.clear[1])
        local after = math.max(gate.after, s.speed * gate.clear[2])
        local rim = at + before
        for lane = -1, 1, 2 do
            local wall = add(s, "obstacle", lane, rim - 1, 2, 0, 5)
            wall.gate, wall.rim = true, rim
        end
        arc(s, 0, rim)
        if s.gates then
            s.gates[#s.gates + 1] = rim
        end
        -- The next pattern only past the empty road after the rim.
        return before + after
    end,
})
