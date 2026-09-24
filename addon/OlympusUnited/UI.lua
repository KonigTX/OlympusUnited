local _, OU = ...
local L, P = OU.L, OU.UIPrimitives
local unpack = unpack or table.unpack

local UI = { activeTab = "FEED", tabs = {}, rows = {}, expandedGuild = nil }
OU.UI = UI

local VIEW_LABELS = {
    FEED = L.VIEW_UPDATES,
    LAYERS = L.VIEW_LAYERS,
    EVENTS = L.VIEW_EVENTS,
    CENSUS = L.VIEW_CENSUS,
    MEMBERS = L.VIEW_PEOPLE,
}

local TAB_COPY = {
    FEED = { prompt = L.UPDATE_PROMPT, button = L.UPDATE_BUTTON },
    LAYERS = { prompt = L.LAYER_PROMPT, button = L.LAYER_BUTTON },
    EVENTS = { prompt = L.EVENT_PROMPT, button = L.EVENT_BUTTON },
    MEMBERS = { prompt = L.CONNECTOR_PROMPT, button = L.CONNECTOR_BUTTON },
}

local function SetColor(label, color)
    label:SetTextColor(color[1], color[2], color[3])
end

local function HideMemberLabels(row)
    for _, label in ipairs(row.memberLabels) do label:Hide() end
end

local function ResetRow(row)
    row:Hide()
    row.action:Hide()
    row.secondaryAction:Hide()
    row.action:SetScript("OnClick", nil)
    row.secondaryAction:SetScript("OnClick", nil)
    row:SetScript("OnMouseDown", nil)
    row.heading:SetText("")
    row.body:SetText("")
    row.meta:SetText("")
    row.count:SetText("")
    row.detail:SetText("")
    row.hint:SetText("")
    row.detail:Hide()
    row.hint:Hide()
    row.chevron:Hide()
    HideMemberLabels(row)
    row.heading:ClearAllPoints()
    row.heading:SetPoint("TOPLEFT", row, "TOPLEFT", 10, -7)
    row.heading:SetPoint("RIGHT", row, "RIGHT", -220, 0)
    row.body:ClearAllPoints()
    row.body:SetPoint("TOPLEFT", row.heading, "BOTTOMLEFT", 0, -4)
    row.body:SetPoint("RIGHT", row, "RIGHT", -140, 0)
    row.meta:ClearAllPoints()
    row.meta:SetPoint("TOPRIGHT", row, "TOPRIGHT", -8, -29)
    row.meta:SetJustifyH("RIGHT")
    row.count:ClearAllPoints()
    row.count:SetPoint("TOPRIGHT", row, "TOPRIGHT", -8, -8)
    row.action:ClearAllPoints()
    row.action:SetPoint("TOPLEFT", row, "TOPLEFT", 24, -98)
    row.action:SetEnabled(true)
    row.secondaryAction:ClearAllPoints()
    row.secondaryAction:SetEnabled(true)
    local bodyFont = row.body.ouDefaultFont
    if bodyFont then row.body:SetFont(bodyFont[1], bodyFont[2], bodyFont[3]) end
    SetColor(row.body, { 0.90, 0.90, 0.90 })
    SetColor(row.meta, P.GREY)
    SetColor(row.count, { 0.90, 0.90, 0.90 })
end

local function GetRow(index)
    local row = UI.rows[index]
    if row then return row end
    row = CreateFrame("Frame", nil, UI.content)
    row:SetHeight(54)
    row:SetPoint("LEFT", UI.content, "LEFT", 0, 0)
    row:SetPoint("RIGHT", UI.content, "RIGHT", 0, 0)
    row:EnableMouse(true)
    row.shade = row:CreateTexture(nil, "BACKGROUND")
    row.shade:SetAllPoints(row)
    row.shade:SetColorTexture(index % 2 == 0 and 1 or 0, 1, 1, index % 2 == 0 and 0.025 or 0)
    row.divider = row:CreateTexture(nil, "ARTWORK")
    row.divider:SetHeight(1)
    row.divider:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
    row.divider:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
    row.divider:SetColorTexture(1, 1, 1, 0.08)
    row.chevron = P.Label(row, "GameFontHighlightSmall")
    row.chevron:SetPoint("TOPLEFT", row, "TOPLEFT", 4, -8)
    row.heading = P.Label(row, "GameFontNormal")
    row.heading:SetPoint("TOPLEFT", row, "TOPLEFT", 10, -7)
    row.heading:SetPoint("RIGHT", row, "RIGHT", -220, 0)
    row.body = P.Label(row, "GameFontHighlightSmall", nil, P.GREY)
    do local path, size, flags = row.body:GetFont(); row.body.ouDefaultFont = { path, size, flags } end
    row.body:SetPoint("TOPLEFT", row.heading, "BOTTOMLEFT", 0, -4)
    row.body:SetPoint("RIGHT", row, "RIGHT", -140, 0)
    row.body:SetWordWrap(true)
    row.meta = P.Label(row, "GameFontHighlightSmall", nil, P.GREY)
    row.meta:SetPoint("TOPRIGHT", row, "TOPRIGHT", -8, -29)
    row.meta:SetJustifyH("RIGHT")
    row.count = P.Label(row, "GameFontHighlightSmall")
    row.count:SetPoint("TOPRIGHT", row, "TOPRIGHT", -8, -8)
    row.count:SetJustifyH("RIGHT")
    row.detail = P.Label(row, "GameFontHighlightSmall", nil, P.GREY)
    row.detail:SetPoint("TOPLEFT", row, "TOPLEFT", 24, -54)
    row.detail:SetPoint("RIGHT", row, "RIGHT", -12, 0)
    row.detail:SetWordWrap(true)
    row.hint = P.Label(row, "GameFontHighlightSmall", nil, P.DIM)
    row.hint:SetPoint("TOPLEFT", row, "TOPLEFT", 24, -76)
    row.hint:SetPoint("RIGHT", row, "RIGHT", -12, 0)
    row.hint:SetWordWrap(true)
    row.action = P.Button(row, L.BUTTON_INVITE, 150, 22)
    row.action:SetPoint("TOPLEFT", row, "TOPLEFT", 24, -98)
    row.secondaryAction = P.Button(row, L.BUTTON_DENY_GUILD, 100, 22)
    row.secondaryAction:SetPoint("RIGHT", row.action, "LEFT", -8, 0)
    row.memberLabels = {}
    UI.rows[index] = row
    return row
