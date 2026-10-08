---@type string, Surfer
local _, app = ...
local track = app.track
local add, arc = track.Add, track.Arc

-- `before`/`after`: the strip around the rim (yards) that the transition dresses; no other
-- pattern reaches into it.
-- `clear`: seconds of empty road before and after the rim at the speed of the moment.
-- `lead`: at least this many empty yards of the zone's own road between the strip and the
-- patterns around it, so the zone's models never stand at its edge.
-- `ramp`: the step up to the portal in every lane, `from` yards before the rim to `to` past it;
-- short enough to read as a step, within the simulation's STEP_UP to run up at full speed.
track.GATE = {
    before = 22,
    after = 18,
    clear = { 0.7, 1.5 },
    lead = 10,
    ramp = { layers = 1, length = 1.5, from = 6.5, to = 5 },
}

-- The gate between two zones, dressed as the next zone's `entrance`. Nothing to die on: empty
-- road around it, a step in every lane up to the portal's platform, coins over the middle lane.
-- Never picked by weight: track.lua lays it out where a zone ends. Its boxes are marked `gate`
-- (and their `rim`) for the transition's `obstacles`.
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
        return before + after
    end,
})
