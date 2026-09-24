local _, OU = ...
local L = OU.L

local State = {}
OU.State = State

local DEFAULTS = {
    enabled = true,
    guestMode = false,
    notifications = true,
    bridgeMode = false,
    bridges = {},
    chat = { delaySeconds = 30, muteNonOlympus = false, knownPlayers = {} },
    window = { point = "CENTER", x = 0, y = 0 },
    recruiting = {
        cooldownMinutes = 30,
        contacted = {},
        doNotContact = {},
    },
}

local CHAT_DELAY_DEFAULT = 30
local CHAT_DELAY_MIN = 5
local CHAT_DELAY_MAX = 300

local function NormalizedChatDelay(value)
    value = tonumber(value)
    if not value then return CHAT_DELAY_DEFAULT end
    value = math.floor(value + 0.5)
    return math.max(CHAT_DELAY_MIN, math.min(CHAT_DELAY_MAX, value))
end

function State.EnsureDatabase(database)
    database = OU.Util.CopyDefaults(database, DEFAULTS)
    if type(database.chat) ~= "table" then database.chat = {} end
    database.chat.delaySeconds = NormalizedChatDelay(database.chat.delaySeconds)
    if OU.ChatGuard and OU.ChatGuard.SanitizeDatabase then OU.ChatGuard.SanitizeDatabase(database) end
    return database
end

function State.ChatDelay(database)
    return NormalizedChatDelay(database and database.chat and database.chat.delaySeconds)
end

function State.SetChatDelay(database, value)
    local number = tonumber(value)
    if not number or number < CHAT_DELAY_MIN or number > CHAT_DELAY_MAX then
        return false, State.ChatDelay(database)
    end
    local delay = NormalizedChatDelay(number)
    database.chat = type(database.chat) == "table" and database.chat or {}
    local changed = database.chat.delaySeconds ~= delay
    database.chat.delaySeconds = delay
    return true, delay, changed
end

function State.NewRuntime()
    return {
        peers = {},
        feed = {},
        layers = {},
        events = {},
        claims = {},
        seen = {},
        rate = {},
        chat = { lastAcceptedByAuthor = {} },
        census = {
            leases = {}, candidates = {}, summaries = {}, routes = {}, transfers = {},
            assemblies = {}, cooldowns = {}, localCapture = { state = "idle" }, pageRate = {},
        },
    }
end

function State.ChatRemaining(runtime, sender, now, database)
    runtime.chat = runtime.chat or { lastAcceptedByAuthor = {} }
    runtime.chat.lastAcceptedByAuthor = runtime.chat.lastAcceptedByAuthor or {}
    local key = OU.Util.NormalizeName(sender) or tostring(sender):lower()
    local last = runtime.chat.lastAcceptedByAuthor[key]
    if not last then return 0 end
    return math.max(0, State.ChatDelay(database) - (now - last))
end

function State.ChatAllowed(runtime, sender, now, database)
    local remaining = State.ChatRemaining(runtime, sender, now, database)
    if remaining > 0 then return false, "chat slow mode", remaining end
    local key = OU.Util.NormalizeName(sender) or tostring(sender):lower()
    runtime.chat.lastAcceptedByAuthor[key] = now
    return true
end

local function PushFront(array, value, limit)
    table.insert(array, 1, value)
    while #array > (limit or 100) do table.remove(array) end
end

function State.Seen(runtime, sender, id, now)
    local key = (OU.Util.NormalizeName(sender) or tostring(sender):lower()) .. "|" .. tostring(id)
    if runtime.seen[key] then return true end
    runtime.seen[key] = now
    return false
end

function State.RateAllowed(runtime, sender, messageType, now)
    local key = OU.Util.NormalizeName(sender) or tostring(sender)
    local bucket = runtime.rate[key]
    if not bucket or now - bucket.started >= 10 then
        bucket = { started = now, count = 0, lastByType = {} }
        runtime.rate[key] = bucket
    end

    if bucket.count >= 20 then return false, "sender rate limit" end
    local spacing = ({ POST = 1, LREQ = 2, LOFFER = 1, EVENT = 5, CLAIM = 1, RELEASE = 1, HELLO = 1,
        CCAND = 1, CLEASE = 1, CSUM = 5, CREQ = 1, CFAIL = 1 })[messageType] or 1
    local last = bucket.lastByType[messageType]
    if last and now - last < spacing then return false, "message rate limit" end

    bucket.count = bucket.count + 1
    bucket.lastByType[messageType] = now
    return true
end

local function Peer(runtime, sender, now)
    local key = OU.Util.NormalizeName(sender) or tostring(sender):lower()
    local peer = runtime.peers[key]
    if not peer then
        peer = { key = key, name = sender, role = "unknown", guild = "", zone = "", classFile = "" }
        runtime.peers[key] = peer
    end
    peer.name = sender
    peer.lastSeen = now
    return peer
end

