---@type string, Surfer
local _, app = ...
local track = app.track
local add, arc = track.Add, track.Arc

-- A stampede: two or three rows of beasts low enough to jump, one in every lane, each up to a
-- yard out of line, some with a crate close by: no way around, only over. A jump's length and more apart at the speed of
-- the moment, so the runner is down again before the next row. An arc of coins over one beast
-- per row, in another lane each row.
track.Register({
    name = "stampede",
    weight = { easy = 1, normal = 2, hard = 2, expert = 2 },
    from = 200,
    place = function(s, at, r)
        local rows = r(2, 3)
        local spacing = track.JumpLength(s) + r(4, 6)
        local coined = r(-1, 1)
        for i = 0, rows - 1 do
            local row = at + i * spacing
            for lane = -1, 1 do
                local beast = row + r(0, 2) * 0.5
                add(s, "enemy", lane, beast, 1.2, 0, 2)
                -- Sometimes a crate a yard or two before or behind it, cleared by the same jump.
                local crate = r(0, 3)
                if crate == 1 then
                    add(s, "obstacle", lane, beast - 0.5 - r(2, 4) * 0.5, 0.5, 0, r(1, 2))
                elseif crate == 2 then
                    add(s, "obstacle", lane, beast + 1.2 + r(2, 4) * 0.5, 0.5, 0, r(1, 2))
                end
                if lane == coined then
                    arc(s, lane, beast + 0.6)
                end
            end
            coined = (coined + 1 + r(1, 2)) % 3 - 1
        end
        -- Past the jump over the last row (its arcs reach less far).
        return (rows - 1) * spacing + 1 + track.Landing(s)
    end,
})
