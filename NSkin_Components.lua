do
local _, NSkin = ...

local resolvedStyles = {}
local appearanceScopes = {}

local function RoundOne(value)
    value = tonumber(value) or 0
    if value >= 0 then return math.floor(value * 10 + 0.5) / 10 end
    return math.ceil(value * 10 - 0.5) / 10
end

local function TablesEqual(left, right)
    if type(left) ~= type(right) then return false end
    if type(left) ~= "table" then return left == right end
    for key, value in pairs(left) do
        if not TablesEqual(value, right[key]) then return false end
    end
    for key in pairs(right) do
        if left[key] == nil then return false end
    end
    return true
end

local function GetPath(root, path, create)
    local node = root
    local parent
    local finalKey
    for key in path:gmatch("[^%.]+") do
        parent = node
        finalKey = key
        local child = node[key]
        if child == nil and create then
            child = {}
            node[key] = child
        end
        node = child
        if node == nil then break end
    end
    return node, parent, finalKey
end

local function PruneEmptyTables(root)
    for key, value in pairs(root) do
        if type(value) == "table" then
            PruneEmptyTables(value)
            if not next(value) then root[key] = nil end
        end
    end
end

local function CopyWithOverrides(defaults, overrides)
    local result = {}
    for key, defaultValue in pairs(defaults) do
        local override = overrides and overrides[key]
        if type(defaultValue) == "table" then
            result[key] = CopyWithOverrides(
                defaultValue,
                type(override) == "table" and override or nil
            )
        elseif override ~= nil then
            result[key] = override
        else
            result[key] = defaultValue
        end
    end
    for key, override in pairs(overrides or {}) do
        if defaults[key] == nil then
            result[key] = type(override) == "table"
                and CopyWithOverrides({}, override) or override
        end
    end
    return result
end

function NSkin:GetStyle(name)
    local cached = resolvedStyles[name]
    if cached then return cached end

    local defaults = self.baseAppearance and self.baseAppearance[name]
    if type(defaults) ~= "table" then return nil end

    local profile = self:GetProfile()
    local overrides = profile.appearance and profile.appearance[name]
    cached = CopyWithOverrides(defaults, overrides)
    resolvedStyles[name] = cached
    return cached
end

local function GetAppearanceScopeChain(scopeID)
    if not scopeID then return nil end
    local chain, seen = {}, {}
    local current = scopeID
    while current do
        if seen[current] then return nil end
        seen[current] = true
        table.insert(chain, 1, current)
        local scope = appearanceScopes[current]
        if not scope then return nil end
        current = scope.parent
    end
    return chain
end

function NSkin:RegisterAppearanceScope(scopeID, definition)
    if type(scopeID) ~= "string" or scopeID == ""
        or type(definition) ~= "table" or appearanceScopes[scopeID]
    then return false end
    local parent = definition.parent
    if parent ~= nil and (type(parent) ~= "string"
        or parent == "" or not appearanceScopes[parent])
    then return false end
    if parent == scopeID then return false end
    local scope = {
        id = scopeID,
        label = definition.label or scopeID,
        parent = parent,
    }
    appearanceScopes[scopeID] = scope
    if not GetAppearanceScopeChain(scopeID) then
        appearanceScopes[scopeID] = nil
        return false
    end
    return true
end

function NSkin:GetAppearanceScope(scopeID)
    return appearanceScopes[scopeID]
end

function NSkin:GetAppearanceScopeChain(scopeID)
    local chain = GetAppearanceScopeChain(scopeID)
    if not chain then return nil end
    local copy = {}
    for i = 1, #chain do copy[i] = chain[i] end
    return copy
end

-- Appearance resolves from the base appearance through optional window
-- and element layers. Each saved layer remains sparse, so reset means removal.
function NSkin:GetAppearanceStyle(name, windowID, elementID)
    local style = self:GetStyle(name)
    if not style then return nil end
    -- baseAppearance contains styling only. GetStyle() adds the sparse global
    -- profile layer, whose explicit geometry must remain available to every
    -- compatible component before window and element overrides are applied.
    style = CopyWithOverrides({}, style)
    local profile = self:GetProfile()
    local overrides = profile.appearanceOverrides
    local chain = windowID and GetAppearanceScopeChain(windowID)
    for i = 1, #(chain or {}) do
        local windowOverride = overrides and overrides.windows
            and overrides.windows[chain[i]]
        if windowOverride and windowOverride[name] then
            style = CopyWithOverrides(style, windowOverride[name])
        end
    end
    local elementOverride = elementID and overrides and overrides.elements
        and overrides.elements[elementID]
    if elementOverride and elementOverride[name] then
        style = CopyWithOverrides(style, elementOverride[name])
    end
    return style
end

function NSkin:GetResolvedTypography(style, prefix)
    style = style or {}
    prefix = prefix or ""
    local useGlobalKey = prefix == "" and "useGlobalTypography"
        or (prefix .. "UseGlobalTypography")
    local fontKey = prefix == "" and "font" or (prefix .. "Font")
    local sizeKey = prefix == "" and "textSize" or (prefix .. "Size")
    local outlineKey = prefix == "" and "outline" or (prefix .. "Outline")
    local global = self:GetStyle("typography")
    local fontModeKey = prefix == "" and "fontMode" or prefix .. "FontMode"
    local sizeModeKey = prefix == "" and "sizeMode" or prefix .. "SizeMode"
    local outlineModeKey = prefix == "" and "outlineMode" or prefix .. "OutlineMode"
    if style[fontModeKey] or style[sizeModeKey] or style[outlineModeKey] then
        local font = style[fontModeKey] == "GLOBAL" and global.font
            or style[fontKey] or global.font
        local size
        if style[sizeModeKey] ~= "BLIZZARD" then
            size = style[sizeModeKey] == "GLOBAL" and global.size
                or style[sizeKey] or global.size
        end
        local outline = style[outlineModeKey] == "GLOBAL" and global.outline
            or style[outlineKey] or global.outline
        return font, size, outline
    elseif style[useGlobalKey] == true then
        return global.font, global.size, global.outline
    end
    return style[fontKey] or global.font, style[sizeKey] or global.size,
        style[outlineKey] or global.outline
end

function NSkin:SkinTextColor(fontString, style)
    if not fontString or not fontString.GetFont then return false end
    style = style or self:GetStyle("text")
    local color = self:GetResolvedAppearanceColor(style, "color")
    if color then fontString:SetTextColor(unpack(color)) end
    return true
end

function NSkin:SkinText(fontString, style)
    if not self:SkinTextColor(fontString, style) then return false end
    style = style or self:GetStyle("text")
    self:ApplyResolvedTypography(fontString, style)
    return true
end

function NSkin:ApplyResolvedTypography(fontString, style, prefix)
    if not fontString or not fontString.GetFont or not fontString.SetFont then return false end
    local data = self:GetSkinData(fontString, "resolvedTypography")
    if not data.baselineID then
        data.baselineID = "Typography:" .. tostring(fontString)
        self:CaptureComponentBaseline(data.baselineID, fontString, {
            font = fontString,
        })
    end
    local baseline = self:GetComponentBaseline(data.baselineID)
    if not data.originalFont then
        data.originalFont = baseline and baseline.font or { fontString:GetFont() }
    end
    local font, size, outline = self:GetResolvedTypography(style, prefix)
    local hasSizeOverride = tonumber(size) ~= nil
    font = font or data.originalFont[1]
    size = tonumber(size) or data.originalFont[2]
    if not font or not size then return false end
    self:MarkComponentGeometryModified(data.baselineID, "font",
        hasSizeOverride)
    fontString:SetFont(font, size,
        outline ~= nil and outline or data.originalFont[3])
    return true
end

function NSkin:GetResolvedAppearanceColor(style, key)
    local color = style and style[key]
    if type(color) ~= "table" then return color end
    local mode = style[key .. "Mode"]
    local resolved
    if mode == "ACCENT" then
        resolved = self:GetAccentColor()
    elseif mode == "CLASS" then
        local _, class = UnitClass("player")
        resolved = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    end
    if not resolved then return color end
    return { resolved.r or resolved[1], resolved.g or resolved[2],
        resolved.b or resolved[3], color[4] or resolved.a or resolved[4] or 1 }
end

local function GetAppearanceParentValue(scope, id, windowID, path)
    local styleName, relativePath = path:match("^([^.]+)%.(.+)$")
    if not styleName then return nil end
    local style
    if scope == "windows" then
        local registered = appearanceScopes[id]
        style = registered and registered.parent
            and NSkin:GetAppearanceStyle(styleName, registered.parent)
            or NSkin:GetStyle(styleName)
    else
        style = NSkin:GetAppearanceStyle(styleName, windowID)
    end
    return style and GetPath(style, relativePath, false), styleName, relativePath
end

local function SetAppearanceOverride(scope, id, windowID, path, value)
    if (scope ~= "windows" and scope ~= "elements")
        or type(id) ~= "string" or id == ""
        or type(path) ~= "string" or path == ""
    then
        return false
    end
    local parentValue, styleName, relativePath =
        GetAppearanceParentValue(scope, id, windowID, path)
    if parentValue ~= nil and type(parentValue) ~= type(value) then return false end

    local profile = NSkin:GetProfile()
    local scopes = profile.appearanceOverrides
    local styleOverrides = scopes and scopes[scope] and scopes[scope][id]
        and scopes[scope][id][styleName]
    local currentValue = styleOverrides
        and GetPath(styleOverrides, relativePath, false) or nil
    local isBlizzardGeometrySentinel = value == 0
        and (path:match("%.width$") or path:match("%.height$")
            or path:match("%.textSize$") or path:match("%.iconSize$"))
    local newValue = (isBlizzardGeometrySentinel
        or (parentValue ~= nil and TablesEqual(value, parentValue)))
        and nil or value
    if TablesEqual(currentValue, newValue) then return false end

    profile.appearanceOverrides = profile.appearanceOverrides or {}
    scopes = profile.appearanceOverrides
    scopes[scope] = scopes[scope] or {}
    scopes[scope][id] = scopes[scope][id] or {}
    scopes[scope][id][styleName] = scopes[scope][id][styleName] or {}
    styleOverrides = scopes[scope][id][styleName]
    local _, parent, key = GetPath(styleOverrides, relativePath, true)
    parent[key] = newValue
    PruneEmptyTables(profile.appearanceOverrides)
    if not next(profile.appearanceOverrides) then profile.appearanceOverrides = nil end
    NSkin:RefreshAppearance()
    return true
end

local function ResetAppearanceOverride(scope, id, path)
    if type(id) ~= "string" or id == "" then return false end
    local profile = NSkin:GetProfile()
    local scopes = profile.appearanceOverrides
    local overrides = scopes and scopes[scope] and scopes[scope][id]
    if not overrides then return false end
    local changed
    if path == nil then
        scopes[scope][id] = nil
        changed = true
    else
        local paths = type(path) == "table" and path or { path }
        for i = 1, #paths do
            local styleName, relativePath = paths[i]:match("^([^.]+)%.(.+)$")
            local styleOverrides = styleName and overrides[styleName]
            if styleOverrides then
                local current, parent, key = GetPath(
                    styleOverrides, relativePath, false)
                if parent and current ~= nil then
                    parent[key] = nil
                    changed = true
                end
            end
        end
    end
    if not changed then return false end
    PruneEmptyTables(profile.appearanceOverrides)
    if not next(profile.appearanceOverrides) then profile.appearanceOverrides = nil end
    NSkin:RefreshAppearance()
    return true
end

function NSkin:SetWindowAppearanceOverride(windowID, path, value)
    if not appearanceScopes[windowID] then return false end
    return SetAppearanceOverride("windows", windowID, nil, path, value)
end

function NSkin:ResetWindowAppearanceOverride(windowID, path)
    if not appearanceScopes[windowID] then return false end
    return ResetAppearanceOverride("windows", windowID, path)
end

function NSkin:SetElementAppearanceOverride(elementID, windowID, path, value)
    if not appearanceScopes[windowID] then return false end
    return SetAppearanceOverride("elements", elementID, windowID, path, value)
end

function NSkin:ResetElementAppearanceOverride(elementID, path)
    return ResetAppearanceOverride("elements", elementID, path)
end

function NSkin:ResetElementAppearanceOverrides(elementID, paths)
    return ResetAppearanceOverride("elements", elementID, paths)
end

function NSkin:GetBorderAccentColor()
    return self:GetStyle("window").border
end

function NSkin:SetBorderAccentColor(color)
    if type(color) ~= "table" then return false end
    return self:SetAppearanceOverride("window.border", color)
end

function NSkin:ResetBorderAccentColor()
    return self:ResetAppearanceOverride("window.border")
end

function NSkin:IsAccentColorEnabled()
    return self:GetStyle("accent").enabled == true
end

function NSkin:GetAccentColor()
    return self:GetStyle("accent").color
end

function NSkin:SetAccentColorEnabled(enabled)
    return self:SetAppearanceOverride("accent.enabled", enabled == true)
end

function NSkin:SetAccentColor(color)
    if type(color) ~= "table" then return false end
    return self:SetAppearanceOverride("accent.color", color)
end

function NSkin:ResetAccentColor()
    return self:ResetAppearanceOverride("accent.color")
end

function NSkin:GetSharedBorderColor()
    if self:IsAccentColorEnabled() then return self:GetAccentColor() end
    return self:GetBorderAccentColor()
end

function NSkin:GetComponentBorderSetting(styleName, style)
    local profile = self:GetProfile()
    local override = profile.appearance and profile.appearance[styleName]
        and profile.appearance[styleName].border
    if override ~= nil then
        style = style or self:GetStyle(styleName)
        if style and style.border then return style.border end
    end
    return self:GetBorderAccentColor()
end

function NSkin:GetComponentBorderColor(styleName, style)
    if self:IsAccentColorEnabled() then return self:GetAccentColor() end
    return self:GetComponentBorderSetting(styleName, style)
end

function NSkin:GetAppearanceBorderColor(styleName, style, windowID, elementID)
    if style and style.borderMode then
        return self:GetResolvedAppearanceColor(style, "border")
    end
    local profile = self:GetProfile()
    local overrides = profile.appearanceOverrides
    local elementBorder = elementID and overrides and overrides.elements
        and overrides.elements[elementID] and overrides.elements[elementID][styleName]
        and overrides.elements[elementID][styleName].border
    if elementBorder ~= nil then return style.border end
    local chain = windowID and GetAppearanceScopeChain(windowID)
    for i = #(chain or {}), 1, -1 do
        local windowBorder = overrides and overrides.windows
            and overrides.windows[chain[i]]
            and overrides.windows[chain[i]][styleName]
            and overrides.windows[chain[i]][styleName].border
        if windowBorder ~= nil then return style.border end
    end
    return self:GetComponentBorderColor(styleName, style)
end

function NSkin:SetComponentBorderColor(styleName, color)
    local defaults = self.baseAppearance and self.baseAppearance[styleName]
    if type(color) ~= "table" or type(defaults) ~= "table"
        or type(defaults.border) ~= "table"
    then
        return false
    end
    local profile = self:GetProfile()
    profile.appearance = profile.appearance or {}
    profile.appearance[styleName] = profile.appearance[styleName] or {}
    profile.appearance[styleName].border = TablesEqual(color, self:GetBorderAccentColor())
        and nil or color
    PruneEmptyTables(profile.appearance)
    if not next(profile.appearance) then profile.appearance = nil end
    self:RefreshAppearance()
    return true
end

function NSkin:ResetComponentBorderColor(styleName)
    return self:ResetAppearanceOverride(styleName .. ".border")
end

function NSkin:GetWindowBorderColor()
    return self:GetSharedBorderColor()
end

function NSkin:GetTabSpacing()
    return self:GetStyle("tab").spacing
end

local function RefreshTabLayouts()
    NSkin:InvalidateAppearance()
    if NSkin.RefreshRegisteredTabGroups then NSkin:RefreshRegisteredTabGroups() end
end

local function SetTabLayoutOverride(path, value)
    local defaultValue = GetPath(NSkin.baseAppearance, path, false)
    local profile = NSkin:GetProfile()
    profile.appearance = profile.appearance or {}
    local _, parent, key = GetPath(profile.appearance, path, true)
    parent[key] = value == defaultValue and nil or value
    PruneEmptyTables(profile.appearance)
    if not next(profile.appearance) then profile.appearance = nil end
    RefreshTabLayouts()
    return true
end

function NSkin:SetTabSpacing(spacing)
    spacing = tonumber(spacing)
    if not spacing then return false end
    spacing = math.max(-30, math.min(30, math.floor(spacing + 0.5)))
    return SetTabLayoutOverride("tab.spacing", spacing)
end

function NSkin:ResetTabSpacing()
    return self:ResetAppearanceOverride("tab.spacing")
end

function NSkin:GetBottomTabAnchor()
    local bottom = self:GetStyle("tab").bottom
    return bottom and bottom.anchor or nil
end

function NSkin:GetBottomTabOffsetX()
    local bottom = self:GetStyle("tab").bottom
    return bottom and bottom.offsetX or nil
end

function NSkin:GetBottomTabOffsetY()
    local bottom = self:GetStyle("tab").bottom
    return bottom and bottom.offsetY or nil
end

function NSkin:GetTabPlacement()
    local layout = self:GetStyle("tab").bottom or {}
    return {
        mode = layout.mode,
        point = layout.point,
        relativePoint = layout.relativePoint,
        x = layout.x,
        y = layout.y,
        edge = layout.edge or "BOTTOM",
        side = layout.side or "OUTSIDE",
        alignment = layout.anchor or "LEFT",
        alongOffset = layout.offsetX or 0,
        edgeOffset = layout.offsetY or 0,
    }
end

function NSkin:SetTabPlacement(placement)
    if type(placement) ~= "table" then return false end
    local profile = self:GetProfile()
    profile.appearance = profile.appearance or {}
    profile.appearance.tab = profile.appearance.tab or {}
    profile.appearance.tab.bottom = profile.appearance.tab.bottom or {}
    local bottom = profile.appearance.tab.bottom
    if placement.mode == "GRID" then
        local x, y = tonumber(placement.x), tonumber(placement.y)
        if not x or not y then return false end
        bottom.mode = "GRID"
        bottom.point = placement.point or "TOPLEFT"
        bottom.relativePoint = placement.relativePoint or "TOPLEFT"
        bottom.x = math.max(-2000, math.min(2000, RoundOne(x)))
        bottom.y = math.max(-2000, math.min(2000, RoundOne(y)))
        bottom.relativeTo = nil
        RefreshTabLayouts()
        return true
    end
    local alignment = placement.alignment
    if alignment ~= "LEFT" and alignment ~= "CENTER" and alignment ~= "RIGHT" then
        return false
    end
    local current = self:GetTabPlacement()
    local edge = placement.edge or current.edge
    local side = placement.side or current.side
    if edge ~= "TOP" and edge ~= "BOTTOM" then return false end
    if side ~= "INSIDE" and side ~= "OUTSIDE" then return false end
    local alongOffset = tonumber(placement.alongOffset)
    local edgeOffset = tonumber(placement.edgeOffset)
    if not alongOffset or not edgeOffset then return false end
    alongOffset = math.max(-2000, math.min(2000, RoundOne(alongOffset)))
    edgeOffset = math.max(-2000, math.min(2000, RoundOne(edgeOffset)))

    bottom.mode, bottom.point, bottom.relativePoint, bottom.x, bottom.y = nil, nil, nil, nil, nil
    bottom.edge = edge
    bottom.side = side
    bottom.anchor = alignment
    bottom.offsetX = alongOffset
    bottom.offsetY = edgeOffset
    PruneEmptyTables(profile.appearance)
    if not next(profile.appearance) then profile.appearance = nil end
    RefreshTabLayouts()
    return true
end

function NSkin:GetBottomTabPlacement()
    return self:GetTabPlacement()
end

function NSkin:SetBottomTabPlacement(placement)
    return self:SetTabPlacement(placement)
end

function NSkin:SetBottomTabAnchor(anchor)
    if anchor ~= "LEFT" and anchor ~= "CENTER" and anchor ~= "RIGHT" then
        return false
    end
    local placement = self:GetTabPlacement()
    placement.alignment = anchor
    return self:SetTabPlacement(placement)
end

function NSkin:SetBottomTabOffsetX(offset)
    offset = tonumber(offset)
    if not offset then return false end
    local placement = self:GetTabPlacement()
    placement.alongOffset = offset
    return self:SetTabPlacement(placement)
end

function NSkin:SetBottomTabOffsetY(offset)
    offset = tonumber(offset)
    if not offset then return false end
    local placement = self:GetTabPlacement()
    placement.edgeOffset = offset
    return self:SetTabPlacement(placement)
end

function NSkin:ResetTabLayout()
    local changed = self:ResetAppearanceOverride("tab.bottom")
    if self.ForEachRegisteredTabGroup then
        self:ForEachRegisteredTabGroup(function(group)
            self:RestoreTabGroupOriginalPlacement(group.id)
        end)
    end
    return changed
end


function NSkin:ResetBottomTabLayout()
    return self:ResetTabLayout()
end

function NSkin:InvalidateAppearance()
    wipe(resolvedStyles)
end

function NSkin:RefreshAppearance()
    self:InvalidateAppearance()

    if self.RefreshOptionsAppearance then self:RefreshOptionsAppearance() end
    if self.RefreshSkinningModeAppearance then self:RefreshSkinningModeAppearance() end
    for _, module in pairs(self.modules) do
        if self:IsModuleEnabled(module.name) and type(module.RefreshAppearance) == "function" then
            module:RefreshAppearance()
        end
    end
    if self.RefreshRegisteredTabGroups then self:RefreshRegisteredTabGroups() end
end

function NSkin:SetAppearanceOverride(path, value)
    if type(path) ~= "string" or path == "" then return false end
    local defaultValue = GetPath(self.baseAppearance, path, false)
    if defaultValue ~= nil and type(defaultValue) ~= type(value) then return false end

    local profile = self:GetProfile()
    profile.appearance = profile.appearance or {}
    local _, parent, key = GetPath(profile.appearance, path, true)
    parent[key] = defaultValue ~= nil and TablesEqual(value, defaultValue)
        and nil or value
    PruneEmptyTables(profile.appearance)
    if not next(profile.appearance) then profile.appearance = nil end
    self:RefreshAppearance()
    return true
end

function NSkin:ResetAppearanceOverride(path)
    if type(path) ~= "string" or path == "" then return false end
    local profile = self:GetProfile()
    if not profile.appearance then return true end

    local _, parent, key = GetPath(profile.appearance, path, false)
    if parent then parent[key] = nil end
    PruneEmptyTables(profile.appearance)
    if not next(profile.appearance) then profile.appearance = nil end
    self:RefreshAppearance()
    return true
end

end

do
local _, NSkin = ...

local skinData = setmetatable({}, { __mode = "k" })
local pixelBorders = setmetatable({}, { __mode = "k" })
local QueuePixelBorderResnap

function NSkin:GetPhysicalPixelSize(frame)
    local _, physicalHeight
    if _G.GetPhysicalScreenSize then
        _, physicalHeight = _G.GetPhysicalScreenSize()
    end
    physicalHeight = tonumber(physicalHeight) or 768
    local scale = frame and frame.GetEffectiveScale and frame:GetEffectiveScale()
        or (UIParent and UIParent:GetEffectiveScale()) or 1
    if not scale or scale <= 0 then scale = 1 end
    return (768 / math.max(1, physicalHeight)) / scale
end

function NSkin:SnapToPhysicalPixel(frame, value)
    value = tonumber(value) or 0
    local pixel = self:GetPhysicalPixelSize(frame)
    local scaled = value / pixel
    if scaled >= 0 then return math.floor(scaled + 0.5) * pixel end
    return math.ceil(scaled - 0.5) * pixel
end

function NSkin:ConfigureOwnedPixelTexture(texture)
    if not texture then return end
    if texture.SetSnapToPixelGrid then texture:SetSnapToPixelGrid(false) end
    if texture.SetTexelSnappingBias then texture:SetTexelSnappingBias(0) end
end

