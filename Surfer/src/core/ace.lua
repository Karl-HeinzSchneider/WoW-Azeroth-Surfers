---@type string, Surfer
local appName, app = ...

local log = app.logger

---@class Surfer.Addon : AceAddon, AceConsole-3.0, AceEvent-3.0
---@field db Surfer.DB
local addon = {}
LibStub("AceAddon-3.0"):NewAddon(addon, appName, "AceConsole-3.0", "AceEvent-3.0")
app.addon = addon
-- `/surfer` subcommands added by the Surfer_Dev addon (never released), by name.
app.devCommands = {}

-- Surfer_Dev reaches the private table through here.
function addon:DevApp()
    return app
end

-- Called once, after ADDON_LOADED for this addon: SavedVariables are available now.
function addon:OnInitialize()
    local db = LibStub("AceDB-3.0"):New("SurferDB", app.dbDefaults, true) --[[@as Surfer.DB]]
    self.db = db
    app.db = db

    db.RegisterCallback(self, "OnProfileChanged", "OnProfileRefresh")
    db.RegisterCallback(self, "OnProfileCopied", "OnProfileRefresh")
    db.RegisterCallback(self, "OnProfileReset", "OnProfileRefresh")

    self:RegisterChatCommand("surfer", "OnSlashCommand")

    self:OnProfileRefresh()
    log:debug("Initialized (profile: %s)", db:GetCurrentProfile())
end

-- Called after OnInitialize and whenever the addon is re-enabled. Register events here.
function addon:OnEnable()
    log:debug("Enabled")
end

-- Ace unregisters events/timers/hooks automatically on disable.
function addon:OnDisable()
    if app.overlay and app.overlay.frame then
        app.overlay.frame:Hide()
    end
    log:debug("Disabled")
end

-- Re-apply everything that depends on profile settings. Modules opt in by defining OnProfileRefresh.
function addon:OnProfileRefresh()
    log:setLevel(self.db.profile.logLevel)
    if app.overlay and app.overlay.frame then
        app.overlay:ApplyMode()
    end
    for _, module in self:IterateModules() do
        if module.OnProfileRefresh then
            module:OnProfileRefresh()
        end
    end
end

---@param input string
function addon:OnSlashCommand(input)
    local cmd, arg = self:GetArgs(input, 2)
    cmd = cmd and cmd:lower() or ""

    if cmd == "" then
        app.overlay:Toggle()
    elseif cmd == "options" then
        app.options:Open()
    elseif cmd == "loglevel" then
        if arg and log:setLevel(arg) then
            self.db.profile.logLevel = log:getLevelName()
            log:chat("Log level set to %s", self.db.profile.logLevel)
            app.options:Refresh()
        else
            log:chat("Log level is %s", log:getLevelName())
        end
    elseif cmd == "seed" then
        local overlay, seed = app.overlay, tonumber(arg or "")
        if seed then
            overlay:SetSeed(seed)
        elseif arg and arg:lower() == "random" then
            overlay:SetSeed(false)
        end
        local fixed = self.db.profile.seed
        log:chat(fixed and "Seed %d on every run" or "A new seed every run", fixed)
        if overlay.state and overlay.state.seed ~= fixed then
            log:chat("This run: seed %d", overlay.state.seed)
        end
    elseif cmd == "auto" then
        -- Auto mode on (opening the game) or off.
        local overlay = app.overlay
        if not overlay.frame or not overlay.frame:IsShown() then
            overlay:Toggle()
        end
        if overlay.frame and overlay.frame:IsShown() then
            overlay:SetAuto(not overlay.auto)
        end
    elseif cmd == "reset" then
        self.db:ResetProfile()
        log:chat("Profile reset")
    elseif app.devCommands[cmd] then
        app.devCommands[cmd].run(input:match("^%s*%S+%s*(.-)%s*$"))
    else
        log:chat(
            "Commands: /surfer [options], /surfer auto, /surfer loglevel <level>, /surfer seed [<number>|random], /surfer reset"
        )
        local names = {}
        for name in pairs(app.devCommands) do
            names[#names + 1] = name
        end
        table.sort(names)
        for _, name in ipairs(names) do
            log:chat("  /surfer %s", app.devCommands[name].usage)
        end
    end
end
