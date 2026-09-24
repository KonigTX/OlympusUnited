local _, OU = ...
local L = OU.L

local Network = {}
OU.Network = Network

local function IsSelf(name)
    local identity = OU.Identity or OU.Util.PlayerIdentity()
    return OU.Util.NormalizeName(name) == OU.Util.NormalizeName(identity.name)
end

local function BridgeKey(name)
    return OU.Util.NormalizeName(name)
end

local function IsTrustedBridge(name)
    local key = BridgeKey(name)
    return key and OU.DB and OU.DB.bridges and OU.DB.bridges[key] ~= nil
end

local function IsOlympusMember(identity)
    return type(identity) == "table" and identity.role == "member" and OU.Util.IsOlympusGuild(identity.guild)
end

function Network.CanParticipate()
    if not OU.DB or not OU.DB.enabled then return false end
    local identity = OU.Identity or OU.Util.PlayerIdentity()
    return identity.role == "member" or OU.DB.guestMode
end

function Network.RegisterPrefix()
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        local ok, result = pcall(C_ChatInfo.RegisterAddonMessagePrefix, OU.Protocol.PREFIX)
        return ok and result ~= false
    end
    if RegisterAddonMessagePrefix then
        local ok, result = pcall(RegisterAddonMessagePrefix, OU.Protocol.PREFIX)
        return ok and result ~= false
    end
    return false
end

local function ResultSucceeded(ok, result)
    if not ok then return false end
    if result == nil or result == true or result == 0 then return true end
    if Enum and Enum.SendAddonMessageResult and result == Enum.SendAddonMessageResult.Success then return true end
    return false
end

local function SendRaw(payload, distribution, target)
    if C_ChatInfo and C_ChatInfo.SendAddonMessageLogged then
        local ok, result = pcall(C_ChatInfo.SendAddonMessageLogged, OU.Protocol.PREFIX, payload, distribution, target)
        return ResultSucceeded(ok, result), result
    end
    if C_ChatInfo and C_ChatInfo.SendAddonMessage then
        local ok, result = pcall(C_ChatInfo.SendAddonMessage, OU.Protocol.PREFIX, payload, distribution, target)
        return ResultSucceeded(ok, result), result
    end
    if SendAddonMessage then
        local ok, result = pcall(SendAddonMessage, OU.Protocol.PREFIX, payload, distribution, target)
        return ResultSucceeded(ok, result), result
    end
    return false, L.ERROR_ADDON_CHAT
end

local function SendToBridges(payload, exceptSender)
    local sent = false
    local exceptKey = BridgeKey(exceptSender)
    for key, displayName in pairs(OU.DB.bridges or {}) do
        if key ~= exceptKey and not IsSelf(displayName) then
            local ok = SendRaw(payload, "WHISPER", displayName)
            sent = ok or sent
        end
    end
    return sent
end