local function ApplyPixelBorderGeometry(border)
    if not border or not border.anchor then return end
    local anchor = border.anchor
    local pixel = NSkin:GetPhysicalPixelSize(anchor)
    local requestedSize = math.max(1, tonumber(border.requestedSize) or 1)
    local thickness = requestedSize * pixel
    local requestedPadding = tonumber(border.requestedPadding)
    local padding = requestedPadding and requestedPadding * pixel or 0
    border.pixelSize = pixel
    border.effectiveSize = thickness
    border.effectivePadding = padding

    for _, key in ipairs({ "top", "bottom", "left", "right" }) do
        local edge = border[key]
        if edge then
            edge:ClearAllPoints()
            NSkin:ConfigureOwnedPixelTexture(edge)
        end
    end
    if border.outside and requestedPadding == nil then
        if border.top then
            border.top:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", -thickness, 0)
            border.top:SetPoint("BOTTOMRIGHT", anchor, "TOPRIGHT", thickness, 0)
        end
        if border.bottom then
            border.bottom:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", -thickness, 0)
            border.bottom:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", thickness, 0)
        end
        if border.left then
            border.left:SetPoint("TOPRIGHT", anchor, "TOPLEFT", 0, thickness)
            border.left:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMLEFT", 0, -thickness)
        end
        if border.right then
            border.right:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 0, thickness)
            border.right:SetPoint("BOTTOMLEFT", anchor, "BOTTOMRIGHT", 0, -thickness)
        end
    else
        if border.top then
            border.top:SetPoint("TOPLEFT", anchor, "TOPLEFT", -padding, padding)
            border.top:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", padding, padding)
        end
        if border.bottom then
            border.bottom:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", -padding, -padding)
            border.bottom:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", padding, -padding)
        end
        if border.left then
            border.left:SetPoint("TOPLEFT", anchor, "TOPLEFT", -padding, padding)
            border.left:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", -padding, -padding)
        end
        if border.right then
            border.right:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", padding, padding)
            border.right:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", padding, -padding)
        end
    end
    if border.top then border.top:SetHeight(thickness) end
    if border.bottom then border.bottom:SetHeight(thickness) end
    if border.left then border.left:SetWidth(thickness) end
    if border.right then border.right:SetWidth(thickness) end
end

function NSkin:ResnapPixelBorder(border)
    ApplyPixelBorderGeometry(border)
end

function NSkin:ResnapAllPixelBorders()
    for border in pairs(pixelBorders) do ApplyPixelBorderGeometry(border) end
end

local function QueueBorderSetResnap(data)
    if not data or data.pending then return end
    data.pending = true
    local function Resnap()
        data.pending = nil
        for border in pairs(data.borders or {}) do ApplyPixelBorderGeometry(border) end
    end
    if C_Timer and C_Timer.After then C_Timer.After(0, Resnap) else Resnap() end
end

function NSkin:GetSkinData(object, namespace, create)
    if not object then return nil end

    -- Preserve GetSkinData(object, false) while allowing each subsystem to
    -- keep its state in a clearly named table.
    if type(namespace) == "boolean" then
        create = namespace
        namespace = nil
    end

    local data = skinData[object]
    if not data and create ~= false then
        data = {}
        skinData[object] = data
    end
    if not data or not namespace then return data end

    local scoped = data[namespace]
    if not scoped and create ~= false then
        scoped = {}
        data[namespace] = scoped
    end
    return scoped
end

function NSkin:GetPixelBorder(frame, key)
    local data = self:GetSkinData(frame, "primitives", false)
    return data and data.borders and data.borders[key]
end

function NSkin:GetFlatBackground(frame, key)
    local data = self:GetSkinData(frame, "primitives", false)
    return data and data.backgrounds and data.backgrounds[key or "NSkinFlatBackground"]
end

-- Creates four simple texture edges without using BackdropTemplate or NineSlice.
-- The regions are owned by the target frame and do not alter protected state.

-- Icons Skinning
function NSkin:CreatePixelBorder(frame, key, size, color, outside, anchor)
    if not frame or not frame.CreateTexture then return nil end
    local data = self:GetSkinData(frame, "primitives")
    if key then
        data.borders = data.borders or {}
        if data.borders[key] then return data.borders[key] end
    end

    size = size or 1
    color = color or self:GetStyle("icon").border
    anchor = anchor or frame

    local function NewEdge()
        local edge = frame:CreateTexture(nil, "OVERLAY", nil, 7)
        edge:SetColorTexture(unpack(color))
        self:ConfigureOwnedPixelTexture(edge)
        return edge
    end

    local top = NewEdge()
    local bottom = NewEdge()
    local left = NewEdge()
    local right = NewEdge()

    local border = { top = top, bottom = bottom, left = left, right = right,
        frame = frame, anchor = anchor, outside = outside == true,
        requestedSize = tonumber(size) or 1 }
    pixelBorders[border] = true
    ApplyPixelBorderGeometry(border)
    -- Only frames support OnSizeChanged/OnShow scripts. Borders may be
    -- anchored to a Texture (for example collection icons), so watch their
    -- owning frame instead of attempting to attach scripts to the region.
    local watchTarget = anchor
    if not (anchor.IsObjectType and anchor:IsObjectType("Frame")) then
        watchTarget = frame
    end
    local watchData = self:GetSkinData(watchTarget, "physicalPixels")
    watchData.borders = watchData.borders
        or setmetatable({}, { __mode = "k" })
    watchData.borders[border] = true
    if not watchData.resnapHooked then
        watchData.resnapHooked = true
        if watchTarget.HookScript then
            watchTarget:HookScript("OnSizeChanged", function()
                QueueBorderSetResnap(watchData)
            end)
            watchTarget:HookScript("OnShow", function()
                QueueBorderSetResnap(watchData)
            end)
        end
        if _G.hooksecurefunc and watchTarget.SetScale then
            pcall(_G.hooksecurefunc, watchTarget, "SetScale", function()
                QueueBorderSetResnap(watchData)
            end)
        end
    end
    if key then data.borders[key] = border end
    return border
end

-- Creates only the requested physical-pixel edges. Components that attach to
-- a window edge can therefore omit that seam instead of drawing a full border
-- and covering one side with another region.
function NSkin:CreatePixelEdgeBorder(frame, key, edges, size, color, anchor)
    if not frame or not frame.CreateTexture or type(edges) ~= "table" then
        return nil
    end
    local data = self:GetSkinData(frame, "primitives")
    data.borders = data.borders or {}
    if key and data.borders[key] then return data.borders[key] end

    color = color or self:GetStyle("icon").border
    local border = {
        frame = frame,
        anchor = anchor or frame,
        outside = false,
        requestedSize = tonumber(size) or 1,
    }
    for _, edgeName in ipairs(edges) do
        if (edgeName == "top" or edgeName == "bottom"
            or edgeName == "left" or edgeName == "right")
            and not border[edgeName]
        then
            local edge = frame:CreateTexture(nil, "OVERLAY", nil, 7)
            edge:SetColorTexture(unpack(color))
            self:ConfigureOwnedPixelTexture(edge)
            border[edgeName] = edge
        end
    end
    if not border.top and not border.bottom and not border.left
        and not border.right
    then return nil end

    pixelBorders[border] = true
    ApplyPixelBorderGeometry(border)
    local watchTarget = border.anchor
    if not (watchTarget.IsObjectType and watchTarget:IsObjectType("Frame")) then
        watchTarget = frame
    end
    local watchData = self:GetSkinData(watchTarget, "physicalPixels")
    watchData.borders = watchData.borders
        or setmetatable({}, { __mode = "k" })
    watchData.borders[border] = true
    if not watchData.resnapHooked then
        watchData.resnapHooked = true
        if watchTarget.HookScript then
            watchTarget:HookScript("OnSizeChanged", function()
                QueueBorderSetResnap(watchData)
            end)
            watchTarget:HookScript("OnShow", function()
                QueueBorderSetResnap(watchData)
            end)
        end
        if _G.hooksecurefunc and watchTarget.SetScale then
            pcall(_G.hooksecurefunc, watchTarget, "SetScale", function()
                QueueBorderSetResnap(watchData)
            end)
        end
    end
    if key then data.borders[key] = border end
    return border
end

function NSkin:SetPixelBorderShown(border, shown)
    if not border or border.shown == shown then return end

    if border.top then border.top:SetShown(shown) end
    if border.bottom then border.bottom:SetShown(shown) end
    if border.left then border.left:SetShown(shown) end
    if border.right then border.right:SetShown(shown) end
    border.shown = shown
end

function NSkin:SetPixelBorderColor(border, red, green, blue, alpha)
    if not border then return end

    alpha = alpha or 1
    for _, key in ipairs({ "top", "bottom", "left", "right" }) do
        local edge = border[key]
        if edge then
            edge:SetColorTexture(red, green, blue, alpha)
            self:ConfigureOwnedPixelTexture(edge)
        end
    end
end

function NSkin:SetPixelBorderSize(border, size)
    if not border or not size then return end
    border.requestedSize = tonumber(size) or border.requestedSize or 1
    ApplyPixelBorderGeometry(border)
end

function NSkin:SetPixelBorderPadding(border, padding)
    if not border or not border.anchor then return end
    border.requestedPadding = tonumber(padding) or 0
    border.padding = border.requestedPadding
    ApplyPixelBorderGeometry(border)
end

function NSkin:CreateQualityBorder(frame, anchor, key, size, outside)
    local border = self:CreatePixelBorder(frame, key, size, nil, outside == true, anchor)
    self:SetPixelBorderShown(border, false)
    return border
end

function NSkin:SetQualityBorder(border, quality)
    local item = _G.C_Item
    if not border then return false end
    local style = self:GetStyle("icon")
    if style and style.qualityColor == false then
        self:SetPixelBorderColor(border, unpack(style.border))
        self:SetPixelBorderShown(border, true)
        return true
    end
    if quality == nil or not item or not item.GetItemQualityColor then
        self:SetPixelBorderShown(border, false)
        return false
    end

    local red, green, blue = item.GetItemQualityColor(quality)
    self:SetPixelBorderColor(border, red, green, blue)
    self:SetPixelBorderShown(border, true)
    return true
end

function NSkin:HideTextureRegions(frame, textureToKeep)
    if not frame or not frame.GetRegions then return end

    local regions = { frame:GetRegions() }
    for i = 1, #regions do
        local region = regions[i]
        if region ~= textureToKeep and region.GetObjectType
            and region:GetObjectType() == "Texture" then
            -- Blizzard frequently shows these regions again when control
            -- state changes. Alpha remains suppressed across those Show calls.
            region:SetAlpha(0)
            region:SetTexture(nil)
            region:Hide()
        end
    end
end

function NSkin:CreateFlatBackground(frame, key, color, borderColor)
    if not frame or not frame.CreateTexture or not color or not borderColor then return nil end

    key = key or "NSkinFlatBackground"
    local data = self:GetSkinData(frame, "primitives")
    data.backgrounds = data.backgrounds or {}
    local background = data.backgrounds[key]
    if not background then
        background = frame:CreateTexture(nil, "BACKGROUND", nil, 7)
        if not background then return nil end
        background:SetPoint("TOPLEFT", 1, -1)
        background:SetPoint("BOTTOMRIGHT", -1, 1)
        data.backgrounds[key] = background
    end
    background:SetColorTexture(unpack(color))
    self:ConfigureOwnedPixelTexture(background)
    background:Show()
    local border = self:CreatePixelBorder(frame, key .. "Border", 1, borderColor)
    self:SetPixelBorderColor(border, unpack(borderColor))
    return background
end

local pixelResnapPending = false
QueuePixelBorderResnap = function()
    if pixelResnapPending then return end
    pixelResnapPending = true
    local function Resnap()
        pixelResnapPending = false
        NSkin:ResnapAllPixelBorders()
    end
    if C_Timer and C_Timer.After then C_Timer.After(0, Resnap) else Resnap() end
end

NSkin:RegisterEvent("UI_SCALE_CHANGED", QueuePixelBorderResnap)
NSkin:RegisterEvent("DISPLAY_SIZE_CHANGED", QueuePixelBorderResnap)

end

local _, NSkin = ...

local COMPONENT_STATE = "components"
local tabGroups = {}
local tabGroupOriginalPoints = {}
local skinningElements = {}
local componentCallbacks = {}
local movableOriginalPoints = {}
local movableOriginalSizes = {}
local componentBaselines = setmetatable({}, { __mode = "k" })
local componentBaselineTargets = setmetatable({}, { __mode = "v" })
local movableElementsByWindow = setmetatable({}, { __mode = "k" })
local movableWatchers = setmetatable({}, { __mode = "k" })
local registeredWindows = setmetatable({}, { __mode = "k" })
local windowSequence = 0
local SUPPRESS_NOTIFICATION = { suppressNotify = true }
local GetCurrentWindowPlacement

local function CaptureFramePoints(target)
    local points = {}
    if target and target.GetNumPoints then
        for i = 1, target:GetNumPoints() do
            points[i] = { target:GetPoint(i) }
        end
    end
    return points
end

local function RestoreFramePoints(target, points)
    if not target or not target.ClearAllPoints or type(points) ~= "table" then
        return false
    end
    target:ClearAllPoints()
    for i = 1, #points do target:SetPoint(unpack(points[i])) end
    return true
end

function NSkin:CaptureComponentBaseline(id, target, options)
    if type(id) ~= "string" or id == "" or not target then return nil end
    options = options or {}
    local baselines = componentBaselines[target]
    if not baselines then
        baselines = {}
        componentBaselines[target] = baselines
    end
    local existing = baselines[id]
    if existing and not options.force then return existing end
    if type(options.canCapture) == "function"
        and options.canCapture(target) ~= true
    then return nil end

    local baseline = existing or { modified = {} }
    baseline.id, baseline.target = id, target
    baseline.options = options
    if options.size and target.GetSize then
        baseline.width, baseline.height = target:GetSize()
    end
    if options.points then baseline.points = CaptureFramePoints(target) end
    local fontString = options.font == true and target or options.font
    if fontString and fontString.GetFont then
        baseline.fontTarget = fontString
        baseline.font = { fontString:GetFont() }
    end
    local editBox = options.textInsets == true and target or options.textInsets
    if editBox and editBox.GetTextInsets then
        baseline.textInsetsTarget = editBox
        baseline.textInsets = { editBox:GetTextInsets() }
    end
    local spacingTarget = options.spacing == true and target or options.spacing
    if spacingTarget then
        baseline.spacingTarget = spacingTarget
        baseline.spacing = spacingTarget.spacing
    end
    baseline.refreshBlizzardLayout = options.refreshBlizzardLayout
    baselines[id] = baseline
    componentBaselineTargets[id] = target
    return baseline
end

function NSkin:GetComponentBaseline(idOrTarget)
    if type(idOrTarget) == "string" then
        local target = componentBaselineTargets[idOrTarget]
        local baselines = target and componentBaselines[target]
        return baselines and baselines[idOrTarget] or nil
    end
    local baselines = idOrTarget and componentBaselines[idOrTarget]
    if not baselines then return nil end
    for _, baseline in pairs(baselines) do return baseline end
end

function NSkin:MarkComponentGeometryModified(idOrTarget, property, modified)
    local baseline = self:GetComponentBaseline(idOrTarget)
    if not baseline then return false end
    baseline.modified[property] = modified ~= false or nil
    return true
end

function NSkin:RestoreComponentBaseline(idOrTarget, properties)
    local baseline = self:GetComponentBaseline(idOrTarget)
    if not baseline then return false end
    if type(baseline.refreshBlizzardLayout) == "function" then
        if baseline.refreshBlizzardLayout(baseline) == true then
            wipe(baseline.modified)
            local options = baseline.options or {}
            options.force = true
            self:CaptureComponentBaseline(
                baseline.id, baseline.target, options)
            options.force = nil
            return true
        end
    end
    local requested = type(properties) == "table" and properties or nil
    local function ShouldRestore(key)
        return (not requested or requested[key]) and baseline.modified[key]
    end
    local target = baseline.target
    if ShouldRestore("size") and target.SetSize
        and baseline.width and baseline.height
    then target:SetSize(baseline.width, baseline.height) end
    if ShouldRestore("points") then RestoreFramePoints(target, baseline.points) end
    if ShouldRestore("font") and baseline.fontTarget and baseline.font then
        baseline.fontTarget:SetFont(unpack(baseline.font))
    end
    if ShouldRestore("textInsets") and baseline.textInsetsTarget
        and baseline.textInsets
    then baseline.textInsetsTarget:SetTextInsets(unpack(baseline.textInsets)) end
    if ShouldRestore("spacing") and baseline.spacingTarget then
        baseline.spacingTarget.spacing = baseline.spacing
        if baseline.spacingTarget.MarkDirty then baseline.spacingTarget:MarkDirty() end
    end
    for key in pairs(baseline.modified) do
        if not requested or requested[key] then baseline.modified[key] = nil end
    end
    return true
end

function NSkin:RefreshComponentBaseline(idOrTarget)
    local baseline = self:GetComponentBaseline(idOrTarget)
    if not baseline or next(baseline.modified) then return false end
    local options = baseline.options or {}
    options.force = true
    self:CaptureComponentBaseline(baseline.id, baseline.target, options)
    options.force = nil
    return true
end

local function CopyPlacement(placement)
    local copy = {}
    for key, value in pairs(placement or {}) do copy[key] = value end
    return copy
end