end

local function MemberLabel(row, index)
    local label = row.memberLabels[index]
    if label then return label end
    label = P.Label(row, "GameFontHighlightSmall")
    label:SetPoint("TOPLEFT", row, "TOPLEFT", 32, -(126 + (index - 1) * 20))
    label:SetPoint("RIGHT", row, "RIGHT", -16, 0)
    row.memberLabels[index] = label
    return label
end

local function PrepareRows()
    for _, row in ipairs(UI.rows) do ResetRow(row) end
end

local function PlaceRow(row, top, height)
    row:SetHeight(height)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", UI.content, "TOPLEFT", 0, -top)
    row:SetPoint("RIGHT", UI.content, "RIGHT", 0, 0)
    row:Show()
    return top + height
end

local function ShowEmpty(title, help, actionText, onClick)
    local row = GetRow(1)
    row.heading:SetText(title)
    SetColor(row.heading, P.GREY)
    row.body:SetText(help or "")
    if actionText then
        row.action:SetText(actionText)
        row.action:SetPoint("TOPLEFT", row, "TOPLEFT", 10, -58)
        row.action:SetScript("OnClick", onClick)
        P.Tip(row.action, actionText, actionText == L.BUTTON_RETRY_ROSTER and L.TIP_RETRY_ROSTER or L.TIP_COMPOSE)
        row.action:Show()
        return PlaceRow(row, 0, 88)
    end
    return PlaceRow(row, 0, 66)
end

local function FeedRows()
    if not OU.Identity or OU.Identity.role ~= "member" then
        return ShowEmpty(L.CHAT_LOCKED, L.CHAT_LOCKED_HELP)
    end
    if #OU.Runtime.feed == 0 then return ShowEmpty(L.UPDATES_EMPTY, L.UPDATES_EMPTY_HELP) end
    local top = 0
    for index, item in ipairs(OU.Runtime.feed) do
        local row = GetRow(index)
        row.heading:SetText(OU.Util.ShortName(item.sender))
        SetColor(row.heading, P.COLORS.gold)
        row.body:SetText(item.text)
        row.meta:SetText(OU.Util.FormatAge(OU.Util.Now() - item.receivedAt))
        top = PlaceRow(row, top, 56)
    end
    return top
end

local function SaveChatDelay()
    if not UI.chatDelayInput then return end
    local ok, delay, changed = OU.State.SetChatDelay(OU.DB, UI.chatDelayInput:GetText())
    UI.chatDelayInput:SetText(tostring(delay))
    if not ok then
        OU.Print(L.CHAT_DELAY_RANGE)
    elseif changed then
        OU.Print(L.CHAT_DELAY_SET:format(delay))
    end
    OU.RefreshUI()
end

local function LayerRows()
    local requests = OU.Util.SortedValues(OU.Runtime.layers, function(a, b) return (a.createdAt or 0) > (b.createdAt or 0) end)
    if #requests == 0 then return ShowEmpty(L.LAYERS_EMPTY, L.LAYERS_EMPTY_HELP) end
    local top = 0
    for index, item in ipairs(requests) do
        local row = GetRow(index)
        row.heading:SetText(L.LAYER_WANTED:format(OU.Util.ShortName(item.sender)))
        SetColor(row.heading, P.COLORS.blue)
        row.body:SetText((item.zone ~= "" and item.zone or L.ZONE_UNKNOWN) .. (item.note ~= "" and ("  —  " .. item.note) or ""))
        row.meta:SetText(OU.Util.FormatAge(OU.Util.Now() - item.createdAt))
        if OU.Util.NormalizeName(item.sender) ~= OU.Util.NormalizeName(OU.Identity.name) then
            row.action:SetText(L.BUTTON_INVITE)
            row.action:SetPoint("TOPRIGHT", row, "TOPRIGHT", -8, -29)
            row.action:SetSize(100, 22)
            row.action:SetScript("OnClick", function() OU.Result(OU.Network.OfferLayer(item.id, L.LAYER_INVITE_NOTE)) end)
            P.Tip(row.action, L.BUTTON_INVITE, L.TIP_INVITE)
            row.action:Show()
        end
        top = PlaceRow(row, top, 62)
    end
    return top
