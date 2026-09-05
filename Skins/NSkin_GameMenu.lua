local _, NSkin = ...

local GameMenuSkin = NSkin:NewModule("GameMenu")

local IDs = {
    Scope = "GameMenu",
    Window = "GameMenu.Window",
    ButtonPrefix = "GameMenu.Button.",
    Settings = {
        Scope = "SettingsPanel",
        Window = "SettingsPanel.Window",
        HeaderControls = "SettingsPanel.HeaderControls",
    },
}

local initialized = false
local settingsInitialized = false
local applyPending = false
local settingsApplyPending = false
local lifecycleHooked = false
local settingsLifecycleHooked = false
local settingsRootTexturesConcealed = false
local nextAnonymousButtonID = 0
local buttonIDs = setmetatable({}, { __mode = "k" })

NSkin:RegisterAppearanceScope(IDs.Scope, {
    label = "Game Menu",
})
NSkin:RegisterAppearanceScope(IDs.Settings.Scope, {
    label = "Settings Panel",
})

local function IsVisible(frame)
    return frame and frame.IsVisible and frame:IsVisible() or false
end

local function QueueApply()
    if applyPending then return end
    applyPending = true
    C_Timer.After(0, function()
        applyPending = false
        GameMenuSkin:Apply()
    end)
end

local function QueueSettingsApply()
    if settingsApplyPending then return end
    settingsApplyPending = true
    C_Timer.After(0, function()
        settingsApplyPending = false
        GameMenuSkin:ApplySettingsPanel()
    end)
end

local function HideDecorativeTextures(frame)
    if not frame then return end
    NSkin:HideTextureRegions(frame)
end

local function CopyTable(source)
    local copy = {}
    for key, value in pairs(source or {}) do copy[key] = value end
    return copy
end

local function GetWindowStyle(scopeID, windowID, headerFrame,
    fallbackHeight)
    local style = CopyTable(NSkin:GetAppearanceStyle(
        "window", scopeID, windowID))
    style.header = CopyTable(style.header)

    local configuredHeight = tonumber(style.header.height)
    if not configuredHeight or configuredHeight <= 0 then
        local height = headerFrame and headerFrame.GetHeight
            and headerFrame:GetHeight()
        style.header.height = tonumber(height) and height > 0
            and height or fallbackHeight or 22
    end
    return style
end

local function GetButtonID(button)
    local assignedID = buttonIDs[button]
    if assignedID then return assignedID end

    local name = button.GetName and button:GetName()
    if type(name) == "string" and name ~= "" then
        local namedID = IDs.ButtonPrefix .. name
        local existing = NSkin:GetSkinningElement(namedID)
        if not existing or existing.target == button then
            buttonIDs[button] = namedID
            return namedID
        end
    end

    nextAnonymousButtonID = nextAnonymousButtonID + 1
    local id = IDs.ButtonPrefix .. "Anonymous" .. nextAnonymousButtonID
    buttonIDs[button] = id
    return id
end

local function GetButtonLabel(button)
    local text = button.GetText and button:GetText()
    if type(text) == "string" and text ~= "" then
        return text .. " button"
    end
    local name = button.GetName and button:GetName()
    if type(name) == "string" and name ~= "" then
        return name .. " button"
    end
    return "Game Menu button"
end

function GameMenuSkin:ApplyWindowChrome(frame)
    if not frame then return false end

    -- DialogBorderTemplate and DialogHeaderTemplate contain only the native
    -- decorative chrome. Keep the frames themselves intact because Blizzard's
    -- layout and title still use them.
    HideDecorativeTextures(frame.Border)
    HideDecorativeTextures(frame.Header)

    local title = frame.Header and frame.Header.Text
    local chrome = NSkin:SkinStandardWindowChrome({
        frame = frame,
        appearanceWindowID = IDs.Scope,
        elementID = IDs.Window,
        style = GetWindowStyle(
            IDs.Scope, IDs.Window, frame.Header, 22),
        title = title,
        skinCloseButton = false,
    })
    if title and chrome and chrome.header then
        title:ClearAllPoints()
        title:SetPoint("CENTER", chrome.header, "CENTER", 0, 0)
    end

    NSkin:RegisterSkinningElement(IDs.Window, {
        label = "Game Menu window",
        kind = "WINDOW",
        module = "GameMenu",
        appearanceWindowID = IDs.Scope,
        window = frame,
        target = frame,
        priority = 0,
        draggable = false,
    })
    return true
