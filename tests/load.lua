-- Loads addon files into `app` as the TOC does, in order: "game/simulation" is a Lua file under
-- AzerothSurfers/src, "patterns/patterns.xml" a loader XML whose every Script is loaded in turn.
return function(app, files)
    for _, file in ipairs(files) do
        local path = "AzerothSurfers/src/" .. file
        if path:match("%.xml$") then
            local xml = assert(io.open(path)):read("*a")
            local folder = path:match("^(.*/)")
            for script in xml:gmatch('<Script file="([^"]+)"') do
                assert(loadfile(folder .. script:gsub("\\", "/")))("AzerothSurfers", app)
            end
        else
            assert(loadfile(path .. ".lua"))("AzerothSurfers", app)
        end
    end
end
