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

    db.RegisterCallback(self, "OnProfileChanged", "OnProfileRefresh")
    db.RegisterCallback(self, "OnProfileCopied", "OnProfileRefresh")
    db.RegisterCallback(self, "OnProfileReset", "OnProfileRefresh")

    self:RegisterChatCommand("azerothsurfers", "OnSlashCommand")
    self:RegisterChatCommand("surfers", "OnSlashCommand")

    self:OnProfileRefresh()
    log:debug("Initialized (profile: %s)", db:GetCurrentProfile())
end

function addon:OnEnable()
    log:debug("Enabled")
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

function addon:ResetProfile()
    self.db:ResetProfile()
    log:chat("Profile reset")
end

local RESET_POPUP = "AZEROTHSURFERS_RESET_PROFILE"

-- `/surfers reset` puts every setting of the profile back to its default, so it asks first;
-- `/surfers reset confirm` skips the question (the only way where the client has no popups).
function addon:ConfirmResetProfile()
    if not StaticPopupDialogs or not StaticPopup_Show then
        log:chat("Type /surfers reset confirm to reset every setting of this profile")
        return
    end
    if not StaticPopupDialogs[RESET_POPUP] then
        StaticPopupDialogs[RESET_POPUP] = {
            text = "Reset every Azeroth Surfers setting of this profile to its default? Your best runs are kept.",
            button1 = YES,
            button2 = NO,
            OnAccept = function()
                addon:ResetProfile()
            end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            showAlert = true,
            preferredIndex = 3,
        }
    end
    StaticPopup_Show(RESET_POPUP)
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
        local overlay = app.overlay
        if not overlay.frame or not overlay.frame:IsShown() then
            overlay:Toggle()
        end
        if overlay.frame and overlay.frame:IsShown() then
            overlay:SetAuto(not overlay.auto)
        end
    elseif cmd == "reset" then
        if arg and arg:lower() == "confirm" then
            self:ResetProfile()
        else
            self:ConfirmResetProfile()
        end
    elseif app.devCommands[cmd] then
        app.devCommands[cmd].run(input:match("^%s*%S+%s*(.-)%s*$"))
    else
        log:chat(
            "Commands: /surfers [options], /surfers auto, /surfers loglevel <level>, /surfers seed [<number>|random], /surfers reset [confirm]"
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
