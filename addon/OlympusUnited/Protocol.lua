local _, OU = ...

local Protocol = {}
OU.Protocol = Protocol

Protocol.PREFIX = "OLYUNITED"
Protocol.VERSION = 1
Protocol.MAX_PAYLOAD = 250

local SEP = ";"

local VALID_TYPES = {
    HELLO = true,
    POST = true,
    LREQ = true,
    LOFFER = true,
    EVENT = true,
    CLAIM = true,
    RELEASE = true,
    CCAND = true,
    CLEASE = true,
    CSUM = true,
    CREQ = true,
    CPAGE = true,
    CFAIL = true,
    GDEC = true,
}

local function Escape(value)
    value = tostring(value or "")
    value = value:gsub("%%", "%%25")
    value = value:gsub(";", "%%3B")
    return value
end

local function Unescape(value)
    return value:gsub("%%(%x%x)", function(hex)
        return string.char(tonumber(hex, 16))
    end)
end

local function Split(payload)
    local fields, start = {}, 1
    for index = 1, #payload + 1 do
        if index > #payload or payload:sub(index, index) == SEP then
            fields[#fields + 1] = Unescape(payload:sub(start, index - 1))
            start = index + 1
        end
    end
    return fields
end

local CENSUS_TYPES = { CCAND = true, CLEASE = true, CSUM = true, CREQ = true, CPAGE = true, CFAIL = true }
local GOVERNANCE_ACTIONS = { approve = true, deny = true, review = true }
local FAILURE_REASONS = { busy = true, cooldown = true, snapshot = true, unavailable = true, expired = true }
local function EncodedAtMost(value, limit)
    return type(value) == "string" and #Escape(value) <= limit
end
local function UInt(value, maximum)
    local text = tostring(value or "")
    local number = tonumber(text)
    return text:match("^%d+$") and number and number <= maximum and tostring(math.floor(number)) == text
end
local function Token(value, limit)
    return type(value) == "string" and #value <= limit and value:match("^[a-z0-9%-]+$") ~= nil
end
local function ValidateCensus(messageType, id, fields, origin)
    if not Token(id, 40) or not EncodedAtMost(origin, 48) then return nil, "invalid census envelope" end
    local n = #fields
    if messageType == "CCAND" then
        if n ~= 3 or not EncodedAtMost(fields[1], 32) or not EncodedAtMost(fields[2], 32) or not UInt(fields[3], 9999999999) then return nil, "invalid candidate" end
    elseif messageType == "CLEASE" then
        if n ~= 4 or not EncodedAtMost(fields[1], 32) or not UInt(fields[2], 9999999999) or not UInt(fields[3], 9999999999) or not UInt(fields[4], 999999) then return nil, "invalid lease" end
    elseif messageType == "CSUM" then
        if n ~= 8 or not EncodedAtMost(fields[1], 32) or not EncodedAtMost(fields[2], 32)
            or not UInt(fields[3], 9999999999) or not UInt(fields[4], 999999) or not Token(fields[5], 20)
            or not UInt(fields[6], 9999999999) or not UInt(fields[7], 1000)
            or not (fields[8] == "U" or UInt(fields[8], 1000)) then return nil, "invalid summary" end
    elseif messageType == "CREQ" then
        if n ~= 4 or not Token(fields[1], 20) or not EncodedAtMost(fields[2], 32) or not Token(fields[3], 20)
            or not EncodedAtMost(fields[4], 48) then return nil, "invalid request" end
    elseif messageType == "CPAGE" then
        if n < 4 or not Token(fields[1], 20) or not UInt(fields[2], 1000) or tonumber(fields[2]) < 1
            or not UInt(fields[3], 1000) or tonumber(fields[3]) < 1 or not UInt(fields[4], 1000) then return nil, "invalid page" end
        for index = 5, n do if not EncodedAtMost(fields[index], 48) then return nil, "invalid page name" end end
    elseif messageType == "CFAIL" then
        if n ~= 2 or not Token(fields[1], 20) or not Token(fields[2], 12) or not FAILURE_REASONS[fields[2]] then
            return nil, "invalid failure"
        end
    end
    return true
end

local function ValidateGovernance(id, fields, origin)
    if not Token(id, 40) or not EncodedAtMost(origin, 48) or #fields ~= 7 then
        return nil, "invalid governance envelope"
    end
    local rootKey, targetKey, targetDisplay, action, generation, previous, decidedAt =
        fields[1], fields[2], fields[3], fields[4], fields[5], fields[6], fields[7]
    if rootKey ~= "olympus" or not EncodedAtMost(targetKey, 32) or not EncodedAtMost(targetDisplay, 32)
        or OU.Util.NormalizeGuild(targetKey) ~= targetKey or OU.Util.NormalizeGuild(targetDisplay) ~= targetKey
        or targetKey == "olympus" or not GOVERNANCE_ACTIONS[action]
        or not UInt(generation, 2147483647) or tonumber(generation) < 1
        or not (previous == "-" or Token(previous, 40))
        or not UInt(decidedAt, 9999999999) then
        return nil, "invalid governance decision"
    end
    return true
end

function Protocol.Encode(messageType, id, fields, origin, hops)
    if not VALID_TYPES[messageType] then return nil, "unknown message type" end
    if type(id) ~= "string" or id == "" then return nil, "message id is required" end

    origin = origin or (OU.Identity and OU.Identity.name) or "unknown"
    origin = OU.Util.SanitizeText(origin, 64)
    hops = math.max(0, math.min(2, tonumber(hops) or 0))

    fields = fields or {}
    if CENSUS_TYPES[messageType] then
        local ok, err = ValidateCensus(messageType, id, fields, origin)
        if not ok then return nil, err end
    elseif messageType == "GDEC" then
        local ok, err = ValidateGovernance(id, fields, origin)
        if not ok then return nil, err end
    end

    local parts = { tostring(Protocol.VERSION), messageType, Escape(id), Escape(origin), tostring(hops) }
    for _, value in ipairs(fields) do parts[#parts + 1] = Escape(value) end
    local payload = table.concat(parts, SEP)
    if #payload > Protocol.MAX_PAYLOAD then return nil, "message is too long" end
    return payload
end

function Protocol.Decode(payload)
    if type(payload) ~= "string" or payload == "" or #payload > Protocol.MAX_PAYLOAD then
        return nil, "invalid payload"
    end

    local fields = Split(payload)
    local version = tonumber(fields[1])
    local messageType = fields[2]
    local id = fields[3]
    if version ~= Protocol.VERSION then return nil, "unsupported protocol version" end
    if not VALID_TYPES[messageType] then return nil, "unknown message type" end
    if not id or id == "" or #id > 80 then return nil, "invalid message id" end

    local origin = OU.Util.SanitizeText(fields[4], 64)
    local hops = tonumber(fields[5])
    if not origin or origin == "" or #origin > 64 then return nil, "invalid origin" end
    if not id:match("^[%w_%-]+$") then return nil, "invalid message id" end
    if not hops or hops < 0 or hops > 2 then return nil, "invalid hop count" end

    local body = {}
    for index = 6, #fields do body[#body + 1] = fields[index] end
    if CENSUS_TYPES[messageType] then
        local ok = ValidateCensus(messageType, id, body, origin)
        if not ok then return nil, "invalid census message" end
    elseif messageType == "GDEC" then
        local ok = ValidateGovernance(id, body, origin)
        if not ok then return nil, "invalid governance message" end
    end
    return { version = version, type = messageType, id = id, origin = origin, hops = hops, fields = body }
end

local function CensusID(prefix)
    OU._censusID = (OU._censusID or 0) + 1
    return ("%s-%d-%d"):format(prefix, OU.Util.Now() % 10000000000, OU._censusID % 1000000)
end

function Protocol.Candidate(guildKey, guildDisplay, term)
    return "CCAND", CensusID("c"), { guildKey, guildDisplay, term }
end

function Protocol.Lease(guildKey, term, leaseStartedAt, leaseSeq)
    return "CLEASE", CensusID("l"), { guildKey, term, leaseStartedAt, leaseSeq }
end

function Protocol.Summary(guildKey, guildDisplay, term, revision, snapshotId, capturedAt, total, online)
    return "CSUM", CensusID("s"), { guildKey, guildDisplay, term, revision, snapshotId, capturedAt, total, online == nil and "U" or online }
end

function Protocol.RosterRequest(requestId, guildKey, snapshotId, targetReporter)
    return "CREQ", CensusID("r"), { requestId, guildKey, snapshotId, targetReporter }
end

function Protocol.Page(requestId, pageIndex, pageCount, totalNames, names)
    local fields = { requestId, pageIndex, pageCount, totalNames }
    for _, name in ipairs(names or {}) do fields[#fields + 1] = name end
    return "CPAGE", OU.CensusLogic.PageEnvelopeID(requestId, pageIndex), fields
end

function Protocol.Failure(requestId, reason)
    OU._censusID = (OU._censusID or 0) + 1
    local id = ("f-%s-%010d-%06d"):format(requestId, OU.Util.Now() % 10000000000, OU._censusID % 1000000)
    return "CFAIL", id, { requestId, reason }
end

function Protocol.Hello(identity)
    return "HELLO", OU.Util.MakeID("hello"), {
        identity.role, identity.guild, identity.zone, identity.level, identity.classFile, "census-1",
    }
end

function Protocol.Post(text, identity)
    identity = identity or OU.Identity or OU.Util.PlayerIdentity()
    return "POST", OU.Util.MakeID("post"), {
        OU.Util.SanitizeText(text, 170),
        identity.role == "member" and "member" or "guest",
        OU.Util.SanitizeText(identity.guild, 64),
    }
end

function Protocol.LayerRequest(zone, note, expires)
    return "LREQ", OU.Util.MakeID("layer"), {
        OU.Util.SanitizeText(zone, 48), OU.Util.SanitizeText(note, 110), tonumber(expires) or 0,
    }
end

function Protocol.LayerOffer(requestID, note)
    return "LOFFER", OU.Util.MakeID("offer"), {
        OU.Util.SanitizeText(requestID, 80), OU.Util.SanitizeText(note, 100),
    }
end

function Protocol.Event(startsAt, title, details)
    return "EVENT", OU.Util.MakeID("event"), {
        tonumber(startsAt) or 0, OU.Util.SanitizeText(title, 70), OU.Util.SanitizeText(details, 100),
    }
end

function Protocol.Claim(candidate, expires)
    return "CLAIM", OU.Util.MakeID("claim"), {
        OU.Util.SanitizeText(candidate, 64), tonumber(expires) or 0,
    }
end

function Protocol.Release(candidate)
    return "RELEASE", OU.Util.MakeID("release"), { OU.Util.SanitizeText(candidate, 64) }
end

function Protocol.GuildDecision(decision)
    if type(decision) ~= "table" then return nil, "invalid governance decision" end
    return "GDEC", decision.id, decision.fields, decision.origin
end

Protocol._Test = { Escape = Escape, Unescape = Unescape, Separator = SEP, ValidateCensus = ValidateCensus,
    ValidateGovernance = ValidateGovernance }
