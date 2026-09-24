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
    return false, L.ERROR_ADDON_CHAT
end

local function SendToBridges(payload, exceptSender, budgeted)
    local sent = false
    local exceptKey = BridgeKey(exceptSender)
    for key, displayName in pairs(OU.DB.bridges or {}) do
        if key ~= exceptKey and not IsSelf(displayName) then
            local ok = not budgeted or OU.State.ForwardAllowed(OU.Runtime, OU.Util.Now())
            if ok then ok = SendRaw(payload, "WHISPER", displayName) end
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
        SendToBridges(payload, transportSender, true)
    elseif distribution == "WHISPER" and IsTrustedBridge(transportSender) then
        if IsInGuild and IsInGuild() and OU.State.ForwardAllowed(OU.Runtime, OU.Util.Now()) then SendRaw(payload, "GUILD") end
        -- A hop-one summary has reached its destination connector. Its only
        -- legal next leg is the final guild broadcast at hop two.
        if message.type ~= "CSUM" or message.hops == 0 then
            SendToBridges(payload, transportSender, true)
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
    if not OU.Util.IsPlainString(name) then return false, L.ERROR_CONNECTOR_NAME end
    name = OU.Util.SanitizeText(name, 64)
    local key = BridgeKey(name)
    if not key then return false, L.ERROR_CONNECTOR_NAME end
    if IsSelf(name) then return false, L.ERROR_CONNECTOR_SELF end
    return OU.State.AddBridge(OU.DB, name)
end

function Network.RemoveBridge(name)
    return OU.State.RemoveBridge(OU.DB, name)
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

local GENERAL_TYPES = {
    HELLO = true, POST = true, LREQ = true, LOFFER = true, EVENT = true, CLAIM = true, RELEASE = true,
}

local function ConnectorInboundAllowed(message, distribution, transportSender)
    if not IsTrustedBridge(transportSender) then return false end
    if distribution == "WHISPER" then return message.hops >= 0 and message.hops <= 2 end
    return distribution == "GUILD" and (message.hops == 1 or message.hops == 2)
end

local function DeclaredGuild(message)
    if message.type == "HELLO" then return message.fields[2] end
    if message.type == "POST" then return message.fields[3] end
    if message.type == "CCAND" or message.type == "CSUM" then
        if OU.Util.NormalizeGuild(message.fields[1]) == OU.Util.NormalizeGuild(message.fields[2]) then
            return message.fields[2]
        end
        return nil
    end
    if message.type == "CLEASE" or message.type == "CREQ" then return message.fields[1 + (message.type == "CREQ" and 1 or 0)] end
    return nil
end

local function ObserveConfiguredCandidate(message, distribution, transportSender, now)
    if not OU.GuildTrust or not ConnectorInboundAllowed(message, distribution, transportSender) then return false end
    local guild = DeclaredGuild(message)
    if not guild then return false end
    local observed = OU.GuildTrust.Observe(guild, "configured-connector", now, OU.DB)
    if observed and OU.RefreshUI then OU.RefreshUI() end
    return observed
end

local function GeneralInboundAllowed(message, distribution, transportSender)
    if not GENERAL_TYPES[message.type] then return false end
    local allowed
    if distribution == "GUILD" and message.hops == 0 then
        allowed = SameName(message.origin, transportSender)
    elseif distribution == "GUILD" and (message.hops == 1 or message.hops == 2) then
        allowed = IsTrustedBridge(transportSender)
    elseif distribution == "WHISPER" and message.hops >= 0 and message.hops <= 2 then
        allowed = IsTrustedBridge(transportSender)
    else
        allowed = false
    end
    if not allowed then return false end
    if message.type == "POST" then
        local identity = OU.Identity or OU.Util.PlayerIdentity()
        return IsOlympusMember(identity) and message.fields[2] == "member"
            and OU.Util.IsParticipatingGuild(message.fields[3])
    elseif message.type == "HELLO" and message.fields[1] == "member" then
        return OU.Util.IsParticipatingGuild(message.fields[2])
    end
    return true
end

local function GovernanceInboundAllowed(message, distribution, transportSender)
    return message.type == "GDEC" and ConnectorInboundAllowed(message, distribution, transportSender)
end

local function ForwardGovernance(message, transportSender, distribution, now)
    if not OU.DB.bridgeMode or message.hops >= 2 then return false end
    local payload = OU.Protocol.Encode(message.type, message.id, message.fields, message.origin, message.hops + 1)
    if not payload then return false end
    local sent = false
    if distribution == "GUILD" then
        sent = SendToBridges(payload, transportSender, true)
    elseif distribution == "WHISPER" and IsTrustedBridge(transportSender) then
        if IsInGuild and IsInGuild() and OU.State.ForwardAllowed(OU.Runtime, now) then
            sent = SendRaw(payload, "GUILD") or sent
        end
        sent = SendToBridges(payload, transportSender, true) or sent
    end
    return sent
