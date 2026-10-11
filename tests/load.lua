-- Loads addon files into `app` as the TOC does, in order: "game/simulation" is a Lua file under
-- AzerothSurfers/src, "patterns/patterns.xml" a loader XML whose every Script is loaded in turn.
-- Without ace.lua's `app.addon`, a stand-in: a module is an instance of its prototype, its
-- AceComm messages are kept in `sent` ({ prefix, text, channel } each).
return function(app, files)
    app.addon = app.addon
        or {
            NewModule = function(_, _, prototype)
                local module = setmetatable({ sent = {} }, { __index = prototype })
                function module:SendCommMessage(prefix, text, channel)
                    self.sent[#self.sent + 1] = { prefix = prefix, text = text, channel = channel }
                end
                function module:RegisterComm() end
                return module
            end,
        }
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
