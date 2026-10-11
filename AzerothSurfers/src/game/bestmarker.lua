---@type string, AzerothSurfers
local _, app = ...
local sim = app.simulation
local shapes = app.shapes
-- Your best on the track: in a challenge (one seed, one track for everyone), a gold line across
-- the road at the yard where the best run ended (`s.target`, challenges.lua's Best when the run
-- began), its score over it. A best that reached the finish ended at the last portal, which
-- shows that already: no line then. Running past the line announces a new best when the run
-- already scores more (it beats a best that ended earlier, whatever comes after: Beats), and
-- otherwise that it went further.
local overlay = app.overlay

local LANE = sim.geometry.laneWidth
-- Yards: how deep the line is, how far it reaches to each side (to the outer lanes' edges) and
-- how high over the ground its label stands.
local DEPTH, HALF, LABEL_HEIGHT = 0.3, 1.5 * LANE, 0.6
local GOLD = { 1, 0.82, 0 }
local LINE_ALPHA = 0.85
-- The announcement's seconds.
local PASS_SECONDS = 1.5

-- The line's face, refilled every frame (shapes.Place's corners: upper left, lower left, upper
-- right, lower right, each yards ahead, to the right and up).
local face = {}
local function project(d, x, z)
    return overlay:Project(d, x, z)
end

function overlay:CreateBestMarker(f)
    -- Over the ground's bands (BACKGROUND), under the boxes (BORDER) and every model.
    local line = f:CreateTexture(nil, "BACKGROUND", nil, 7)
    line:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1)
    line:Hide()
    local label = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    label:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
    label:Hide()
    self.bestMarker = { line = line, label = label }
end

-- Where the run's best ended, in the track's yards (as `s.distance`); nil without a line.
function overlay.BestMarkerAt(s)
    local best = s.challenge and s.target
    if not best or best.finished or type(best.distance) ~= "number" or best.distance <= 0 then
        return nil
    end
    if s.finish and s.start + best.distance >= s.finish then
        return nil
    end
    return s.start + best.distance
end

local function hide(marker)
    shapes.Hide(marker.line)
    shapes.Hide(marker.label)
end

-- Once a frame, after the camera and the view's fade: the line and its label, and the
-- announcement once the runner is past it.
function overlay:ShowBestMarker()
    local marker = self.bestMarker
    if not marker then
        return
    end
    local s = self.state
    local at = self.BestMarkerAt(s)
    if not at or self.screen then
        hide(marker)
        return
    end
    if marker.best ~= s.target then
        marker.best = s.target
        marker.label:SetFormattedText("Your best  %d", s.target.score)
    end
    if s.status == "running" and not s.bestPassed and s.distance >= at then
        s.bestPassed = true
        self:PassBest(s)
    end
    local d = at - s.distance
    local alpha = self:FadeAlpha(d)
    if d < -DEPTH or alpha <= 0 then
        hide(marker)
        return
    end
    local near, far = d - DEPTH / 2, d + DEPTH / 2
    local zNear, zFar = shapes.Ground(near), shapes.Ground(far)
    face[1], face[2], face[3] = far, -HALF, zFar
    face[4], face[5], face[6] = near, -HALF, zNear
    face[7], face[8], face[9] = far, HALF, zFar
    face[10], face[11], face[12] = near, HALF, zNear
    local line, label = marker.line, marker.label
    if not shapes.Place(line, project, face) then
        shapes.Hide(label)
        return
    end
    if marker.alpha ~= alpha then
        marker.alpha = alpha
        line:SetAlpha(alpha * LINE_ALPHA)
        label:SetAlpha(alpha)
    end
    shapes.Show(line)
    local x, y = self:Project(d, 0, shapes.Ground(d) + LABEL_HEIGHT)
    if x then
        if marker.x ~= x or marker.y ~= y then
            marker.x, marker.y = x, y
            label:SetPoint("BOTTOM", self.groundParent, "BOTTOMLEFT", x, y)
        end
        shapes.Show(label)
    else
        shapes.Hide(label)
    end
end

-- The runner went past where the best ended.
function overlay:PassBest(s)
    if sim.Score(s) > s.target.score then
        self:Announce("New best!", PASS_SECONDS, "Past your best run")
    else
        self:Announce("Past your best run", PASS_SECONDS, string.format("%d points to beat", s.target.score))
    end
end
