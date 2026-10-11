-- Loads addon files into `app` as the TOC does, in order: "game/simulation" is a Lua file under
-- AzerothSurfers/src, "game/game.xml" a loader XML whose every Script and Include is loaded in turn.
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
    -- A Script is loaded, an Include's XML is loaded in its place, both from the XML's folder.
    local function loadXml(path)
        local xml = assert(io.open(path)):read("*a")
        local folder = path:match("^(.*/)")
        for tag, file in xml:gmatch('<(%a+) file="([^"]+)"') do
            file = folder .. file:gsub("\\", "/")
            if tag == "Include" then
                loadXml(file)
            elseif tag == "Script" then
                assert(loadfile(file))("AzerothSurfers", app)
            end
        end
    end
    for _, file in ipairs(files) do
        local path = "AzerothSurfers/src/" .. file
        if path:match("%.xml$") then
            loadXml(path)
        else
            assert(loadfile(path .. ".lua"))("AzerothSurfers", app)
        end
    end
end
