---@type string, Surfer
local _, app = ...
local track = app.track
local add, arc = track.Add, track.Arc

-- The strip around the rim, in yards before and after it, which the next zone's transition
-- dresses (overlay.lua): no other pattern reaches into it.
-- `clear`: seconds of empty road before the rim and after it at the speed of the moment (at
-- least the strip and `lead`): at full speed a runner sees the gate coming with nothing left to
-- dodge, and after the flash has time to see what the next zone brings before it has to react.
-- `lead`: yards of the zone's own road, empty, at least between the strip and the patterns
-- before and after it, so the zone's boxes (their models, enemies) never stand at its edge.
-- `ramp`: the step up to the portal, in every lane: `layers` up over a ramp `length` yards
-- long (steep enough to look like steps, gentle enough to run up at full speed: the
-- simulation's STEP_UP), starting `from` yards before the rim, its top running on to `to`
-- yards past it, where the runner drops back to the road.
track.GATE = {
    before = 22,
    after = 18,
    clear = { 0.7, 1.5 },
    lead = 10,
    ramp = { layers = 1, length = 1.5, from = 6.5, to = 5 },
}

-- The gate between two zones (simulation.lua's `zones`: in auto, the biome changes there),
-- dressed as the next zone's entrance (a biome's `entrance`). Nothing to die on: empty road
-- leads to it and away from it (`clear`), and a step in every lane climbs to the platform the
-- portal stands on, an arc of coins over the middle lane for a jump. Never picked by weight:
-- the track lays it out where a zone ends (track.lua); it adds where the next zone starts, at
-- the rim, to the run's `gates`. Its boxes are marked `gate` (and their `rim`), so the views
-- give them the transition's looks (its `obstacles`).
track.Register({
    name = "gate",
    weight = 0,
    place = function(s, at)
        local gate, ramp = track.GATE, track.GATE.ramp
        local before = math.max(gate.before + gate.lead, s.speed * gate.clear[1])
        local after = math.max(gate.after + gate.lead, s.speed * gate.clear[2])
        local rim = at + before
        for lane = -1, 1 do
            local box = add(s, "platform", lane, rim - ramp.from, ramp.from + ramp.to, 0, ramp.layers, ramp.length)
            box.gate, box.rim = true, rim
        end
        arc(s, 0, rim, ramp.layers)
        if s.gates then
            s.gates[#s.gates + 1] = rim
        end
        -- The next pattern only past the empty road after the rim.
        return before + after
    end,
})
