local _, OU = ...
local L = OU.L

local State = {}
OU.State = State

local SCHEMA_VERSION = 2
local PRODUCTION_GUILD_DEFAULTS = { "OLYMPUS" }
local ROOT_GUILD_KEY = assert(OU.Util.NormalizeGuild(PRODUCTION_GUILD_DEFAULTS[1]))
local VALID_POINTS = {
    TOPLEFT = true, TOP = true, TOPRIGHT = true,
    LEFT = true, CENTER = true, RIGHT = true,
    BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true,
}

local LIMITS = {
    BRIDGES = 16,
    PARTICIPATING_GUILDS = 32,
    RECRUITING_CONTACTED = 512,
    DO_NOT_CONTACT = 2000,
    KNOWN_PLAYERS = 2000,
    PEERS = 256,
    ORIGIN_RATE = 256,
    TRANSPORT_RATE = 256,
    CHAT_AUTHORS = 512,
    FEED = 120,
    LAYERS = 128,
    EVENTS = 128,
    CLAIMS = 256,
    DEDUPE = 4096,
    DYNAMIC_BYTES = 512 * 1024,
    GUILD_GOVERNANCE = 64,
    GUILD_CANDIDATE_TTL = 30 * 86400,
    RECRUITING_RETENTION = 30 * 86400,
    PEER_TTL = 900,
    RATE_TTL = 60,
    DEDUPE_TTL = 600,
}

local CHAT_DELAY_DEFAULT = 30
local CHAT_DELAY_MIN = 5
local CHAT_DELAY_MAX = 300

local function FiniteNumber(value)
    return type(value) == "number" and not (issecretvalue and issecretvalue(value))
        and value == value and value ~= math.huge and value ~= -math.huge
end

local function BooleanOr(value, fallback)
    if type(value) == "boolean" and not (issecretvalue and issecretvalue(value)) then return value end
    return fallback
end

local function IntegerIn(value, low, high, fallback)
    if not FiniteNumber(value) then return fallback end
    if value ~= math.floor(value) then return fallback end
    if value < low or value > high then return fallback end
    return value
end

local function NormalizedChatDelay(value)
    return IntegerIn(value, CHAT_DELAY_MIN, CHAT_DELAY_MAX, CHAT_DELAY_DEFAULT)
end