end

local function EventRows()
    local events = OU.Util.SortedValues(OU.Runtime.events, function(a, b) return (a.startsAt or 0) < (b.startsAt or 0) end)
    if #events == 0 then return ShowEmpty(L.EVENTS_EMPTY, L.EVENTS_EMPTY_HELP) end
    local top = 0
    for index, item in ipairs(events) do
        local row = GetRow(index)
        row.heading:SetText(item.title)
        SetColor(row.heading, P.COLORS.gold)
        row.body:SetText(item.details ~= "" and item.details or L.EVENT_POSTED_BY:format(OU.Util.ShortName(item.sender)))
        row.meta:SetText(OU.Util.FormatStart(item.startsAt))
        top = PlaceRow(row, top, 58)
    end
    return top
end

local function GuildDecisionError(reason)
    if reason == "unavailable" then OU.Print(L.GUILD_AUTHORITY_UNAVAILABLE)
    elseif reason == "not_authorized" then OU.Print(L.GUILD_AUTHORITY_DENIED)
    elseif reason == "allowlist-capacity" then OU.Print(L.GUILD_ALLOWLIST_FULL)
    elseif reason == "missing-candidate" then OU.Print(L.GUILD_CANDIDATE_MISSING)
    else OU.Print(L.GUILD_DECISION_INVALID) end
end