end

function Network.SendGuildDecision(decision)
    local messageType, id, fields, origin = OU.Protocol.GuildDecision(decision)
    if not messageType then return false, id end
    local payload, err = Encode(messageType, id, fields, origin, 0)
    if not payload then return false, err end
    local sent = SendToBridges(payload, nil, true)
    return sent, sent and nil or L.ERROR_NO_ROUTE
end

function Network.OnGuildTrustChanged(wasLocalParticipant, now)
    now = now or OU.Util.Now()
    OU.Identity = OU.Util.PlayerIdentity()
    if OU.ChatGuard and OU.ChatGuard.OnGuildTrustChanged then OU.ChatGuard.OnGuildTrustChanged(OU.DB, now) end
    if OU.Runtime then OU.State.Prune(OU.Runtime, now) end
    local isLocalParticipant = OU.Util.IsParticipatingGuild(OU.Identity.guild)
    if wasLocalParticipant ~= isLocalParticipant and OU.Census and OU.Census.OnGuildChanged then
        OU.Census.OnGuildChanged()
    end
    if OU.RefreshUI then OU.RefreshUI() end
    return isLocalParticipant
end

local function LocalGuildKey()
    local identity = OU.Identity or OU.Util.PlayerIdentity()
    if not OU.Util.IsParticipatingGuild(identity.guild) then return nil end
    return OU.Util.NormalizeGuild(identity.guild)
end

local function GuildOnlyElection(message, distribution, transportSender)
    if distribution ~= "GUILD" or message.hops ~= 0 or not SameName(message.origin, transportSender) then return false end
    return OU.Util.NormalizeGuild(message.fields[1]) == LocalGuildKey()
end

local function RequestInboundAllowed(message, distribution, transportSender)
    if not OU.Util.IsParticipatingGuild(message.fields[2]) then return false end
    if distribution == "GUILD" then
        if message.hops == 0 then return SameName(message.origin, transportSender) end
        return message.hops == 2 and IsTrustedBridge(transportSender)
    end
    return distribution == "WHISPER" and message.hops == 1 and OU.DB.bridgeMode
        and IsTrustedBridge(transportSender)
end

local function SummaryInboundAllowed(message, distribution, transportSender)
    local guildKey = OU.Util.NormalizeGuild(message.fields[1])
    if not guildKey or not OU.Util.IsParticipatingGuild(message.fields[2]) then return false end
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
        if not OU.Census.AdmitRoute(runtime, requestId, route, now) then return nil, "route capacity" end
        return OU.Census.HandleRequest(runtime, route, message, now)
    end

    if guildKey == LocalGuildKey() and distribution == "GUILD" then return nil, "local reporter receives directly" end

    if not OU.DB.bridgeMode or message.hops >= 2 then return nil, "not endpoint" end
    local payload = OU.Protocol.Encode(message.type, message.id, message.fields, message.origin, message.hops + 1)
    if not payload then return nil, "encode failed" end
    local route = { role = "intermediary", requestId = requestId, guildKey = guildKey, requester = message.origin,
        reporter = targetReporter, upstream = UpstreamLeg(distribution, transportSender),
        expiresAt = now + OU.CensusLogic.CONSTANTS.ROUTE_TTL }
    if not OU.Census.AdmitRoute(runtime, requestId, route, now) then return nil, "route capacity" end
    local sent = false
    if distribution == "GUILD" then
        route.downstream = { distribution = "WHISPER", senders = {} }
        for _, target in ipairs(BridgeTargets(transportSender)) do
            route.downstream.senders[OU.Util.NormalizeName(target)] = true
            if OU.State.ForwardAllowed(runtime, now) then sent = SendRaw(payload, "WHISPER", target) or sent end
        end
    elseif distribution == "WHISPER" and IsTrustedBridge(transportSender) and IsInGuild and IsInGuild() then
        route.downstream = { distribution = "GUILD", sender = targetReporter }
        if OU.State.ForwardAllowed(runtime, now) then sent = SendRaw(payload, "GUILD") end
    end
    if sent then return { kind = "census-route", value = route } end
    runtime.census.routes[requestId] = nil
    return nil, "no directed route"
end