local function SortedKeys(map)
    local keys = {}
    for key in pairs(type(map) == "table" and map or {}) do
        if type(key) == "string" then keys[#keys + 1] = key end
    end
    table.sort(keys)
    return keys
end

local function MapCount(map)
    local count = 0
    for _ in pairs(type(map) == "table" and map or {}) do count = count + 1 end
    return count
end

local function SanitizeDisplayMap(input, normalizer, cap, maxBytes)
    local candidates = {}
    if type(input) == "table" then
        for rawKey, rawValue in pairs(input) do
            local display
            if OU.Util.IsPlainString(rawValue) then display = OU.Util.SanitizeText(rawValue, maxBytes)
            elseif type(rawValue) == "boolean" and not (issecretvalue and issecretvalue(rawValue))
                and rawValue == true and type(rawKey) == "string" then display = OU.Util.SanitizeText(rawKey, maxBytes) end
            local key = display ~= "" and normalizer(display) or nil
            if key then candidates[#candidates + 1] = { key = key, display = display } end
        end
    end
    table.sort(candidates, function(left, right)
        if left.key ~= right.key then return left.key < right.key end
        return left.display < right.display
    end)
    local result = {}
    for _, item in ipairs(candidates) do
        if not result[item.key] and MapCount(result) < cap then result[item.key] = item.display end
    end
    return result
end

local function DefaultParticipatingGuilds()
    local result = {}
    for _, display in ipairs(PRODUCTION_GUILD_DEFAULTS) do
        local key = OU.Util.NormalizeGuild(display)
        if key then result[key] = display end
    end
    return result
end

local GOVERNANCE_STATES = { pending = true, approved = true, denied = true, conflict = true }
local GOVERNANCE_SOURCES = { ["local-officer"] = true, ["configured-connector"] = true }

local function DecisionToken(value)
    return OU.Util.IsPlainString(value) and value ~= "" and #value <= 40 and value:match("^[a-z0-9%-]+$") ~= nil
end

local function SanitizedGovernanceRecord(rawKey, raw, now)
    if type(raw) ~= "table" or not OU.Util.IsPlainString(rawKey) or not OU.Util.IsPlainString(raw.displayName)
        or not OU.Util.IsPlainString(raw.state) then return nil end
    local display = OU.Util.SanitizeText(raw.displayName, 32)
    local key = OU.Util.NormalizeGuild(display)
    if not key or key == ROOT_GUILD_KEY or key ~= OU.Util.NormalizeGuild(rawKey) or not GOVERNANCE_STATES[raw.state] then return nil end
    local firstSeenAt = FiniteNumber(raw.firstSeenAt) and math.max(0, math.floor(raw.firstSeenAt)) or nil
    local lastSeenAt = FiniteNumber(raw.lastSeenAt) and math.max(0, math.floor(raw.lastSeenAt)) or nil
    if not firstSeenAt or not lastSeenAt or firstSeenAt > lastSeenAt or lastSeenAt > now + 60 then return nil end
    if (raw.state == "pending" or raw.state == "conflict") and now - lastSeenAt > LIMITS.GUILD_CANDIDATE_TTL then return nil end
    local evidenceMask = IntegerIn(raw.evidenceMask, 0, 3, 0)
    local observations = IntegerIn(raw.observations, 0, 255, 0)
    local deniedEvidenceMask = IntegerIn(raw.deniedEvidenceMask, 0, 3, 0)
    local generation = IntegerIn(raw.generation, 0, 2147483647, 0)
    local decisionId = DecisionToken(raw.decisionId) and raw.decisionId or nil
    local decidedAt = FiniteNumber(raw.decidedAt) and math.max(0, math.floor(raw.decidedAt)) or nil
    local sourceClass = OU.Util.IsPlainString(raw.sourceClass) and GOVERNANCE_SOURCES[raw.sourceClass]
        and raw.sourceClass or nil
    if (generation > 0 or raw.state == "approved" or raw.state == "denied" or raw.state == "conflict")
        and (generation < 1 or not decisionId or not decidedAt or not sourceClass) then return nil end
    return {
        displayName = display,
        state = raw.state,
        firstSeenAt = firstSeenAt,
        lastSeenAt = lastSeenAt,
        evidenceMask = evidenceMask,
        observations = observations,
        deniedEvidenceMask = deniedEvidenceMask,
        generation = generation,
        decisionId = decisionId,
        decidedAt = decidedAt,
        sourceClass = sourceClass,
    }
end

local function SanitizeGovernance(input, now)
    local durable, transient = {}, {}
    for rawKey, raw in pairs(type(input) == "table" and input or {}) do
        local record = SanitizedGovernanceRecord(rawKey, raw, now)
        if record then
            local item = { key = OU.Util.NormalizeGuild(record.displayName), record = record }
            if record.state == "approved" or record.state == "denied" then durable[#durable + 1] = item
            else transient[#transient + 1] = item end
        end
    end
    local function SortRecords(left, right)
        if left.record.lastSeenAt ~= right.record.lastSeenAt then return left.record.lastSeenAt > right.record.lastSeenAt end
        if left.key ~= right.key then return left.key < right.key end
        local leftTie = table.concat({ left.record.displayName, left.record.state, left.record.decisionId or "",
            left.record.sourceClass or "" }, "|")
        local rightTie = table.concat({ right.record.displayName, right.record.state, right.record.decisionId or "",
            right.record.sourceClass or "" }, "|")
        return leftTie < rightTie
    end
    table.sort(durable, SortRecords)
    table.sort(transient, SortRecords)
    local result = {}
    for _, list in ipairs({ durable, transient }) do
        for _, item in ipairs(list) do
            if MapCount(result) < LIMITS.GUILD_GOVERNANCE and not result[item.key] then result[item.key] = item.record end
        end
    end
    return result
end

function State._ProjectParticipatingGuilds(governance)
    local result = DefaultParticipatingGuilds()
    local keys = SortedKeys(governance)
    for _, key in ipairs(keys) do
        local record = governance[key]
        if record.state == "approved" then
            if MapCount(result) < LIMITS.PARTICIPATING_GUILDS then result[key] = record.displayName
            else record.state = "conflict" end
        end
    end
    result[ROOT_GUILD_KEY] = PRODUCTION_GUILD_DEFAULTS[1]
    return result
end

local function SanitizeTimestampMap(input, cap, retainFor, now)
    local candidates = {}
    for rawKey, rawTimestamp in pairs(type(input) == "table" and input or {}) do
        local key = type(rawKey) == "string" and OU.Util.NormalizeName(rawKey) or nil
        if key and FiniteNumber(rawTimestamp) then
            local timestamp = math.max(0, math.floor(rawTimestamp))
            if timestamp <= now + 60 and now - timestamp <= retainFor then
                candidates[#candidates + 1] = { key = key, timestamp = timestamp }
            end
        end
    end
    table.sort(candidates, function(a, b)
        if a.timestamp ~= b.timestamp then return a.timestamp > b.timestamp end
        return a.key < b.key
    end)
    local result = {}
    for _, item in ipairs(candidates) do
        if not result[item.key] and MapCount(result) < cap then result[item.key] = item.timestamp end
    end
    return result
end

local function SanitizeBooleanMembership(input, cap)
    local keys = {}
    for rawKey, value in pairs(type(input) == "table" and input or {}) do
        local plainTrue = type(value) == "boolean" and not (issecretvalue and issecretvalue(value)) and value == true
        local key = plainTrue and type(rawKey) == "string" and OU.Util.NormalizeName(rawKey) or nil
        if key then keys[#keys + 1] = key end
    end
    table.sort(keys)
    local result, previous = {}, nil
    for _, key in ipairs(keys) do
        if key ~= previous and MapCount(result) < cap then result[key] = true end
        previous = key
    end
    return result
end

local function SanitizeWindow(input)
    if type(input) ~= "table" or not OU.Util.IsPlainString(input.point) or not VALID_POINTS[input.point]
        or not FiniteNumber(input.x) or not FiniteNumber(input.y) then
        return { point = "CENTER", x = 0, y = 0 }
    end
    return {
        point = input.point,
        x = math.max(-4096, math.min(4096, input.x)),
        y = math.max(-4096, math.min(4096, input.y)),
    }
end

function State.EnsureDatabase(database)
    local source = type(database) == "table" and database or {}
    local now = OU.Util.Now()
    local cooldown = IntegerIn(type(source.recruiting) == "table" and source.recruiting.cooldownMinutes or nil,
        1, 1440, 30)
    local governance = SanitizeGovernance(source.guildGovernance, now)
    local migrated = {
        schemaVersion = SCHEMA_VERSION,
        enabled = BooleanOr(source.enabled, true),
        guestMode = BooleanOr(source.guestMode, false),
        notifications = BooleanOr(source.notifications, true),
        bridgeMode = BooleanOr(source.bridgeMode, false),
        bridges = SanitizeDisplayMap(source.bridges, OU.Util.NormalizeName, LIMITS.BRIDGES, 64),
        participatingGuilds = State._ProjectParticipatingGuilds(governance),
        guildGovernance = governance,
        chat = {
            delaySeconds = NormalizedChatDelay(type(source.chat) == "table" and source.chat.delaySeconds or nil),
            muteNonOlympus = BooleanOr(type(source.chat) == "table" and source.chat.muteNonOlympus or nil, false),
            knownPlayers = type(source.chat) == "table" and source.chat.knownPlayers or {},
        },
        window = SanitizeWindow(source.window),
        recruiting = {
            cooldownMinutes = cooldown,
            contacted = SanitizeTimestampMap(type(source.recruiting) == "table" and source.recruiting.contacted or {},
                LIMITS.RECRUITING_CONTACTED, math.min(LIMITS.RECRUITING_RETENTION, cooldown * 60), now),
            doNotContact = SanitizeBooleanMembership(type(source.recruiting) == "table" and source.recruiting.doNotContact or {},
                LIMITS.DO_NOT_CONTACT),
        },
    }
    if OU.ChatGuard and OU.ChatGuard.SanitizeDatabase then OU.ChatGuard.SanitizeDatabase(migrated) end
    return migrated
end

function State.ChatDelay(database)
    return NormalizedChatDelay(database and database.chat and database.chat.delaySeconds)
end

function State.SetChatDelay(database, value)
    local delay = IntegerIn(tonumber(value), CHAT_DELAY_MIN, CHAT_DELAY_MAX, nil)
    if not delay then return false, State.ChatDelay(database) end
    database.chat = type(database.chat) == "table" and database.chat or { muteNonOlympus = false, knownPlayers = {} }
    local changed = database.chat.delaySeconds ~= delay
    database.chat.delaySeconds = delay
    return true, delay, changed
end

function State.SetWindowPosition(database, point, x, y)
    if type(database) ~= "table" then return false end
    database.window = SanitizeWindow({ point = point, x = x, y = y })
    return true
end

function State.AddBridge(database, name)
    if not OU.Util.IsPlainString(name) then return false, L.ERROR_CONNECTOR_NAME end
    name = OU.Util.SanitizeText(name, 64)
    local key = OU.Util.NormalizeName(name)
    if not key then return false, L.ERROR_CONNECTOR_NAME end
    database.bridges = type(database.bridges) == "table" and database.bridges or {}
    if not database.bridges[key] and MapCount(database.bridges) >= LIMITS.BRIDGES then return false, L.ERROR_CONNECTOR_LIMIT end
    database.bridges[key] = name
    return true
end

function State.RemoveBridge(database, name)
    if not OU.Util.IsPlainString(name) then return false, L.ERROR_CONNECTOR_MISSING end
    local key = OU.Util.NormalizeName(name)
    if not key or type(database.bridges) ~= "table" or not database.bridges[key] then
        return false, L.ERROR_CONNECTOR_MISSING
    end
    database.bridges[key] = nil
    return true
end

function State.ParticipatingGuilds(database)
    local values = {}
    for _, display in pairs(type(database) == "table" and type(database.participatingGuilds) == "table"
        and database.participatingGuilds or {}) do values[#values + 1] = display end
    table.sort(values, function(a, b) return tostring(a):lower() < tostring(b):lower() end)
    return values
end

function State.SetDoNotContact(database, name, blocked)
    if not OU.Util.IsPlainString(name) then return false, "invalid" end
    local key = OU.Util.NormalizeName(name)
    if not key then return false, "invalid" end
    local map = database.recruiting.doNotContact
    if blocked then
        if not map[key] and MapCount(map) >= LIMITS.DO_NOT_CONTACT then return false, "full" end
        map[key] = true
    else
        map[key] = nil
    end
    return true
end

function State.NewRuntime()
    return {
        peers = {}, feed = {}, layers = {}, events = {}, claims = {}, seen = {}, rate = {}, transportRate = {},
        receive = { types = {} }, forward = nil,
        chat = { lastAcceptedByAuthor = {} },
        census = {
            leases = {}, candidates = {}, summaries = {}, routes = {}, assemblies = {}, cooldowns = {},
            localCapture = { state = "idle" }, pageRate = {},
        },
    }
end

local function PruneTimestampValues(map, now, ttl)
    if type(map) ~= "table" then return end
    for key, timestamp in pairs(map) do
        if not FiniteNumber(timestamp) or timestamp > now + 60 or now - timestamp > ttl then map[key] = nil end
    end
end

local function PruneRateMap(map, now)
    if type(map) ~= "table" then return end
    for key, bucket in pairs(map) do
        if type(bucket) ~= "table" or not FiniteNumber(bucket.started) or now - bucket.started >= LIMITS.RATE_TTL then
            map[key] = nil
        end
    end
end

local function EnsureMapSlot(map, key, cap, prune)
    if map[key] ~= nil then return true end
    if prune then prune() end
    return MapCount(map) < cap
end

function State.ChatRemaining(runtime, sender, now, database)
    runtime.chat = type(runtime.chat) == "table" and runtime.chat or { lastAcceptedByAuthor = {} }
    runtime.chat.lastAcceptedByAuthor = type(runtime.chat.lastAcceptedByAuthor) == "table" and runtime.chat.lastAcceptedByAuthor or {}
    local key = OU.Util.NormalizeName(sender)
    if not key then return State.ChatDelay(database) end
    local last = runtime.chat.lastAcceptedByAuthor[key]
    if not FiniteNumber(last) then return 0 end
    return math.max(0, State.ChatDelay(database) - (now - last))
end

function State.ChatAllowed(runtime, sender, now, database)
    local remaining = State.ChatRemaining(runtime, sender, now, database)
    if remaining > 0 then return false, "chat slow mode", remaining end
    local key = OU.Util.NormalizeName(sender)
    if not key then return false, "invalid author" end
    local map = runtime.chat.lastAcceptedByAuthor
    local keepFor = math.max(600, State.ChatDelay(database) * 2)
    if not EnsureMapSlot(map, key, LIMITS.CHAT_AUTHORS, function() PruneTimestampValues(map, now, keepFor) end) then
        return false, "chat author capacity"
    end
    map[key] = now
    return true
end

local function PushFront(array, value, limit)
    table.insert(array, 1, value)
    while #array > limit do table.remove(array) end
end

local function SeenKey(sender, id)
    local origin = OU.Util.NormalizeName(sender)
    if not origin then return nil end
    return origin .. "|" .. tostring(id)
end

function State.IsSeen(runtime, sender, id)
    local key = SeenKey(sender, id)
    return key ~= nil and runtime.seen[key] ~= nil
end

function State.RememberSeen(runtime, sender, id, now)
    local key = SeenKey(sender, id)
    if not key then return false end
    if runtime.seen[key] ~= nil then return false end
    PruneTimestampValues(runtime.seen, now, LIMITS.DEDUPE_TTL)
    if MapCount(runtime.seen) >= LIMITS.DEDUPE then return false end
    runtime.seen[key] = now
    return true
end

function State.Seen(runtime, sender, id, now)
    if State.IsSeen(runtime, sender, id) then return true end
    return not State.RememberSeen(runtime, sender, id, now)
end

local TYPE_SPACING = {
    POST = 1, LREQ = 2, LOFFER = 1, EVENT = 5, CLAIM = 1, RELEASE = 1, HELLO = 1,
    CCAND = 1, CLEASE = 1, CSUM = 5, CREQ = 1, CPAGE = 0, CFAIL = 1,
}

local function KeyedRateAllowed(map, key, cap, now, limit, messageType, spacing)
    if not key then return false, "invalid rate identity" end
    if not EnsureMapSlot(map, key, cap, function() PruneRateMap(map, now) end) then return false, "rate capacity" end
    local bucket = map[key]
    if type(bucket) ~= "table" or not FiniteNumber(bucket.started) or now - bucket.started >= 10 then
        bucket = { started = now, count = 0, lastByType = {} }
        map[key] = bucket
    end
    if bucket.count >= limit then return false, "rate limit" end
    local last = bucket.lastByType[messageType]
    if FiniteNumber(last) and now - last < spacing then return false, "message rate limit" end
    bucket.count = bucket.count + 1
    bucket.lastByType[messageType] = now
    return true
end

local function WindowAllowed(bucket, now, limit)
    if type(bucket) ~= "table" or not FiniteNumber(bucket.started) or now - bucket.started >= 10 then
        bucket = { started = now, count = 0 }
    end
    if bucket.count >= limit then return false, bucket end
    bucket.count = bucket.count + 1
    return true, bucket
end

function State.RateAllowed(runtime, sender, messageType, now)
    runtime.rate = type(runtime.rate) == "table" and runtime.rate or {}
    local key = OU.Util.NormalizeName(sender)
    return KeyedRateAllowed(runtime.rate, key, LIMITS.ORIGIN_RATE, now, 20, messageType, TYPE_SPACING[messageType] or 1)
end

local function TypeBudget(messageType)
    if messageType == "POST" then return "post", 20 end
    if messageType == "HELLO" then return "hello", 40 end
    if messageType == "CPAGE" then return "census-pages", 80 end
    if messageType == "GDEC" then return "governance", 20 end
    if messageType == "CCAND" or messageType == "CLEASE" or messageType == "CSUM"
        or messageType == "CREQ" or messageType == "CFAIL" then return "census-control", 80 end
    return "coordination", 40
end

local function Estimate(value, visited, ceiling)
    local kind = type(value)
    if kind == "string" then return #value + 16 end
    if kind == "number" or kind == "boolean" then return 16 end
    if kind ~= "table" or visited[value] then return 0 end
    visited[value] = true
    local total = 40
    for key, item in pairs(value) do
        total = total + Estimate(key, visited, ceiling) + Estimate(item, visited, ceiling) + 16
        if total > ceiling then return total end
    end
    return total
end

function State.DynamicBytes(runtime)
    return Estimate(runtime, {}, LIMITS.DYNAMIC_BYTES)
end

local function CapacityAllowed(runtime, message, now)
    if State.DynamicBytes(runtime) >= LIMITS.DYNAMIC_BYTES then return false, "memory capacity" end
    local messageType, id = message.type, message.id
    if messageType == "HELLO" and not runtime.peers[OU.Util.NormalizeName(message.origin)] then
        for key, peer in pairs(runtime.peers) do
            if type(peer) ~= "table" or not FiniteNumber(peer.lastSeen) or now - peer.lastSeen > LIMITS.PEER_TTL then runtime.peers[key] = nil end
        end
        if MapCount(runtime.peers) >= LIMITS.PEERS then return false, "peer capacity" end
    elseif messageType == "LREQ" and not runtime.layers[id] and MapCount(runtime.layers) >= LIMITS.LAYERS then
        return false, "layer capacity"
    elseif messageType == "EVENT" and not runtime.events[id] and MapCount(runtime.events) >= LIMITS.EVENTS then
        return false, "event capacity"
    elseif messageType == "CLAIM" then
        local candidate = OU.Util.NormalizeName(message.fields and message.fields[1])
        if candidate and not runtime.claims[candidate] and MapCount(runtime.claims) >= LIMITS.CLAIMS then
            return false, "claim capacity"
        end
    end
    return true
end

function State.AdmitInbound(runtime, context, message, now)
    if type(runtime) ~= "table" or type(message) ~= "table" then return false, "invalid admission" end
    local origin = OU.Util.NormalizeName(message.origin)
    local transport = OU.Util.NormalizeName(context and context.transportSender)
    if not origin or not transport then return false, "invalid identity" end
    if State.IsSeen(runtime, origin, message.id) then return false, "duplicate" end

    local allowed, reason = State.RateAllowed(runtime, origin, message.type, now)
    if not allowed then return false, reason end
    runtime.transportRate = type(runtime.transportRate) == "table" and runtime.transportRate or {}
    allowed, reason = KeyedRateAllowed(runtime.transportRate, transport, LIMITS.TRANSPORT_RATE, now, 80,
        message.type, 0)
    if not allowed then return false, "transport " .. reason end

    runtime.receive = type(runtime.receive) == "table" and runtime.receive or { types = {} }
    runtime.receive.types = type(runtime.receive.types) == "table" and runtime.receive.types or {}
    allowed, runtime.receive.global = WindowAllowed(runtime.receive.global, now, 160)
    if not allowed then return false, "receiver rate limit" end
    local group, limit = TypeBudget(message.type)
    allowed, runtime.receive.types[group] = WindowAllowed(runtime.receive.types[group], now, limit)
    if not allowed then return false, "message type rate limit" end
    allowed, reason = CapacityAllowed(runtime, message, now)
    if not allowed then return false, reason end
    if not State.RememberSeen(runtime, origin, message.id, now) then return false, "dedupe capacity" end
    return true
end

function State.ForwardAllowed(runtime, now)
    local allowed
    allowed, runtime.forward = WindowAllowed(runtime.forward, now, 160)
    return allowed
end

local function Peer(runtime, author, context, now)
    local key = OU.Util.NormalizeName(author)
    if not key then return nil end
    local peer = runtime.peers[key]
    if not peer then
        if MapCount(runtime.peers) >= LIMITS.PEERS then return nil end
        peer = { key = key, name = author, role = "unknown", guild = "", zone = "", classFile = "" }
        runtime.peers[key] = peer
    end
    peer.name = author
    peer.lastSeen = now
    if context then
        peer.lastTransport = context.transportSender
        peer.lastDistribution = context.distribution
        peer.lastHops = context.hops
    end
    return peer
end

function State.Apply(runtime, sender, message, now, context, admitted)
    local author = context and (message.origin or sender) or sender
    context = context or { origin = author, transportSender = sender, distribution = "LOCAL", hops = message.hops or 0 }
    if not admitted then
        local allowed, reason = State.AdmitInbound(runtime, context, message, now)
        if not allowed then return nil, reason end
    end

    local fields = message.fields
    if message.type == "CCAND" or message.type == "CLEASE" or message.type == "CSUM" then
        if OU.Census and OU.Census.ApplyMessage then return OU.Census.ApplyMessage(runtime, sender, message, now) end
        return nil, "census unavailable"
    end
    if message.type == "CREQ" or message.type == "CPAGE" or message.type == "CFAIL" then
        return nil, "directed census message"
    end
    local peer = Peer(runtime, author, context, now)
    if not peer then return nil, "peer capacity" end

    if message.type == "HELLO" then
        peer.role = fields[1] == "member" and OU.Util.IsParticipatingGuild(fields[2]) and "member" or "guest"
        peer.guild = OU.Util.SanitizeText(fields[2], 64)
        peer.zone = OU.Util.SanitizeText(fields[3], 48)
        peer.level = tonumber(fields[4]) or 0
        peer.classFile = OU.Util.SanitizeText(fields[5], 20)
        return { kind = "peer", value = peer }
    elseif message.type == "POST" then
        local text = OU.Util.SanitizeText(fields[1], 170)
        if text == "" then return nil, "empty post" end
        local chatAllowed, chatReason = State.ChatAllowed(runtime, author, now, OU.DB)
        if not chatAllowed then return nil, chatReason end
        local item = { id = message.id, sender = author, text = text, receivedAt = now,
            transportSender = context.transportSender, distribution = context.distribution, hops = context.hops }
        PushFront(runtime.feed, item, LIMITS.FEED)
        return { kind = "post", value = item }
    elseif message.type == "LREQ" then
        local expires = tonumber(fields[3]) or 0
        if expires <= now or expires > now + 3600 then return nil, "invalid layer expiry" end
        if not runtime.layers[message.id] and MapCount(runtime.layers) >= LIMITS.LAYERS then return nil, "layer capacity" end
        local item = { id = message.id, sender = author, zone = OU.Util.SanitizeText(fields[1], 48),
            note = OU.Util.SanitizeText(fields[2], 110), createdAt = now, expires = expires,
            transportSender = context.transportSender }
        runtime.layers[message.id] = item
        return { kind = "layer", value = item }
    elseif message.type == "LOFFER" then
        local requestID = OU.Util.SanitizeText(fields[1], 80)
        local request = runtime.layers[requestID]
        local item = { id = message.id, sender = author, requestID = requestID,
            note = OU.Util.SanitizeText(fields[2], 100), receivedAt = now, transportSender = context.transportSender }
        if request then request.lastOffer = item end
        PushFront(runtime.feed, { id = message.id, sender = author,
            text = L.LAYER_FEED:format(item.note ~= "" and (": " .. item.note) or ""), receivedAt = now,
            transportSender = context.transportSender }, LIMITS.FEED)
        return { kind = "offer", value = item }
    elseif message.type == "EVENT" then
        local startsAt = tonumber(fields[1]) or 0
        local title = OU.Util.SanitizeText(fields[2], 70)
        if title == "" or startsAt < now - 900 or startsAt > now + 604800 then return nil, "invalid event" end
        if not runtime.events[message.id] and MapCount(runtime.events) >= LIMITS.EVENTS then return nil, "event capacity" end
        local item = { id = message.id, sender = author, startsAt = startsAt, title = title,
            details = OU.Util.SanitizeText(fields[3], 100), receivedAt = now, transportSender = context.transportSender }
        runtime.events[message.id] = item
        return { kind = "event", value = item }
    elseif message.type == "CLAIM" then
        local candidate = OU.Util.NormalizeName(fields[1])
        local expires = tonumber(fields[2]) or 0
        if not candidate or expires <= now or expires > now + 1800 then return nil, "invalid claim" end
        local existing = runtime.claims[candidate]
        if existing and existing.expires > now and OU.Util.NormalizeName(existing.sender) ~= OU.Util.NormalizeName(author) then
            return nil, "already claimed"
        end
        if not existing and MapCount(runtime.claims) >= LIMITS.CLAIMS then return nil, "claim capacity" end
        local item = { candidate = candidate, sender = author, expires = expires, id = message.id,
            transportSender = context.transportSender }
        runtime.claims[candidate] = item
        return { kind = "claim", value = item }
    elseif message.type == "RELEASE" then
        local candidate = OU.Util.NormalizeName(fields[1])
        local existing = candidate and runtime.claims[candidate]
        if existing and OU.Util.NormalizeName(existing.sender) == OU.Util.NormalizeName(author) then runtime.claims[candidate] = nil end
        return { kind = "release", value = candidate }
    end
    return nil, "unhandled message"
end

function State.Prune(runtime, now)
    runtime.seen = type(runtime.seen) == "table" and runtime.seen or {}
    runtime.rate = type(runtime.rate) == "table" and runtime.rate or {}
    runtime.transportRate = type(runtime.transportRate) == "table" and runtime.transportRate or {}
    PruneTimestampValues(runtime.seen, now, LIMITS.DEDUPE_TTL)
    PruneRateMap(runtime.rate, now)
    PruneRateMap(runtime.transportRate, now)
    if type(runtime.receive) == "table" then
        if type(runtime.receive.global) == "table" and now - (runtime.receive.global.started or now) >= 60 then runtime.receive.global = nil end
        for key, bucket in pairs(type(runtime.receive.types) == "table" and runtime.receive.types or {}) do
            if type(bucket) ~= "table" or now - (bucket.started or now) >= 60 then runtime.receive.types[key] = nil end
        end
    end
    if type(runtime.forward) == "table" and now - (runtime.forward.started or now) >= 60 then runtime.forward = nil end
    if type(runtime.chat) == "table" and type(runtime.chat.lastAcceptedByAuthor) == "table" then
        PruneTimestampValues(runtime.chat.lastAcceptedByAuthor, now, math.max(600, State.ChatDelay(OU.DB) * 2))
    end
    for id, request in pairs(type(runtime.layers) == "table" and runtime.layers or {}) do
        if type(request) ~= "table" or not FiniteNumber(request.expires) or request.expires <= now then runtime.layers[id] = nil end
    end
    for id, event in pairs(type(runtime.events) == "table" and runtime.events or {}) do
        if type(event) ~= "table" or not FiniteNumber(event.startsAt) or event.startsAt < now - 7200 then runtime.events[id] = nil end
    end
    for candidate, claim in pairs(type(runtime.claims) == "table" and runtime.claims or {}) do
        if type(claim) ~= "table" or not FiniteNumber(claim.expires) or claim.expires <= now then runtime.claims[candidate] = nil end
    end
    for key, peer in pairs(type(runtime.peers) == "table" and runtime.peers or {}) do
        if type(peer) ~= "table" or not FiniteNumber(peer.lastSeen) or now - peer.lastSeen > LIMITS.PEER_TTL then runtime.peers[key] = nil end
    end
    while #runtime.feed > LIMITS.FEED do table.remove(runtime.feed) end
    if type(OU.GuildTrust) == "table" and type(OU.GuildTrust.Prune) == "function" and type(OU.DB) == "table" then
        OU.GuildTrust.Prune(OU.DB, now)
    end
    if OU.Census and OU.Census.Prune then OU.Census.Prune(runtime, now) end
    if OU.ChatGuard and OU.ChatGuard.PruneRuntime then OU.ChatGuard.PruneRuntime(now) end
end

function State.ContactStatus(database, runtime, name, now)
    local key = OU.Util.NormalizeName(name)
    if not key then return "invalid" end
    if database.recruiting.doNotContact[key] then return "do-not-contact" end
    local claim = runtime.claims[key]
    if claim and claim.expires > now then return "claimed", claim end
    local contacted = tonumber(database.recruiting.contacted[key]) or 0
    local cooldown = database.recruiting.cooldownMinutes * 60
    if now - contacted < cooldown then return "cooldown", cooldown - (now - contacted) end
    return "available"
end

function State.MarkContacted(database, name, now)
    if not OU.Util.IsPlainString(name) then return false end
    local key = OU.Util.NormalizeName(name)
    if not key or not FiniteNumber(now) then return false end
    local map = database.recruiting.contacted
    local retainFor = math.min(LIMITS.RECRUITING_RETENTION, database.recruiting.cooldownMinutes * 60)
    PruneTimestampValues(map, now, retainFor)
    if not map[key] and MapCount(map) >= LIMITS.RECRUITING_CONTACTED then return false end
    map[key] = math.max(0, math.floor(now))
    return true
end

State.DEFAULTS = {
    schemaVersion = SCHEMA_VERSION, enabled = true, guestMode = false, notifications = true, bridgeMode = false,
    bridges = {}, participatingGuilds = DefaultParticipatingGuilds(), guildGovernance = {},
    chat = { delaySeconds = CHAT_DELAY_DEFAULT, muteNonOlympus = false, knownPlayers = {} },
    window = { point = "CENTER", x = 0, y = 0 },
    recruiting = { cooldownMinutes = 30, contacted = {}, doNotContact = {} },
}
State.SCHEMA_VERSION = SCHEMA_VERSION
State.PRODUCTION_GUILD_DEFAULTS = PRODUCTION_GUILD_DEFAULTS
State.ROOT_GUILD_KEY = ROOT_GUILD_KEY
State.LIMITS = LIMITS
State.CHAT_DELAY_DEFAULT = CHAT_DELAY_DEFAULT
State.CHAT_DELAY_MIN = CHAT_DELAY_MIN
State.CHAT_DELAY_MAX = CHAT_DELAY_MAX
State._Test = { FiniteNumber = FiniteNumber, MapCount = MapCount, SanitizeWindow = SanitizeWindow,
    TypeBudget = TypeBudget, CapacityAllowed = CapacityAllowed, DecisionToken = DecisionToken,
    SanitizeGovernance = SanitizeGovernance }
