local _, OU = ...

local P = {}
OU.UIPrimitives = P

P.MARGIN = 14
P.GREY = { 0.62, 0.62, 0.62 }
P.DIM = { 0.50, 0.50, 0.50 }
P.COLORS = {
    gold = { 1.00, 0.78, 0.20 },
    blue = { 0.35, 0.66, 0.92 },
    green = { 0.35, 0.90, 0.42 },
    amber = { 1.00, 0.68, 0.20 },
    red = { 0.88, 0.35, 0.35 },
    grey = { 0.62, 0.62, 0.62 },
}

P.assets = {
    panelBg = { kind = "file", path = "Interface\\FrameGeneral\\UI-Background-Rock", ok = nil },
    logo = { kind = "file", path = "Interface\\AddOns\\OlympusUnited\\Media\\OlympusLogo", ok = nil },
}

function P.CheckAssets(parent)
    parent = parent or UIParent
    for _, entry in pairs(P.assets) do
        if entry.kind == "file" then
            local probe = parent:CreateTexture(nil, "BACKGROUND")
            entry.ok = probe:SetTexture(entry.path) and true or false
            probe:Hide()
        elseif entry.kind == "atlas" then
            entry.ok = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(entry.name) ~= nil
        end
    end
end

function P.Label(parent, font, text, color)
    local label = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
    label:SetJustifyH("LEFT")
    if text then label:SetText(text) end
    if color then label:SetTextColor(color[1], color[2], color[3]) end
    return label
end

function P.Panel(frame, titleText)
    if NineSliceUtil and NineSliceUtil.ApplyLayoutByName then
        NineSliceUtil.ApplyLayoutByName(frame, "ButtonFrameTemplateNoPortrait")
    end
    if P.assets.panelBg.ok == nil then P.CheckAssets(frame) end
    local fill = frame:CreateTexture(nil, "BACKGROUND", nil, -1)
    fill:SetPoint("TOPLEFT", frame, "TOPLEFT", 6, -21)
    fill:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, 2)
    if P.assets.panelBg.ok and fill:SetTexture(P.assets.panelBg.path, "REPEAT", "REPEAT") then
        fill:SetHorizTile(true)
        fill:SetVertTile(true)
    else
        fill:SetColorTexture(0.06, 0.06, 0.07, 0.95)
    end
    local shade = frame:CreateTexture(nil, "BACKGROUND", nil, 0)
    shade:SetPoint("TOPLEFT", fill, "TOPLEFT", 0, 0)
    shade:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT", 0, 0)
    shade:SetColorTexture(0, 0, 0, 0.18)
    local title = P.Label(frame, "GameFontNormal", titleText)
    title:SetPoint("TOP", frame, "TOP", 0, -6)
    frame.ouTitle = title
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButtonDefaultAnchors")
    close:SetScript("OnClick", function() frame:Hide() end)
    frame.ouClose = close
    return frame
end

function P.Tip(widget, title, ...)
    local lines = { ... }
    widget:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(title, 1, 1, 1)
        for _, line in ipairs(lines) do GameTooltip:AddLine(line, 0.85, 0.85, 0.85, true) end
        GameTooltip:Show()
    end)
    widget:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

function P.Button(parent, text, width, height, onClick)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width or 100, height or 22)
    button:SetText(text or "")
    if onClick then button:SetScript("OnClick", onClick) end
    return button
end

function P.Checkbox(parent, text, onClick)
    local checkbox = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    checkbox:SetSize(26, 26)
    if not checkbox.Text then checkbox.Text = P.Label(checkbox, "GameFontHighlightSmall") end
    checkbox.Text:ClearAllPoints()
    checkbox.Text:SetPoint("LEFT", checkbox, "RIGHT", 2, 0)
    checkbox.Text:SetText(text or "")
    if onClick then checkbox:SetScript("OnClick", onClick) end
    return checkbox
end

function P.Divider(parent, y, inset)
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", parent, "TOPLEFT", inset or P.MARGIN, y)
    line:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -(inset or P.MARGIN), y)
    line:SetColorTexture(1, 1, 1, 0.12)
    return line
end

function P.ScrollWell(parent)
    local well = parent:CreateTexture(nil, "BACKGROUND", nil, 1)
    well:SetColorTexture(0, 0, 0, 0.25)
    local scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(640, 1)
    scroll:SetScrollChild(child)
    return well, scroll, child
end
