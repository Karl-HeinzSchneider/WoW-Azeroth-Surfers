-- Client selection, immutable baseline data, and schema-aware asset substitutions.
local function fresh()
    local app = {}
    dofile("tests/load.lua")(app, {
        "biomes/biomes.xml",
        "scenes/lobby",
    })
    return app
end
local function retail(app, interface, project)
    WOW_PROJECT_MAINLINE, WOW_PROJECT_ID = 1, project
    GetBuildInfo = function()
        return "test", "test", "", interface
    end
    assert(loadfile("AzerothSurfers/src/overrides/retail.lua"))("AzerothSurfers", app)
end
local app = fresh()
local baseline = app.biomes.list
local cached = app.biomes.Get("durotar")
retail(app, 16001, 1)
assert(
    app.biomes.list == baseline and app.biomes.Get("durotar") == cached,
    "Forever is an exact no-op even when Mainline"
)
retail(app, 50500, 5)
assert(app.biomes.list == baseline, "Classic does not get retail substitutions")
retail(app, 120100, 1)
local ids = app.biomes.Get("durotar").obstacles.enemy[4].items[1].creature
assert(ids[1] == 1218 and ids[2] == 1967 and ids[3] == 6096 and ids[4] == 1964, "retail resolves missing quilboars")
assert(baseline.durotar.obstacles.enemy[4].items[1].creature[2] == 1252, "source data remains unchanged")
assert(app.biomes.Get("durotar") ~= cached, "merged cache invalidated")
assert(app.biomes.Get("tirisfal").obstacles.enemy[2].items[1].creature == 418, "retail resolves spider")
assert(app.biomes.Get("lobby").ambient.creatures[2].creature == 328, "retail resolves lobby rabbit")
assert(app.biomes.Get("elwynn").ambient.creatures[2].creature == 328, "retail resolves Elwynn rabbit")

app = fresh()
local item = {
    creature = { 1252, 1218 },
    model = { 10, 11 },
    texture = 10,
    animation = 25,
    attack = 16,
    height = 10,
    weight = 25,
    sound = { [1252] = { 20 }, [1218] = { 21 } },
    voice = { 20 },
    finale = 20,
}
app.biomes.Register("fixture", { items = { item }, footsteps = { ground = { 20 }, wood = { 21 }, stride = 20 } })
app.biomes.RegisterTransition("fixture", { items = { item }, sounds = { approach = 20, through = 21 } })
app.lobby.items = { item }
app.lobby.music = 20
app.biomes.ApplyAssetOverrides({
    creatures = { [1252] = 1218 },
    models = { [10] = 100, [100] = 200 },
    textures = { [10] = 101 },
    sounds = { [20] = "replacement.ogg", [21] = 22 },
    animations = { [25] = 0 },
})
local result = app.biomes.Get("fixture")
local changed = result.items[1]
assert(changed.model[1] == 100 and changed.model[2] == 11, "model list mapping is single-pass")
assert(
    changed.texture == 101 and changed.animation == 0 and changed.attack == 16,
    "asset types kept separate, zero ID supported"
)
assert(changed.height == 10 and changed.weight == 25, "non-asset numbers untouched")
assert(
    changed.sound[1252] == nil and changed.sound[1218][1] == 22,
    "display-keyed sound collision prefers target voice"
)
assert(changed.voice[1] == "replacement.ogg" and changed.finale == "replacement.ogg", "sound list and scalar mapping")
assert(
    result.footsteps.ground[1] == "replacement.ogg" and result.footsteps.stride == 20,
    "footstep mapping preserves stride"
)
assert(app.biomes.transitions.fixture.items[1].model[1] == 100, "transition models remapped")
assert(app.biomes.transitions.fixture.sounds.through == 22, "portal sounds remapped")
assert(app.lobby.items[1].model[1] == 100 and app.lobby.music == "replacement.ogg", "lobby remapped")
assert(item.model[1] == 10 and item.animation == 25 and item.sound[1252][1] == 20, "shared baseline tables untouched")
print("PASS client asset overrides: Forever/Classic no-op, retail mappings, caches, schemas and baseline preservation")
