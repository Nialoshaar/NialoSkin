local _, NSkin = ...

local GameMenuSkin = NSkin:NewModule("GameMenu")

local IDs = {
    Scope = "GameMenu",
    Window = "GameMenu.Window",
    ButtonPrefix = "GameMenu.Button.",
}

local initialized = false
local applyPending = false
local lifecycleHooked = false
local nextAnonymousButtonID = 0
local buttonIDs = setmetatable({}, { __mode = "k" })

NSkin:RegisterAppearanceScope(IDs.Scope, {
    label = "Game Menu",
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

local function HideDecorativeTextures(frame)
    if not frame then return end
    NSkin:HideTextureRegions(frame)
end

local function CopyTable(source)
    local copy = {}
    for key, value in pairs(source or {}) do copy[key] = value end
    return copy
end

local function GetWindowStyle(frame)
    local style = CopyTable(NSkin:GetAppearanceStyle(
        "window", IDs.Scope, IDs.Window))
    style.header = CopyTable(style.header)

    local configuredHeight = tonumber(style.header.height)
    if not configuredHeight or configuredHeight <= 0 then
        local header = frame and frame.Header
        local height = header and header.GetHeight and header:GetHeight()
        style.header.height = tonumber(height) and height > 0 and height or 22
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
        style = GetWindowStyle(frame),
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

function GameMenuSkin:RefreshAppearance()
    if initialized then self:Apply() end
end

NSkin:RegisterWindowSkin({
    module = "GameMenu",
    addon = "Blizzard_GameMenu",
    apply = function() return GameMenuSkin:Initialize() end,
})