local function PeopleRows()
    local peers = OU.Util.SortedValues(OU.Runtime.peers, function(a, b)
        if a.role ~= b.role then return a.role == "member" end
        return tostring(a.name) < tostring(b.name)
    end)
    local top, rowIndex = 0, 1
    local network = GetRow(rowIndex)
    network.heading:SetText(L.LINK_TITLE)
    SetColor(network.heading, P.COLORS.gold)
    network.body:SetText(L.LINK_HELP)
    local linkCount = OU.Util.Count(OU.DB.bridges)
    network.meta:SetText((OU.DB.bridgeMode and L.LINK_STATUS_ON or L.LINK_STATUS_OFF):format(linkCount))
    network.action:SetText(OU.DB.bridgeMode and L.BUTTON_STOP_LINKING or L.BUTTON_START_LINKING)
    network.action:SetPoint("BOTTOMRIGHT", network, "BOTTOMRIGHT", -8, 7)
    network.action:SetScript("OnClick", function()
        OU.Network.SetBridgeMode(not OU.DB.bridgeMode)
        OU.Print(OU.DB.bridgeMode and L.LINKING_ON or L.LINKING_OFF)
        OU.RefreshUI()
    end)
    P.Tip(network.action, network.action:GetText(), L.TIP_LINKING)
    network.action:Show()
    top = PlaceRow(network, top, 74)
    rowIndex = rowIndex + 1
    local bridges = OU.Util.SortedValues(OU.DB.bridges, function(a, b) return tostring(a) < tostring(b) end)
    for _, displayName in ipairs(bridges) do
        local row = GetRow(rowIndex)
        row.heading:SetText(L.CONNECTOR_TITLE)
        SetColor(row.heading, P.COLORS.blue)
        row.body:SetText(displayName)
        row.meta:SetText(L.CONNECTOR_HELP)
        row.action:SetText(L.BUTTON_REMOVE)
        row.action:SetSize(100, 22)
        row.action:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -8, 7)
        row.action:SetScript("OnClick", function()
            local ok, err = OU.Network.RemoveBridge(displayName)
            OU.Result(ok, err, ok and L.CONNECTOR_REMOVED:format(displayName) or nil)
            OU.RefreshUI()
        end)
        P.Tip(row.action, L.BUTTON_REMOVE, L.TIP_REMOVE_CONNECTOR)
        row.action:Show()
        top = PlaceRow(row, top, 58)
        rowIndex = rowIndex + 1
    end
    local authority = OU.GuildTrust and OU.GuildTrust.RefreshAuthority() or "unavailable"
    if authority == "authorized" then
        local section = GetRow(rowIndex)
        section.heading:SetText(L.GUILD_REVIEW_TITLE)
        SetColor(section.heading, P.COLORS.gold)
        section.body:SetText(L.GUILD_REVIEW_HELP)
        top = PlaceRow(section, top, 66)
        rowIndex = rowIndex + 1

        local records = OU.GuildTrust.Records(OU.DB)
        for _, item in ipairs(records) do
            if item.record.state == "pending" then
                local record, name = item.record, item.record.displayName
                local row = GetRow(rowIndex)
                row.heading:SetText(name)
                SetColor(row.heading, P.COLORS.amber)
                row.body:SetText(L.GUILD_STATE_PENDING)
                row.meta:SetText(L.GUILD_CANDIDATE_UNTRUSTED)
                row.action:SetText(L.BUTTON_APPROVE_GUILD)
                row.action:SetSize(100, 22)
                row.action:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -8, 7)
                row.action:SetScript("OnClick", function()
                    local wasLocalParticipant = OU.Identity and OU.Util.IsParticipatingGuild(OU.Identity.guild) or false
                    local ok, decision, changed = OU.GuildTrust.Decide("approve", name, OU.Util.Now(), OU.DB)
                    if ok then
                        OU.Network.SendGuildDecision(decision)
                        OU.Network.OnGuildTrustChanged(wasLocalParticipant, OU.Util.Now())
                        OU.Print(L.GUILD_DECISION_APPLIED:format(changed.displayName, L.GUILD_STATE_APPROVED))
                    else GuildDecisionError(decision) end
                    OU.RefreshUI()
                end)
                P.Tip(row.action, L.BUTTON_APPROVE_GUILD, L.TIP_GUILD_REVIEW)
                row.action:Show()
                row.secondaryAction:SetText(L.BUTTON_DENY_GUILD)
                row.secondaryAction:SetSize(100, 22)
                row.secondaryAction:SetPoint("RIGHT", row.action, "LEFT", -8, 0)
                row.secondaryAction:SetScript("OnClick", function()
                    local wasLocalParticipant = OU.Identity and OU.Util.IsParticipatingGuild(OU.Identity.guild) or false
                    local ok, decision, changed = OU.GuildTrust.Decide("deny", name, OU.Util.Now(), OU.DB)
                    if ok then
                        OU.Network.SendGuildDecision(decision)
                        OU.Network.OnGuildTrustChanged(wasLocalParticipant, OU.Util.Now())
                        OU.Print(L.GUILD_DECISION_APPLIED:format(changed.displayName, L.GUILD_STATE_DENIED))
                    else GuildDecisionError(decision) end
                    OU.RefreshUI()
                end)
                P.Tip(row.secondaryAction, L.BUTTON_DENY_GUILD, L.TIP_GUILD_REVIEW)
                row.secondaryAction:Show()
                top = PlaceRow(row, top, 62)
                rowIndex = rowIndex + 1
            end
        end
    end

    local trustSection = GetRow(rowIndex)
    trustSection.heading:SetText(L.GUILD_TRUST_TITLE)
    SetColor(trustSection.heading, P.COLORS.gold)
    trustSection.body:SetText(L.GUILD_TRUST_HELP)
    top = PlaceRow(trustSection, top, 66)
    rowIndex = rowIndex + 1
    local rootRow = GetRow(rowIndex)
    rootRow.heading:SetText(OU.GuildTrust and OU.GuildTrust.ROOT_DISPLAY or "OLYMPUS")
    SetColor(rootRow.heading, P.COLORS.green)
    rootRow.body:SetText(L.GUILD_STATE_APPROVED)
    rootRow.meta:SetText(L.GUILD_TRUST_SOURCE_LOCAL)
    top = PlaceRow(rootRow, top, 54)
    rowIndex = rowIndex + 1
    if OU.GuildTrust then
        for _, item in ipairs(OU.GuildTrust.Records(OU.DB)) do
            local record, name = item.record, item.record.displayName
            if record.state == "approved" or (authority == "authorized" and record.state ~= "pending") then
                local row = GetRow(rowIndex)
                row.heading:SetText(name)
                SetColor(row.heading, record.state == "approved" and P.COLORS.green or P.COLORS.amber)
                row.body:SetText(L["GUILD_STATE_" .. record.state:upper()] or record.state)
                row.meta:SetText(record.sourceClass == "configured-connector"
                    and L.GUILD_TRUST_SOURCE_CONNECTOR or L.GUILD_TRUST_SOURCE_LOCAL)
                if authority == "authorized" then
                    row.action:SetText(L.BUTTON_RECONSIDER_GUILD)
                    row.action:SetSize(110, 22)
                    row.action:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -8, 7)
                    row.action:SetScript("OnClick", function()
                        local wasLocalParticipant = OU.Identity and OU.Util.IsParticipatingGuild(OU.Identity.guild) or false
                        local ok, decision, changed = OU.GuildTrust.Decide("review", name, OU.Util.Now(), OU.DB)
                        if ok then
                            OU.Network.SendGuildDecision(decision)
                            OU.Network.OnGuildTrustChanged(wasLocalParticipant, OU.Util.Now())
                            OU.Print(L.GUILD_DECISION_APPLIED:format(changed.displayName, L.GUILD_STATE_PENDING))
                        else GuildDecisionError(decision) end
                        OU.RefreshUI()
                    end)
                    P.Tip(row.action, L.BUTTON_RECONSIDER_GUILD, L.TIP_GUILD_RECONSIDER)
                    row.action:Show()
                end
                top = PlaceRow(row, top, 60)
                rowIndex = rowIndex + 1
            end
        end
    end
    if #peers == 0 then
        local row = GetRow(rowIndex)
        row.heading:SetText(L.PEOPLE_EMPTY)
        SetColor(row.heading, P.GREY)
        row.body:SetText(L.PEOPLE_EMPTY_HELP)
        return PlaceRow(row, top, 66)
    end
    for _, peer in ipairs(peers) do
        local row = GetRow(rowIndex)
        row.heading:SetText(OU.Util.ShortName(peer.name))
        SetColor(row.heading, peer.role == "member" and P.COLORS.gold or P.COLORS.blue)
        local guild = peer.guild ~= "" and ("<" .. peer.guild .. ">") or L.GUILD_UNKNOWN
        row.body:SetText(guild .. (peer.zone ~= "" and ("  •  " .. peer.zone) or ""))
        local role = peer.role == "member" and L.PERSON_OLYMPUS or L.PERSON_GUEST
        local age = OU.Util.FormatAge(OU.Util.Now() - (peer.lastSeen or 0))
        row.meta:SetText(age == "just now" and L.SEEN_JUST_NOW:format(role) or L.SEEN_AGO:format(role, age))
        top = PlaceRow(row, top, 56)
        rowIndex = rowIndex + 1
    end
    return top