function NSkin:RegisterComponentCallback(event, callback, owner)
    if type(event) ~= "string" or type(callback) ~= "function" then return false end
    local listeners = componentCallbacks[event]
    if not listeners then
        listeners = {}
        componentCallbacks[event] = listeners
    end
    listeners[#listeners + 1] = { callback = callback, owner = owner }
    return true
end

function NSkin:UnregisterComponentCallbacks(owner)
    if owner == nil then return false end
    for _, listeners in pairs(componentCallbacks) do
        for i = #listeners, 1, -1 do
            if listeners[i].owner == owner then table.remove(listeners, i) end
        end
    end
    return true
end

local function FireComponentCallback(event, ...)
    local listeners = componentCallbacks[event]
    if not listeners then return end
    for i = 1, #listeners do
        local listener = listeners[i]
        listener.callback(listener.owner, ...)
    end
end

function NSkin:CreateOptionsSlider(parent, options)
    if not parent then return nil end
    options = options or {}
    local slider = CreateFrame("Slider", nil, parent)
    slider:SetSize(options.width or 280, options.height or 18)
    slider:SetOrientation("HORIZONTAL")
    slider:SetMinMaxValues(options.min or 0, options.max or 100)
    slider:SetValueStep(options.step or 1)
    slider:SetObeyStepOnDrag(options.obeyStep ~= false)
    local track = slider:CreateTexture(nil, "BACKGROUND")
    track:SetPoint("LEFT", slider, "LEFT", 0, 0)
    track:SetPoint("RIGHT", slider, "RIGHT", 0, 0)
    track:SetHeight(4)
    track:SetColorTexture(0.35, 0.35, 0.35, 1)

    local accent = self:GetAccentColor()
    local fillGlows = {}
    local glowHeights = { 12, 8, 4 }
    local glowAlphas = { 0.10, 0.18, 0.34 }
    for i = 1, 3 do
        local glow = slider:CreateTexture(nil, "ARTWORK", nil, -2 + i)
        glow:SetPoint("LEFT", slider, "LEFT", 0, 0)
        glow:SetHeight(glowHeights[i])
        glow:SetBlendMode("ADD")
        glow:SetColorTexture(accent[1], accent[2], accent[3], glowAlphas[i])
        fillGlows[i] = glow
    end

    local fill = slider:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("LEFT", slider, "LEFT", 0, 0)
    fill:SetHeight(4)
    fill:SetColorTexture(unpack(accent))

    slider:SetThumbTexture("Interface\\Buttons\\WHITE8X8")
    local marker = slider:GetThumbTexture()
    marker:SetSize(3, 14)
    marker:SetColorTexture(unpack(accent))
    local markerGlowOuter = slider:CreateTexture(nil, "ARTWORK")
    markerGlowOuter:SetPoint("CENTER", marker, "CENTER", 0, 0)
    markerGlowOuter:SetSize(7, 17)
    markerGlowOuter:SetBlendMode("ADD")
    markerGlowOuter:SetColorTexture(accent[1], accent[2], accent[3], 0.12)
    local markerGlowInner = slider:CreateTexture(nil, "ARTWORK", nil, 1)
    markerGlowInner:SetPoint("CENTER", marker, "CENTER", 0, 0)
    markerGlowInner:SetSize(3, 13)
    markerGlowInner:SetBlendMode("ADD")
    markerGlowInner:SetColorTexture(accent[1], accent[2], accent[3], 0.30)

    local minimum, maximum = options.min or 0, options.max or 100
    local function RefreshSliderVisual(value)
        local range = maximum - minimum
        local ratio = range > 0 and math.max(0, math.min(1,
            ((tonumber(value) or minimum) - minimum) / range)) or 0
        local width = math.max(0.001, slider:GetWidth() * ratio)
        fill:SetWidth(width)
        for i = 1, 3 do fillGlows[i]:SetWidth(width) end
    end
    local function RefreshSlider(_, value)
        RefreshSliderVisual(value)
        if type(options.onValueChanged) == "function" then
            options.onValueChanged(slider, value)
        end
        if not slider.nskinDragging
            and type(options.onValueCommitted) == "function"
        then
            options.onValueCommitted(slider, value)
        end
    end
    slider:SetScript("OnMouseDown", function(self) self.nskinDragging = true end)
    slider:SetScript("OnMouseUp", function(self)
        if not self.nskinDragging then return end
        self.nskinDragging = nil
        if type(options.onValueCommitted) == "function" then
            options.onValueCommitted(self, self:GetValue())
        end
    end)
    slider:SetScript("OnValueChanged", RefreshSlider)
    RefreshSliderVisual(slider:GetValue())
    return slider
end

-- Buttons Skinning
local function ShowFlatButtonGlow(button)
    local data = NSkin:GetSkinData(button, COMPONENT_STATE, false)
    if data and data.hoverGlow and (not button.IsEnabled or button:IsEnabled()) then
        data.hoverGlow:Show()
    end
end

local function HideFlatButtonGlow(button)
    local data = NSkin:GetSkinData(button, COMPONENT_STATE, false)
    if data and data.hoverGlow then data.hoverGlow:Hide() end
end

function NSkin:CreateFlatButtonGlow(button, alpha)
    if not button or not button.CreateTexture then return nil end
    local data = self:GetSkinData(button, COMPONENT_STATE)
    if data.hoverGlow then
        data.hoverGlow:SetColorTexture(1, 1, 1, alpha or 0.10)
        return data.hoverGlow
    end

    local glow = button:CreateTexture(nil, "OVERLAY", nil, -1)
    glow:SetPoint("TOPLEFT", 1, -1)
    glow:SetPoint("BOTTOMRIGHT", -1, 1)
    glow:SetColorTexture(1, 1, 1, alpha or 0.10)
    glow:Hide()
    data.hoverGlow = glow

    if button.HookScript then
        button:HookScript("OnEnter", ShowFlatButtonGlow)
        button:HookScript("OnLeave", HideFlatButtonGlow)
    end

    return glow
end

function NSkin:SetFlatButtonLabel(button, label, size, offsetX, offsetY)
    if not button or not button.CreateFontString then return nil end

    local data = self:GetSkinData(button, COMPONENT_STATE)
    local text = data.label
    if not text then
        text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        data.label = text
    end

    text:ClearAllPoints()
    text:SetPoint("CENTER", button, "CENTER", offsetX or 0, offsetY or 0)
    text:SetText(label or "")

    if size then
        local font, _, flags = text:GetFont()
        if font then text:SetFont(font, size, flags) end
    end

    text:SetAlpha(1)
    text:Show()
    return text
end

function NSkin:SkinFlatButton(button, label, backgroundColor, borderColor,
    labelSize, labelOffsetX, labelOffsetY)
    if not button or not button.CreateTexture or not button.CreateFontString then return end

    local style = self:GetStyle("button")
    backgroundColor = backgroundColor or style.background
    borderColor = borderColor or self:GetComponentBorderColor("button", style)

    local background = self:GetFlatBackground(button)
    if not background then
        self:HideTextureRegions(button)
    end

    self:CreateFlatBackground(button, nil, backgroundColor, borderColor)
    self:CreateFlatButtonGlow(button, style.hoverAlpha)
    local text = self:SetFlatButtonLabel(button, label, labelSize, labelOffsetX, labelOffsetY)
    if text then text:SetTextColor(unpack(style.text)) end
end

local function SuppressActionButtonNativeText(button)
    local data = NSkin:GetSkinData(button, COMPONENT_STATE, false)
    if not data then return end
    data.actionNativeTexts = data.actionNativeTexts or setmetatable({}, {
        __mode = "k",
    })
    data.actionNativeTextHooks = data.actionNativeTextHooks or setmetatable({}, {
        __mode = "k",
    })
    local function AddNativeText(region)
        if not region or region == data.label
            or not region.GetObjectType
            or region:GetObjectType() ~= "FontString"
        then return end
        data.actionNativeTexts[region] = true
        if not data.actionNativeText then data.actionNativeText = region end
        if not data.actionNativeTextHooks[region] and _G.hooksecurefunc then
            data.actionNativeTextHooks[region] = true
            _G.hooksecurefunc(region, "SetAlpha", function(_, alpha)
                local state = NSkin:GetSkinData(
                    button, COMPONENT_STATE, false)
                if state and region ~= state.label and tonumber(alpha) ~= 0
                    and not state.suppressingActionNativeText
                then
                    state.suppressingActionNativeText = true
                    region:SetAlpha(0)
                    state.suppressingActionNativeText = nil
                end
            end)
        end
    end
    if button.GetFontString then AddNativeText(button:GetFontString()) end
    AddNativeText(button.Text)
    local buttonName = button.GetName and button:GetName()
    if buttonName then AddNativeText(_G[buttonName .. "Text"]) end
    if button.GetRegions then
        for _, region in ipairs({ button:GetRegions() }) do
            AddNativeText(region)
        end
    end
    for region in pairs(data.actionNativeTexts) do
        if region == data.label then
            data.actionNativeTexts[region] = nil
        else
            region:SetAlpha(0)
        end
    end
end

local function RefreshActionButton(button)
    local data = NSkin:GetSkinData(button, COMPONENT_STATE, false)
    if not data or not data.label then return end
    SuppressActionButtonNativeText(button)
    NSkin:ApplyResolvedTypography(data.label, NSkin:GetStyle("text"))
    local enabled = not button.IsEnabled or button:IsEnabled()
    local color = data.actionTextColor
        or NSkin:GetStyle("text").color
    local disabledAlpha = data.actionDisabledTextAlpha or 0.45
    data.label:SetTextColor(color[1], color[2], color[3],
        (color[4] or 1) * (enabled and 1 or disabledAlpha))
end

function NSkin:SkinActionButton(button, options)
    if not button then return end
    options = options or {}
    local data = self:GetSkinData(button, COMPONENT_STATE)
    local style = options.style
        or (options.background and options.text and options)
        or self:GetStyle("button")
    data.actionStyle = style
    data.actionTextColor = self:GetResolvedAppearanceColor(style, "text")
    data.actionDisabledTextAlpha = options.disabledTextAlpha
        or style.disabledTextAlpha or 0.45
    local label = button.GetText and button:GetText() or ""
    local nativeText = button.GetFontString and button:GetFontString()
    if nativeText and nativeText.GetObjectType
        and nativeText:GetObjectType() == "FontString"
    then
        local previousLabel = data.label
        if previousLabel and previousLabel ~= nativeText then
            previousLabel:SetAlpha(0)
            previousLabel:Hide()
            data.actionOwnedLabel = previousLabel
        end
        data.label = nativeText
        if data.actionNativeTexts then
            data.actionNativeTexts[nativeText] = nil
        end
        nativeText:SetAlpha(1)
        nativeText:Show()
    end
    self:SkinFlatButton(button, label,
        options.background or style.background,
        options.border or self:GetComponentBorderColor("button", style),
        options.textSize)
    local border = self:GetPixelBorder(button, "NSkinFlatBackgroundBorder")
    self:SetPixelBorderSize(border, 1)
    SuppressActionButtonNativeText(button)
    if data.label then
        self:ApplyResolvedTypography(data.label, self:GetStyle("text"))
    end
    if not data.actionTextHooked and button.SetText and _G.hooksecurefunc then
        _G.hooksecurefunc(button, "SetText", function(_, value)
            local state = NSkin:GetSkinData(button, COMPONENT_STATE, false)
            if state and state.label then state.label:SetText(value or "") end
            SuppressActionButtonNativeText(button)
        end)
        data.actionTextHooked = true
    end
    if not data.actionStateHooked and button.HookScript then
        for _, script in ipairs({
            "OnShow", "OnEnter", "OnLeave", "OnMouseDown", "OnMouseUp",
            "OnEnable", "OnDisable",
        }) do
            button:HookScript(script, RefreshActionButton)
        end
        data.actionStateHooked = true
    end
    RefreshActionButton(button)
end

function NSkin:SkinCheckButton(checkButton, options)
    if not checkButton or not checkButton.CreateTexture then return false end
    options = options or {}
    local style = options.style
        or (options.background and options.text and options)
        or self:GetStyle("button")
    local data = self:GetSkinData(checkButton, COMPONENT_STATE)

    if not data.checkButtonArtworkSuppressed then
        self:HideTextureRegions(checkButton)
        data.checkButtonArtworkSuppressed = true
    end
    self:CreateFlatBackground(checkButton, nil,
        options.background or style.background,
        options.border or self:GetComponentBorderColor("button", style))
    self:CreateFlatButtonGlow(checkButton, style.hoverAlpha)

    local checked = data.checkButtonCheckedTexture
    if not checked then
        checked = checkButton:CreateTexture(nil, "ARTWORK")
        checked:SetPoint("TOPLEFT", checkButton, "TOPLEFT", 4, -4)
        checked:SetPoint("BOTTOMRIGHT", checkButton, "BOTTOMRIGHT", -4, 4)
        self:ConfigureOwnedPixelTexture(checked)
        data.checkButtonCheckedTexture = checked
    end
    checked:SetColorTexture(unpack(
        options.checked or self:GetSharedBorderColor()))
    if checkButton.SetCheckedTexture then checkButton:SetCheckedTexture(checked) end

    local label = options.text or checkButton.Text
    if label then
        label:SetTextColor(unpack(
            options.textColor or style.text or self:GetStyle("text").color))
        self:ApplyResolvedTypography(label, self:GetStyle("text"))
        label:SetAlpha(1)
        label:Show()
    end
    return true
end

function NSkin:SkinDropdown(dropdown, options)
    if not dropdown then return end
    options = options or {}
    local style = options.style
        or (options.background and options.text and options)
        or self:GetStyle("button")
    self:CreateFlatBackground(dropdown, nil,
        options.background or style.background,
        options.border or self:GetComponentBorderColor("button", style))
    local border = self:GetPixelBorder(dropdown, "NSkinFlatBackgroundBorder")
    self:SetPixelBorderSize(border, 1)
    self:CreateFlatButtonGlow(dropdown, style.hoverAlpha)
    if dropdown.Background then dropdown.Background:SetAlpha(0) end
    if dropdown.Arrow then dropdown.Arrow:SetAlpha(0) end
    if dropdown.NineSlice then dropdown.NineSlice:Hide() end
    if dropdown.Text then
        dropdown.Text:SetTextColor(unpack(style.text))
        dropdown.Text:SetAlpha(options.preserveText == false and 0 or 1)
        self:ApplyResolvedTypography(dropdown.Text, self:GetStyle("text"))
    end
    local data = self:GetSkinData(dropdown, COMPONENT_STATE)
    if options.preserveText == false then
        local label = self:SetFlatButtonLabel(
            dropdown, options.label or "", options.textSize)
        if label then label:SetTextColor(unpack(style.text)) end
    elseif data.label then
        data.label:Hide()
    end
    local arrow = data.dropdownArrow
    if not arrow then
        arrow = dropdown:CreateTexture(nil, "OVERLAY")
        arrow:SetSize(14, 14)
        arrow:SetPoint("RIGHT", dropdown, "RIGHT", -8, 0)
        arrow:SetTexture(self.mediaPath .. "angle-small-down.png")
        self:ConfigureOwnedPixelTexture(arrow)
        data.dropdownArrow = arrow
    end
    arrow:SetVertexColor(unpack(self:GetSharedBorderColor()))
    arrow:Show()

    data.dropdownMenuStyle = {
        -- Popup menus deliberately use one canonical palette instead of
        -- inheriting per-owner button overrides. This is the established
        -- Adventure Guide expansion-menu treatment shared by every dropdown.
        background = self:GetStyle("window").background,
        border = self:GetSharedBorderColor(),
        textColor = self:GetStyle("button").text,
        textStyle = self:GetStyle("text"),
    }
    self:RegisterDropdownMenuSkin(options.menus)
    self:HookDropdownMenuSkin(dropdown, function()
        local state = NSkin:GetSkinData(dropdown, COMPONENT_STATE, false)
        return state and state.dropdownMenuStyle
    end)
end

local SHARED_DROPDOWN_MENU_BOTTOM_INSET = 0
local sharedDropdownMenu = {
    owners = setmetatable({}, { __mode = "k" }),
    managerHooked = false,
    generateHooked = false,
    activeOwner = nil,
    activeMenu = nil,
    registeredTags = {},
    pendingTags = {},
}
local sharedDropdownMenuFontObjects = {}
local sharedDropdownMenuFontObjectCount = 0

local function GetDropdownMenuFontObject(fontString, textStyle)
    if not fontString or not fontString.GetFont or not _G.CreateFont then
        return nil
    end
    local sourceFont, sourceSize, sourceOutline = fontString:GetFont()
    local globalFont, resolvedSize, globalOutline = NSkin:GetResolvedTypography(
        textStyle or NSkin:GetStyle("text"))
    local font = globalFont or sourceFont
    local size = tonumber(resolvedSize) or tonumber(sourceSize)
    local outline = globalOutline ~= nil and globalOutline or sourceOutline
    if not font or not size then return nil end

    local key = table.concat({ font, tostring(size), tostring(outline or "") },
        "\031")
    local fontObject = sharedDropdownMenuFontObjects[key]
    if not fontObject then
        sharedDropdownMenuFontObjectCount = sharedDropdownMenuFontObjectCount + 1
        fontObject = _G.CreateFont(
            "NSkinSharedDropdownMenuFont" .. sharedDropdownMenuFontObjectCount)
        sharedDropdownMenuFontObjects[key] = fontObject
    end
    fontObject:SetFont(font, size, outline)
    return fontObject
end

local function SkinDropdownMenuDescription(frame, description)
    if not frame then return end
    local style = NSkin:GetStyle("text")
    local fontString = frame.fontString
    local textColor = NSkin:GetStyle("button").text
    local function SkinFontString(target)
        if not target then return end
        local fontObject = GetDropdownMenuFontObject(target, style)
        if fontObject and target.SetFontObject then
            target:SetFontObject(fontObject)
        end
        if target.SetTextColor then
            target:SetTextColor(unpack(textColor))
        end
    end
    SkinFontString(fontString)
    if frame.GetRegions then
        for _, region in ipairs({ frame:GetRegions() }) do
            if region ~= fontString and region.IsObjectType
                and region:IsObjectType("FontString")
            then
                SkinFontString(region)
            end
        end
    end

    local borderColor = NSkin:GetSharedBorderColor()
    if frame.highlight and frame.highlight.SetColorTexture then
        if frame.highlight.SetBlendMode then
            frame.highlight:SetBlendMode("BLEND")
        end
        frame.highlight:SetColorTexture(
            borderColor[1], borderColor[2], borderColor[3], 0.14)
    end

    -- Blizzard also builds selection rows with CreateButton + SetIsSelected,
    -- so the generated selector region is the reliable common signal here.
    local selector = description and description.IsSelected
        and frame.leftTexture1
    if selector then
        local selected = description.IsSelected and description:IsSelected()
        selector:SetTexture(NSkin.mediaPath
            .. (selected and "checkbox-checked.png"
                or "checkbox-unchecked.png"))
        selector:SetTexCoord(0, 1, 0, 1)
        selector:ClearAllPoints()
        selector:SetPoint("LEFT")
        selector:SetSize(16, 16)
        NSkin:ConfigureOwnedPixelTexture(selector)
        selector:SetVertexColor(unpack(selected
            and NSkin:GetAccentColor() or borderColor))
        if fontString then
            fontString:ClearAllPoints()
            fontString:SetPoint("LEFT", selector, "RIGHT", 7, 0)
        end
    end
    if frame.leftTexture2 then frame.leftTexture2:Hide() end
end

local function AddDropdownMenuInitializers(_, rootDescription)
    local function Visit(description)
        if not description or not description.EnumerateElementDescriptions then
            return
        end
        for _, child in description:EnumerateElementDescriptions() do
            if child.AddInitializer then
                local elementDescription = child
                child:AddInitializer(function(frame)
                    SkinDropdownMenuDescription(frame, elementDescription)
                end)
            end
            Visit(child)
        end
    end
    Visit(rootDescription)
end

local function FlushPendingDropdownMenuTags()
    if not _G.Menu or type(_G.Menu.ModifyMenu) ~= "function" then
        return false
    end
    for tag in pairs(sharedDropdownMenu.pendingTags) do
        if not sharedDropdownMenu.registeredTags[tag] then
            _G.Menu.ModifyMenu(tag, AddDropdownMenuInitializers)
            sharedDropdownMenu.registeredTags[tag] = true
        end
        sharedDropdownMenu.pendingTags[tag] = nil
    end
    return true
end

function NSkin:RegisterDropdownMenuSkin(menus)
    if type(menus) == "string" then menus = { menus } end
    if type(menus) ~= "table" then
        FlushPendingDropdownMenuTags()
        return false
    end
    for _, tag in ipairs(menus) do
        if type(tag) == "string" and tag ~= ""
            and not sharedDropdownMenu.registeredTags[tag]
        then
            sharedDropdownMenu.pendingTags[tag] = true
        end
    end
    FlushPendingDropdownMenuTags()
    return true
end

local function HideSharedDropdownMenuBorder(menu)
    local data = menu and NSkin:GetSkinData(menu, COMPONENT_STATE, false)
    if data and data.sharedMenuBorderFrame then
        data.sharedMenuBorderFrame:Hide()
    end
end

local function TintSharedDropdownMenuTexture(texture, color)
    if not texture then return end
    if texture.SetDesaturated then texture:SetDesaturated(true) end
    if texture.SetVertexColor then texture:SetVertexColor(unpack(color)) end
end

local function SkinSharedDropdownMenuEntry(frame, style)
    if not frame then return end
    local borderColor = style.border or NSkin:GetSharedBorderColor()
    local textStyle = style.textStyle or NSkin:GetStyle("text")
    local textColor = style.textColor or textStyle.color or textStyle.text
        or NSkin:GetStyle("button").text
    if frame.fontString and frame.fontString.SetTextColor then
        frame.fontString:SetTextColor(unpack(textColor))
    end
    if frame.highlight then
        if frame.highlight.SetBlendMode then frame.highlight:SetBlendMode("BLEND") end
        if frame.highlight.SetColorTexture then
            frame.highlight:SetColorTexture(
                borderColor[1], borderColor[2], borderColor[3], 0.14)
        end
    end
    TintSharedDropdownMenuTexture(frame.arrow, borderColor)
end

function NSkin:SkinDropdownMenu(menu, style)
    if not menu or not menu.IsShown or not menu:IsShown() then return false end
    style = style or {}
    local backgroundColor = style.background or self:GetStyle("window").background
    local borderColor = style.border or self:GetSharedBorderColor()
    local data = self:GetSkinData(menu, COMPONENT_STATE)

    if menu == sharedDropdownMenu.activeMenu
        and sharedDropdownMenu.activeOwner
        and not (menu.IsProtected and menu:IsProtected())
        and not (_G.InCombatLockdown and _G.InCombatLockdown())
    then
        menu:ClearAllPoints()
        menu:SetPoint("TOPLEFT", sharedDropdownMenu.activeOwner,
            "BOTTOMLEFT", 0, 0)
    end

    for _, region in ipairs({ menu:GetRegions() }) do
        if region.IsObjectType and region:IsObjectType("Texture") then
            region:SetColorTexture(unpack(backgroundColor))
            region:ClearAllPoints()
            region:SetPoint("TOPLEFT", menu, "TOPLEFT", 1, -1)
            region:SetPoint("BOTTOMRIGHT", menu, "BOTTOMRIGHT", -1,
                SHARED_DROPDOWN_MENU_BOTTOM_INSET + 1)
            region:SetAlpha(1)
            region:Show()
        end
    end
    if not data.sharedMenuBorderFrame then
        local borderFrame = CreateFrame("Frame", nil, UIParent)
        borderFrame:EnableMouse(false)
        data.sharedMenuBorderFrame = borderFrame
        self:CreatePixelBorder(borderFrame, "NSkinSharedDropdownMenuBorder",
            1, borderColor, false, borderFrame)
    end
    local borderFrame = data.sharedMenuBorderFrame
    borderFrame:ClearAllPoints()
    borderFrame:SetPoint("TOPLEFT", menu, "TOPLEFT")
    borderFrame:SetPoint("BOTTOMRIGHT", menu, "BOTTOMRIGHT", 0,
        SHARED_DROPDOWN_MENU_BOTTOM_INSET)
    borderFrame:SetFrameStrata(menu:GetFrameStrata())
    borderFrame:SetFrameLevel(menu:GetFrameLevel() + 1)
    local border = self:GetPixelBorder(borderFrame,
        "NSkinSharedDropdownMenuBorder")
    self:SetPixelBorderColor(border, unpack(borderColor))
    self:SetPixelBorderSize(border, 1)
    self:SetPixelBorderShown(border, true)
    borderFrame:Show()
    if not data.sharedMenuHideHooked and menu.HookScript then
        menu:HookScript("OnHide", HideSharedDropdownMenuBorder)
        data.sharedMenuHideHooked = true
    end
    if menu.GetChildren then
        for _, child in ipairs({ menu:GetChildren() }) do
            SkinSharedDropdownMenuEntry(child, style)
        end
    end
    return true
end

function NSkin:SkinDropdownArrowButton(button, color)
    if not button then return false end
    local data = self:GetSkinData(button, COMPONENT_STATE)
    self:HideTextureRegions(button, data.sharedDropdownArrow)
    for _, child in ipairs({ button:GetChildren() }) do
        self:HideTextureRegions(child)
    end
    if not data.sharedDropdownArrow then
        local arrow = button:CreateTexture(nil, "OVERLAY")
        arrow:SetSize(14, 14)
        arrow:SetPoint("CENTER", button, "CENTER", 0, -1)
        arrow:SetTexture(self.mediaPath .. "angle-small-down.png")
        self:ConfigureOwnedPixelTexture(arrow)
        data.sharedDropdownArrow = arrow
    end
    data.sharedDropdownArrow:SetVertexColor(unpack(color or self:GetSharedBorderColor()))
    data.sharedDropdownArrow:SetAlpha(button.IsEnabled and button:IsEnabled() and 1 or 0.4)
    data.sharedDropdownArrow:Show()
    return true
end

local function GetRegisteredDropdownMenuStyle(dropdown)
    local provider = dropdown and sharedDropdownMenu.owners[dropdown]
    return type(provider) == "function" and provider() or provider
end

local function SkinRegisteredDropdownMenu(dropdown, menu)
    if not dropdown or not sharedDropdownMenu.owners[dropdown]
        or not menu or not menu.IsShown or not menu:IsShown()
    then return false end
    sharedDropdownMenu.activeOwner = dropdown
    sharedDropdownMenu.activeMenu = menu
    return NSkin:SkinDropdownMenu(
        menu, GetRegisteredDropdownMenuStyle(dropdown))
end

local function HookSharedDropdownMenuManager()
    if not _G.hooksecurefunc then return false end
    if not sharedDropdownMenu.managerHooked and _G.Menu
        and type(_G.Menu.GetManager) == "function"
    then
        local manager = _G.Menu.GetManager()
        if manager and type(manager.OpenMenu) == "function" then
            _G.hooksecurefunc(manager, "OpenMenu", function(self, ownerRegion)
                if not sharedDropdownMenu.owners[ownerRegion] then return end
                local menu = self:GetOpenMenu()
                if not menu then return end
                sharedDropdownMenu.activeOwner = ownerRegion
                sharedDropdownMenu.activeMenu = menu
                C_Timer.After(0, function()
                    SkinRegisteredDropdownMenu(ownerRegion, menu)
                end)
            end)
            sharedDropdownMenu.managerHooked = true
        end
    end
    if not sharedDropdownMenu.generateHooked and _G.MenuStyle1Mixin
        and type(_G.MenuStyle1Mixin.Generate) == "function"
    then
        _G.hooksecurefunc(_G.MenuStyle1Mixin, "Generate", function(menu)
            local owner = sharedDropdownMenu.activeOwner
            local root = sharedDropdownMenu.activeMenu
            if not owner or not root or menu == root or not root:IsShown() then
                return
            end
            C_Timer.After(0, function()
                if root:IsShown() and menu:IsShown() then
                    NSkin:SkinDropdownMenu(
                        menu, GetRegisteredDropdownMenuStyle(owner))
                end
            end)
        end)
        sharedDropdownMenu.generateHooked = true
    end
    return sharedDropdownMenu.managerHooked
end

function NSkin:HookDropdownMenuSkin(dropdown, styleProvider)
    if not dropdown then return false end
    local data = self:GetSkinData(dropdown, COMPONENT_STATE)
    data.sharedMenuStyleProvider = styleProvider
    sharedDropdownMenu.owners[dropdown] = styleProvider
    HookSharedDropdownMenuManager()
    if not _G.hooksecurefunc then return false end
    if data.sharedMenuSkinHooked then return true end
    if type(dropdown.OnMenuOpened) == "function" then
        _G.hooksecurefunc(dropdown, "OnMenuOpened", function(_, menu)
            menu = menu or dropdown.menu
            C_Timer.After(0, function()
                SkinRegisteredDropdownMenu(dropdown, menu)
            end)
        end)
    end
    if type(dropdown.OnMenuClosed) == "function" then
        _G.hooksecurefunc(dropdown, "OnMenuClosed", function(_, menu)
            menu = menu or dropdown.menu
            HideSharedDropdownMenuBorder(menu)
            if sharedDropdownMenu.activeOwner == dropdown then
                sharedDropdownMenu.activeOwner = nil
                sharedDropdownMenu.activeMenu = nil
            end
        end)
    end
    data.sharedMenuSkinHooked = true
    return true
end

local navigationBarAddButtonHooked = false

local function RefreshNavigationLeftButton(button)
    local data = NSkin:GetSkinData(button, COMPONENT_STATE, false)
    local arrow = data and data.navigationLeftArrow
    if not arrow then return end
    -- Blizzard collapses the overflow button by reducing it to zero width
    -- without necessarily hiding the frame. Hide every NSkin-owned region in
    -- that state so its coincident border edges do not leave a divider across
    -- the first breadcrumb button.
    local shown = (not button.IsShown or button:IsShown())
        and (not button.GetWidth or button:GetWidth() > 2)
    local background = NSkin:GetFlatBackground(button)
    if background then background:SetShown(shown) end
    NSkin:SetPixelBorderShown(
        NSkin:GetPixelBorder(button, "NSkinFlatBackgroundBorder"), shown)
    if not shown and data.hoverGlow then data.hoverGlow:Hide() end
    arrow:SetShown(shown)
    if not shown then return end
    local color = data.navigationLeftArrowColor or { 1, 1, 1, 1 }
    local enabled = not button.IsEnabled or button:IsEnabled()
    arrow:SetVertexColor(color[1], color[2], color[3],
        (color[4] or 1) * (enabled and 1 or 0.4))
end

local function GetNavigationLeftButton(navigationBar)
    local button = navigationBar and (
        navigationBar.overflow or navigationBar.Overflow
        or navigationBar.overflowButton or navigationBar.OverflowButton
        or navigationBar.backButton or navigationBar.BackButton)
    if button and button.IsObjectType and button:IsObjectType("Button") then
        return button
    end
    return button and (button.Button or button.button)
end

local function NormalizeNavigationButtonSpacing(navigationBar)
    if not navigationBar then return end
    local home = navigationBar.home or navigationBar.homeButton
    local overflow = navigationBar.overflow or navigationBar.overflowButton
    local changed = false

    -- Blizzard's arrow-shaped navigation art overlaps the following button.
    -- NSkin uses rectangular buttons, so retaining those negative offsets
    -- leaves the home/overflow border inside the next entry.
    if home and home.xoffset ~= 0 then
        home.xoffset = 0
        changed = true
    end
    if overflow and overflow.xoffset ~= 0 then
        overflow.xoffset = 0
        changed = true
    end
    if changed and type(_G.NavBar_CheckLength) == "function" then
        _G.NavBar_CheckLength(navigationBar)
    end
end

function NSkin:SkinNavigationLeftButton(button, style)
    if not button then return false end
    self:SkinActionButton(button, {
        style = {
            background = style.homeBackground,
            border = style.homeBorder,
            text = style.homeText,
            disabledTextAlpha = style.disabledTextAlpha,
            hoverAlpha = style.hoverAlpha,
        },
    })

    local data = self:GetSkinData(button, COMPONENT_STATE)
    if data.label then data.label:SetText("") end
    if not data.navigationLeftArrow then
        local arrow = button:CreateTexture(nil, "OVERLAY", nil, 2)
        arrow:SetSize(14, 14)
        arrow:SetPoint("CENTER", button, "CENTER", 0, 0)
        arrow:SetTexture(self.mediaPath .. "angle-small-down.png")
        self:ConfigureOwnedPixelTexture(arrow)
        data.navigationLeftArrow = arrow
    end
    data.navigationLeftArrow:SetRotation(-math.pi / 2)
    data.navigationLeftArrowColor = style.homeText
    if not data.navigationLeftArrowStateHooked and button.HookScript then
        button:HookScript("OnEnable", RefreshNavigationLeftButton)
        button:HookScript("OnDisable", RefreshNavigationLeftButton)
        button:HookScript("OnShow", RefreshNavigationLeftButton)
        button:HookScript("OnHide", RefreshNavigationLeftButton)
        button:HookScript("OnSizeChanged", RefreshNavigationLeftButton)
        data.navigationLeftArrowStateHooked = true
    end
    RefreshNavigationLeftButton(button)
    return true
end

function NSkin:SkinNavigationBar(navigationBar, style)
    if not navigationBar then return false end
    style = style or self:GetStyle("navigationBar")
    local data = self:GetSkinData(navigationBar, COMPONENT_STATE)
    data.navigationBarStyle = style

    -- Both the bevel and gray edge are baked into Blizzard's tiled regions.
    -- Replace those regions with a borderless NSkin-owned background.
    for _, region in ipairs({ navigationBar:GetRegions() }) do
        if region.IsObjectType and region:IsObjectType("Texture")
            and region ~= data.navigationBarBackground
        then
            region:SetAlpha(0)
        end
    end
    if navigationBar.overlay then navigationBar.overlay:SetAlpha(0) end
    if not data.navigationBarBackground then
        local background = navigationBar:CreateTexture(nil, "BACKGROUND", nil, -8)
        background:SetAllPoints(navigationBar)
        self:ConfigureOwnedPixelTexture(background)
        data.navigationBarBackground = background
    end
    data.navigationBarBackground:SetColorTexture(unpack(style.background))

    NormalizeNavigationButtonSpacing(navigationBar)
    self:SkinNavigationLeftButton(
        GetNavigationLeftButton(navigationBar), style)

    local skinnedButtons = setmetatable({}, { __mode = "k" })
    local function SkinNavigationButton(button)
        if not button or skinnedButtons[button] then return end
        skinnedButtons[button] = true
        self:SkinActionButton(button, {
            style = {
                background = style.homeBackground,
                border = style.homeBorder,
                text = style.homeText,
                disabledTextAlpha = style.disabledTextAlpha,
                hoverAlpha = style.hoverAlpha,
            },
        })
        local menuArrow = button.MenuArrowButton
        if menuArrow then
            self:SkinDropdownArrowButton(menuArrow,
                self:GetSharedBorderColor())
            self:HookDropdownMenuSkin(menuArrow, function()
                return {
                    background = style.menuBackground,
                    border = style.menuBorder,
                    textStyle = NSkin:GetStyle("text"),
                }
            end)
        end
    end

    -- The home entry is not guaranteed to be part of navList. Always refresh
    -- it explicitly because Blizzard can restore its tiled artwork while the
    -- breadcrumb list changes.
    SkinNavigationButton(navigationBar.home or navigationBar.homeButton)
    for _, button in ipairs(navigationBar.navList or {}) do
        if button then
            SkinNavigationButton(button)
        end
    end

    if not navigationBarAddButtonHooked and _G.hooksecurefunc
        and type(_G.NavBar_AddButton) == "function"
    then
        _G.hooksecurefunc("NavBar_AddButton", function(bar)
            local barData = NSkin:GetSkinData(bar, COMPONENT_STATE, false)
            if barData and barData.navigationBarStyle then
                NSkin:SkinNavigationBar(bar, barData.navigationBarStyle)
            end
        end)
        navigationBarAddButtonHooked = true
    end
    return true
end

local function RefreshScrollBarArrow(button)
    local data = NSkin:GetSkinData(button, COMPONENT_STATE, false)
    if data and data.scrollArrow then
        local enabled = not button.IsEnabled or button:IsEnabled()
        data.scrollArrow:SetAlpha(enabled and 1 or 0.35)
    end
end

function NSkin:SkinScrollBar(scrollBar, style)
    if not scrollBar then return end
    style = style or self:GetStyle("scrollBar")
    local trackColor = self:GetResolvedAppearanceColor(style, "track")
    local thumbColor = self:GetResolvedAppearanceColor(style, "thumb")
    local arrowColor = self:GetResolvedAppearanceColor(style, "arrow")
    local track = scrollBar.Track
    local thumb = track and track.Thumb
    local data = self:GetSkinData(scrollBar, COMPONENT_STATE)
    if track then
        for _, texture in ipairs({ track.Begin, track.Middle, track.End }) do
            if texture then texture:SetAlpha(0) end
        end
        if not data.scrollTrack then
            data.scrollTrack = track:CreateTexture(nil, "BACKGROUND", nil, -8)
            data.scrollTrack:SetPoint("TOP", track, "TOP", 0, 0)
            data.scrollTrack:SetPoint("BOTTOM", track, "BOTTOM", 0, 0)
            data.scrollTrack:SetWidth(2)
            self:ConfigureOwnedPixelTexture(data.scrollTrack)
        end
        data.scrollTrack:SetColorTexture(unpack(trackColor))
    end
    if thumb then
        for _, texture in ipairs({ thumb.Begin, thumb.Middle, thumb.End }) do
            if texture then texture:SetAlpha(0) end
        end
        if not data.scrollThumb then
            data.scrollThumb = thumb:CreateTexture(nil, "ARTWORK", nil, 7)
            data.scrollThumb:SetPoint("TOP", thumb, "TOP", 0, 0)
            data.scrollThumb:SetPoint("BOTTOM", thumb, "BOTTOM", 0, 0)
            data.scrollThumb:SetWidth(6)
            self:ConfigureOwnedPixelTexture(data.scrollThumb)
        end
        data.scrollThumb:SetColorTexture(unpack(thumbColor))
    end
    for _, entry in ipairs({ { scrollBar.Back, math.pi },
        { scrollBar.Forward, 0 } })
    do
        local button, rotation = entry[1], entry[2]
        if button then
            if button.Texture then button.Texture:SetAlpha(0) end
            local buttonData = self:GetSkinData(button, COMPONENT_STATE)
            if not buttonData.scrollArrow then
                buttonData.scrollArrow = button:CreateTexture(nil, "OVERLAY")
                buttonData.scrollArrow:SetAllPoints(button)
                buttonData.scrollArrow:SetTexture(
                    self.mediaPath .. "angle-small-down.png")
                buttonData.scrollArrow:SetRotation(rotation)
                self:ConfigureOwnedPixelTexture(buttonData.scrollArrow)
            end
            if not buttonData.scrollArrowHooked and button.HookScript then
                button:HookScript("OnEnable", RefreshScrollBarArrow)
                button:HookScript("OnDisable", RefreshScrollBarArrow)
                buttonData.scrollArrowHooked = true
            end
            buttonData.scrollArrow:SetVertexColor(unpack(arrowColor))
            RefreshScrollBarArrow(button)
        end
    end
end

function NSkin:SkinSearchBox(searchBox, style, borderColor)
    if not searchBox then return end

    local searchData = self:GetSkinData(searchBox, COMPONENT_STATE)
    if not searchData.baselineID then
        searchData.baselineID = "SearchBox:" .. tostring(searchBox)
        self:CaptureComponentBaseline(searchData.baselineID, searchBox, {
            size = true, textInsets = true,
        })
    end
    local searchIcon = searchBox.SearchIcon or searchBox.searchIcon
    if not self:GetFlatBackground(searchBox) then
        self:HideTextureRegions(searchBox, searchIcon)
    end
    style = style or self:GetStyle("searchBox")
    local configuredWidth, configuredHeight = tonumber(style.width), tonumber(style.height)
    configuredWidth = configuredWidth and configuredWidth > 0 and configuredWidth or nil
    configuredHeight = configuredHeight and configuredHeight > 0 and configuredHeight or nil
    if configuredWidth or configuredHeight then
        self:MarkComponentGeometryModified(searchData.baselineID, "size", true)
        if not searchData.searchOriginalSize then
            searchData.searchOriginalSize = { searchBox:GetWidth(), searchBox:GetHeight() }
        end
        local originalSize = searchData.searchOriginalSize
        searchBox:SetSize(configuredWidth or originalSize[1],
            configuredHeight or originalSize[2])
    elseif searchData.searchOriginalSize then
        self:RestoreComponentBaseline(searchData.baselineID, { size = true })
        searchData.searchOriginalSize = nil
    end
    self:CreateFlatBackground(
        searchBox, nil, self:GetResolvedAppearanceColor(style, "background"),
        borderColor or self:GetResolvedAppearanceColor(style, "border")
            or self:GetComponentBorderColor("searchBox", style)
    )
    local searchBorder = self:GetPixelBorder(searchBox, "NSkinFlatBackgroundBorder")
    self:SetPixelBorderSize(searchBorder, style.borderSize or 1)
    self:SetPixelBorderPadding(searchBorder, style.borderPadding or 0)
    if searchBox.SetTextColor then
        searchBox:SetTextColor(unpack(self:GetResolvedAppearanceColor(style, "text")))
    end
    self:ApplyResolvedTypography(searchBox, style)
    if searchBox.GetTextInsets and searchBox.SetTextInsets then
        local hasInsetOverride = style.textOffsetX ~= nil
            or style.textOffsetY ~= nil
        if hasInsetOverride then
            local baseline = self:GetComponentBaseline(searchData.baselineID)
            local insets = baseline and baseline.textInsets
            if insets then
                local offsetX = style.textOffsetX or 0
                local offsetY = style.textOffsetY or 0
                self:MarkComponentGeometryModified(
                    searchData.baselineID, "textInsets", true)
                searchBox:SetTextInsets((insets[1] or 0) + offsetX,
                    (insets[2] or 0) - offsetX,
                    (insets[3] or 0) - offsetY,
                    (insets[4] or 0) + offsetY)
            end
        else
            self:RestoreComponentBaseline(
                searchData.baselineID, { textInsets = true })
        end
    end
    local instructions = searchBox.Instructions or searchBox.instructions
    if instructions then
        instructions:SetTextColor(unpack(
            self:GetResolvedAppearanceColor(style, "placeholderText")))
        self:ApplyResolvedTypography(instructions, style, "placeholder")
        local data = self:GetSkinData(instructions, COMPONENT_STATE)
        if not data.placeholderBaselineID then
            data.placeholderBaselineID =
                "SearchPlaceholder:" .. tostring(instructions)
            self:CaptureComponentBaseline(
                data.placeholderBaselineID, instructions, {
                points = true,
            })
        end
        local hasPlaceholderOverride = style.placeholderOffsetX ~= nil
            or style.placeholderOffsetY ~= nil
        if hasPlaceholderOverride then
            local baseline = self:GetComponentBaseline(
                data.placeholderBaselineID)
            local points = baseline and baseline.points
            if points then
                self:MarkComponentGeometryModified(
                    data.placeholderBaselineID, "points", true)
                instructions:ClearAllPoints()
                for i = 1, #points do
                    local point = points[i]
                    instructions:SetPoint(point[1], point[2], point[3],
                        (point[4] or 0) + (style.placeholderOffsetX or 0),
                        (point[5] or 0) + (style.placeholderOffsetY or 0))
                end
            end
        else
            self:RestoreComponentBaseline(
                data.placeholderBaselineID, { points = true })
        end
    end
    if searchIcon then searchIcon:Show() end
end

local function RefreshPagingButton(button)
    local data = NSkin:GetSkinData(button, COMPONENT_STATE, false)
    if data and data.label then
        local enabled = not button.IsEnabled or button:IsEnabled()
        data.label:SetAlpha(enabled and 1 or 0.35)
    end
end

local function SkinPagingButton(button, label, textSize)
    if not button then return end
    NSkin:SkinFlatButton(button, label, nil, nil, textSize)
    local data = NSkin:GetSkinData(button, COMPONENT_STATE)
    if not data.pagingStateHooked and button.HookScript then
        button:HookScript("OnEnable", RefreshPagingButton)
        button:HookScript("OnDisable", RefreshPagingButton)
        data.pagingStateHooked = true
    end
    RefreshPagingButton(button)
end

function NSkin:SkinPagingControls(pagingControls, textSize)
    if not pagingControls then return end

    local previous = pagingControls.PrevPageButton or pagingControls.prevPageButton
    local nextPage = pagingControls.NextPageButton or pagingControls.nextPageButton
    local pageText = pagingControls.PageText or pagingControls.pageText
    SkinPagingButton(previous, "<", textSize)
    SkinPagingButton(nextPage, ">", textSize)
    if pageText then pageText:SetTextColor(unpack(self:GetStyle("button").text)) end
end

-- Windows Skinning

function NSkin:ApplyGlobalTypography(frame)
    if not frame then return end
    local typography = self:GetStyle("typography")
    local font, size, outline = typography.font, typography.size, typography.outline
    if not font and not size and outline == nil then return end

    local function Apply(target)
        if target.GetObjectType and target:GetObjectType() == "FontString" then
            local currentFont, currentSize, currentOutline = target:GetFont()
            target:SetFont(font or currentFont, size or currentSize,
                outline ~= nil and outline or currentOutline)
        elseif target.GetObjectType and target:GetObjectType() == "EditBox"
            and target.SetFont
        then
            local currentFont, currentSize, currentOutline = target:GetFont()
            target:SetFont(font or currentFont, size or currentSize,
                outline ~= nil and outline or currentOutline)
        end
        if target.GetRegions then
            for _, region in ipairs({ target:GetRegions() }) do
                if region.GetObjectType and region:GetObjectType() == "FontString" then
                    local currentFont, currentSize, currentOutline = region:GetFont()
                    region:SetFont(font or currentFont, size or currentSize,
                        outline ~= nil and outline or currentOutline)
                end
            end
        end
        if target.GetChildren then
            for _, child in ipairs({ target:GetChildren() }) do Apply(child) end
        end
    end

    Apply(frame)
end

local EDITOR_PRESETS = {
    WINDOW = {
        { id = "shared.windowSurfaceAppearance", label = "Window Surface",
            presentation = "INLINE", category = "CUSTOMIZE" },
        { id = "shared.windowHeaderAppearance", label = "Header",
            category = "CUSTOMIZE" },
    },
    WINDOW_HEADER_CONTROLS = {
        { id = "shared.windowHeaderControlsAppearance",
            label = "Header Buttons", category = "CUSTOMIZE" },
    },
    TAB_GROUP = {
        { id = "tabs.layout", label = "Position",
            presentation = "INLINE", category = "POSITION" },
        { id = "shared.tabSurfaceAppearance", label = "Tab Surface",
            presentation = "INLINE", category = "CUSTOMIZE" },
        { id = "shared.tabTextAppearance", label = "Tab Text",
            category = "CUSTOMIZE" },
    },
    SIDE_TAB = {
        { id = "shared.movable", label = "Position",
            presentation = "INLINE", category = "POSITION" },
        { id = "shared.sideTabAppearance", label = "Side Tab",
            presentation = "INLINE", category = "CUSTOMIZE" },
    },
    SEARCH_GROUP = {
        { id = "shared.searchPosition", label = "Position",
            presentation = "INLINE", category = "POSITION" },
        { id = "shared.searchBoxAppearance", label = "Search Box",
            presentation = "INLINE", category = "CUSTOMIZE" },
        { id = "shared.searchTextAppearance", label = "Search Text",
            category = "CUSTOMIZE" },
        { id = "shared.placeholderTextAppearance", label = "Placeholder Text",
            category = "CUSTOMIZE" },
    },
    SEARCH_ACCESSORY = {
        { id = "shared.movable", label = "Position",
            presentation = "INLINE", category = "POSITION" },
    },
    PAGINATION_GROUP = {
        { id = "shared.paginationPosition", label = "Position",
            presentation = "INLINE", category = "POSITION" },
        { id = "shared.paginationLayout", label = "Layout",
            presentation = "INLINE", category = "LAYOUT" },
    },
    PAGINATION_CHILD = {
        { id = "shared.paginationPosition", label = "Position",
            presentation = "INLINE", category = "POSITION" },
        { id = "shared.paginationLayout", label = "Layout",
            presentation = "INLINE", category = "LAYOUT" },
    },
    SECTION_HEADERS = {
        { id = "shared.sectionHeaderPlacement", label = "Offset",
            presentation = "INLINE", category = "POSITION" },
        { id = "shared.headerTextAppearance", label = "Header Text",
            category = "CUSTOMIZE" },
        { id = "shared.headerUnderlineAppearance", label = "Underline",
            category = "CUSTOMIZE" },
    },
    MOVABLE = {
        { id = "shared.movable", label = "Position",
            presentation = "INLINE", category = "POSITION" },
    },
    SCROLLBAR = {
        { id = "shared.movable", label = "Position",
            presentation = "INLINE", category = "POSITION" },
        { id = "shared.scrollBarAppearance", label = "Scrollbar",
            category = "CUSTOMIZE" },
    },
    TEXT = {
        { id = "shared.textAppearance", label = "Text",
            category = "CUSTOMIZE" },
    },
}

local SHARED_ELEMENT_TYPES = {}

function NSkin:RegisterSharedElementType(typeID, definition)
    if type(typeID) ~= "string" or typeID == ""
        or type(definition) ~= "table" or SHARED_ELEMENT_TYPES[typeID]
    then return false end
    local preset = definition.editorPreset or typeID
    if not EDITOR_PRESETS[preset] then return false end
    definition.id = typeID
    definition.editorPreset = preset
    SHARED_ELEMENT_TYPES[typeID] = definition
    return true
end

function NSkin:GetSharedElementType(typeID)
    return SHARED_ELEMENT_TYPES[typeID]
end

function NSkin:CreateSharedElementEditorOptions(typeID, extras)
    local definition = SHARED_ELEMENT_TYPES[typeID]
    return definition and self:CreateEditorOptionsPreset(
        definition.editorPreset, extras) or nil
end

local function CopyEditorOption(option)
    local copy = {}
    for key, value in pairs(option or {}) do copy[key] = value end
    return copy
end

function NSkin:CreateEditorOptionsPreset(preset, extraEditorOptions)
    local standard = EDITOR_PRESETS[preset] or {}
    local before, after = {}, {}
    for i = 1, #(extraEditorOptions or {}) do
        local option = CopyEditorOption(extraEditorOptions[i])
        local isLayout = option.category == "POSITION"
            or option.category == "LAYOUT"
        local destination = isLayout and before or after
        destination[#destination + 1] = option
    end
    local result = {}
    for i = 1, #before do result[#result + 1] = before[i] end
    for i = 1, #standard do
        result[#result + 1] = CopyEditorOption(standard[i])
    end
    for i = 1, #after do result[#result + 1] = after[i] end
    return result
end

local SHARED_TYPE_DEFINITIONS = {
    WINDOW = { style = "window", skin = "SkinWindow",
        appearanceControls = "shared.windowAppearance" },
    WINDOW_HEADER = { style = "window.header", skin = "SkinWindowHeader",
        appearanceControls = "shared.windowHeaderAppearance", editorPreset = "WINDOW" },
    WINDOW_HEADER_CONTROLS = { style = "windowHeaderButton",
        skin = "SkinWindowHeaderButton",
        appearanceControls = "shared.windowHeaderControlsAppearance" },
    TAB_GROUP = { style = "tab", skin = "SkinTab",
        appearanceControls = "shared.tabAppearance" },
    SIDE_TAB = { style = "sideTab", skin = "SkinSideTab",
        appearanceControls = "shared.sideTabAppearance",
        editorPreset = "SIDE_TAB" },
    BUTTON = { style = "button", skin = "SkinFlatButton", editorPreset = "MOVABLE" },
    ACTION_BUTTON = { style = "button", skin = "SkinActionButton",
        editorPreset = "MOVABLE" },
    CHECKBOX = { style = "button", skin = "SkinCheckButton",
        editorPreset = "MOVABLE" },
    DROPDOWN = { style = "button", skin = "SkinDropdown", editorPreset = "MOVABLE" },
    NAVIGATION_BAR = { style = "navigationBar", skin = "SkinNavigationBar",
        editorPreset = "MOVABLE" },
    SEARCH_GROUP = { style = "searchBox", skin = "SkinSearchBox" },
    SEARCH_ACCESSORY = { style = "button", skin = "SkinDropdown" },
    PAGINATION_GROUP = { style = "button", skin = "SkinPagingControls" },
    PAGINATION_CHILD = { style = "button", skin = "SkinFlatButton" },
    PROGRESS_BAR = { style = "progressBar", skin = "SkinProgressBar",
        editorPreset = "MOVABLE" },
    ICON = { style = "icon", skin = "CreateQualityBorder", editorPreset = "MOVABLE" },
    SCROLLBAR = { style = "scrollBar", skin = "SkinScrollBar",
        editorPreset = "SCROLLBAR", preserveAnchorSpan = true },
    SECTION_HEADER = { style = "sectionHeader", editorPreset = "SECTION_HEADERS" },
    TEXT = { style = "text", skin = "SkinText",
        appearanceControls = "shared.textAppearance", editorPreset = "TEXT" },
}
for typeID, definition in pairs(SHARED_TYPE_DEFINITIONS) do
    NSkin:RegisterSharedElementType(typeID, definition)
end

local function LayoutWindowBackground(frame, data, anchor)
    local background = data and data.windowBackground
    if not background or not anchor then return end
    background:ClearAllPoints()
    if anchor == frame and (tonumber(data.windowHeaderHeight) or 0) > 0 then
        background:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -data.windowHeaderHeight)
        background:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    else
        background:SetAllPoints(anchor)
    end
end

local function ConcealWindowRegion(region)
    if not region or not region.GetObjectType then return end
    local objectType = region:GetObjectType()
    if region.SetAlpha then region:SetAlpha(0) end
    if objectType == "Texture" then
        if region.SetTexture then region:SetTexture(nil) end
        region:Hide()
        return
    end
    if not (region.IsObjectType and region:IsObjectType("Frame")) then return end
    local data = NSkin:GetSkinData(region, COMPONENT_STATE)
    region:Hide()
    if not data.windowArtworkConcealHooked and region.HookScript then
        data.windowArtworkConcealHooked = true
        region:HookScript("OnShow", function(self)
            self:SetAlpha(0)
            self:Hide()
        end)
    end
end

function NSkin:ConcealWindowArtwork(frame, preserveArtwork)
    if not frame then return end
    preserveArtwork = type(preserveArtwork) == "table"
        and preserveArtwork or nil
    local function Conceal(key)
        if not preserveArtwork or preserveArtwork[key] ~= true then
            ConcealWindowRegion(frame[key])
        end
    end
    Conceal("NineSlice")
    Conceal("Bg")
    Conceal("TopTileStreaks")
    Conceal("TitleBg")
    Conceal("PortraitContainer")
    Conceal("portrait")
    Conceal("portraitFrame")
    Conceal("topBorderBar")
    Conceal("topLeftCorner")
    Conceal("TopRightCorner")
end

function NSkin:SkinWindow(frame, backgroundAnchor, style, borderColor,
    backgroundOwner, preserveArtwork)
    if not frame then return nil end

    local data = self:GetSkinData(frame, COMPONENT_STATE)
    if not data.blizzardHeaderHeight then
        local titleBackground = frame.TitleBg or frame.titleBg
        local height = titleBackground and titleBackground.GetHeight
            and titleBackground:GetHeight()
        data.blizzardHeaderHeight = tonumber(height) and height > 0 and height or nil
    end
    self:ConcealWindowArtwork(frame, preserveArtwork)
    style = style or self:GetStyle("window")
    local anchor = backgroundAnchor or frame
    backgroundOwner = backgroundOwner or frame
    local background = data.windowBackground
    if background and data.windowBackgroundOwner ~= backgroundOwner then
        background:Hide()
        background = nil
    end
    if not background then
        background = backgroundOwner:CreateTexture(
            nil, "BACKGROUND", nil, 0)
        data.windowBackground = background
    end
    data.windowBackgroundOwner = backgroundOwner
    data.windowBackgroundAnchor = anchor
    LayoutWindowBackground(frame, data, anchor)
    local backgroundColor = self:GetResolvedAppearanceColor(style, "background")
    background:SetColorTexture(unpack(backgroundColor))
    data.windowBackgroundColor = {
        backgroundColor[1], backgroundColor[2], backgroundColor[3], backgroundColor[4],
    }

    local border = self:CreatePixelBorder(
        frame, "NSkinWindowBorder", style.borderSize,
        borderColor or self:GetWindowBorderColor(), false, anchor
    )
    self:SetPixelBorderSize(border, style.borderSize)
    self:SetPixelBorderPadding(border, style.borderPadding or 0)
    self:SetPixelBorderColor(border, unpack(borderColor or self:GetWindowBorderColor()))
    return background, border
end

function NSkin:SkinWindowHeader(frame, style)
    if not frame then return nil end

    style = style or self:GetStyle("window").header
    local data = self:GetSkinData(frame, COMPONENT_STATE)
    local background = data.windowHeaderBackground
    if not background then
        background = frame:CreateTexture(nil, "BACKGROUND", nil, 7)
        background:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
        background:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
        data.windowHeaderBackground = background
    end
    local height = tonumber(style.height) or data.blizzardHeaderHeight
        or (frame.nskinOwnedGeometry and 22 or nil)
    if height then
        height = self:SnapToPhysicalPixel(frame, math.max(0, height))
        background:SetHeight(height)
    end
    local color = style.matchBackground and data.windowBackgroundColor
        or self:GetResolvedAppearanceColor(style, "background")
    color = color or self:GetResolvedAppearanceColor(style, "background")
    background:SetColorTexture(unpack(color))
    data.windowHeaderHeight = height or 0
    LayoutWindowBackground(frame, data, data.windowBackgroundAnchor or frame)
    return background
end

local STANDARD_WINDOW_HEADER_GLYPHS = {
    close = { text = "X", offsetX = 0, offsetY = 0 },
    maximize = { text = "+", offsetX = 0, offsetY = 0 },
    minimize = { text = "-", offsetX = 0, offsetY = 0 },
    fullscreen = { text = "□", offsetX = 0, offsetY = 0 },
}

local function RefreshWindowHeaderButtonAppearance(button)
    local data = NSkin:GetSkinData(button, COMPONENT_STATE, false)
    local state = data and data.windowHeaderButton
    if not state then return end

    local enabled = not button.IsEnabled or button:IsEnabled()
    local alpha = enabled and 1 or state.disabledAlpha
    local color = state.contentColor
    if state.text then
        state.text:SetTextColor(
            color[1], color[2], color[3], (color[4] or 1) * alpha)
    end
    if state.icon then
        state.icon:SetVertexColor(
            color[1], color[2], color[3], (color[4] or 1) * alpha)
    end
    if not enabled and data.hoverGlow then data.hoverGlow:Hide() end
end

function NSkin:SkinWindowHeaderButton(button, content, options)
    if not button or type(content) ~= "table" then return nil end
    options = options or {}

    local style = options.style or self:GetStyle("button")
    local background = self:GetFlatBackground(button)
    if not background then self:HideTextureRegions(button) end
    self:CreateFlatBackground(
        button, nil, options.background
            or self:GetResolvedAppearanceColor(style, "background")
            or style.background,
        options.border or self:GetComponentBorderColor("button", style))
    self:CreateFlatButtonGlow(button, style.hoverAlpha)

    local data = self:GetSkinData(button, COMPONENT_STATE)
    local state = data.windowHeaderButton or {}
    data.windowHeaderButton = state
    state.contentColor = self:GetResolvedAppearanceColor(style, "text")
        or style.text or self:GetStyle("text").color
    state.disabledAlpha = tonumber(style.disabledTextAlpha) or 0.45

    local glyph = content.glyph
        and STANDARD_WINDOW_HEADER_GLYPHS[content.glyph]
    if glyph then
        local text = state.text
        if not text then
            text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            state.text = text
        end
        text:ClearAllPoints()
        text:SetPoint("CENTER", button, "CENTER",
            glyph.offsetX or 0, glyph.offsetY or 0)
        text:SetText(glyph.text)
        self:ApplyResolvedTypography(text, self:GetStyle("text"))
        local font, _, flags = text:GetFont()
        if font then
            text:SetFont(font, tonumber(style.textSize) or 20, flags)
        end
        text:SetAlpha(1)
        text:Show()
        if state.icon then state.icon:Hide() end
    elseif content.icon then
        local iconDefinition = type(content.icon) == "table"
            and content.icon or { texture = content.icon }
        local icon = state.icon
        if not icon then
            icon = button:CreateTexture(nil, "OVERLAY", nil, 1)
            self:ConfigureOwnedPixelTexture(icon)
            state.icon = icon
        end
        icon:ClearAllPoints()
        icon:SetPoint("CENTER", button, "CENTER",
            tonumber(iconDefinition.offsetX) or 0,
            tonumber(iconDefinition.offsetY) or 0)
        local iconSize = tonumber(iconDefinition.size) or 14
        icon:SetSize(iconSize, iconSize)
        if iconDefinition.atlas and icon.SetAtlas then
            icon:SetAtlas(iconDefinition.atlas, false)
        else
            icon:SetTexture(iconDefinition.texture)
        end
        icon:SetAlpha(1)
        icon:Show()
        if state.text then state.text:Hide() end
    else
        return nil
    end

    if not state.stateHooked and button.HookScript then
        button:HookScript("OnEnable", RefreshWindowHeaderButtonAppearance)
        button:HookScript("OnDisable", RefreshWindowHeaderButtonAppearance)
        button:HookScript("OnShow", RefreshWindowHeaderButtonAppearance)
        state.stateHooked = true
    end
    RefreshWindowHeaderButtonAppearance(button)
    return state
end

function NSkin:SkinStandardCloseButton(window, closeButton, options)
    if not window or not closeButton then return nil end
    options = options or {}

    local data = self:GetSkinData(closeButton, COMPONENT_STATE)
    if not data.standardHeaderOriginalSize and closeButton.GetSize then
        local originalWidth, originalHeight = closeButton:GetSize()
        if tonumber(originalWidth) and originalWidth > 0
            and tonumber(originalHeight) and originalHeight > 0
        then
            data.standardHeaderOriginalSize = {
                originalWidth, originalHeight,
            }
        end
    end
    local width = tonumber(options.width)
    local height = tonumber(options.height)
    local originalSize = data.standardHeaderOriginalSize
    width = width or (originalSize and originalSize[1])
    height = height or (originalSize and originalSize[2])

    closeButton:ClearAllPoints()
    closeButton:SetPoint("TOPRIGHT", window, "TOPRIGHT", 0, 0)
    if width and height and closeButton.SetSize then
        closeButton:SetSize(width, height)
    end

    self:SkinWindowHeaderButton(closeButton, { glyph = "close" }, {
        style = options.style,
        background = options.background,
        border = options.border,
    })

    local border = self:GetPixelBorder(
        closeButton, "NSkinFlatBackgroundBorder")
    self:SetPixelBorderSize(border, options.borderSize or 1)
    self:SetPixelBorderPadding(border, 0)
    if border then
        -- The window border supplies the two exterior edges. Drawing the
        -- button edges over them would darken translucent borders and can
        -- produce an apparent double-thickness seam.
        border.top:Hide()
        border.right:Hide()
        border.left:Show()
        border.bottom:Show()
    end
    return closeButton
end

local function ConfigureWindowHeaderControlBorder(control, borderSize)
    local border = NSkin:GetPixelBorder(
        control, "NSkinFlatBackgroundBorder")
    if not border then return end

    NSkin:SetPixelBorderSize(border, borderSize or 1)
    NSkin:SetPixelBorderPadding(border, 0)
    -- The window supplies the shared top edge and the control to the right
    -- supplies the shared vertical edge. Keep only this slot's left and
    -- bottom separators so translucent borders are never drawn twice.
    border.top:Hide()
    border.right:Hide()
    border.left:Show()
    border.bottom:Show()
end

local function ResolveWindowHeaderControlTargets(controlDefinition)
    local resolved = {}
    local function AddTarget(value)
        if type(value) == "function" then value = value() end
        if not value then return end

        local target, content = value, controlDefinition
        if type(value) == "table" and value.target
            and (value.glyph or value.icon)
        then
            target, content = value.target, value
            if type(target) == "function" then target = target() end
        end
        if target then
            resolved[#resolved + 1] = { target = target, content = content }
        end
    end

    if type(controlDefinition.targets) == "table" then
        for _, value in ipairs(controlDefinition.targets) do AddTarget(value) end
    else
        AddTarget(controlDefinition.target)
    end
    return resolved
end

function NSkin:RegisterWindowHeaderControls(definition)
    if type(definition) ~= "table"
        or type(definition.id) ~= "string"
        or not definition.window
        or not definition.closeButton
    then return nil end

    local window = definition.window
    local closeButton = definition.closeButton
    local data = self:GetSkinData(window, COMPONENT_STATE)
    data.windowHeaderControlGroups = data.windowHeaderControlGroups or {}
    data.windowHeaderControlGroups[definition.id] = definition

    local defaultWidth = tonumber(definition.buttonWidth)
    if not defaultWidth and closeButton.GetWidth then
        local width = closeButton:GetWidth()
        if tonumber(width) and width > 0 then defaultWidth = width end
    end
    local defaultHeight = tonumber(definition.buttonHeight)
    if not defaultHeight and closeButton.GetHeight then
        local height = closeButton:GetHeight()
        if tonumber(height) and height > 0 then defaultHeight = height end
    end

    local previousControl = closeButton
    local spacing = tonumber(definition.spacing) or 0
    for _, controlDefinition in ipairs(definition.controls or {}) do
        local targets = ResolveWindowHeaderControlTargets(controlDefinition)
        local slotAnchor = targets[1] and targets[1].target
        local width = tonumber(controlDefinition.width) or defaultWidth
        local height = tonumber(controlDefinition.height) or defaultHeight
        if slotAnchor and width and height then
            for _, resolved in ipairs(targets) do
                local target = resolved.target
                target:ClearAllPoints()
                target:SetPoint(
                    "TOPRIGHT", previousControl, "TOPLEFT", -spacing, 0)
                if target.SetSize then target:SetSize(width, height) end
                ConfigureWindowHeaderControlBorder(
                    target, definition.borderSize)
            end
            previousControl = slotAnchor
        end
    end

    return data.windowHeaderControlGroups[definition.id]
end

function NSkin:GetWindowHeaderControlRegions(window, groupID)
    local data = self:GetSkinData(window, COMPONENT_STATE, false)
    local group = data and data.windowHeaderControlGroups
        and data.windowHeaderControlGroups[groupID]
    if not group then return {} end

    local regions = { group.closeButton }
    for _, controlDefinition in ipairs(group.controls or {}) do
        for _, resolved in ipairs(
            ResolveWindowHeaderControlTargets(controlDefinition))
        do
            regions[#regions + 1] = resolved.target
        end
    end
    return regions
end

function NSkin:SkinStandardWindowChrome(definition)
    if type(definition) ~= "table" or not definition.frame
        or type(definition.appearanceWindowID) ~= "string"
        or type(definition.elementID) ~= "string"
    then return nil end

    local frame = definition.frame
    local appearanceWindowID = definition.appearanceWindowID
    local elementID = definition.elementID
    local style = definition.style or self:GetAppearanceStyle(
        "window", appearanceWindowID, elementID)
    if not style then return nil end

    local borderColor = definition.borderColor
        or self:GetAppearanceBorderColor(
            "window", style, appearanceWindowID, elementID)
    if definition.artworkFrame and definition.artworkFrame ~= frame then
        self:ConcealWindowArtwork(
            definition.artworkFrame, definition.preserveArtwork)
    end
    local background, border = self:SkinWindow(
        frame, definition.backgroundAnchor, style, borderColor,
        definition.backgroundOwner, definition.preserveArtwork)
    local header = self:SkinWindowHeader(frame, style.header)

    local title = definition.title
    if title == nil then
        title = frame.TitleContainer and frame.TitleContainer.TitleText
    end
    if title then
        title:SetTextColor(unpack(
            self:GetResolvedAppearanceColor(style.header, "text")))
        self:ApplyResolvedTypography(title, style.header)
    end

    local closeButton = definition.closeButton
    if closeButton == nil then closeButton = frame.CloseButton end
    if closeButton and definition.skinCloseButton ~= false then
        local headerControlsID = definition.headerControlsID
            or (elementID .. ".HeaderControls")
        local headerButtonStyle = self:GetAppearanceStyle(
            "windowHeaderButton", appearanceWindowID, headerControlsID)
        local headerButtonBorder = self:GetAppearanceBorderColor(
            "windowHeaderButton", headerButtonStyle,
            appearanceWindowID, headerControlsID)
        local buttonWidth = tonumber(headerButtonStyle.width)
        local buttonHeight = tonumber(headerButtonStyle.height)
        buttonWidth = buttonWidth and buttonWidth > 0 and buttonWidth or nil
        buttonHeight = buttonHeight and buttonHeight > 0 and buttonHeight or nil
        self:SkinStandardCloseButton(frame, closeButton, {
            style = headerButtonStyle,
            background = definition.closeButtonBackground,
            border = definition.closeButtonBorder or headerButtonBorder,
            borderSize = style.borderSize,
            width = buttonWidth,
            height = buttonHeight,
        })
        for _, controlDefinition in ipairs(definition.headerControls or {}) do
            for _, resolved in ipairs(
                ResolveWindowHeaderControlTargets(controlDefinition))
            do
                self:SkinWindowHeaderButton(resolved.target, resolved.content, {
                    style = headerButtonStyle,
                    border = headerButtonBorder,
                })
            end
        end
        self:RegisterWindowHeaderControls({
            id = headerControlsID,
            window = frame,
            closeButton = closeButton,
            controls = definition.headerControls,
            spacing = definition.headerControlSpacing,
            buttonWidth = buttonWidth,
            buttonHeight = buttonHeight,
            borderSize = style.borderSize,
        })
        if not self:GetSkinningElement(headerControlsID) then
            self:RegisterSkinningElement(headerControlsID, {
                label = definition.headerControlsLabel
                    or "Window header buttons",
                kind = "WINDOW_HEADER_CONTROLS",
                appearanceWindowID = appearanceWindowID,
                window = frame,
                target = closeButton,
                priority = 95,
                draggable = false,
                highlightRegions = function()
                    return NSkin:GetWindowHeaderControlRegions(
                        frame, headerControlsID)
                end,
                isEditable = function()
                    return frame:IsVisible() and closeButton:IsVisible()
                end,
            })
        else
            self:NotifySkinningElementBoundsChanged(headerControlsID)
        end
    end

    return {
        style = style,
        background = background,
        border = border,
        header = header,
        title = title,
        closeButton = closeButton,
    }
end

-- Tab Skinning

local function ApplyTabDimensions(tab, style, data)
    local configuredWidth, configuredHeight = tonumber(style.width), tonumber(style.height)
    configuredWidth = configuredWidth and configuredWidth > 0 and configuredWidth or nil
    configuredHeight = configuredHeight and configuredHeight > 0 and configuredHeight or nil
    if configuredWidth or configuredHeight then
        if not data.tabOriginalSize then
            data.tabOriginalSize = { tab:GetWidth(), tab:GetHeight() }
        end
        tab:SetSize(configuredWidth or data.tabOriginalSize[1],
            configuredHeight or data.tabOriginalSize[2])
    elseif data.tabOriginalSize then
        tab:SetSize(data.tabOriginalSize[1], data.tabOriginalSize[2])
        data.tabOriginalSize = nil
    end
end

local function RefreshTabSelection(tab, selected)
    local data = NSkin:GetSkinData(tab, COMPONENT_STATE, false)
    NSkin:SkinTab(tab, selected, data and data.tabStyle, data and data.tabBorderColor)
end

function NSkin:SkinTab(tab, selected, style, borderColor)
    if not tab then return end
    style = style or self:GetStyle("tab")
    local data = self:GetSkinData(tab, COMPONENT_STATE)
    data.tabStyle, data.tabBorderColor = style, borderColor
    ApplyTabDimensions(tab, style, data)

    local background = self:GetFlatBackground(tab)
    if not background then
        if type(tab.SetTabSelected) == "function" and _G.hooksecurefunc then
            _G.hooksecurefunc(tab, "SetTabSelected", RefreshTabSelection)
        end
        self:HideTextureRegions(tab)
        background = self:CreateFlatBackground(tab, nil, style.background,
            borderColor or self:GetResolvedAppearanceColor(style, "border")
                or self:GetComponentBorderColor("tab", style))
    end

    self:CreateFlatButtonGlow(tab, style.hoverAlpha)
    self:SetPixelBorderColor(self:GetPixelBorder(tab, "NSkinFlatBackgroundBorder"),
        unpack(borderColor or self:GetResolvedAppearanceColor(style, "border")
            or self:GetComponentBorderColor("tab", style)))
    local tabBorder = self:GetPixelBorder(tab, "NSkinFlatBackgroundBorder")
    self:SetPixelBorderSize(tabBorder, style.borderSize or 1)
    self:SetPixelBorderPadding(tabBorder, style.borderPadding or 0)
    background:SetColorTexture(unpack(
        selected and self:GetResolvedAppearanceColor(style, "selectedBackground")
            or self:GetResolvedAppearanceColor(style, "background")
    ))
    if tab.Text then
        tab.Text:SetTextColor(unpack(self:GetResolvedAppearanceColor(style, "text")))
        self:ApplyResolvedTypography(tab.Text, style)
    end
end

local SIDE_TAB_BORDER_KEY = "NSkinSideTabBorder"

local function CenterSideTabIcon(tab)
    local icon = tab and tab.Icon
    if not icon then return end
    icon:ClearAllPoints()
    icon:SetPoint("CENTER", tab, "CENTER", 0, 0)
end

local function SuppressSideTabArtwork(tab)
    if tab.Background then tab.Background:SetAlpha(0) end
    if tab.SelectedTexture then tab.SelectedTexture:SetAlpha(0) end
    if tab.HighlightTexture then tab.HighlightTexture:SetAlpha(0) end
    if tab.TabGlow then
        tab.TabGlow:SetAlpha(0)
        tab.TabGlow:Hide()
    end
end

local function CaptureSideTabArtwork(tab, data)
    if data.sideTabArtworkBaseline then return end
    data.sideTabArtworkBaseline = {}
    for _, key in ipairs({ "Background", "SelectedTexture",
        "HighlightTexture", "TabGlow" }) do
        local region = tab[key]
        if region then
            data.sideTabArtworkBaseline[#data.sideTabArtworkBaseline + 1] = {
                region = region,
                alpha = region.GetAlpha and region:GetAlpha() or 1,
                shown = region.IsShown and region:IsShown() or true,
            }
        end
    end
end

function NSkin:RestoreSideTabOriginalState(tab, baselineID)
    local data = tab and self:GetSkinData(tab, COMPONENT_STATE, false)
    if not tab or not data then return false end
    local restored = self:RestoreComponentBaseline(
        baselineID or data.sideTabBaselineID)
    if tab.Icon and data.sideTabOriginalIconPoints then
        RestoreFramePoints(tab.Icon, data.sideTabOriginalIconPoints)
        restored = true
    end
    for _, state in ipairs(data.sideTabArtworkBaseline or {}) do
        if state.region.SetAlpha then state.region:SetAlpha(state.alpha) end
        if state.region.SetShown then state.region:SetShown(state.shown) end
    end
    if data.sideTabBackground then data.sideTabBackground:Hide() end
    if data.hoverGlow then data.hoverGlow:Hide() end
    self:SetPixelBorderShown(
        self:GetPixelBorder(tab, SIDE_TAB_BORDER_KEY), false)
    return restored == true
end

function NSkin:SkinSideTab(tab, style, borderColor)
    if not tab or not tab.CreateTexture then return false end
    style = style or self:GetStyle("sideTab")
    if not style then return false end
    local data = self:GetSkinData(tab, COMPONENT_STATE)
    if not data.sideTabBaselineID then
        data.sideTabBaselineID = "SideTab:" .. tostring(tab)
        self:CaptureComponentBaseline(data.sideTabBaselineID, tab, {
            size = true,
            points = true,
        })
    end
    local baseline = self:GetComponentBaseline(data.sideTabBaselineID)
    local width, height = tonumber(style.width), tonumber(style.height)
    width = width and width > 0 and width or nil
    height = height and height > 0 and height or nil
    if width or height then
        self:MarkComponentGeometryModified(
            data.sideTabBaselineID, "size", true)
        tab:SetSize(width or (baseline and baseline.width) or tab:GetWidth(),
            height or (baseline and baseline.height) or tab:GetHeight())
    elseif baseline and baseline.modified.size then
        self:RestoreComponentBaseline(data.sideTabBaselineID, { size = true })
    end

    if tab.Icon and not data.sideTabOriginalIconPoints then
        data.sideTabOriginalIconPoints = CaptureFramePoints(tab.Icon)
    end
    CaptureSideTabArtwork(tab, data)
    CenterSideTabIcon(tab)
    SuppressSideTabArtwork(tab)

    if not data.sideTabBackground then
        local background = tab:CreateTexture(nil, "BACKGROUND", nil, 7)
        background:SetAllPoints(tab)
        self:ConfigureOwnedPixelTexture(background)
        data.sideTabBackground = background
    end
    data.sideTabBackground:SetColorTexture(unpack(
        self:GetResolvedAppearanceColor(style, "background")))
    data.sideTabBackground:Show()

    local resolvedBorder = borderColor
        or self:GetResolvedAppearanceColor(style, "border")
        or self:GetComponentBorderColor("sideTab", style)
    local border = self:GetPixelBorder(tab, SIDE_TAB_BORDER_KEY)
        or self:CreatePixelEdgeBorder(tab, SIDE_TAB_BORDER_KEY,
            { "top", "right", "bottom" }, 1, resolvedBorder, tab)
    self:SetPixelBorderColor(border, unpack(resolvedBorder))
    self:SetPixelBorderSize(border, 1)
    self:SetPixelBorderPadding(border, 0)
    self:SetPixelBorderShown(border, true)

    local glow = self:CreateFlatButtonGlow(tab, style.hoverAlpha)
    if glow then glow:SetColorTexture(1, 1, 1, style.hoverAlpha or 0.10) end
    if not data.sideTabInteractionHooked and tab.HookScript then
        tab:HookScript("OnMouseDown", CenterSideTabIcon)
        tab:HookScript("OnMouseUp", CenterSideTabIcon)
        tab:HookScript("OnShow", function(shownTab)
            local shownData = NSkin:GetSkinData(
                shownTab, COMPONENT_STATE, false)
            local shownStyle = shownData and shownData.sideTabStyle
            if shownStyle then
                NSkin:SkinSideTab(shownTab, shownStyle,
                    shownData.sideTabBorderColor)
            end
        end)
        data.sideTabInteractionHooked = true
    end
    data.sideTabStyle = style
    data.sideTabBorderColor = resolvedBorder
    return true
end

function NSkin:LayoutTabGroup(tabs, options)
    if type(tabs) ~= "table" then return end
    options = options or {}

    local spacing = tonumber(options.spacing) or self:GetTabSpacing() or 0
    local vertical = options.orientation == "VERTICAL"
    local anchor = options.anchor
    local anchorPoint = anchor and anchor.point
    local anchorRelativeTo = anchor and anchor.relativeTo
    local anchorRelativePoint = anchor and anchor.relativePoint
    local anchorX = anchor and anchor.x or 0
    local anchorY = anchor and anchor.y or 0
    local owner = options.owner
    local edge = options.edge
    local previous

    if owner and not vertical and (edge == "BOTTOM" or edge == "TOP") then
        local layout = options.placement or self:GetStyle("tab").bottom or {}
        if layout.mode == "GRID" then
            anchorPoint = layout.point or "TOPLEFT"
            anchorRelativeTo = owner
            anchorRelativePoint = layout.relativePoint or "TOPLEFT"
            anchorX = tonumber(layout.x) or 0
            anchorY = tonumber(layout.y) or 0
        else
        edge = layout.edge or edge
        local side = layout.side or "OUTSIDE"
        local visibleCount = 0
        local totalWidth = 0
        for i = 1, #tabs do
            local tab = tabs[i]
            if tab and (not tab.IsShown or tab:IsShown()) then
                visibleCount = visibleCount + 1
                totalWidth = totalWidth + (tab.GetWidth and tab:GetWidth() or 0)
            end
        end
        totalWidth = totalWidth + math.max(0, visibleCount - 1) * spacing
        local relativePoint = edge .. "LEFT"
        local alignment = layout.alignment or layout.anchor
        local startX = layout.alongOffset or layout.offsetX or 0
        if alignment == "CENTER" then
            relativePoint = edge
            startX = startX - totalWidth / 2
        elseif alignment == "RIGHT" then
            relativePoint = edge .. "RIGHT"
            startX = startX - totalWidth
        end
        if edge == "TOP" then
            anchorPoint = side == "INSIDE" and "TOPLEFT" or "BOTTOMLEFT"
        else
            anchorPoint = side == "INSIDE" and "BOTTOMLEFT" or "TOPLEFT"
        end
        anchorRelativeTo = owner
        anchorRelativePoint = relativePoint
        anchorX = startX
        anchorY = layout.edgeOffset or layout.offsetY or 0
        end
    end

    for i = 1, #tabs do
        local tab = tabs[i]
        local usable = tab
            and (not tab.IsShown or tab:IsShown())
            and tab.ClearAllPoints and tab.SetPoint
            and not (tab.IsForbidden and tab:IsForbidden())
            and not (tab.IsProtected and tab:IsProtected())
        if usable then
            if not previous then
                if anchorPoint then
                    tab:ClearAllPoints()
                    tab:SetPoint(anchorPoint, anchorRelativeTo,
                        anchorRelativePoint, anchorX, anchorY)
                end
            else
                tab:ClearAllPoints()
                if vertical then
                    tab:SetPoint("TOP", previous, "BOTTOM", 0, -spacing)
                else
                    tab:SetPoint("LEFT", previous, "RIGHT", spacing, 0)
                end
            end
            previous = tab
        end
    end
    return previous ~= nil
end

function NSkin:LayoutTabSystem(tabSystem, options)
    if not tabSystem or type(tabSystem.tabs) ~= "table"
        or not tabSystem.MarkDirty
        or (tabSystem.IsForbidden and tabSystem:IsForbidden())
        or (tabSystem.IsProtected and tabSystem:IsProtected())
    then
        return
    end

    tabSystem.spacing = tonumber(options and options.spacing)
        or self:GetTabSpacing() or tabSystem.spacing or 0
    tabSystem:MarkDirty()

    if options and options.owner
        and (options.edge == "BOTTOM" or options.edge == "TOP")
    then
        local layout = options.placement or self:GetStyle("tab").bottom or {}
        if layout.mode == "GRID" then
            tabSystem:ClearAllPoints()
            tabSystem:SetPoint(layout.point or "TOPLEFT", options.owner,
                layout.relativePoint or "TOPLEFT", tonumber(layout.x) or 0,
                tonumber(layout.y) or 0)
            return true
        end
        local relativeElement = layout.relativeTo and skinningElements[layout.relativeTo]
        if relativeElement and relativeElement.snapTarget
            and relativeElement.window == options.owner and relativeElement.target
            and (not relativeElement.target.IsShown or relativeElement.target:IsShown())
        then
            tabSystem:ClearAllPoints()
            tabSystem:SetPoint(layout.point, relativeElement.target, layout.relativePoint,
                tonumber(layout.offsetX) or 0, tonumber(layout.offsetY) or 0)
            return true
        end
        local edge = layout.edge or options.edge
        local side = layout.side or "OUTSIDE"
        local alignment = layout.alignment or layout.anchor
        local alongOffset = layout.alongOffset or layout.offsetX or 0
        local edgeOffset = layout.edgeOffset or layout.offsetY or 0
        local point
        if edge == "TOP" then
            point = side == "INSIDE" and "TOPLEFT" or "BOTTOMLEFT"
        else
            point = side == "INSIDE" and "BOTTOMLEFT" or "TOPLEFT"
        end
        local relativePoint = edge .. "LEFT"
        if alignment == "CENTER" then
            point = point:gsub("LEFT", "")
            relativePoint = edge
        elseif alignment == "RIGHT" then
            point = point:gsub("LEFT", "RIGHT")
            relativePoint = edge .. "RIGHT"
        end
        tabSystem:ClearAllPoints()
        tabSystem:SetPoint(point, options.owner, relativePoint,
            alongOffset, edgeOffset)
    end
    return true
end

function NSkin:SkinTabSystem(tabSystem, style, borderColor)
    if not tabSystem or not tabSystem.tabs then return end
    style = style or self:GetStyle("tab")

    for i = 1, #tabSystem.tabs do
        local tab = tabSystem.tabs[i]
        local selected = tab and tab.IsSelected and tab:IsSelected()
        self:SkinTab(tab, selected, style, borderColor)
    end
end

function NSkin:RegisterTabGroup(groupID, definition)
    if type(groupID) ~= "string" or groupID == ""
        or type(definition) ~= "table"
        or type(definition.appearanceWindowID) ~= "string"
        or not self:GetAppearanceScope(definition.appearanceWindowID)
        or not (definition.window or definition.owner)
        or definition.orientation ~= "HORIZONTAL"
        or (definition.edge ~= "BOTTOM" and definition.edge ~= "TOP")
        or (not definition.container and type(definition.tabs) ~= "table")
    then
        return false
    end

    if not tabGroupOriginalPoints[groupID] then
        local originals = {}
        local targets = definition.container and { definition.container }
            or definition.tabs
        for i = 1, #(targets or {}) do
            local target = targets[i]
            local points = {}
            if target and target.GetNumPoints then
                for pointIndex = 1, target:GetNumPoints() do
                    points[pointIndex] = { target:GetPoint(pointIndex) }
                end
            end
            originals[i] = { target = target, points = points }
        end
        tabGroupOriginalPoints[groupID] = originals
    end

    if definition.originalSpacing == nil then
        if definition.container and tonumber(definition.container.spacing) then
            definition.originalSpacing = tonumber(definition.container.spacing)
        elseif type(definition.tabs) == "table" and #definition.tabs > 1 then
            local first, second = definition.tabs[1], definition.tabs[2]
            local firstRight = first and first.GetRight and first:GetRight()
            local secondLeft = second and second.GetLeft and second:GetLeft()
            if firstRight and secondLeft then
                definition.originalSpacing = secondLeft - firstRight
            end
        end
    end

    definition.kind = "TAB_GROUP"
    definition.editorOptions = self:CreateEditorOptionsPreset(
        "TAB_GROUP", definition.extraEditorOptions)

    local group = tabGroups[groupID]
    if group then
        for key, value in pairs(definition) do group[key] = value end
    else
        group = definition
        group.id = groupID
        tabGroups[groupID] = group
    end
    self:RefreshTabGroupBaseline(groupID, true)
    if type(group.applyPlacement) ~= "function" then
        group.applyPlacement = function(element, placement, applyOptions)
            return NSkin:ApplyTabGroupPlacement(element, placement, applyOptions)
        end
    end
    if type(group.module) == "string" and not group.getPlacement then
        group.hasPlacement = function(element)
            local moduleOptions = NSkin:GetModuleOptions(element.module, false)
            return moduleOptions and moduleOptions.tabPlacements
                and moduleOptions.tabPlacements[element.id] ~= nil
        end
        group.getPlacement = function(element)
            local moduleOptions = NSkin:GetModuleOptions(element.module, false)
            local saved = moduleOptions and moduleOptions.tabPlacements
                and moduleOptions.tabPlacements[element.id]
            if saved then return CopyPlacement(saved) end
            local originals = tabGroupOriginalPoints[element.id]
            local target = originals and originals[1] and originals[1].target
            if target then return GetCurrentWindowPlacement(element.window, target) end
            return CopyPlacement(NSkin:GetTabPlacement())
        end
        group.setPlacement = function(element, placement)
            if not NSkin:ApplyTabGroupPlacement(element, placement,
                { suppressNotify = true })
            then
                return false
            end
            local moduleOptions = NSkin:GetModuleOptions(element.module, true)
            moduleOptions.tabPlacements = moduleOptions.tabPlacements or {}
            moduleOptions.tabPlacements[element.id] = CopyPlacement(placement)
            FireComponentCallback("TabGroupLayoutApplied", element)
            return true
        end
        group.resetPlacement = function(element)
            NSkin:RestoreTabGroupOriginalPlacement(element.id)
            local moduleOptions = NSkin:GetModuleOptions(element.module, false)
            if moduleOptions and moduleOptions.tabPlacements then
                moduleOptions.tabPlacements[element.id] = nil
                if not next(moduleOptions.tabPlacements) then
                    moduleOptions.tabPlacements = nil
                end
                if not next(moduleOptions) then
                    local profile = NSkin:GetProfile()
                    if profile.moduleOptions then
                        profile.moduleOptions[element.module] = nil
                        if not next(profile.moduleOptions) then
                            profile.moduleOptions = nil
                        end
                    end
                end
            end
            FireComponentCallback("TabGroupLayoutApplied", element)
            return true
        end
    end

    self:RegisterSkinningElement(groupID, group)
    return true
end

function NSkin:RefreshTabGroupBaseline(groupID, force)
    local group = tabGroups[groupID]
    if not group then return false end
    if type(group.canCaptureBaseline) == "function"
        and group.canCaptureBaseline(group) ~= true
    then return false end
    if force then
        for i = 1, #(group.tabBaselineIDs or {}) do
            local baseline = self:GetComponentBaseline(group.tabBaselineIDs[i])
            if baseline and next(baseline.modified) then return false end
        end
        local groupBaseline = self:GetComponentBaseline(group.groupBaselineID)
        if groupBaseline and next(groupBaseline.modified) then return false end
    end
    group.tabBaselineIDs = group.tabBaselineIDs or {}
    local tabs = group.container and group.container.tabs or group.tabs
    for i = 1, #(tabs or {}) do
        local tab = tabs[i]
        if tab then
            local id = groupID .. ":tab:" .. i
            group.tabBaselineIDs[i] = id
            self:CaptureComponentBaseline(id, tab, {
                size = true, points = true, force = force == true,
            })
        end
    end
    local groupTarget = group.container or (tabs and tabs[1])
    if groupTarget then
        group.groupBaselineID = groupID .. ":group"
        self:CaptureComponentBaseline(group.groupBaselineID, groupTarget, {
            points = group.container ~= nil,
            spacing = group.container or false,
            force = force == true,
        })
        local baseline = self:GetComponentBaseline(group.groupBaselineID)
        if baseline and baseline.spacing ~= nil then
            group.originalSpacing = baseline.spacing
        end
    end
    return true
end

function NSkin:RegisterSkinningElement(elementID, definition)
    if type(elementID) ~= "string" or elementID == ""
        or type(definition) ~= "table"
        or not (definition.window or definition.owner)
    then
        return false
    end

    definition.window = definition.window or definition.owner
    definition.target = definition.target or definition.container or definition.owner
    if type(definition.appearanceWindowID) ~= "string"
        or definition.appearanceWindowID == ""
        or not self:GetAppearanceScope(definition.appearanceWindowID)
    then
        return false
    end
    if not definition.editorOptions and EDITOR_PRESETS[definition.kind] then
        definition.editorOptions = self:CreateEditorOptionsPreset(
            definition.kind, definition.extraEditorOptions)
    end
    definition.owner = nil
    definition.priority = tonumber(definition.priority) or 0
    definition.highlightPadding = tonumber(definition.highlightPadding) or 0
    if type(definition.baseline) == "table" and definition.target then
        self:CaptureComponentBaseline(elementID, definition.target,
            definition.baseline)
    end
    definition.captureBaseline = definition.captureBaseline or function(element)
        if type(element.baseline) ~= "table" then return false end
        return NSkin:CaptureComponentBaseline(
            element.id, element.target, element.baseline) ~= nil
    end
    definition.restoreGeometry = definition.restoreGeometry or function(element)
        return NSkin:RestoreComponentBaseline(element.id)
    end
    definition.refreshBaseline = definition.refreshBaseline or function(element)
        return NSkin:RefreshComponentBaseline(element.id)
    end
    if not registeredWindows[definition.window] then
        windowSequence = windowSequence + 1
        registeredWindows[definition.window] = windowSequence
    end

    local element = skinningElements[elementID]
    if element then
        for key, value in pairs(definition) do element[key] = value end
    else
        element = definition
        element.id = elementID
        skinningElements[elementID] = element
    end
    FireComponentCallback("SkinningElementRegistered", element)
    return true
end

function NSkin:MarkSkinningWindowActive(window)
    if not window then return false end
    windowSequence = windowSequence + 1
    registeredWindows[window] = windowSequence
    return true
end

function NSkin:GetMostRecentVisibleSkinningWindow(excludedWindow)
    local bestWindow, bestSequence
    for window, sequence in pairs(registeredWindows) do
        if window ~= excludedWindow and window.IsShown and window:IsShown()
            and (not bestSequence or sequence > bestSequence)
        then
            bestWindow, bestSequence = window, sequence
        end
    end
    return bestWindow
end

function NSkin:ForEachRegisteredSkinningElement(callback)
    if type(callback) ~= "function" then return end
    for _, element in pairs(skinningElements) do callback(element) end
end

function NSkin:GetSkinningElement(elementID)
    return skinningElements[elementID]
end

function NSkin:IsSkinningElementEditable(element)
    if not element then return false end
    return type(element.isEditable) ~= "function" or element.isEditable(element) == true
end

function NSkin:LayoutWindowElement(element, placement, options)
    local target = element and element.target
    local window = element and element.window
    if not target or not window or type(placement) ~= "table"
        or not target.ClearAllPoints or not target.SetPoint
        or (target.IsProtected and target:IsProtected())
        or (_G.InCombatLockdown and _G.InCombatLockdown())
    then
        return false
    end
    if placement.mode == "GRID" then
        target:ClearAllPoints()
        target:SetPoint(placement.point or "TOPLEFT", window,
            placement.relativePoint or "TOPLEFT", tonumber(placement.x) or 0,
            tonumber(placement.y) or 0)
        if not (options and options.suppressNotify) then
            self:NotifySkinningElementBoundsChanged(element.id)
        end
        return true
    end
    local relativeElement = placement.relativeTo and skinningElements[placement.relativeTo]
    if relativeElement and relativeElement.snapTarget and relativeElement.window == window
        and relativeElement.target and (not relativeElement.target.IsShown
            or relativeElement.target:IsShown())
    then
        target:ClearAllPoints()
        target:SetPoint(placement.point, relativeElement.target, placement.relativePoint,
            tonumber(placement.offsetX) or 0, tonumber(placement.offsetY) or 0)
        if not (options and options.suppressNotify) then
            self:NotifySkinningElementBoundsChanged(element.id)
        end
        return true
    end
    local edge = placement.edge
    local side = placement.side
    local alignment = placement.alignment
    if (edge ~= "TOP" and edge ~= "BOTTOM")
        or (side ~= "INSIDE" and side ~= "OUTSIDE")
        or (alignment ~= "LEFT" and alignment ~= "CENTER" and alignment ~= "RIGHT")
    then return false end
    local point
    if edge == "TOP" then point = side == "INSIDE" and "TOP" or "BOTTOM"
    else point = side == "INSIDE" and "BOTTOM" or "TOP" end
    local relativePoint = edge
    if alignment ~= "CENTER" then
        point = point .. alignment
        relativePoint = relativePoint .. alignment
    end
    target:ClearAllPoints()
    target:SetPoint(point, window, relativePoint,
        tonumber(placement.alongOffset) or 0, tonumber(placement.edgeOffset) or 0)
    if not (options and options.suppressNotify) then
        self:NotifySkinningElementBoundsChanged(element.id)
    end
    return true
end

-- Scrollbars commonly use both TOP and BOTTOM anchors so their parent owns
-- their height. Replacing that pair with one movable anchor changes the
-- resolved height. Translate the complete captured anchor set instead.
function NSkin:LayoutWindowElementPreservingAnchorSpan(element, placement, options)
    local target = element and element.target
    local window = element and element.window
    if not target or not window or type(placement) ~= "table"
        or (target.IsProtected and target:IsProtected())
        or (_G.InCombatLockdown and _G.InCombatLockdown())
    then return false end

    local baseline = self:GetComponentBaseline(element.id)
    if not baseline or type(baseline.points) ~= "table"
        or #baseline.points < 2
    then return self:LayoutWindowElement(element, placement, options) end

    RestoreFramePoints(target, baseline.points)
    local windowLeft, windowTop = window:GetLeft(), window:GetTop()
    local targetLeft, targetTop = target:GetLeft(), target:GetTop()
    local width, height = target:GetWidth(), target:GetHeight()
    local windowWidth, windowHeight = window:GetWidth(), window:GetHeight()
    if not windowLeft or not windowTop or not targetLeft or not targetTop
        or not width or not height or not windowWidth or not windowHeight
    then return false end

    local desiredX, desiredY
    if placement.mode == "GRID" then
        desiredX = tonumber(placement.x) or 0
        desiredY = tonumber(placement.y) or 0
    elseif not placement.relativeTo then
        local alignment, edge, side = placement.alignment,
            placement.edge, placement.side
        local along = tonumber(placement.alongOffset) or 0
        local edgeOffset = tonumber(placement.edgeOffset) or 0
        if alignment == "LEFT" then
            desiredX = along
        elseif alignment == "CENTER" then
            desiredX = along + windowWidth / 2 - width / 2
        elseif alignment == "RIGHT" then
            desiredX = along + windowWidth - width
        end
        if edge == "TOP" then
            desiredY = side == "INSIDE" and edgeOffset
                or edgeOffset + height
        elseif edge == "BOTTOM" then
            desiredY = side == "INSIDE"
                and edgeOffset + height - windowHeight
                or edgeOffset - windowHeight
        end
    end
    if desiredX == nil or desiredY == nil then return false end

    local deltaX = desiredX - (targetLeft - windowLeft)
    local deltaY = desiredY - (targetTop - windowTop)
    target:ClearAllPoints()
    for i = 1, #baseline.points do
        local point = baseline.points[i]
        target:SetPoint(point[1], point[2], point[3],
            (tonumber(point[4]) or 0) + deltaX,
            (tonumber(point[5]) or 0) + deltaY)
    end
    if not (options and options.suppressNotify) then
        self:NotifySkinningElementBoundsChanged(element.id)
    end
    return true
end

local function GetSavedMovablePlacement(element)
    local options = NSkin:GetModuleOptions(element.module, false)
    return options and options.movablePlacements
        and options.movablePlacements[element.id]
end

local function EnsureMovableWatcher(window)
    local watcher = movableWatchers[window]
    if not watcher then
        watcher = CreateFrame("Frame", nil, window)
        watcher:Hide()
        watcher:SetScript("OnShow", function()
            local elements = movableElementsByWindow[window]
            for i = 1, #(elements or {}) do
                local element = elements[i]
                local placement = GetSavedMovablePlacement(element)
                if placement and NSkin:IsSkinningElementEditable(element) then
                    element.applyPlacement(element, placement)
                end
            end
        end)
        movableWatchers[window] = watcher
    end
    watcher:Show()
end

function NSkin:GetSavedMovableElementPlacement(elementID)
    local element = skinningElements[elementID]
    local placement = element and element.module and GetSavedMovablePlacement(element)
    return placement and CopyPlacement(placement) or nil
end

function NSkin:RestoreMovableElementOriginal(elementOrID, suppressNotify)
    local element = type(elementOrID) == "table"
        and elementOrID or skinningElements[elementOrID]
    if not element or not element.target then return false end
    local restored = self:RestoreComponentBaseline(element.id)
    if not restored then
        local points = movableOriginalPoints[element.id]
        if not points then return false end
        RestoreFramePoints(element.target, points)
        local size = movableOriginalSizes[element.id]
        if size and element.supportsResize and element.target.SetSize then
            element.target:SetSize(size[1], size[2])
        end
    end
    if not suppressNotify then self:NotifySkinningElementBoundsChanged(element.id) end
    return true
end

local function ClearSavedMovablePlacement(element)
    local options = element and NSkin:GetModuleOptions(element.module, false)
    if not options or not options.movablePlacements then return false end
    if options.movablePlacements[element.id] == nil then return false end
    options.movablePlacements[element.id] = nil
    if not next(options.movablePlacements) then options.movablePlacements = nil end
    if not next(options) then
        local profile = NSkin:GetProfile()
        if profile.moduleOptions then
            profile.moduleOptions[element.module] = nil
            if not next(profile.moduleOptions) then profile.moduleOptions = nil end
        end
    end
    return true
end

function NSkin:RegisterMovableElement(definition)
    if type(definition) ~= "table" or type(definition.id) ~= "string"
        or type(definition.module) ~= "string" or not definition.window
        or type(definition.appearanceWindowID) ~= "string"
        or definition.appearanceWindowID == ""
        or not self:GetAppearanceScope(definition.appearanceWindowID)
        or not definition.target
    then return false end
    local id = definition.id
    self:CaptureComponentBaseline(id, definition.target, {
        points = true,
        size = definition.supportsResize == true,
        refreshBlizzardLayout = definition.refreshBlizzardLayout,
        canCapture = definition.canCaptureBaseline,
    })
    if not movableOriginalPoints[id] then
        local points = {}
        for i = 1, definition.target:GetNumPoints() do
            points[i] = { definition.target:GetPoint(i) }
        end
        movableOriginalPoints[id] = points
        if definition.supportsResize and definition.target.GetSize then
            movableOriginalSizes[id] = { definition.target:GetSize() }
        end
    end
    local customApply = definition.applyPlacement
    definition.kind = definition.kind or "MOVABLE"
    local sharedType = self:GetSharedElementType(definition.kind)
    if definition.preserveAnchorSpan == nil and sharedType then
        definition.preserveAnchorSpan = sharedType.preserveAnchorSpan
    end
    if not definition.editorOptions then
        definition.editorOptions = self:CreateEditorOptionsPreset(
            definition.editorPreset
                or (sharedType and sharedType.editorPreset)
                or definition.kind,
            definition.extraEditorOptions)
    end
    definition.draggable = definition.draggable ~= false
    definition.movable = true
    definition.getPlacement = definition.getPlacement or function(element)
        local saved = GetSavedMovablePlacement(element)
        if saved then return CopyPlacement(saved) end
        return CopyPlacement(element.defaultPlacement
            or GetCurrentWindowPlacement(element.window, element.target))
    end
    definition.applyPlacement = customApply or function(element, placement, applyOptions)
        if element.preserveAnchorSpan then
            return NSkin:LayoutWindowElementPreservingAnchorSpan(
                element, placement, applyOptions)
        end
        return NSkin:LayoutWindowElement(element, placement, applyOptions)
    end
    definition.setPlacement = definition.setPlacement or function(element, placement)
        if placement.relativeTo
            and NSkin:WouldCreateSkinningPlacementCycle(element.id, placement.relativeTo)
        then return false end
        if not element.applyPlacement(element, placement) then return false end
        local options = NSkin:GetModuleOptions(element.module, true)
        options.movablePlacements = options.movablePlacements or {}
        options.movablePlacements[element.id] = CopyPlacement(placement)
        NSkin:MarkComponentGeometryModified(element.id, "points", true)
        EnsureMovableWatcher(element.window)
        return true
    end
    definition.resetPlacement = definition.resetPlacement or function(element)
        if not NSkin:RestoreMovableElementOriginal(element) then return false end
        ClearSavedMovablePlacement(element)
        return true
    end
    self:RegisterSkinningElement(id, definition)
    local element = skinningElements[id]
    local elements = movableElementsByWindow[element.window]
    if not elements then
        elements = {}
        movableElementsByWindow[element.window] = elements
    end
    local alreadyRegistered
    for i = 1, #elements do
        if elements[i] == element then alreadyRegistered = true break end
    end
    if not alreadyRegistered then elements[#elements + 1] = element end
    local saved = GetSavedMovablePlacement(element)
    if saved and self:IsSkinningElementEditable(element) then
        if element.applyPlacement(element, saved) then
            self:MarkComponentGeometryModified(element.id, "points", true)
            EnsureMovableWatcher(element.window)
        end
    end
    return true
end

local PROGRESS_COMPONENT_STATE = "progressBarComponent"
local PROGRESS_BACKGROUND_KEY = "NSkinProgressBarBackground"

local function HideProgressBarArtwork(region, fill)
    if region == fill or not region or not region.IsObjectType
        or not region:IsObjectType("Texture")
    then return end
    region:SetAlpha(0)
    region:SetTexture(nil)
    region:Hide()
end

local function CenterProgressBarText(bar, region, offsetX, offsetY)
    if not region or not region.IsObjectType or not region:IsObjectType("FontString") then
        return
    end
    region:ClearAllPoints()
    region:SetPoint("CENTER", bar, "CENTER", offsetX, offsetY)
end

function NSkin:SkinProgressBar(bar, options)
    if not bar or not bar.GetObjectType or bar:GetObjectType() ~= "StatusBar"
        or not bar.SetStatusBarTexture or (bar.IsForbidden and bar:IsForbidden())
    then return false end
    options = options or {}
    local style = self:GetStyle("progressBar")
    local data = self:GetSkinData(bar, PROGRESS_COMPONENT_STATE)
    if not data.baselineID then
        data.baselineID = "ProgressBar:" .. tostring(bar)
        self:CaptureComponentBaseline(data.baselineID, bar, { size = true })
    end
    local baseline = self:GetComponentBaseline(data.baselineID)
    if not data.originalHeight then
        data.originalHeight = baseline and baseline.height or bar:GetHeight()
    end
    local height = tonumber(options.height)
    if height and height > 0 then
        self:MarkComponentGeometryModified(data.baselineID, "size", true)
        bar:SetHeight(height)
    elseif baseline and baseline.modified.size then
        self:RestoreComponentBaseline(data.baselineID, { size = true })
    end

    local fill = bar:GetStatusBarTexture()
    if type(options.artworkRegions) == "table" then
        for i = 1, #options.artworkRegions do
            HideProgressBarArtwork(options.artworkRegions[i], fill)
        end
    elseif options.stripArtwork and not data.artworkStripped and bar.GetRegions then
        local regions = { bar:GetRegions() }
        for i = 1, #regions do HideProgressBarArtwork(regions[i], fill) end
        data.artworkStripped = true
    end

    local texture = options.texture
    if options.useAppearanceTexture then texture = style and style.texture end
    if type(texture) == "string" and texture ~= "" then
        bar:SetStatusBarTexture(texture)
        fill = bar:GetStatusBarTexture()
        if fill then
            fill:Show()
            if fill.SetHorizTile then fill:SetHorizTile(false) end
            if fill.SetVertTile then fill:SetVertTile(false) end
        end
    end

    if options.background then
        local backgroundColor = options.backgroundColor or style.background
        local borderColor = options.borderColor or self:GetWindowBorderColor()
            or style.border
        local background = self:CreateFlatBackground(
            bar, PROGRESS_BACKGROUND_KEY, backgroundColor, borderColor)
        if background then
            -- Blizzard progress templates can alter their regions again while
            -- refreshing. Reassert the complete NSkin-owned surface each pass.
            local pixel = self:GetPhysicalPixelSize(bar)
            background:ClearAllPoints()
            background:SetPoint("TOPLEFT", bar, "TOPLEFT", pixel, -pixel)
            background:SetPoint(
                "BOTTOMRIGHT", bar, "BOTTOMRIGHT", -pixel, pixel)
            background:SetColorTexture(unpack(backgroundColor))
            background:SetAlpha(1)
            background:Show()
        end
        local border = self:GetPixelBorder(
            bar, PROGRESS_BACKGROUND_KEY .. "Border")
        self:SetPixelBorderColor(border, unpack(borderColor))
        self:SetPixelBorderSize(border, 1)
        self:SetPixelBorderPadding(border, 0)
        self:SetPixelBorderShown(border, true)
    end

    if options.centerText then
        local offsetX = tonumber(options.textOffsetX) or 0
        local offsetY = tonumber(options.textOffsetY) or 0
        if type(options.textRegions) == "table" then
            for i = 1, #options.textRegions do
                CenterProgressBarText(bar, options.textRegions[i], offsetX, offsetY)
            end
        else
            CenterProgressBarText(bar, bar.Label, offsetX, offsetY)
            if bar.GetRegions then
                local regions = { bar:GetRegions() }
                for i = 1, #regions do
                    CenterProgressBarText(bar, regions[i], offsetX, offsetY)
                end
            end
        end
    end
    return true
end

GetCurrentWindowPlacement = function(window, target)
    local windowLeft, windowTop = window:GetLeft(), window:GetTop()
    local targetLeft, targetTop = target:GetLeft(), target:GetTop()
    if windowLeft and windowTop and targetLeft and targetTop then
        return { mode = "GRID", point = "TOPLEFT", relativePoint = "TOPLEFT",
            x = targetLeft - windowLeft, y = targetTop - windowTop }
    end
    return { edge = "TOP", side = "INSIDE", alignment = "CENTER",
        alongOffset = 0, edgeOffset = -46 }
end

function NSkin:GetCurrentWindowElementPlacement(window, target)
    if not window or not target then return nil end
    return CopyPlacement(GetCurrentWindowPlacement(window, target))
end

function NSkin:RegisterSimpleMovableElement(definition)
    if type(definition) ~= "table" then return nil end
    local existing = definition.id and self:GetSkinningElement(definition.id)
    if existing then
        local saved = self:GetSavedMovableElementPlacement(definition.id)
        if saved and self:IsSkinningElementEditable(existing) then
            existing.applyPlacement(existing, saved, SUPPRESS_NOTIFICATION)
        end
        self:NotifySkinningElementBoundsChanged(definition.id)
        return existing
    end
    if not self:RegisterMovableElement(definition) then return nil end
    return self:GetSkinningElement(definition.id)
end

local SHARED_SKIN_ADAPTERS = {
    ACTION_BUTTON = function(self, skinMethod, target, style, borderColor,
        definition)
        local options = {}
        for key, value in pairs(definition.skinOptions or {}) do
            options[key] = value
        end
        options.style = style
        if options.border == nil then options.border = borderColor end
        skinMethod(self, target, options)
    end,
    CHECKBOX = function(self, skinMethod, target, style, borderColor, definition)
        local options = {}
        for key, value in pairs(definition.skinOptions or {}) do
            options[key] = value
        end
        options.style = style
        if options.border == nil then options.border = borderColor end
        if options.text == nil then options.text = definition.text end
        skinMethod(self, target, options)
    end,
    DROPDOWN = function(self, skinMethod, target, style, borderColor, definition)
        local options = {}
        for key, value in pairs(definition.skinOptions or {}) do
            options[key] = value
        end
        options.style = style
        if options.border == nil then options.border = borderColor end
        options.menus = definition.menus
        skinMethod(self, target, options)
    end,
    SEARCH_ACCESSORY = function(self, skinMethod, target, style, borderColor,
        definition)
        local options = {}
        for key, value in pairs(definition.skinOptions or {}) do
            options[key] = value
        end
        options.style = style
        if options.border == nil then options.border = borderColor end
        options.menus = definition.menus
        skinMethod(self, target, options)
    end,
    SCROLLBAR = function(self, skinMethod, target, style)
        skinMethod(self, target, style)
    end,
    SEARCH_GROUP = function(self, skinMethod, target, style, borderColor)
        skinMethod(self, target, style, borderColor)
    end,
    TEXT = function(self, skinMethod, target, style)
        skinMethod(self, target, style)
    end,
}

function NSkin:SkinTypedElement(typeID, definition)
    if type(definition) ~= "table" or not definition.target then return false end
    local typeDefinition = self:GetSharedElementType(typeID)
    local adapter = SHARED_SKIN_ADAPTERS[typeID]
    local skinMethod = typeDefinition and self[typeDefinition.skin]
    if not typeDefinition or not adapter or type(skinMethod) ~= "function" then
        return false
    end
    local style = self:GetAppearanceStyle(typeDefinition.style,
        definition.appearanceWindowID, definition.id)
    local borderColor = self:GetAppearanceBorderColor(
        typeDefinition.style, style, definition.appearanceWindowID, definition.id)
    if type(definition.skinAdapter) == "function" then
        definition.skinAdapter(self, definition.target, style, borderColor,
            definition)
    else
        adapter(self, skinMethod, definition.target, style, borderColor,
            definition)
    end
    return true
end

function NSkin:RegisterTypedElement(typeID, definition)
    if type(definition) ~= "table" or type(definition.id) ~= "string"
        or not definition.target
    then return nil end
    local typeDefinition = self:GetSharedElementType(typeID)
    if not typeDefinition or not self:SkinTypedElement(typeID, definition) then
        return nil
    end

    local element = {}
    for key, value in pairs(definition) do element[key] = value end
    element.kind = typeID
    if not element.editorOptions then
        element.editorOptions = self:CreateEditorOptionsPreset(
            typeDefinition.editorPreset or typeID,
            element.extraEditorOptions)
    end
    if element.preserveAnchorSpan == nil then
        element.preserveAnchorSpan = typeDefinition.preserveAnchorSpan
    end
    return self:RegisterSimpleMovableElement(element)
end

function NSkin:RegisterActionButton(definition)
    return self:RegisterTypedElement("ACTION_BUTTON", definition)
end

function NSkin:RegisterCheckbox(definition)
    return self:RegisterTypedElement("CHECKBOX", definition)
end

function NSkin:RegisterDropdown(definition)
    return self:RegisterTypedElement("DROPDOWN", definition)
end

function NSkin:RegisterScrollBar(definition)
    return self:RegisterTypedElement("SCROLLBAR", definition)
end

function NSkin:RegisterSearchBox(definition)
    return self:RegisterTypedElement("SEARCH_GROUP", definition)
end

function NSkin:RegisterTextElement(definition)
    return self:RegisterTypedElement("TEXT", definition)
end

function NSkin:RegisterSideTab(definition)
    if type(definition) ~= "table" or type(definition.id) ~= "string"
        or not definition.target
    then return nil end
    local id = definition.id
    self:CaptureComponentBaseline(id, definition.target, {
        points = true,
        size = true,
    })
    local data = self:GetSkinData(definition.target, COMPONENT_STATE)
    data.sideTabBaselineID = id
    local style = self:GetAppearanceStyle(
        "sideTab", definition.appearanceWindowID, id)
    local borderColor = self:GetAppearanceBorderColor(
        "sideTab", style, definition.appearanceWindowID, id)
    self:SkinSideTab(definition.target, style, borderColor)

    definition.kind = "SIDE_TAB"
    definition.supportsResize = true
    definition.restoreGeometry = definition.restoreGeometry or function(element)
        return NSkin:RestoreSideTabOriginalState(element.target, element.id)
    end
    definition.defaultPlacement = definition.defaultPlacement
        or GetCurrentWindowPlacement(definition.window, definition.target)
    if not definition.resetPlacement then
        definition.resetPlacement = function(element)
            local restored
            if element.defaultPlacement then
                restored = element.applyPlacement(element,
                    CopyPlacement(element.defaultPlacement), SUPPRESS_NOTIFICATION)
            else
                restored = NSkin:RestoreMovableElementOriginal(element, true)
            end
            if not restored then return false end
            ClearSavedMovablePlacement(element)
            NSkin:MarkComponentGeometryModified(element.id, "points", false)
            NSkin:NotifySkinningElementBoundsChanged(element.id)
            return true
        end
    end

    local element = self:RegisterSimpleMovableElement(definition)
    if element and not GetSavedMovablePlacement(element)
        and element.defaultPlacement
    then
        element.applyPlacement(element,
            CopyPlacement(element.defaultPlacement), SUPPRESS_NOTIFICATION)
    end
    return element
end

function NSkin:RegisterSideTabGroup(groupID, definition)
    if type(groupID) ~= "string" or groupID == ""
        or type(definition) ~= "table"
        or type(definition.targets) ~= "table"
        or #definition.targets == 0
        or not definition.window
    then return nil end

    local targets = definition.targets
    local primary = targets[1]
    if not primary then return nil end

    local baselineIDs = {}
    local style = self:GetAppearanceStyle(
        "sideTab", definition.appearanceWindowID, groupID)
    local borderColor = self:GetAppearanceBorderColor(
        "sideTab", style, definition.appearanceWindowID, groupID)
    for i = 1, #targets do
        local tab = targets[i]
        if tab then
            local baselineID = groupID .. ":tab:" .. i
            baselineIDs[i] = baselineID
            self:CaptureComponentBaseline(baselineID, tab, {
                points = true,
                size = true,
            })
            local data = self:GetSkinData(tab, COMPONENT_STATE)
            data.sideTabBaselineID = baselineID
            self:SkinSideTab(tab, style, borderColor)
        end
    end

    definition.id = groupID
    definition.target = primary
    definition.kind = "SIDE_TAB"
    definition.highlightRegions = definition.highlightRegions or targets
    definition.defaultPlacement = definition.defaultPlacement
        or GetCurrentWindowPlacement(definition.window, primary)

    definition.applyPlacement = function(element, placement, applyOptions)
        local window = element.window
        if not window or not window.GetLeft or not window.GetTop then return false end

        for i = 1, #targets do
            self:RestoreComponentBaseline(baselineIDs[i], { points = true })
        end
        local windowLeft, windowTop = window:GetLeft(), window:GetTop()
        local primaryLeft, primaryTop = primary:GetLeft(), primary:GetTop()
        if not windowLeft or not windowTop or not primaryLeft or not primaryTop then
            return false
        end

        local originalPositions = {}
        for i = 1, #targets do
            local tab = targets[i]
            local left, top = tab:GetLeft(), tab:GetTop()
            if not left or not top then return false end
            originalPositions[i] = {
                x = left - windowLeft,
                y = top - windowTop,
            }
        end

        if not self:LayoutWindowElement({
            id = element.id,
            window = window,
            target = primary,
        }, placement, SUPPRESS_NOTIFICATION) then
            return false
        end
        local desiredLeft, desiredTop = primary:GetLeft(), primary:GetTop()
        if not desiredLeft or not desiredTop then return false end
        local deltaX = desiredLeft - primaryLeft
        local deltaY = desiredTop - primaryTop

        for i = 1, #targets do
            local tab = targets[i]
            tab:ClearAllPoints()
            tab:SetPoint("TOPLEFT", window, "TOPLEFT",
                originalPositions[i].x + deltaX,
                originalPositions[i].y + deltaY)
            self:MarkComponentGeometryModified(
                baselineIDs[i], "points", true)
        end
        if not (applyOptions and applyOptions.suppressNotify) then
            self:NotifySkinningElementBoundsChanged(element.id)
        end
        return true
    end

    definition.restoreGeometry = function()
        local restored = true
        for i = 1, #targets do
            restored = self:RestoreComponentBaseline(
                baselineIDs[i], { points = true }) and restored
        end
        return restored
    end
    definition.resetPlacement = function(element)
        if not definition.restoreGeometry() then return false end
        ClearSavedMovablePlacement(element)
        self:MarkComponentGeometryModified(element.id, "points", false)
        self:NotifySkinningElementBoundsChanged(element.id)
        return true
    end

    return self:RegisterSimpleMovableElement(definition)
end

function NSkin:RegisterNavigationBar(elementID, definition)
    if type(elementID) ~= "string" or type(definition) ~= "table"
        or not definition.target
    then return nil end
    definition.id = elementID
    definition.kind = "NAVIGATION_BAR"
    local style = self:GetAppearanceStyle("navigationBar",
        definition.appearanceWindowID, elementID)
    self:SkinNavigationBar(definition.target, style)

    local data = self:GetSkinData(definition.target, COMPONENT_STATE)
    if not data.navigationBarShowHooked and definition.target.HookScript then
        definition.target:HookScript("OnShow", function(bar)
            NSkin:SkinNavigationBar(bar, NSkin:GetAppearanceStyle(
                "navigationBar", definition.appearanceWindowID, elementID))
        end)
        data.navigationBarShowHooked = true
    end
    return self:RegisterSimpleMovableElement(definition)
end

function NSkin:RegisterProgressBarElement(definition)
    if type(definition) ~= "table" then return nil end
    definition.kind = definition.kind or "PROGRESS_BAR"
    return self:RegisterSimpleMovableElement(definition)
end

local function GetControllerState(module, id, create)
    local options = NSkin:GetModuleOptions(module, create == true)
    if not options then return end
    if create and not options.componentStates then options.componentStates = {} end
    local states = options.componentStates
    if not states then return nil, options end
    if create and not states[id] then states[id] = {} end
    return states[id], options
end

local function PruneControllerState(module, options, id)
    local states = options and options.componentStates
    local state = states and states[id]
    if state and not next(state) then states[id] = nil end
    if states and not next(states) then options.componentStates = nil end
    if options and not next(options) then
        local profile = NSkin:GetProfile()
        if profile.moduleOptions then
            profile.moduleOptions[module] = nil
            if not next(profile.moduleOptions) then profile.moduleOptions = nil end
        end
    end
end

local function RegisterControllerElement(controller, id, label, target, options)
    if not id or not target then return end
    options = options or {}
    local elementDefinition = {
        id = id,
        module = controller.module,
        appearanceWindowID = controller.appearanceWindowID,
        label = label,
        kind = options.kind,
        window = controller.window,
        target = target,
        editorOptions = options.editorOptions,
        defaultPlacement = CopyPlacement(options.defaultPlacement
            or GetCurrentWindowPlacement(controller.window, target)),
        priority = options.priority,
        anchorHighlight = options.anchorHighlight,
        highlightRegions = options.highlightRegions,
        isEditable = options.isEditable,
        applyPlacement = options.applyPlacement,
        snapTarget = options.snapTarget,
        livePreview = options.livePreview,
        draggable = options.draggable,
        skinOptions = options.skinOptions,
        menus = options.menus,
    }
    if SHARED_SKIN_ADAPTERS[options.kind] then
        NSkin:RegisterTypedElement(options.kind, elementDefinition)
    else
        NSkin:RegisterMovableElement(elementDefinition)
    end
    return skinningElements[id]
end

function NSkin:RegisterPaginationGroup(definition)
    if type(definition) ~= "table" or type(definition.module) ~= "string"
        or type(definition.appearanceWindowID) ~= "string"
        or definition.appearanceWindowID == ""
        or not self:GetAppearanceScope(definition.appearanceWindowID)
        or not definition.window or type(definition.ids) ~= "table"
        or type(definition.controls) ~= "table"
    then return end
    local ids, controls = definition.ids, definition.controls
    if not ids.group or not ids.previous or not ids.next or not ids.text
        or not controls.group or not controls.previous or not controls.next
        or not controls.text
    then return end
    local controller = { module = definition.module,
        appearanceWindowID = definition.appearanceWindowID,
        window = definition.window,
        visibilityFrame = definition.visibilityFrame,
        id = definition.id or ids.group, ids = ids, controls = controls }
    local legacySeparateKey = definition.legacySeparateOptionKey
    local legacyTextKey = definition.legacyTextOptionKey

    function controller:GetSeparateButtons()
        local state, options = GetControllerState(self.module, self.id, false)
        if state and state.separateButtons ~= nil then return state.separateButtons == true end
        return legacySeparateKey and options and options[legacySeparateKey] == true or false
    end
    function controller:GetTextMode()
        local state, options = GetControllerState(self.module, self.id, false)
        local mode = state and state.textMode
        if not mode and legacyTextKey and options then mode = options[legacyTextKey] end
        mode = mode or "GROUPED"
        return mode == "GROUPED" and self:GetSeparateButtons() and "INDEPENDENT" or mode
    end
    function controller:IsVisible()
        local target = self.visibilityFrame or self.controls.group
        return not target or not target.IsVisible or target:IsVisible()
    end
    function controller:NotifyBounds()
        NSkin:NotifySkinningElementBoundsChanged(self.ids.group)
        NSkin:NotifySkinningElementBoundsChanged(self.ids.previous)
        NSkin:NotifySkinningElementBoundsChanged(self.ids.next)
        NSkin:NotifySkinningElementBoundsChanged(self.ids.text)
    end
    function controller:Refresh()
        self.controls.text:SetShown(self:GetTextMode() ~= "HIDDEN")
        local function ApplyMode(id, independent)
            local element = skinningElements[id]
            if not element then return end
            local saved = GetSavedMovablePlacement(element)
            if independent and saved then
                element.applyPlacement(element, saved, SUPPRESS_NOTIFICATION)
            elseif not independent then
                NSkin:RestoreMovableElementOriginal(element, true)
            end
        end
        local separate = self:GetSeparateButtons()
        ApplyMode(self.ids.previous, separate)
        ApplyMode(self.ids.next, separate)
        ApplyMode(self.ids.text, self:GetTextMode() == "INDEPENDENT")
        self:NotifyBounds()
    end
    function controller:UpdateWatcher()
        local state, options = GetControllerState(self.module, self.id, false)
        local active = state and next(state) ~= nil
        if not active and options then
            active = (legacySeparateKey and options[legacySeparateKey])
                or (legacyTextKey and options[legacyTextKey])
        end
        if active and not self.watcher then
            self.watcher = CreateFrame("Frame", nil,
                definition.visibilityFrame or self.controls.group)
            self.watcher:Hide()
            self.watcher:SetScript("OnShow", function() self:Refresh() end)
        end
        if self.watcher then self.watcher:SetShown(not not active) end
    end
    function controller:SetSeparateButtons(value)
        local textMode = value == true and "INDEPENDENT" or self:GetTextMode()
        local state, options = GetControllerState(self.module, self.id, true)
        state.separateButtons = value == true and true or nil
        state.textMode = textMode == "GROUPED" and nil or textMode
        if legacySeparateKey then options[legacySeparateKey] = nil end
        if legacyTextKey then options[legacyTextKey] = nil end
        PruneControllerState(self.module, options, self.id)
        self:UpdateWatcher()
        self:Refresh()
        return true
    end
    function controller:SetTextMode(mode)
        if mode ~= "GROUPED" and mode ~= "INDEPENDENT" and mode ~= "HIDDEN"
            or (mode == "GROUPED" and self:GetSeparateButtons())
        then return false end
        local state, options = GetControllerState(self.module, self.id, true)
        state.textMode = mode == "GROUPED" and nil or mode
        if legacyTextKey then options[legacyTextKey] = nil end
        PruneControllerState(self.module, options, self.id)
        self:UpdateWatcher()
        self:Refresh()
        return true
    end

    local elementDefinitions = definition.elements or {}
    local groupDefinition = elementDefinitions.group or {}
    local previousDefinition = elementDefinitions.previous or {}
    local nextDefinition = elementDefinitions.next or {}
    local textDefinition = elementDefinitions.text or {}
    controller.groupedRegions = { controls.previous, controls.next }
    controller.groupedRegionsWithText = { controls.previous, controls.text, controls.next }
    local groupEditorOptions = NSkin:CreateEditorOptionsPreset(
        "PAGINATION_GROUP", definition.extraEditorOptions)
    local defaultPlacement = definition.defaultPlacement
    local group = RegisterControllerElement(controller, ids.group,
        definition.groupLabel or "Pagination", controls.group, {
            kind = "PAGINATION_GROUP",
            editorOptions = groupEditorOptions,
            defaultPlacement = groupDefinition.defaultPlacement or defaultPlacement,
            priority = groupDefinition.priority or definition.groupPriority or 70,
            anchorHighlight = groupDefinition.anchorHighlight or definition.anchorHighlight,
            highlightRegions = function()
                return controller:GetTextMode() == "GROUPED"
                    and controller.groupedRegionsWithText or controller.groupedRegions
            end,
            applyPlacement = groupDefinition.applyPlacement,
            livePreview = groupDefinition.livePreview,
            draggable = groupDefinition.draggable,
            isEditable = function()
                return controller:IsVisible() and not controller:GetSeparateButtons()
            end,
        })
    local previous = RegisterControllerElement(controller, ids.previous,
        definition.previousLabel or "Previous page button", controls.previous, {
            kind = "PAGINATION_CHILD",
            editorOptions = NSkin:CreateEditorOptionsPreset(
                "PAGINATION_CHILD", definition.childExtraEditorOptions),
            defaultPlacement = previousDefinition.defaultPlacement
                or definition.previousPlacement or defaultPlacement,
            priority = previousDefinition.priority or definition.buttonPriority or 90,
            isEditable = function()
                return controller:IsVisible()
            end,
            applyPlacement = previousDefinition.applyPlacement,
            livePreview = previousDefinition.livePreview,
            draggable = previousDefinition.draggable,
        })
    local nextPage = RegisterControllerElement(controller, ids.next,
        definition.nextLabel or "Next page button", controls.next, {
            kind = "PAGINATION_CHILD",
            editorOptions = NSkin:CreateEditorOptionsPreset(
                "PAGINATION_CHILD", definition.childExtraEditorOptions),
            defaultPlacement = nextDefinition.defaultPlacement
                or definition.nextPlacement or defaultPlacement,
            priority = nextDefinition.priority or definition.buttonPriority or 90,
            isEditable = function()
                return controller:IsVisible()
            end,
            applyPlacement = nextDefinition.applyPlacement,
            livePreview = nextDefinition.livePreview,
            draggable = nextDefinition.draggable,
        })
    local text = RegisterControllerElement(controller, ids.text,
        definition.textLabel or "Page text", controls.text, {
            kind = "PAGINATION_CHILD",
            editorOptions = NSkin:CreateEditorOptionsPreset(
                "PAGINATION_CHILD", definition.childExtraEditorOptions),
            defaultPlacement = textDefinition.defaultPlacement
                or definition.textPlacement or defaultPlacement,
            priority = textDefinition.priority or definition.textPriority or 100,
            isEditable = function()
                return controller:IsVisible()
                    and controller:GetTextMode() == "INDEPENDENT"
            end,
            applyPlacement = textDefinition.applyPlacement,
            livePreview = textDefinition.livePreview,
            draggable = textDefinition.draggable,
        })
    for _, element in ipairs({ group, previous, nextPage, text }) do
        if element then
            element.getPaginationSeparateButtons = function() return controller:GetSeparateButtons() end
            element.setPaginationSeparateButtons = function(_, value)
                return controller:SetSeparateButtons(value)
            end
            element.getPaginationTextMode = function() return controller:GetTextMode() end
            element.setPaginationTextMode = function(_, mode)
                return controller:SetTextMode(mode)
            end
        end
    end
    for _, buttonElement in ipairs({ previous, nextPage }) do
        if buttonElement then
            local setPlacement = buttonElement.setPlacement
            buttonElement.setPlacement = function(element, placement)
                if not controller:GetSeparateButtons() then
                    controller:SetSeparateButtons(true)
                end
                return setPlacement(element, placement)
            end
        end
    end
    controller:UpdateWatcher()
    controller:Refresh()
    return controller
end

function NSkin:RegisterAccessoryGroup(definition)
    if type(definition) ~= "table" or type(definition.module) ~= "string"
        or type(definition.appearanceWindowID) ~= "string"
        or definition.appearanceWindowID == ""
        or not self:GetAppearanceScope(definition.appearanceWindowID)
        or not definition.window or not definition.primary or not definition.accessory
        or type(definition.ids) ~= "table" or not definition.ids.primary
        or not definition.ids.accessory or type(definition.anchorGrouped) ~= "function"
    then return end
    local controller = { module = definition.module,
        appearanceWindowID = definition.appearanceWindowID,
        window = definition.window,
        visibilityFrame = definition.visibilityFrame,
        id = definition.id or definition.ids.primary, ids = definition.ids,
        primary = definition.primary, accessory = definition.accessory }
    local legacyOptionKey = definition.legacyOptionKey
    function controller:GetMode()
        local state, options = GetControllerState(self.module, self.id, false)
        if state and state.mode then return state.mode end
        return legacyOptionKey and options and options[legacyOptionKey] or "GROUPED"
    end
    function controller:IsVisible()
        local target = self.visibilityFrame or self.primary:GetParent()
        return not target or not target.IsVisible or target:IsVisible()
    end
    function controller:AnchorGrouped()
        if definition.anchorGrouped(self.primary, self.accessory) ~= true then
            return false
        end
        -- Grouping replaces the accessory's Blizzard anchor. Track that
        -- mutation so placement and full-customization resets restore it
        -- before restoring the primary control that may anchor back to it.
        NSkin:MarkComponentGeometryModified(self.ids.accessory, "points", true)
        return true
    end
    function controller:ApplyPrimary(element, placement, applyOptions)
        if self:GetMode() == "GROUPED"
            and (placement.relativeTo == self.ids.accessory
                or placement.relativeTo == self.ids.primary)
        then
            placement = CopyPlacement(definition.primaryPlacement)
        end
        if not NSkin:LayoutWindowElement(element, placement, SUPPRESS_NOTIFICATION) then
            return false
        end
        if self:GetMode() == "GROUPED" then self:AnchorGrouped() end
        if not (applyOptions and applyOptions.suppressNotify) then
            NSkin:NotifySkinningElementBoundsChanged(element.id)
        end
        return true
    end
    function controller:NotifyBounds()
        NSkin:NotifySkinningElementBoundsChanged(self.ids.primary)
        NSkin:NotifySkinningElementBoundsChanged(self.ids.accessory)
    end
    function controller:Refresh()
        NSkin:SkinTypedElement("SEARCH_GROUP", {
            id = self.ids.primary,
            target = self.primary,
            appearanceWindowID = self.appearanceWindowID,
            skinOptions = self.primarySkinOptions,
        })
        NSkin:SkinTypedElement("SEARCH_ACCESSORY", {
            id = self.ids.accessory,
            target = self.accessory,
            appearanceWindowID = self.appearanceWindowID,
            skinOptions = self.accessorySkinOptions,
            menus = self.accessoryMenus,
        })
        local mode = self:GetMode()
        self.accessory:SetShown(mode ~= "HIDDEN")
        if mode == "GROUPED" then
            local primaryElement = skinningElements[self.ids.primary]
            local saved = primaryElement and GetSavedMovablePlacement(primaryElement)
            if saved then
                primaryElement.applyPlacement(primaryElement, saved, SUPPRESS_NOTIFICATION)
            else
                NSkin:RestoreMovableElementOriginal(self.ids.accessory, true)
                NSkin:RestoreMovableElementOriginal(self.ids.primary, true)
            end
        elseif mode == "INDEPENDENT" then
            local element = skinningElements[self.ids.accessory]
            local saved = element and GetSavedMovablePlacement(element)
            if saved then element.applyPlacement(element, saved, SUPPRESS_NOTIFICATION) end
        end
        self:NotifyBounds()
    end
    function controller:UpdateWatcher()
        local state, options = GetControllerState(self.module, self.id, false)
        local active = state and next(state) ~= nil
        if not active and legacyOptionKey and options then active = options[legacyOptionKey] end
        if active and not self.watcher then
            self.watcher = CreateFrame("Frame", nil,
                definition.visibilityFrame or self.primary:GetParent() or self.window)
            self.watcher:Hide()
            self.watcher:SetScript("OnShow", function() self:Refresh() end)
        end
        if self.watcher then self.watcher:SetShown(not not active) end
    end
    function controller:SetMode(mode)
        if mode ~= "GROUPED" and mode ~= "INDEPENDENT" and mode ~= "HIDDEN" then
            return false
        end
        local state, options = GetControllerState(self.module, self.id, true)
        state.mode = mode == "GROUPED" and nil or mode
        if legacyOptionKey then options[legacyOptionKey] = nil end
        PruneControllerState(self.module, options, self.id)
        self:UpdateWatcher()
        self:Refresh()
        return true
    end

    local elementDefinitions = definition.elements or {}
    local primaryDefinition = elementDefinitions.primary or {}
    local accessoryDefinition = elementDefinitions.accessory or {}
    controller.primarySkinOptions = primaryDefinition.skinOptions
        or definition.primarySkinOptions
    controller.accessorySkinOptions = accessoryDefinition.skinOptions
        or definition.accessorySkinOptions
    controller.accessoryMenus = accessoryDefinition.menus
        or definition.accessoryMenus
    controller.groupedHighlightRegions = { controller.primary, controller.accessory }
    controller.primaryHighlightRegion = { controller.primary }
    local primaryEditorOptions = NSkin:CreateEditorOptionsPreset(
        "SEARCH_GROUP", definition.extraEditorOptions)
    local accessoryEditorOptions = NSkin:CreateEditorOptionsPreset(
        "SEARCH_ACCESSORY", definition.accessoryExtraEditorOptions)
    local accessory = RegisterControllerElement(controller, definition.ids.accessory,
        definition.accessoryLabel or "Search accessory", definition.accessory, {
            kind = "SEARCH_ACCESSORY",
            editorOptions = accessoryEditorOptions,
            defaultPlacement = accessoryDefinition.defaultPlacement
                or definition.accessoryPlacement,
            priority = accessoryDefinition.priority or definition.accessoryPriority or 90,
            isEditable = function()
                return controller:IsVisible() and controller:GetMode() == "INDEPENDENT"
            end,
            applyPlacement = accessoryDefinition.applyPlacement,
            livePreview = accessoryDefinition.livePreview,
            draggable = accessoryDefinition.draggable,
            skinOptions = controller.accessorySkinOptions,
            menus = controller.accessoryMenus,
        })
    local primary = RegisterControllerElement(controller, definition.ids.primary,
        definition.primaryLabel or "Search", definition.primary, {
            kind = "SEARCH_GROUP",
            editorOptions = primaryEditorOptions,
            defaultPlacement = primaryDefinition.defaultPlacement or definition.primaryPlacement,
            priority = primaryDefinition.priority or definition.primaryPriority or 80,
            snapTarget = definition.snapTarget,
            isEditable = function() return controller:IsVisible() end,
            applyPlacement = function(element, placement, applyOptions)
                if primaryDefinition.applyPlacement then
                    if not primaryDefinition.applyPlacement(element, placement,
                        applyOptions)
                    then return false end
                    if controller:GetMode() == "GROUPED" then controller:AnchorGrouped() end
                    if not (applyOptions and applyOptions.suppressNotify) then
                        NSkin:NotifySkinningElementBoundsChanged(element.id)
                    end
                    return true
                end
                return controller:ApplyPrimary(element, placement, applyOptions)
            end,
            livePreview = primaryDefinition.livePreview,
            draggable = primaryDefinition.draggable,
            skinOptions = controller.primarySkinOptions,
            highlightRegions = function()
                return controller:GetMode() == "GROUPED"
                    and controller.groupedHighlightRegions
                    or controller.primaryHighlightRegion
            end,
        })
    for _, element in ipairs({ primary, accessory }) do
        if element then
            element.getSearchAccessoryMode = function() return controller:GetMode() end
            element.setSearchAccessoryMode = function(_, mode) return controller:SetMode(mode) end
        end
    end
    if primary then
        local resetPrimary = primary.resetPlacement
        primary.resetPlacement = function(element)
            NSkin:RestoreMovableElementOriginal(controller.ids.accessory, true)
            local reset = resetPrimary(element)
            controller:Refresh()
            return reset
        end
    end
    controller:UpdateWatcher()
    controller:Refresh()
    return controller
end

function NSkin:WouldCreateSkinningPlacementCycle(elementID, relativeTo)
    local visited = {}
    local current = relativeTo
    while current do
        if current == elementID or visited[current] then return true end
        visited[current] = true
        local element = skinningElements[current]
        if not element or type(element.getPlacement) ~= "function" then return false end
        local placement = element.getPlacement(element)
        current = placement and placement.relativeTo
    end
    return false
end

function NSkin:GetUIParentNormalizedBounds(region, left, right, bottom, top)
    if not region or not region.GetEffectiveScale or not UIParent
        or not UIParent.GetEffectiveScale
    then
        return
    end
    left = left or (region.GetLeft and region:GetLeft())
    right = right or (region.GetRight and region:GetRight())
    bottom = bottom or (region.GetBottom and region:GetBottom())
    top = top or (region.GetTop and region:GetTop())
    if not left or not right or not bottom or not top then return end
    local parentScale = UIParent:GetEffectiveScale()
    local regionScale = region:GetEffectiveScale()
    if not parentScale or parentScale == 0 or not regionScale then return end
    local scale = regionScale / parentScale
    return left * scale, right * scale, bottom * scale, top * scale
end

function NSkin:GetSkinningElementBounds(element)
    if not element then return end
    local regions = element.highlightRegions
    if type(regions) == "function" then regions = regions(element) end
    if type(regions) == "table" then
        local left, right, bottom, top
        for i = 1, #regions do
            local region = regions[i]
            if region and (not region.IsShown or region:IsShown()) then
                local regionLeft, regionRight, regionBottom, regionTop =
                    self:GetUIParentNormalizedBounds(region)
                if regionLeft then
                    left = not left and regionLeft or math.min(left, regionLeft)
                    right = not right and regionRight or math.max(right, regionRight)
                    bottom = not bottom and regionBottom or math.min(bottom, regionBottom)
                    top = not top and regionTop or math.max(top, regionTop)
                end
            end
        end
        if left then return left, right, bottom, top end
    end
    if type(element.getHighlightBounds) == "function" then
        local ok, left, right, bottom, top = pcall(element.getHighlightBounds, element)
        if ok and left and right and bottom and top then
            return self:GetUIParentNormalizedBounds(
                element.target or element.window, left, right, bottom, top
            )
        end
    end

    if element.kind == "TAB_GROUP" then
        local tabs = element.container and element.container.tabs or element.tabs
        local left, right, bottom, top
        if type(tabs) == "table" then
            for i = 1, #tabs do
                local tab = tabs[i]
                if tab and (not tab.IsShown or tab:IsShown()) then
                    local tabLeft, tabRight = tab:GetLeft(), tab:GetRight()
                    local tabBottom, tabTop = tab:GetBottom(), tab:GetTop()
                    if tabLeft and tabRight and tabBottom and tabTop then
                        tabLeft, tabRight, tabBottom, tabTop =
                            self:GetUIParentNormalizedBounds(
                                tab, tabLeft, tabRight, tabBottom, tabTop
                            )
                        left = not left and tabLeft or math.min(left, tabLeft)
                        right = not right and tabRight or math.max(right, tabRight)
                        bottom = not bottom and tabBottom or math.min(bottom, tabBottom)
                        top = not top and tabTop or math.max(top, tabTop)
                    end
                end
            end
        end
        if left then return left, right, bottom, top end
    end

    local target = element.target
    if not target or (target.IsShown and not target:IsShown()) then return end
    if not target.GetLeft then return end
    return self:GetUIParentNormalizedBounds(target)
end

function NSkin:NotifySkinningElementBoundsChanged(elementID)
    local element = skinningElements[elementID]
    if not element then return false end
    FireComponentCallback("SkinningElementBoundsChanged", element)
    return true
end

function NSkin:GetTabGroup(groupID)
    return tabGroups[groupID]
end

function NSkin:GetTabGroupPlacement(groupID)
    local group = tabGroups[groupID]
    if group and type(group.getPlacement) == "function" then
        return group.getPlacement(group)
    end
    return nil
end

function NSkin:SetTabGroupPlacement(groupID, placement)
    local group = tabGroups[groupID]
    if placement and placement.relativeTo
        and self:WouldCreateSkinningPlacementCycle(groupID, placement.relativeTo)
    then return false end
    if not group then return self:SetTabPlacement(placement) end
    if type(group.setPlacement) == "function" then
        return group.setPlacement(group, placement) == true
    end
    return self:SetTabPlacement(placement)
end

function NSkin:ResetTabGroupPlacement(groupID)
    local group = tabGroups[groupID]
    if not group then return self:ResetTabLayout() end
    if type(group.resetPlacement) == "function" then
        return group.resetPlacement(group) == true
    end
    return self:ResetTabLayout()
end

function NSkin:ForEachRegisteredTabGroup(callback)
    if type(callback) ~= "function" then return end
    for _, group in pairs(tabGroups) do callback(group) end
end

local function RestoreTabDimensions(group)
    local tabs = group and group.container and group.container.tabs
        or group and group.tabs
    if type(tabs) ~= "table" then return false end
    local restored = false
    for i = 1, #tabs do
        local tab = tabs[i]
        if tab then
            local baselineID = group.tabBaselineIDs and group.tabBaselineIDs[i]
            if baselineID and NSkin:RestoreComponentBaseline(
                baselineID, { size = true })
            then
                restored = true
            end
            local data = NSkin:GetSkinData(tab, COMPONENT_STATE, false)
            if data and data.tabOriginalSize then
                tab:SetSize(data.tabOriginalSize[1], data.tabOriginalSize[2])
                data.tabOriginalSize = nil
                restored = true
            end
        end
    end
    return restored
end

local function RestoreTabPoints(groupID)
    local group = tabGroups[groupID]
    local restored
    for i = 1, #(group and group.tabBaselineIDs or {}) do
        restored = NSkin:RestoreComponentBaseline(
            group.tabBaselineIDs[i], { points = true }) or restored
    end
    if group and group.groupBaselineID then
        restored = NSkin:RestoreComponentBaseline(
            group.groupBaselineID, { points = true, spacing = true }) or restored
    end
    if restored then return true end
    local originals = tabGroupOriginalPoints[groupID]
    if not originals then return false end
    for i = 1, #originals do
        local original = originals[i]
        if original.target and original.target.ClearAllPoints then
            original.target:ClearAllPoints()
            for pointIndex = 1, #original.points do
                original.target:SetPoint(unpack(original.points[pointIndex]))
            end
        end
    end
    return true
end

local function ApplyTabGeometryWithoutPlacement(group, tabStyle)
    local tabs = group.container and group.container.tabs or group.tabs
    local applied = false
    if type(tabs) == "table" then
        for i = 1, #tabs do
            local tab = tabs[i]
            if tab then
                local hasSize = tonumber(tabStyle and tabStyle.width)
                    or tonumber(tabStyle and tabStyle.height)
                local baselineID = group.tabBaselineIDs and group.tabBaselineIDs[i]
                if baselineID then
                    if hasSize then
                        NSkin:MarkComponentGeometryModified(
                            baselineID, "size", true)
                    else
                        NSkin:RestoreComponentBaseline(
                            baselineID, { size = true })
                    end
                end
                ApplyTabDimensions(tab, tabStyle,
                    NSkin:GetSkinData(tab, COMPONENT_STATE))
                applied = true
            end
        end
    end

    if group.container and group.container.MarkDirty then
        local spacing = tonumber(tabStyle and tabStyle.spacing)
        if spacing ~= nil then
            NSkin:MarkComponentGeometryModified(
                group.groupBaselineID, "spacing", true)
            group.container.spacing = spacing
            group.spacingOverrideApplied = true
        elseif group.spacingOverrideApplied then
            NSkin:RestoreComponentBaseline(
                group.groupBaselineID, { spacing = true })
            group.container.spacing = group.originalSpacing
            group.spacingOverrideApplied = nil
        end
        group.container:MarkDirty()
    else
        local spacing = tonumber(tabStyle and tabStyle.spacing)
        if spacing ~= nil then
            for i = 1, #(group.tabBaselineIDs or {}) do
                NSkin:MarkComponentGeometryModified(
                    group.tabBaselineIDs[i], "points", true)
            end
            if not group.spacingOverrideApplied then
                RestoreTabPoints(group.id)
            end
            NSkin:LayoutTabGroup(tabs, {
                spacing = spacing,
                orientation = group.orientation,
            })
            group.spacingOverrideApplied = true
        elseif group.spacingOverrideApplied then
            RestoreTabPoints(group.id)
            group.spacingOverrideApplied = nil
        end
    end
    return applied
end

function NSkin:ApplyTabGroupPlacement(group, placement, applyOptions)
    if not group or (_G.InCombatLockdown and _G.InCombatLockdown()) then return false end
    local options = group.layoutOptions
    if not options then
        options = {}
        group.layoutOptions = options
    end
    options.element = group
    options.owner = group.window
    options.edge = group.edge
    options.orientation = group.orientation
    local tabStyle = self:GetAppearanceStyle(
        "tab", group.appearanceWindowID, group.id)
    options.spacing = tonumber(tabStyle and tabStyle.spacing)
        or group.originalSpacing or 0
    options.placement = placement
    local applied
    if group.container and group.container.MarkDirty then
        applied = self:LayoutTabSystem(group.container, options) == true
    else
        applied = self:LayoutTabGroup(group.tabs, options) == true
    end
    if applied and group.groupBaselineID then
        self:MarkComponentGeometryModified(
            group.groupBaselineID, "points", group.container ~= nil)
        if tonumber(tabStyle and tabStyle.spacing) ~= nil then
            self:MarkComponentGeometryModified(
                group.groupBaselineID, "spacing", true)
        end
    end
    local tabs = group.container and group.container.tabs or group.tabs
    if applied and type(tabs) == "table" then
        for i = 1, #tabs do
            local tab = tabs[i]
            if tab then
                local baselineID = group.tabBaselineIDs and group.tabBaselineIDs[i]
                if baselineID then
                    NSkin:MarkComponentGeometryModified(
                        baselineID, "points", true)
                    if tonumber(tabStyle and tabStyle.width)
                        or tonumber(tabStyle and tabStyle.height)
                    then
                        NSkin:MarkComponentGeometryModified(
                            baselineID, "size", true)
                    end
                end
                ApplyTabDimensions(tab, tabStyle,
                    self:GetSkinData(tab, COMPONENT_STATE))
            end
        end
    end
    if applied and not (applyOptions and applyOptions.suppressNotify) then
        FireComponentCallback("TabGroupLayoutApplied", group)
    end
    return applied
end

function NSkin:ApplyTabGroupLayout(groupID)
    local group = tabGroups[groupID]
    if not group or (_G.InCombatLockdown and _G.InCombatLockdown()) then return false end
    if type(group.hasPlacement) == "function" and not group.hasPlacement(group) then
        local tabStyle = self:GetAppearanceStyle(
            "tab", group.appearanceWindowID, group.id)
        local applied = ApplyTabGeometryWithoutPlacement(group, tabStyle)
        if applied then FireComponentCallback("TabGroupLayoutApplied", group) end
        return applied
    end
    local placement = self:GetTabGroupPlacement(groupID)
    if type(group.applyPlacement) == "function" then
        local applied = group.applyPlacement(group, placement, { suppressNotify = true }) == true
        if applied then FireComponentCallback("TabGroupLayoutApplied", group) end
        return applied
    end
    return self:ApplyTabGroupPlacement(group, placement)
end

function NSkin:RefreshRegisteredTabGroups()
    if _G.InCombatLockdown and _G.InCombatLockdown() then return false end
    for groupID in pairs(tabGroups) do
        self:ApplyTabGroupLayout(groupID)
    end
    return true
end

function NSkin:RestoreTabGroupOriginalPlacement(groupID)
    local group = tabGroups[groupID]
    if not group then return false end
    local refreshed
    if type(group.refreshBlizzardLayout) == "function" then
        refreshed = group.refreshBlizzardLayout(group) == true
    end
    if refreshed then
        for i = 1, #(group.tabBaselineIDs or {}) do
            local baseline = self:GetComponentBaseline(group.tabBaselineIDs[i])
            if baseline then wipe(baseline.modified) end
        end
        local baseline = self:GetComponentBaseline(group.groupBaselineID)
        if baseline then wipe(baseline.modified) end
        self:RefreshTabGroupBaseline(groupID, true)
    elseif not RestoreTabPoints(groupID) then
        return false
    end
    if group then
        RestoreTabDimensions(group)
        group.spacingOverrideApplied = nil
        if group.container and group.container.MarkDirty then
            if group.originalSpacing ~= nil then
                group.container.spacing = group.originalSpacing
            end
            group.container:MarkDirty()
        end
    end
    return true
end