function State.Apply(runtime, sender, message, now)
    if State.Seen(runtime, message.origin or sender, message.id, now) then return nil, "duplicate" end
    local allowed, reason = State.RateAllowed(runtime, sender, message.type, now)
    if not allowed then return nil, reason end

    local fields = message.fields
    if message.type == "CCAND" or message.type == "CLEASE" or message.type == "CSUM" then
        if OU.Census and OU.Census.ApplyMessage then return OU.Census.ApplyMessage(runtime, sender, message, now) end
        return nil, "census unavailable"
    end
    if message.type == "CREQ" or message.type == "CPAGE" or message.type == "CFAIL" then
        return nil, "directed census message"
    end
    local peer = Peer(runtime, sender, now)

    if message.type == "HELLO" then
        peer.role = fields[1] == "member" and "member" or "guest"
        peer.guild = OU.Util.SanitizeText(fields[2], 64)
        peer.zone = OU.Util.SanitizeText(fields[3], 48)
        peer.level = tonumber(fields[4]) or 0
        peer.classFile = OU.Util.SanitizeText(fields[5], 20)
        return { kind = "peer", value = peer }
    elseif message.type == "POST" then
        local text = OU.Util.SanitizeText(fields[1], 170)
        if text == "" then return nil, "empty post" end
        local chatAllowed, chatReason = State.ChatAllowed(runtime, sender, now, OU.DB)
        if not chatAllowed then return nil, chatReason end
        local item = { id = message.id, sender = sender, text = text, receivedAt = now }
        PushFront(runtime.feed, item, 120)
        return { kind = "post", value = item }
    elseif message.type == "LREQ" then
        local expires = tonumber(fields[3]) or 0
        if expires <= now or expires > now + 3600 then return nil, "invalid layer expiry" end
        local item = {
            id = message.id,
            sender = sender,
            zone = OU.Util.SanitizeText(fields[1], 48),
            note = OU.Util.SanitizeText(fields[2], 110),
            createdAt = now,
            expires = expires,
        }
        runtime.layers[message.id] = item
        return { kind = "layer", value = item }
    elseif message.type == "LOFFER" then
        local requestID = OU.Util.SanitizeText(fields[1], 80)
        local request = runtime.layers[requestID]
        local item = {
            id = message.id,
            sender = sender,
            requestID = requestID,
            note = OU.Util.SanitizeText(fields[2], 100),
            receivedAt = now,
        }
        if request then request.lastOffer = item end
        PushFront(runtime.feed, {
            id = message.id,
            sender = sender,
            text = L.LAYER_FEED:format(item.note ~= "" and (": " .. item.note) or ""),
            receivedAt = now,
        }, 120)
        return { kind = "offer", value = item }
    elseif message.type == "EVENT" then
        local startsAt = tonumber(fields[1]) or 0
        local title = OU.Util.SanitizeText(fields[2], 70)
        if title == "" or startsAt < now - 900 or startsAt > now + 604800 then return nil, "invalid event" end
        local item = {
            id = message.id,
            sender = sender,
            startsAt = startsAt,
            title = title,
            details = OU.Util.SanitizeText(fields[3], 100),
            receivedAt = now,
        }
        runtime.events[message.id] = item
        return { kind = "event", value = item }
    elseif message.type == "CLAIM" then
        local candidate = OU.Util.NormalizeName(fields[1])
        local expires = tonumber(fields[2]) or 0
        if not candidate or expires <= now or expires > now + 1800 then return nil, "invalid claim" end
        local existing = runtime.claims[candidate]
        if existing and existing.expires > now and OU.Util.NormalizeName(existing.sender) ~= OU.Util.NormalizeName(sender) then
            return nil, "already claimed"
        end
        local item = { candidate = candidate, sender = sender, expires = expires, id = message.id }
        runtime.claims[candidate] = item
        return { kind = "claim", value = item }
    elseif message.type == "RELEASE" then
        local candidate = OU.Util.NormalizeName(fields[1])
        local existing = candidate and runtime.claims[candidate]
        if existing and OU.Util.NormalizeName(existing.sender) == OU.Util.NormalizeName(sender) then
            runtime.claims[candidate] = nil
        end
        return { kind = "release", value = candidate }
    end

    return nil, "unhandled message"
end

function State.Prune(runtime, now)
    for id, timestamp in pairs(runtime.seen) do
        if now - timestamp > 600 then runtime.seen[id] = nil end
    end
    for key, bucket in pairs(runtime.rate) do
        if now - bucket.started > 60 then runtime.rate[key] = nil end
    end
    if runtime.chat and runtime.chat.lastAcceptedByAuthor then
        local keepFor = math.max(600, State.ChatDelay(OU.DB) * 2)
        for key, timestamp in pairs(runtime.chat.lastAcceptedByAuthor) do
            if now - timestamp > keepFor then runtime.chat.lastAcceptedByAuthor[key] = nil end
        end
    end
    for id, request in pairs(runtime.layers) do
        if request.expires <= now then runtime.layers[id] = nil end
    end
    for id, event in pairs(runtime.events) do
        if event.startsAt < now - 7200 then runtime.events[id] = nil end
    end
    for candidate, claim in pairs(runtime.claims) do
        if claim.expires <= now then runtime.claims[candidate] = nil end
    end
    for key, peer in pairs(runtime.peers) do
        if now - (peer.lastSeen or 0) > 900 then runtime.peers[key] = nil end
    end
    if OU.Census and OU.Census.Prune then OU.Census.Prune(runtime, now) end
end

function State.ContactStatus(database, runtime, name, now)
    local key = OU.Util.NormalizeName(name)
    if not key then return "invalid" end
    if database.recruiting.doNotContact[key] then return "do-not-contact" end

    local claim = runtime.claims[key]
    if claim and claim.expires > now then return "claimed", claim end

    local contacted = tonumber(database.recruiting.contacted[key]) or 0
    local cooldown = math.max(1, tonumber(database.recruiting.cooldownMinutes) or 30) * 60
    if now - contacted < cooldown then return "cooldown", cooldown - (now - contacted) end
    return "available"
end

function State.MarkContacted(database, name, now)
    local key = OU.Util.NormalizeName(name)
    if not key then return false end
    database.recruiting.contacted[key] = now
    return true
end

State.DEFAULTS = DEFAULTS
State.CHAT_DELAY_DEFAULT = CHAT_DELAY_DEFAULT
State.CHAT_DELAY_MIN = CHAT_DELAY_MIN
State.CHAT_DELAY_MAX = CHAT_DELAY_MAX