end

local function AssemblyForGuild(guildKey, snapshotId)
    local best, changed
    for _, assembly in pairs(OU.Runtime.census.assemblies) do
        if assembly.guildKey == guildKey then
            if assembly.snapshotId == snapshotId then
                if not best or (assembly.startedAt or 0) > (best.startedAt or 0) then best = assembly end
            else
                changed = true
            end
        end
    end
    return best, changed
end

local function StateColor(state)
    if state == "fresh" then return P.COLORS.green end
    if state == "stale" then return P.COLORS.amber end
    if state == "expired" then return P.COLORS.red end
    return P.COLORS.grey
end

local function CensusHeader(row, totals)
    row.heading:SetText(L.CENSUS_NETWORK)
    SetColor(row.heading, P.GREY)
    local contributing = totals.current + totals.stale
    row.body:SetText(contributing > 0 and L.CENSUS_MEMBERS:format(totals.members) or L.CENSUS_NO_CURRENT)
    SetColor(row.body, P.COLORS.gold)
    local path, _, flags = row.body:GetFont()
    if path then row.body:SetFont(path, 22, flags) end
    row.body:SetPoint("TOPLEFT", row, "TOPLEFT", 10, -27)
    row.count:SetText(contributing > 0 and totals.onlineKnown and L.CENSUS_ONLINE:format(totals.online) or L.CENSUS_ONLINE_UNKNOWN)
    row.count:SetPoint("TOPRIGHT", row, "TOPRIGHT", -8, -31)
    local reportText = L.CENSUS_CURRENT:format(totals.current + totals.stale)
    if totals.stale > 0 then reportText = reportText .. " • " .. L.CENSUS_STALE_COUNT:format(totals.stale) end
    row.meta:SetText(totals.current + totals.stale == 0 and L.CENSUS_NO_CURRENT_HELP or reportText)
    row.meta:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 10, 8)
    row.meta:SetJustifyH("LEFT")
end

