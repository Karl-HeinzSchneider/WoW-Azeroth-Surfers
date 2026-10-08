---@type string, Surfer
local _, app = ...
-- Seeded random numbers (the game's `math.random` cannot be seeded): Park and Miller's minimal
-- standard, x = x * 16807 mod (2^31 - 1), exact in Lua's doubles.
local random = {}
app.random = random

local M, A = 2147483647, 16807
-- Seeds and states run from 1 to MAX.
random.MAX = M - 1

-- Streams: each system starts this far along the cycle (as a factor), so they do not repeat
-- one another (consecutive values as seeds would only shift one sequence by one).
random.TRACK, random.LEFT, random.RIGHT, random.LOOK = 1, 1583458089, 784588716, 2045073574
random.AMBIENT = 1209675413
-- Auto mode's zone route (biomes.lua) and gates (simulation.lua).
random.ZONES = 1650567391
random.GATES = 937513201

-- x * c mod M, exactly: c split in two halves keeps every product below 2^53.
local function times(x, c)
    local high, low = math.floor(c / 65536), c % 65536
    return ((x * high) % M * 65536 + x * low) % M
end

-- For the tests' known value.
function random.Step(x)
    return x * A % M
end

-- Any whole number as a seed: from 1 to MAX, which stay as they are.
function random.Normalize(n)
    return (math.floor(n) - 1) % random.MAX + 1
end

function random.Seed()
    return math.random(1, random.MAX)
end

-- A generator is called like `math.random`: r() is a number from 0 up to 1, r(n) a whole
-- number from 1 to n, r(m, n) one from m to n.
local Generator = {}
Generator.__index = Generator

function Generator.__call(r, m, n)
    local x = r.state * A % M
    r.state = x
    local u = (x - 1) / random.MAX
    if not m then
        return u
    end
    if not n then
        m, n = 1, m
    end
    return m + math.floor(u * (n - m + 1))
end

-- Starts over from `seed` in `stream` (random.TRACK when left out), without a new table. The
-- first value is skipped: a small seed's is small.
function Generator:Seed(seed, stream)
    self.state = times(random.Normalize(seed), stream or random.TRACK)
    self()
    return self
end

function random.New(seed, stream)
    return setmetatable({}, Generator):Seed(seed, stream)
end