end

function GameMenuSkin:ApplyButtons(frame)
    if not frame or not frame.GetChildren then return false end

    local applied = false
    local children = { frame:GetChildren() }
    for index = 1, #children do
        local button = children[index]
        if button and button.IsObjectType and button:IsObjectType("Button") then
            local id = GetButtonID(button)
            local element = NSkin:RegisterActionButton({
                id = id,
                module = "GameMenu",
                appearanceWindowID = IDs.Scope,
                label = GetButtonLabel(button),
                window = frame,
                target = button,
                priority = 50 + index,
                highlightRegions = { button },
                isEditable = function()
                    return IsVisible(frame) and IsVisible(button)
                end,
            })
            if element then
                -- Pooled buttons can represent a different command the next
                -- time the menu opens, so keep their editor label current.
                element.label = GetButtonLabel(button)
                applied = true
            end
        end
    end
    return applied
end

function GameMenuSkin:Apply()
    local frame = _G.GameMenuFrame
    if not frame then return false end

    self:ApplyWindowChrome(frame)
    self:ApplyButtons(frame)
    return true
end

function GameMenuSkin:ApplySettingsPanel()
    local frame = _G.SettingsPanel
    if not frame then return false end

    -- The unnamed root texture is Options_InnerFrame. Suppress it before
    -- creating NSkin's own root textures so subsequent refreshes cannot hide
    -- the shared chrome.
    if not settingsRootTexturesConcealed then
        HideDecorativeTextures(frame)
        settingsRootTexturesConcealed = true
    end

    -- NineSlice owns the functional title FontString. Preserve the container
    -- and remove only its decorative regions.
    HideDecorativeTextures(frame.NineSlice)
    local title = frame.NineSlice and frame.NineSlice.Text
    local closeButton = frame.ClosePanelButton
    local chrome = NSkin:SkinStandardWindowChrome({
        frame = frame,
        appearanceWindowID = IDs.Settings.Scope,
        elementID = IDs.Settings.Window,
        headerControlsID = IDs.Settings.HeaderControls,
        style = GetWindowStyle(IDs.Settings.Scope, IDs.Settings.Window,
            closeButton, 24),
        title = title,
        closeButton = closeButton,
        preserveArtwork = {
            NineSlice = true,
        },
    })
    if title and chrome and chrome.header then
        title:ClearAllPoints()
        title:SetPoint("CENTER", chrome.header, "CENTER", 0, 0)
    end

    NSkin:RegisterSkinningElement(IDs.Settings.Window, {
        label = "Settings Panel window",
        kind = "WINDOW",
        module = "GameMenu",
        appearanceWindowID = IDs.Settings.Scope,
        window = frame,
        target = frame,
        priority = 0,
        draggable = false,
    })
    return true
end

function GameMenuSkin:HookLifecycle(frame)
    if lifecycleHooked then return end

    if frame.HookScript then frame:HookScript("OnShow", QueueApply) end
    if _G.hooksecurefunc and type(frame.AddButton) == "function"
    then
        _G.hooksecurefunc(frame, "AddButton", QueueApply)
    end
    lifecycleHooked = true
end

function GameMenuSkin:Initialize()
    local frame = _G.GameMenuFrame
    if not frame then return false end

    self:HookLifecycle(frame)
    initialized = true
    self:Apply()
    if frame:IsShown() then QueueApply() end
    return true
end

function GameMenuSkin:InitializeSettingsPanel()
    local frame = _G.SettingsPanel
    if not frame then return false end

    if not settingsLifecycleHooked and frame.HookScript then
        frame:HookScript("OnShow", QueueSettingsApply)
        settingsLifecycleHooked = true
    end
    settingsInitialized = true
    self:ApplySettingsPanel()
    if frame:IsShown() then QueueSettingsApply() end
    return true
end

function GameMenuSkin:RefreshAppearance()
    if initialized then self:Apply() end
    if settingsInitialized then self:ApplySettingsPanel() end
end

NSkin:RegisterWindowSkin({
    module = "GameMenu",
    addon = "Blizzard_GameMenu",
    apply = function() return GameMenuSkin:Initialize() end,
})

NSkin:RegisterWindowSkin({
    key = "GameMenu.SettingsPanel",
    module = "GameMenu",
    addon = "Blizzard_Settings_Shared",
    apply = function() return GameMenuSkin:InitializeSettingsPanel() end,
})