local function BridgeTargets(exceptSender)
    local targets, exceptKey = {}, BridgeKey(exceptSender)
    for key, displayName in pairs(OU.DB.bridges or {}) do
        if key ~= exceptKey and not IsSelf(displayName) then targets[#targets + 1] = displayName end
    end
    table.sort(targets, function(a, b) return tostring(a):lower() < tostring(b):lower() end)
    return targets
end

local function Encode(messageType, id, fields, origin, hops)
    return OU.Protocol.Encode(messageType, id, fields, origin or OU.Identity.name, hops or 0)
end

local function Forward(message, transportSender, distribution)
    if not OU.DB.bridgeMode or message.hops >= 2 then return end

    local payload = OU.Protocol.Encode(message.type, message.id, message.fields, message.origin, message.hops + 1)
    if not payload then return end

    if distribution == "GUILD" then
        SendToBridges(payload, transportSender)
    elseif distribution == "WHISPER" and IsTrustedBridge(transportSender) then
        if IsInGuild and IsInGuild() then SendRaw(payload, "GUILD") end
        -- A hop-one summary has reached its destination connector. Its only
        -- legal next leg is the final guild broadcast at hop two.
        if message.type ~= "CSUM" or message.hops == 0 then
            SendToBridges(payload, transportSender)
        end
    end
end

function Network.Send(messageType, id, fields)
    if not Network.CanParticipate() then return false, L.ERROR_ACCESS end
    local payload, err = Encode(messageType, id, fields)
    if not payload then return false, err end

    local sent = false
    if IsInGuild and IsInGuild() then
        local ok = SendRaw(payload, "GUILD")
        sent = ok or sent
    end

    if messageType == "CREQ" then
        if not sent then return false, L.ERROR_NO_ROUTE end
        return true
    end

    if OU.DB.bridgeMode or OU.Identity.role == "guest" then
        sent = SendToBridges(payload) or sent
    end

    if not sent then
        return false, L.ERROR_NO_ROUTE
    end
    return true
end

function Network.SendGuildOnly(messageType, id, fields, origin, hops)
    if not Network.CanParticipate() or not (IsInGuild and IsInGuild()) then return false, L.ERROR_NO_ROUTE end
    local payload, err = Encode(messageType, id, fields, origin, hops)
    if not payload then return false, err end
    return SendRaw(payload, "GUILD")
end

function Network.SendDirectedReply(route, messageType, id, fields, origin)
    if type(route) ~= "table" or type(route.upstream) ~= "table" then return false, "missing route" end
    local payload, err = Encode(messageType, id, fields, origin, 0)
    if not payload then return false, err end
    if route.upstream.distribution == "GUILD" then return SendRaw(payload, "GUILD") end
    if route.upstream.distribution == "WHISPER" and route.upstream.sender then
        return SendRaw(payload, "WHISPER", route.upstream.sender)
    end
    return false, "invalid route"
end

function Network.AddBridge(name)
    name = OU.Util.SanitizeText(name, 64)
    local key = BridgeKey(name)
    if not key then return false, L.ERROR_CONNECTOR_NAME end
    if IsSelf(name) then return false, L.ERROR_CONNECTOR_SELF end
    OU.DB.bridges[key] = name
    return true
end

function Network.RemoveBridge(name)
    local key = BridgeKey(name)
    if not key or not OU.DB.bridges[key] then return false, L.ERROR_CONNECTOR_MISSING end
    OU.DB.bridges[key] = nil
    return true
end

function Network.SetBridgeMode(enabled)
    OU.DB.bridgeMode = enabled and true or false
    if OU.DB.bridgeMode then Network.SendHello() end
end

function Network.SendHello()
    OU.Identity = OU.Util.PlayerIdentity()
    local messageType, id, fields = OU.Protocol.Hello(OU.Identity)
    return Network.Send(messageType, id, fields)
end

local function ApplyLocal(messageType, id, fields)
    OU.State.Apply(OU.Runtime, OU.Identity.name, {
        type = messageType,
        id = id,
        origin = OU.Identity.name,
        hops = 0,
        fields = fields,
    }, OU.Util.Now())
    if OU.RefreshUI then OU.RefreshUI() end
end

function Network.Post(text)
    text = OU.Util.SanitizeText(text, 170)
    if text == "" then return false, L.ERROR_EMPTY_UPDATE end
    OU.Identity = OU.Util.PlayerIdentity()
    if not IsOlympusMember(OU.Identity) then return false, L.ERROR_CHAT_MEMBERS_ONLY end
    local now = OU.Util.Now()
    local remaining = OU.State.ChatRemaining(OU.Runtime, OU.Identity.name, now, OU.DB)
    if remaining > 0 then return false, L.ERROR_CHAT_SLOW_MODE:format(math.ceil(remaining)) end
    local messageType, id, fields = OU.Protocol.Post(text, OU.Identity)
    local sent, err = Network.Send(messageType, id, fields)
    if sent then ApplyLocal(messageType, id, fields) end
    return sent, err
end

function Network.RequestLayer(note)
    local identity = OU.Util.PlayerIdentity()
    local messageType, id, fields = OU.Protocol.LayerRequest(identity.zone, note, OU.Util.Now() + 600)
    local sent, err = Network.Send(messageType, id, fields)
    if sent then ApplyLocal(messageType, id, fields) end
    return sent, err
end

function Network.OfferLayer(requestID, note)
    local request = OU.Runtime.layers[requestID]
    if not request then return false, L.ERROR_LAYER_EXPIRED end
    local messageType, id, fields = OU.Protocol.LayerOffer(requestID, note or L.LAYER_INVITE_NOTE)
    local sent, err = Network.Send(messageType, id, fields)
    if sent then
        if C_PartyInfo and C_PartyInfo.InviteUnit then
            pcall(C_PartyInfo.InviteUnit, request.sender)
        elseif InviteUnit then
            pcall(InviteUnit, request.sender)
        end
    end
    return sent, err
end

function Network.CreateEvent(minutes, title, details)
    minutes = math.max(0, math.min(10080, tonumber(minutes) or 0))
    title = OU.Util.SanitizeText(title, 70)
    if title == "" then return false, L.ERROR_EVENT_TITLE end
    local messageType, id, fields = OU.Protocol.Event(OU.Util.Now() + minutes * 60, title, details)
    local sent, err = Network.Send(messageType, id, fields)
    if sent then ApplyLocal(messageType, id, fields) end
    return sent, err
end

function Network.ClaimRecruit(candidate)
    local status, detail = OU.State.ContactStatus(OU.DB, OU.Runtime, candidate, OU.Util.Now())
    if status ~= "available" then return false, status, detail end

    local expires = OU.Util.Now() + 300
    local messageType, id, fields = OU.Protocol.Claim(candidate, expires)
    local sent, err = Network.Send(messageType, id, fields)
    if sent then
        OU.State.MarkContacted(OU.DB, candidate, OU.Util.Now())
        ApplyLocal(messageType, id, fields)
    end
    return sent, err
end

function Network.ReleaseRecruit(candidate)
    local messageType, id, fields = OU.Protocol.Release(candidate)
    local sent, err = Network.Send(messageType, id, fields)
    if sent then ApplyLocal(messageType, id, fields) end
    return sent, err
end

local function SameName(left, right)
    local a, b = OU.Util.NormalizeName(left), OU.Util.NormalizeName(right)
    return a ~= nil and a == b
end

local function PostDeclaresOlympusMember(message)
    return message.fields[2] == "member" and OU.Util.IsOlympusGuild(message.fields[3])
end

local function PostInboundAllowed(message, distribution, transportSender)
    local identity = OU.Identity or OU.Util.PlayerIdentity()
    if not IsOlympusMember(identity) then return false end
    if distribution == "GUILD" and message.hops == 0 then
        return SameName(message.origin, transportSender)
    end
    if not PostDeclaresOlympusMember(message) then return false end
    if distribution == "GUILD" then return message.hops == 1 or message.hops == 2 end
    return distribution == "WHISPER" and IsTrustedBridge(transportSender)
end

local function LocalGuildKey()
    local identity = OU.Identity or OU.Util.PlayerIdentity()
    return OU.Util.NormalizeGuild(identity.guild)
end

local function GuildOnlyElection(message, distribution, transportSender)
    if distribution ~= "GUILD" or message.hops ~= 0 or not SameName(message.origin, transportSender) then return false end
    return OU.Util.NormalizeGuild(message.fields[1]) == LocalGuildKey()
end

local function RequestInboundAllowed(message, distribution, transportSender)
    if distribution == "GUILD" then
        if message.hops == 0 then return SameName(message.origin, transportSender) end
        return message.hops == 2 and IsTrustedBridge(transportSender)
    end
    return distribution == "WHISPER" and message.hops == 1 and OU.DB.bridgeMode
        and IsTrustedBridge(transportSender)
end

local function SummaryInboundAllowed(message, distribution, transportSender)
    local guildKey = OU.Util.NormalizeGuild(message.fields[1])
    if not guildKey then return false end
    if distribution == "GUILD" and message.hops == 0 then
        return guildKey == LocalGuildKey() and SameName(message.origin, transportSender)
    end
    if guildKey == LocalGuildKey() then return false end
    if distribution == "GUILD" then
        return (message.hops == 1 or message.hops == 2) and IsTrustedBridge(transportSender)
    end
    return distribution == "WHISPER" and (message.hops == 0 or message.hops == 1)
        and OU.DB.bridgeMode and IsTrustedBridge(transportSender)
end

local function UpstreamLeg(distribution, sender)
    return { distribution = distribution, sender = distribution == "WHISPER" and sender or nil }
end

local function ForwardRequest(message, transportSender, distribution, now)
    local requestId, guildKey, targetReporter = message.fields[1], OU.Util.NormalizeGuild(message.fields[2]), message.fields[4]
    if not requestId or not guildKey or not targetReporter or message.hops > 2 then return nil end
    local runtime = OU.Runtime
    local existing = runtime.census.routes[requestId]
    if existing then return nil, "duplicate route" end

    if SameName(targetReporter, OU.Identity.name) and guildKey == LocalGuildKey() then
        local guildEndpoint = distribution == "GUILD" and (message.hops == 0 or message.hops == 2)
        local connectorEndpoint = distribution == "WHISPER" and message.hops == 1
            and OU.DB.bridgeMode and IsTrustedBridge(transportSender)
        if not guildEndpoint and not connectorEndpoint then return nil, "invalid reporter endpoint" end
        local route = { role = "reporter", requestId = requestId, guildKey = guildKey, requester = message.origin,
            reporter = targetReporter, upstream = UpstreamLeg(distribution, transportSender),
            acceptedInbound = UpstreamLeg(distribution, transportSender), expiresAt = now + OU.CensusLogic.CONSTANTS.ROUTE_TTL }
        runtime.census.routes[requestId] = route
        return OU.Census.HandleRequest(runtime, route, message, now)
    end

    if guildKey == LocalGuildKey() and distribution == "GUILD" then return nil, "local reporter receives directly" end

    if not OU.DB.bridgeMode or message.hops >= 2 then return nil, "not endpoint" end
    local payload = OU.Protocol.Encode(message.type, message.id, message.fields, message.origin, message.hops + 1)
    if not payload then return nil, "encode failed" end
    local route = { role = "intermediary", requestId = requestId, guildKey = guildKey, requester = message.origin,
        reporter = targetReporter, upstream = UpstreamLeg(distribution, transportSender),
        expiresAt = now + OU.CensusLogic.CONSTANTS.ROUTE_TTL }
    local sent = false
    if distribution == "GUILD" then
        route.downstream = { distribution = "WHISPER", senders = {} }
        for _, target in ipairs(BridgeTargets(transportSender)) do
            route.downstream.senders[OU.Util.NormalizeName(target)] = true
            sent = SendRaw(payload, "WHISPER", target) or sent
        end
    elseif distribution == "WHISPER" and IsTrustedBridge(transportSender) and IsInGuild and IsInGuild() then
        route.downstream = { distribution = "GUILD", sender = targetReporter }
        sent = SendRaw(payload, "GUILD")
    end
    if sent then runtime.census.routes[requestId] = route; return { kind = "census-route", value = route } end
    return nil, "no directed route"
end

local function PageRateAllowed(runtime, sender, requestId, now)
    local key = (OU.Util.NormalizeName(sender) or tostring(sender):lower()) .. "|" .. requestId
    local bucket = runtime.census.pageRate[key]
    if not bucket then
        bucket = { tokens = 8, last = now, windowStart = now, windowCount = 0, total = 0 }
        runtime.census.pageRate[key] = bucket
    end
    local elapsed = math.max(0, now - bucket.last)
    bucket.tokens = math.min(8, bucket.tokens + elapsed * 5)
    bucket.last = now
    if now - bucket.windowStart >= 10 then bucket.windowStart, bucket.windowCount = now, 0 end
    if bucket.tokens < 1 or bucket.windowCount >= 60 or bucket.total >= 1000 then return false end
    bucket.tokens = bucket.tokens - 1
    bucket.windowCount = bucket.windowCount + 1
    bucket.total = bucket.total + 1
    return true
end

local function DownstreamMatches(route, distribution, sender)
    local leg = route.downstream
    if not leg or leg.distribution ~= distribution then return false end
    if distribution == "GUILD" then return SameName(leg.sender, sender) end
    local key = OU.Util.NormalizeName(sender)
    return key and leg.senders and leg.senders[key] == true
end

local function ForwardReply(route, message)
    if message.hops >= 2 then return false end
    local payload = OU.Protocol.Encode(message.type, message.id, message.fields, message.origin, message.hops + 1)
    if not payload then return false end
    if route.upstream.distribution == "GUILD" then return SendRaw(payload, "GUILD") end
    return SendRaw(payload, "WHISPER", route.upstream.sender)
end

local function HandleReply(message, transportSender, distribution, now)
    local requestId = message.fields[1]
    local route = requestId and OU.Runtime.census.routes[requestId]
    if not route or (route.expiresAt or 0) <= now or not SameName(message.origin, route.reporter) then return nil end
    if route.role == "intermediary" then
        if route.terminal then return nil end
        if not DownstreamMatches(route, distribution, transportSender) then return nil end
        if distribution == "WHISPER" and not route.lockedDownstream then route.lockedDownstream = OU.Util.NormalizeName(transportSender) end
        if route.lockedDownstream and distribution == "WHISPER" and route.lockedDownstream ~= OU.Util.NormalizeName(transportSender) then return nil end
        if OU.State.Seen(OU.Runtime, message.origin, message.id, now) then return nil end
        if message.type == "CPAGE" and not PageRateAllowed(OU.Runtime, transportSender, requestId, now) then return nil end
        if not ForwardReply(route, message) then return nil end
        if message.type == "CFAIL" then route.terminal = true end
        return { kind = "census-forward", value = route }
    end
    if route.role == "requester" then
        if route.terminal then return nil end
        if route.guildKey == LocalGuildKey() then
            if distribution ~= "GUILD" or message.hops ~= 0 or not SameName(route.reporter, transportSender) then return nil end
        else
            if distribution ~= "GUILD" or (message.hops ~= 1 and message.hops ~= 2)
                or not IsTrustedBridge(transportSender) then return nil end
            local senderKey = OU.Util.NormalizeName(transportSender)
            if not senderKey or (route.lockedGuildSender and route.lockedGuildSender ~= senderKey) then return nil end
            route.lockedGuildSender = route.lockedGuildSender or senderKey
        end
        if OU.State.Seen(OU.Runtime, message.origin, message.id, now) then return nil end
        if message.type == "CPAGE" and not PageRateAllowed(OU.Runtime, transportSender, requestId, now) then return nil end
        if message.type == "CPAGE" then
            local change = OU.Census.ReceivePage(OU.Runtime, message, now)
            if change and change.status == "complete" then route.terminal = true end
            return change
        end
        route.terminal = true
        return OU.Census.ReceiveFailure(OU.Runtime, message, now)
    end
    return nil
end

function Network.OnAddonMessage(prefix, payload, distribution, transportSender)
    if prefix ~= OU.Protocol.PREFIX or not Network.CanParticipate() or IsSelf(transportSender) then return end
    if distribution == "WHISPER" and not IsTrustedBridge(transportSender) then return end

    local message = OU.Protocol.Decode(payload)
    if not message then return end

    local now = OU.Util.Now()
    if message.type == "CCAND" or message.type == "CLEASE" then
        if not GuildOnlyElection(message, distribution, transportSender) then return end
        local change = OU.State.Apply(OU.Runtime, transportSender, message, now)
        if change and OU.OnNetworkChange then OU.OnNetworkChange(change, distribution) end
        return
    end
    if message.type == "CSUM" then
        if not SummaryInboundAllowed(message, distribution, transportSender) then return end
        local change = OU.State.Apply(OU.Runtime, transportSender, message, now)
        if not change then return end
        Forward(message, transportSender, distribution)
        if OU.OnNetworkChange then OU.OnNetworkChange(change, distribution) end
        return
    end
    if message.type == "CREQ" then
        if not RequestInboundAllowed(message, distribution, transportSender) then return end
        if OU.State.Seen(OU.Runtime, message.origin, message.id, now) then return end
        local allowed = OU.State.RateAllowed(OU.Runtime, transportSender, message.type, now)
        if not allowed then return end
        local change = ForwardRequest(message, transportSender, distribution, now)
        if change and OU.OnNetworkChange then OU.OnNetworkChange(change, distribution) end
        return
    end
    if message.type == "CPAGE" or message.type == "CFAIL" then
        local change = HandleReply(message, transportSender, distribution, now)
        if change and OU.OnNetworkChange then OU.OnNetworkChange(change, distribution) end
        return
    end

    if message.type == "POST" and not PostInboundAllowed(message, distribution, transportSender) then return end

    if message.hops == 0 then message.origin = transportSender end
    local author = message.origin
    local change = OU.State.Apply(OU.Runtime, author, message, now)
    if not change then return end

    Forward(message, transportSender, distribution)
    if OU.OnNetworkChange then OU.OnNetworkChange(change, distribution) end
end

Network._Test = {
    SendRaw = SendRaw,
    SendToBridges = SendToBridges,
    IsSelf = IsSelf,
    IsTrustedBridge = IsTrustedBridge,
    RequestInboundAllowed = RequestInboundAllowed,
    SummaryInboundAllowed = SummaryInboundAllowed,
    ForwardRequest = ForwardRequest,
    HandleReply = HandleReply,
    PageRateAllowed = PageRateAllowed,
    BridgeTargets = BridgeTargets,
    PostInboundAllowed = PostInboundAllowed,
}
