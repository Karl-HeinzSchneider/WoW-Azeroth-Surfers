---@type string, AzerothSurfers
local appName, app = ...

local log = app.logger

---@class AzerothSurfers.Addon : AceAddon, AceConsole-3.0, AceEvent-3.0
---@field db AzerothSurfers.DB
local addon = {}
LibStub("AceAddon-3.0"):NewAddon(addon, appName, "AceConsole-3.0", "AceEvent-3.0")
app.addon = addon
-- `/surfers` subcommands added by the AzerothSurfers_Dev addon (never released), by name.
app.devCommands = {}

-- AzerothSurfers_Dev reaches the private table through here.
function addon:DevApp()
    return app
end

function addon:OnInitialize()
    local db = LibStub("AceDB-3.0"):New("AzerothSurfersDB", app.dbDefaults, true) --[[@as AzerothSurfers.DB]]
    self.db = db
    app.db = db
    -- Past challenges keep their best without its trace (challenges.lua's history).
    app.challenges.Compact()

    db.RegisterCallback(self, "OnProfileChanged", "OnProfileRefresh")
    db.RegisterCallback(self, "OnProfileCopied", "OnProfileRefresh")
    db.RegisterCallback(self, "OnProfileReset", "OnProfileRefresh")

    self:RegisterChatCommand("azerothsurfers", "OnSlashCommand")
    self:RegisterChatCommand("surfers", "OnSlashCommand")

    self:OnProfileRefresh()
    log:debug("Initialized (profile: %s)", db:GetCurrentProfile())
end

function addon:OnEnable()
    self:RegisterEvent("PLAYER_ENTERING_WORLD")
    log:debug("Enabled")
end

-- At login (not on a reload or a loading screen): the challenge reminder, once the realm's
-- clock is known.
function addon:PLAYER_ENTERING_WORLD(_, isInitialLogin)
    self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    if isInitialLogin and self.db.profile.challengeReminder then
        log:chat(app.challenges.Reminder())
    end
end

function addon:OnDisable()
    if app.overlay and app.overlay.frame then
        app.overlay.frame:Hide()
    end
    log:debug("Disabled")
end

-- Modules opt in by defining OnProfileRefresh.
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
        -- `/surfers seed <number> [<yards>]`: the yards a restart begins into it.
        local _, typed, yards = self:GetArgs(input, 3)
        local overlay, seed = app.overlay, tonumber(typed or "")
        if seed then
            overlay:SetSeed(seed)
            overlay:SetStartAt(tonumber(yards or "") or 0)
        elseif typed and typed:lower() == "random" then
            overlay:SetSeed(false)
        end
        local fixed, startAt = self.db.profile.seed, self.db.profile.startAt or 0
        if fixed and startAt > 0 then
            log:chat("Seed %d on every run, restarts from %d yards", fixed, startAt)
        else
            log:chat(fixed and "Seed %d on every run" or "A new seed every run", fixed)
        end
        if overlay.state and overlay.state.seed ~= fixed then
            log:chat("This run: seed %d", overlay.state.seed)
        end
    elseif cmd == "auto" then
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
            "Commands: /surfers [options], /surfers auto, /surfers loglevel <level>, /surfers seed [<number> [<yards>]|random], /surfers reset"
        )
        local names = {}
        for name in pairs(app.devCommands) do
            names[#names + 1] = name
        end
        table.sort(names)
        for _, name in ipairs(names) do
            log:chat("  /surfers %s", app.devCommands[name].usage)
        end
    end
end