local function PageRateAllowed(runtime, sender, requestId, now)
    local key = (OU.Util.NormalizeName(sender) or tostring(sender):lower()) .. "|" .. requestId
    local bucket = runtime.census.pageRate[key]
    if not bucket then
        for oldKey, old in pairs(runtime.census.pageRate) do
            if type(old) ~= "table" or now - (old.lastTouched or old.last or 0) > OU.CensusLogic.CONSTANTS.PAGE_RATE_TTL
                or not runtime.census.routes[old.requestId] then runtime.census.pageRate[oldKey] = nil end
        end
        if OU.Util.Count(runtime.census.pageRate) >= OU.CensusLogic.CONSTANTS.MAX_PAGE_RATE then return false end
        bucket = { tokens = 8, last = now, lastTouched = now, windowStart = now, windowCount = 0,
            total = 0, requestId = requestId }
        runtime.census.pageRate[key] = bucket
    end
    local elapsed = math.max(0, now - bucket.last)
    bucket.tokens = math.min(8, bucket.tokens + elapsed * 5)
    bucket.last = now
    bucket.lastTouched = now
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
    if not OU.State.ForwardAllowed(OU.Runtime, OU.Util.Now()) then return false end
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
        if route.lockedDownstream and distribution == "WHISPER" and route.lockedDownstream ~= OU.Util.NormalizeName(transportSender) then return nil end
        local context = { origin = message.origin, transportSender = transportSender,
            distribution = distribution, hops = message.hops }
        local admitted = OU.State.AdmitInbound(OU.Runtime, context, message, now)
        if not admitted then return nil end
        if distribution == "WHISPER" and not route.lockedDownstream then route.lockedDownstream = OU.Util.NormalizeName(transportSender) end
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
        local context = { origin = message.origin, transportSender = transportSender,
            distribution = distribution, hops = message.hops }
        local admitted = OU.State.AdmitInbound(OU.Runtime, context, message, now)
        if not admitted then return nil end
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
    local context = { origin = message.origin, transportSender = transportSender,
        distribution = distribution, hops = message.hops }
    ObserveConfiguredCandidate(message, distribution, transportSender, now)
    if message.type == "GDEC" then
        if not GovernanceInboundAllowed(message, distribution, transportSender) then return end
        if not OU.State.AdmitInbound(OU.Runtime, context, message, now) then return end
        local wasLocalParticipant = OU.Identity and OU.Util.IsParticipatingGuild(OU.Identity.guild) or false
        local changed, reason
        if OU.GuildTrust then changed, reason = OU.GuildTrust.ApplyRemote(message, now, OU.DB) end
        if not changed then
            if reason == "decision-conflict" then Network.OnGuildTrustChanged(wasLocalParticipant, now) end
            return
        end
        ForwardGovernance(message, transportSender, distribution, now)
        Network.OnGuildTrustChanged(wasLocalParticipant, now)
        return
    end
    if message.type == "CCAND" or message.type == "CLEASE" then
        if not GuildOnlyElection(message, distribution, transportSender) then return end
        if not OU.State.AdmitInbound(OU.Runtime, context, message, now) then return end
        local change = OU.State.Apply(OU.Runtime, transportSender, message, now, context, true)
        if change and OU.OnNetworkChange then OU.OnNetworkChange(change, distribution) end
        return
    end
    if message.type == "CSUM" then
        if not SummaryInboundAllowed(message, distribution, transportSender) then return end
        if not OU.State.AdmitInbound(OU.Runtime, context, message, now) then return end
        local change = OU.State.Apply(OU.Runtime, transportSender, message, now, context, true)
        if not change then return end
        Forward(message, transportSender, distribution)
        if OU.OnNetworkChange then OU.OnNetworkChange(change, distribution) end
        return
    end
    if message.type == "CREQ" then
        if not RequestInboundAllowed(message, distribution, transportSender) then return end
        if not OU.State.AdmitInbound(OU.Runtime, context, message, now) then return end
        local change = ForwardRequest(message, transportSender, distribution, now)
        if change and OU.OnNetworkChange then OU.OnNetworkChange(change, distribution) end
        return
    end
    if message.type == "CPAGE" or message.type == "CFAIL" then
        local change = HandleReply(message, transportSender, distribution, now)
        if change and OU.OnNetworkChange then OU.OnNetworkChange(change, distribution) end
        return
    end

    if not GeneralInboundAllowed(message, distribution, transportSender) then return end
    if not OU.State.AdmitInbound(OU.Runtime, context, message, now) then return end
    local change = OU.State.Apply(OU.Runtime, message.origin, message, now, context, true)
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
    GeneralInboundAllowed = GeneralInboundAllowed,
    PostInboundAllowed = GeneralInboundAllowed,
    ConnectorInboundAllowed = ConnectorInboundAllowed,
    GovernanceInboundAllowed = GovernanceInboundAllowed,
    ObserveConfiguredCandidate = ObserveConfiguredCandidate,
    DeclaredGuild = DeclaredGuild,
    ForwardGovernance = ForwardGovernance,
}