local function ExpandedCensus(row, entry, summary, state, age, now)
    row.detail:SetText(L.CENSUS_SOURCE:format(OU.Util.ShortName(summary.reporter), OU.Util.FormatAge(age)))
    row.detail:Show()
    row.hint:SetText(state == "stale" and L.CENSUS_STALE_HELP or L.CENSUS_NAMES_ON_DEMAND)
    row.hint:Show()
    if state == "expired" then return 98 end
    local assembly, snapshotChanged = AssemblyForGuild(entry.key, summary.snapshotId)
    local cooldown = OU.Runtime.census.cooldowns[entry.key .. "|requester"] or 0
    local names
    row.action:SetSize(160, 22)
    if assembly and assembly.state == "loading" then
        row.action:SetText(L.CENSUS_LOADING_BUTTON:format(assembly.received or 0, assembly.pageCount or "?"))
        row.action:SetEnabled(false)
        row.hint:SetText(L.CENSUS_RECEIVING:format(assembly.received or 0, assembly.pageCount or 0))
        row.action:Show()
    elseif assembly and assembly.state == "complete" then
        names = assembly.names
        row.action:SetText(L.BUTTON_REFRESH_MEMBERS)
        row.action:SetEnabled(cooldown <= now)
        row.hint:SetText(L.CENSUS_LOADED:format(#names, OU.Util.FormatAge(now - (assembly.loadedAt or now))))
        row.action:Show()
    elseif assembly and assembly.state == "error" then
        row.action:SetText(L.BUTTON_LOAD_MEMBERS)
        row.action:SetEnabled(cooldown <= now)
        if assembly.reason == "busy" then row.hint:SetText(L.CENSUS_BUSY)
        elseif assembly.reason == "snapshot" then row.hint:SetText(L.CENSUS_SNAPSHOT_CHANGED)
        else row.hint:SetText(L.CENSUS_TRANSFER_FAILED) end
        row.action:Show()
    else
        row.action:SetText(L.BUTTON_LOAD_MEMBERS)
        row.action:SetEnabled(cooldown <= now)
        if snapshotChanged then row.hint:SetText(L.CENSUS_SNAPSHOT_CHANGED) end
        row.action:Show()
    end
    if cooldown > now and not (assembly and assembly.state == "error") then
        row.hint:SetText(L.CENSUS_COOLDOWN:format(math.max(1, math.ceil((cooldown - now) / 60))))
    end
    row.action:SetScript("OnClick", function()
        local ok, err = OU.Census.RequestRoster(entry.key)
        if not ok then OU.Print(err == "cooldown" and L.CENSUS_COOLDOWN:format(1) or L.CENSUS_REQUEST_FAILED) end
        OU.RefreshUI()
    end)
    P.Tip(row.action, L.BUTTON_LOAD_MEMBERS, L.TIP_LOAD_MEMBERS)
    local height = 128
    for index, name in ipairs(names or {}) do
        local label = MemberLabel(row, index)
        label:SetText(name)
        label:Show()
        height = height + 20
    end
    return height
end

local function CensusRows()
    local census, now = OU.Runtime.census, OU.Util.Now()
    local totals = OU.CensusLogic.Totals(census.summaries, now)
    if #totals.rows == 0 then
        local capture = census.localCapture
        if capture.state == "loading" then return ShowEmpty(L.CENSUS_LOADING_LOCAL, L.CENSUS_LOADING_LOCAL_HELP) end
        if capture.state == "unavailable" then
            return ShowEmpty(L.CENSUS_LOCAL_UNAVAILABLE, L.CENSUS_LOCAL_UNAVAILABLE_HELP, L.BUTTON_RETRY_ROSTER,
                function() OU.Census.Capture(OU.Runtime) end)
        end
        return ShowEmpty(L.CENSUS_NO_REPORTS, L.CENSUS_NO_REPORTS_HELP)
    end
    local top, index = 0, 1
    local header = GetRow(index)
    CensusHeader(header, totals)
    top = PlaceRow(header, top, 84)
    index = index + 1
    local section = GetRow(index)
    section.heading:SetText(L.CENSUS_PARTICIPATING)
    SetColor(section.heading, P.GREY)
    top = PlaceRow(section, top, 34)
    index = index + 1
    for _, entry in ipairs(totals.rows) do
        local row, summary = GetRow(index), entry.summary
        row.chevron:SetText(UI.expandedGuild == entry.key and "▼" or "▶")
        row.chevron:Show()
        row.heading:SetPoint("TOPLEFT", row, "TOPLEFT", 24, -7)
        row.heading:SetText(summary.guildDisplay)
        SetColor(row.heading, P.COLORS.gold)
        local onlineText = summary.online == nil and L.CENSUS_ONLINE_UNKNOWN or L.CENSUS_ONLINE:format(summary.online)
        row.count:SetText(entry.state == "expired" and L.CENSUS_EXPIRED_COUNTS or L.CENSUS_COUNTS:format(summary.total, onlineText))
        SetColor(row.count, entry.state == "expired" and P.COLORS.grey or P.COLORS.green)
        local stateWord = entry.state == "fresh" and L.CENSUS_FRESH or (entry.state == "stale" and L.CENSUS_STALE or L.CENSUS_EXPIRED)
        row.body:SetText(entry.state == "expired" and L.CENSUS_LAST_REPORT:format(OU.Util.FormatAge(entry.age))
            or L.CENSUS_REPORTED:format(stateWord, OU.Util.FormatAge(entry.age), OU.Util.ShortName(summary.reporter)))
        SetColor(row.body, StateColor(entry.state))
        row:SetScript("OnMouseDown", function()
            UI.expandedGuild = UI.expandedGuild == entry.key and nil or entry.key
            OU.RefreshUI()
        end)
        local height = 56
        if UI.expandedGuild == entry.key then height = ExpandedCensus(row, entry, summary, entry.state, entry.age, now) end
        top = PlaceRow(row, top, height)
        index = index + 1
    end
    return top
end

local function RunComposer()
    local text = OU.Util.Trim(UI.input:GetText())
    local ok, err
    if UI.activeTab == "FEED" then ok, err = OU.Network.Post(text)
    elseif UI.activeTab == "LAYERS" then ok, err = OU.Network.RequestLayer(text)
    elseif UI.activeTab == "EVENTS" then
        local minutes, rest = text:match("^(%d+)%s+(.+)$")
        if not minutes then OU.Print(L.EVENT_FORMAT_HELP); return end
        local title, details = rest:match("^(.-)%s*::%s*(.*)$")
        if not title then title, details = rest, "" end
        ok, err = OU.Network.CreateEvent(minutes, title, details)
    elseif UI.activeTab == "MEMBERS" then ok, err = OU.Network.AddBridge(text) end
    if OU.Result(ok, err) then UI.input:SetText("") end
    OU.RefreshUI()
end

local function SetTab(tab)
    local changed = UI.activeTab ~= tab
    UI.activeTab = tab
    for name, button in pairs(UI.tabs) do button.activeLine:SetShown(name == tab) end
    if changed and UI.input then UI.input:SetText("") end
    OU.RefreshUI()
end

function OU.RefreshUI()
    if not UI.frame or not UI.frame:IsShown() or not OU.Runtime then return end
    OU.State.Prune(OU.Runtime, OU.Util.Now())
    UI.status:SetText(OU.StatusText())
    UI.section:SetText(VIEW_LABELS[UI.activeTab])
    local census = UI.activeTab == "CENSUS"
    local chat = UI.activeTab == "FEED"
    local chatLocked = chat and (not OU.Identity or OU.Identity.role ~= "member")
    local showComposer = not census and not chatLocked
    UI.prompt:SetShown(showComposer)
    UI.input:SetShown(showComposer)
    UI.composeButton:SetShown(showComposer)
    UI.chatDelayLabel:SetShown(chat and not chatLocked)
    UI.chatDelayInput:SetShown(chat and not chatLocked)
    UI.chatDelaySuffix:SetShown(chat and not chatLocked)
    UI.chatMuteCheck:SetShown(chat and not chatLocked)
    UI.chatMuteCheck:SetChecked(OU.DB.chat.muteNonOlympus == true)
    if chat and not UI.chatDelayInput:HasFocus() then
        UI.chatDelayInput:SetText(tostring(OU.State.ChatDelay(OU.DB)))
    end
    UI.viewport:ClearAllPoints()
    UI.viewport:SetPoint("TOPLEFT", UI.frame, "TOPLEFT", 14, -154)
    UI.viewport:SetPoint("BOTTOMRIGHT", UI.frame, "BOTTOMRIGHT", -14, showComposer and 78 or 14)
    if showComposer then
        local copy = TAB_COPY[UI.activeTab]
        UI.prompt:SetText(copy.prompt)
        UI.composeButton:SetText(copy.button)
    end
    PrepareRows()
    local height
    if UI.activeTab == "FEED" then height = FeedRows()
    elseif UI.activeTab == "LAYERS" then height = LayerRows()
    elseif UI.activeTab == "EVENTS" then height = EventRows()
    elseif UI.activeTab == "CENSUS" then height = CensusRows()
    else height = PeopleRows() end
    UI.content:SetSize(UI.scroll:GetWidth() > 0 and UI.scroll:GetWidth() or 640,
        math.max(height or 1, UI.scroll:GetHeight(), 1))
end

function OU.CreateUI()
    if UI.frame then return UI.frame end
    local frame = CreateFrame("Frame", "OlympusUnitedFrame", UIParent)
    UI.frame = frame
    frame:SetSize(720, 540)
    frame:SetPoint(OU.DB.window.point or "CENTER", UIParent, OU.DB.window.point or "CENTER", OU.DB.window.x or 0, OU.DB.window.y or 0)
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    P.Panel(frame, L.TITLE)
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, _, x, y = self:GetPoint(1)
        OU.State.SetWindowPosition(OU.DB, point, x, y)
    end)
    frame:SetScript("OnShow", OU.RefreshUI)
    frame:Hide()
    table.insert(UISpecialFrames, "OlympusUnitedFrame")

    UI.helpButton = P.Button(frame, "?", 18, 18)
    UI.helpButton:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -3)
    P.Tip(UI.helpButton, L.GUIDE_TOOLTIP_TITLE, L.GUIDE_TOOLTIP_1, L.GUIDE_TOOLTIP_2, L.GUIDE_TOOLTIP_3,
        L.GUIDE_TOOLTIP_MORE, L.GUIDE_TOOLTIP_GUARD)
    UI.helpButton:SetScript("OnClick", function(self)
        local enter = self:GetScript("OnEnter")
        if enter then enter(self) end
    end)

    local crest = frame:CreateTexture(nil, "ARTWORK")
    UI.crest = crest
    crest:SetSize(40, 40)
    crest:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -32)
    if P.assets.logo.ok == nil then P.CheckAssets(frame) end
    if not (P.assets.logo.ok and crest:SetTexture(P.assets.logo.path)) then crest:SetColorTexture(0.10, 0.28, 0.50, 1) end
    UI.status = P.Label(frame, "GameFontHighlightSmall")
    UI.status:SetPoint("LEFT", crest, "RIGHT", 12, 0)
    UI.status:SetPoint("RIGHT", frame, "RIGHT", -18, 0)
    UI.status:SetJustifyH("LEFT")
    P.Divider(frame, -80)

    local tabs = {
        { "FEED", L.TAB_UPDATES, L.TIP_TAB_UPDATES }, { "LAYERS", L.TAB_LAYERS, L.TIP_TAB_LAYERS },
        { "EVENTS", L.TAB_EVENTS, L.TIP_TAB_EVENTS }, { "CENSUS", L.TAB_CENSUS, L.TIP_TAB_CENSUS },
        { "MEMBERS", L.TAB_PEOPLE, L.TIP_TAB_PEOPLE },
    }
    local previous
    for _, data in ipairs(tabs) do
        local name, text, tooltip = data[1], data[2], data[3]
        local button = P.Button(frame, text, 130, 24, function() SetTab(name) end)
        P.Tip(button, text, tooltip)
        if previous then button:SetPoint("LEFT", previous, "RIGHT", 8, 0) else button:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -90) end
        button.activeLine = button:CreateTexture(nil, "ARTWORK")
        button.activeLine:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 5, 2)
        button.activeLine:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -5, 2)
        button.activeLine:SetHeight(2)
        button.activeLine:SetColorTexture(unpack(P.COLORS.gold))
        UI.tabs[name] = button
        previous = button
    end
    UI.section = P.Label(frame, "GameFontNormalSmall", VIEW_LABELS.FEED, P.GREY)
    UI.section:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -136)

    local viewport = CreateFrame("Frame", nil, frame)
    UI.viewport = viewport
    local well, scroll, content = P.ScrollWell(viewport)
    UI.well, UI.scroll, UI.content = well, scroll, content
    well:SetPoint("TOPLEFT", viewport, "TOPLEFT", 0, 0)
    well:SetPoint("BOTTOMRIGHT", viewport, "BOTTOMRIGHT", 0, 0)
    scroll:SetPoint("TOPLEFT", viewport, "TOPLEFT", 6, -6)
    scroll:SetPoint("BOTTOMRIGHT", viewport, "BOTTOMRIGHT", -26, 6)

    UI.prompt = P.Label(frame, "GameFontNormalSmall", L.UPDATE_PROMPT, P.GREY)
    UI.prompt:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 18, 54)
    UI.chatDelaySuffix = P.Label(frame, "GameFontHighlightSmall", L.CHAT_DELAY_SUFFIX, P.GREY)
    UI.chatDelaySuffix:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -18, 52)
    UI.chatDelayInput = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    UI.chatDelayInput:SetSize(44, 20)
    UI.chatDelayInput:SetPoint("RIGHT", UI.chatDelaySuffix, "LEFT", -8, 1)
    UI.chatDelayInput:SetAutoFocus(false)
    UI.chatDelayInput:SetText(tostring(OU.State.ChatDelay(OU.DB)))
    UI.chatDelayInput:SetScript("OnEnterPressed", function(self) SaveChatDelay(); self:ClearFocus() end)
    UI.chatDelayInput:SetScript("OnEditFocusLost", SaveChatDelay)
    UI.chatDelayInput:SetScript("OnEscapePressed", function(self)
        self:SetText(tostring(OU.State.ChatDelay(OU.DB)))
        self:ClearFocus()
    end)
    P.Tip(UI.chatDelayInput, L.CHAT_DELAY_LABEL, L.TIP_CHAT_DELAY)
    UI.chatDelayLabel = P.Label(frame, "GameFontHighlightSmall", L.CHAT_DELAY_LABEL, P.GREY)
    UI.chatDelayLabel:SetPoint("RIGHT", UI.chatDelayInput, "LEFT", -8, 0)
    UI.chatMuteCheck = P.Checkbox(frame, L.CHAT_MUTE_LABEL, function(self)
        local enabled = self:GetChecked() == true
        OU.ChatGuard.SetEnabled(enabled)
        OU.Print(enabled and L.CHAT_MUTE_ON or L.CHAT_MUTE_OFF)
        OU.RefreshUI()
    end)
    UI.chatMuteCheck:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 190, 43)
    P.Tip(UI.chatMuteCheck, L.CHAT_MUTE_LABEL, L.TIP_CHAT_MUTE)
    UI.input = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    UI.input:SetSize(535, 24)
    UI.input:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 22, 20)
    UI.input:SetAutoFocus(false)
    UI.input:SetScript("OnEnterPressed", function(self) RunComposer(); self:ClearFocus() end)
    UI.input:SetScript("OnEditFocusLost", function() end)
    UI.input:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    UI.composeButton = P.Button(frame, L.UPDATE_BUTTON, 135, 24, RunComposer)
    UI.composeButton:SetPoint("LEFT", UI.input, "RIGHT", 12, 0)
    P.Tip(UI.composeButton, L.UPDATE_BUTTON, L.TIP_COMPOSE)

    SetTab("FEED")
    return frame
end

function OU.Open(tab)
    if not UI.frame then OU.CreateUI() end
    if tab and UI.tabs[tab] then UI.activeTab = tab end
    UI.frame:Show()
    SetTab(UI.activeTab)
end

function OU.Toggle()
    if not UI.frame then OU.CreateUI() end
    if UI.frame:IsShown() then UI.frame:Hide() else OU.Open() end
end

UI._Test = { SetTab = SetTab, CensusRows = CensusRows, AssemblyForGuild = AssemblyForGuild }
