local _, OU = ...

local Trust = { authority = "unavailable" }
OU.GuildTrust = Trust

local ROOT_KEY = OU.State.ROOT_GUILD_KEY
local ROOT_DISPLAY = OU.State.PRODUCTION_GUILD_DEFAULTS[1]
local EVIDENCE = { ["local-visible"] = 1, ["configured-connector"] = 2 }
local RECORD_CAP = 64
local PENDING_TTL = 30 * 86400
local WIRE_PAST = 600
local WIRE_FUTURE = 60
local STATES = { pending = true, approved = true, denied = true, conflict = true }
local SOURCES = { ["local-officer"] = true, ["configured-connector"] = true }
local RECORD_FIELDS = {
    displayName = true, state = true, firstSeenAt = true, lastSeenAt = true,
    evidenceMask = true, observations = true, deniedEvidenceMask = true, generation = true,
    decisionId = true, decidedAt = true, sourceClass = true,
}

local function PlainBoolean(value)
    return type(value) == "boolean" and not (issecretvalue and issecretvalue(value))
end

local function PlainString(value)
    return OU.Util.IsPlainString(value)
end

local function IntegerIn(value, low, high)
    return type(value) == "number" and not (issecretvalue and issecretvalue(value))
        and value == value and value ~= math.huge and value ~= -math.huge
        and value == math.floor(value) and value >= low and value <= high
end

local function DecisionToken(value)
    return PlainString(value) and value ~= "" and #value <= 40 and value:match("^[a-z0-9%-]+$") ~= nil
end

local function ValidRecord(key, record, now)
    if not PlainString(key) or key == ROOT_KEY or OU.Util.NormalizeGuild(key) ~= key
        or type(record) ~= "table" or not PlainString(record.displayName)
        or #record.displayName > 32 or OU.Util.NormalizeGuild(record.displayName) ~= key
        or not PlainString(record.state) or not STATES[record.state] then return false end
    for field in pairs(record) do if not RECORD_FIELDS[field] then return false end end
    if not IntegerIn(record.firstSeenAt, 0, 9999999999)
        or not IntegerIn(record.lastSeenAt, 0, 9999999999)
        or record.firstSeenAt > record.lastSeenAt or record.lastSeenAt > now + WIRE_FUTURE
        or not IntegerIn(record.evidenceMask, 0, 3)
        or not IntegerIn(record.observations, 0, 255)
        or not IntegerIn(record.deniedEvidenceMask, 0, 3)
        or not IntegerIn(record.generation, 0, 2147483647) then return false end
    if record.generation > 0 or record.state == "approved" or record.state == "denied" or record.state == "conflict" then
        if record.generation < 1 or not DecisionToken(record.decisionId)
            or not IntegerIn(record.decidedAt, 0, 9999999999)
            or not PlainString(record.sourceClass) or not SOURCES[record.sourceClass] then return false end
    elseif record.decisionId ~= nil or record.decidedAt ~= nil or record.sourceClass ~= nil then
        return false
    end
    return true
end

local function Count(map)
    local total = 0
    for _ in pairs(type(map) == "table" and map or {}) do total = total + 1 end
    return total
end

local function HasBit(mask, bit)
    mask = tonumber(mask) or 0
    return math.floor(mask / bit) % 2 == 1
end

local function AddBit(mask, bit)
    mask = tonumber(mask) or 0
    if HasBit(mask, bit) then return mask end
    return mask + bit
end

local function Governance(database)
    if type(database) ~= "table" then return nil end
    database.guildGovernance = type(database.guildGovernance) == "table" and database.guildGovernance or {}
    database.participatingGuilds = type(database.participatingGuilds) == "table" and database.participatingGuilds or {}
    database.participatingGuilds[ROOT_KEY] = ROOT_DISPLAY
    return database.guildGovernance
end

function Trust.LooksLikeOlympusGuild(guild)
    local key = OU.Util.NormalizeGuild(guild)
    return key ~= nil and key ~= ROOT_KEY and key:find("olympus", 1, true) ~= nil
end

function Trust.LocalAuthority()
    if type(GetGuildInfo) ~= "function" then return "unavailable" end
    local guildOK, guild = pcall(GetGuildInfo, "player")
    if not guildOK or not PlainString(guild) then return "unavailable" end
    if OU.Util.NormalizeGuild(guild) ~= ROOT_KEY then return "not_authorized" end

    local leaderValid, leaderValue = false, false
    if type(IsGuildLeader) == "function" then
        local ok, value = pcall(IsGuildLeader)
        leaderValid, leaderValue = ok and PlainBoolean(value), value
        if leaderValid and leaderValue then return "authorized" end
    end
    local officerValid, officerValue = false, false
    if type(C_GuildInfo) == "table" and type(C_GuildInfo.IsGuildOfficer) == "function" then
        local ok, value = pcall(C_GuildInfo.IsGuildOfficer)
        officerValid, officerValue = ok and PlainBoolean(value), value
        if officerValid and officerValue then return "authorized" end
    end
    if leaderValid and officerValid and leaderValue == false and officerValue == false then return "not_authorized" end
    return "unavailable"
end

function Trust.RefreshAuthority()
    Trust.authority = Trust.LocalAuthority()
    return Trust.authority
end

function Trust.Prune(database, now)
    local governance = Governance(database)
    if not governance then return 0 end
    if type(now) ~= "number" or (issecretvalue and issecretvalue(now))
        or now ~= now or now == math.huge or now == -math.huge then now = OU.Util.Now() end
    now = math.max(0, math.floor(now))
    for key, record in pairs(governance) do
        if not ValidRecord(key, record, now) then
            governance[key] = nil
        elseif (record.state == "pending" or record.state == "conflict")
            and now - record.lastSeenAt > PENDING_TTL then
            governance[key] = nil
        end
    end
    database.participatingGuilds = OU.State._ProjectParticipatingGuilds(governance)
    return Count(governance)
end

function Trust.Observe(guild, source, now, database)
    database = database or OU.DB
    local bit = EVIDENCE[source]
    if not PlainString(guild) then return false, "invalid-candidate" end
    local display = OU.Util.SanitizeText(guild, 32)
    local key = OU.Util.NormalizeGuild(display)
    if not bit or not key or not Trust.LooksLikeOlympusGuild(display) then return false, "not-candidate" end
    now = math.max(0, math.floor(tonumber(now) or OU.Util.Now()))
    local governance = Governance(database)
    Trust.Prune(database, now)
    local record = governance[key]
    if not record then
        if Count(governance) >= RECORD_CAP then return false, "candidate-capacity" end
        record = {
            displayName = display, state = "pending", firstSeenAt = now, lastSeenAt = now,
            evidenceMask = 0, observations = 0, deniedEvidenceMask = 0, generation = 0,
        }
        governance[key] = record
    end
    local newlyObserved = not HasBit(record.evidenceMask, bit)
    record.displayName = display
    record.firstSeenAt = math.min(tonumber(record.firstSeenAt) or now, now)
    record.lastSeenAt = now
    record.evidenceMask = AddBit(record.evidenceMask, bit)
    record.observations = math.min(255, math.max(0, tonumber(record.observations) or 0) + 1)
    if record.state == "denied" and newlyObserved and not HasBit(record.deniedEvidenceMask, bit) then
        record.state = "pending"
    end
    return true, record
end

local function NewDecisionID(now)
    OU._guildDecisionCounter = (OU._guildDecisionCounter or 0) + 1
    local uptime = math.floor(OU.Util.Uptime() * 1000) % 1000000
    return ("g-%010d-%06d-%06d"):format(math.floor(now) % 10000000000, uptime,
        OU._guildDecisionCounter % 1000000)
end

local function ApplyDecisionState(database, key, record, action)
    if action == "approve" then
        if not database.participatingGuilds[key]
            and Count(database.participatingGuilds) >= OU.State.LIMITS.PARTICIPATING_GUILDS then return false, "allowlist-capacity" end
        record.state = "approved"
        database.participatingGuilds[key] = record.displayName
    elseif action == "deny" then
        record.state = "denied"
        record.deniedEvidenceMask = record.evidenceMask or 0
        database.participatingGuilds[key] = nil
    elseif action == "review" then
        record.state = "pending"
        record.deniedEvidenceMask = 0
        database.participatingGuilds[key] = nil
    else
        return false, "invalid-action"
    end
    database.participatingGuilds[ROOT_KEY] = ROOT_DISPLAY
    return true
end

function Trust.Decide(action, guild, now, database)
    database = database or OU.DB
    local authority = Trust.LocalAuthority()
    Trust.authority = authority
    if authority ~= "authorized" then return false, authority end
    if not PlainString(guild) then return false, "invalid-target" end
    local key = OU.Util.NormalizeGuild(guild)
    if not key or key == ROOT_KEY then return false, "invalid-target" end
    local governance = Governance(database)
    local record = governance[key]
    if type(record) ~= "table" or OU.Util.NormalizeGuild(record.displayName) ~= key then return false, "missing-candidate" end
    if action == "review" and record.state ~= "denied" and record.state ~= "approved" and record.state ~= "conflict" then
        return false, "invalid-action"
    end
    if action ~= "review" and action ~= "approve" and action ~= "deny" then return false, "invalid-action" end
    local generation = math.floor(tonumber(record.generation) or 0)
    if generation >= 2147483647 then return false, "generation-capacity" end
    now = math.max(0, math.floor(tonumber(now) or OU.Util.Now()))
    local previous = record.decisionId or "-"
    local decisionId = NewDecisionID(now)
    local ok, reason = ApplyDecisionState(database, key, record, action)
    if not ok then return false, reason end
    record.generation = generation + 1
    record.decisionId = decisionId
    record.decidedAt = now
    record.sourceClass = "local-officer"
    local decision = {
        id = decisionId, origin = OU.Identity and OU.Identity.name or (UnitName and UnitName("player")) or "unknown",
        fields = { ROOT_KEY, key, record.displayName, action, record.generation, previous, now },
    }
    return true, decision, record
end

local function MarkConflict(database, key, record, now)
    record.state = "conflict"
    record.lastSeenAt = now
    database.participatingGuilds[key] = nil
    database.participatingGuilds[ROOT_KEY] = ROOT_DISPLAY
end

function Trust.ApplyRemote(message, now, database)
    database = database or OU.DB
    local fields = type(message) == "table" and message.fields or nil
    if type(fields) ~= "table" or fields[1] ~= ROOT_KEY then return false, "invalid-decision" end
    local key, display, action = fields[2], fields[3], fields[4]
    local generation, previous, decidedAt = tonumber(fields[5]), fields[6], tonumber(fields[7])
    if not PlainString(message.id) or #message.id > 40 or not message.id:match("^[a-z0-9%-]+$")
        or not PlainString(key) or #key > 32 or not PlainString(display) or #display > 32 or OU.Util.NormalizeGuild(key) ~= key
        or OU.Util.NormalizeGuild(display) ~= key or key == ROOT_KEY
        or (action ~= "approve" and action ~= "deny" and action ~= "review")
        or not generation or generation < 1 or generation > 2147483647 or generation ~= math.floor(generation)
        or not PlainString(previous) or (previous ~= "-" and (#previous > 40 or not previous:match("^[a-z0-9%-]+$")))
        or not decidedAt or decidedAt < 0 or decidedAt > 9999999999 or decidedAt ~= math.floor(decidedAt) then
        return false, "invalid-decision"
    end
    now = math.max(0, math.floor(tonumber(now) or OU.Util.Now()))
    if decidedAt < now - WIRE_PAST or decidedAt > now + WIRE_FUTURE then return false, "stale-decision" end
    local governance = Governance(database)
    Trust.Prune(database, now)
    local record = governance[key]
    local existed = type(record) == "table"
    if record and record.decisionId == message.id then return false, "current-decision" end
    if not record then
        if Count(governance) >= RECORD_CAP then return false, "candidate-capacity" end
        record = { displayName = display, state = "pending", firstSeenAt = now, lastSeenAt = now,
            evidenceMask = EVIDENCE["configured-connector"], observations = 1, deniedEvidenceMask = 0, generation = 0 }
        governance[key] = record
    end
    local currentGeneration = math.floor(tonumber(record.generation) or 0)
    local expectedPrevious = record.decisionId or "-"
    local validChain = (not existed) or (generation == currentGeneration + 1 and previous == expectedPrevious)
    if not validChain then MarkConflict(database, key, record, now); return false, "decision-conflict" end

    record.displayName = display
    record.lastSeenAt = now
    record.evidenceMask = AddBit(record.evidenceMask, EVIDENCE["configured-connector"])
    record.observations = math.min(255, math.max(0, tonumber(record.observations) or 0) + 1)
    record.generation = generation
    record.decisionId = message.id
    record.decidedAt = decidedAt
    record.sourceClass = "configured-connector"
    local ok = ApplyDecisionState(database, key, record, action)
    if not ok then MarkConflict(database, key, record, now); return false, "decision-conflict" end
    return true, record
end

function Trust.Records(database)
    local values = {}
    for key, record in pairs(type(database) == "table" and type(database.guildGovernance) == "table"
        and database.guildGovernance or {}) do values[#values + 1] = { key = key, record = record } end
    table.sort(values, function(a, b)
        if a.record.state ~= b.record.state then return a.record.state < b.record.state end
        return a.key < b.key
    end)
    return values
end

function Trust.Status(guild, database)
    local key = OU.Util.NormalizeGuild(guild)
    if key == ROOT_KEY then return "approved", { displayName = ROOT_DISPLAY, state = "approved" } end
    local record = key and type(database) == "table" and type(database.guildGovernance) == "table"
        and database.guildGovernance[key] or nil
    return record and record.state or "unseen", record
end

Trust.ROOT_KEY = ROOT_KEY
Trust.ROOT_DISPLAY = ROOT_DISPLAY
Trust.EVIDENCE = EVIDENCE
Trust.RECORD_CAP = RECORD_CAP
Trust.PENDING_TTL = PENDING_TTL
Trust.WIRE_PAST = WIRE_PAST
Trust.WIRE_FUTURE = WIRE_FUTURE
Trust._Test = { HasBit = HasBit, AddBit = AddBit, Count = Count, NewDecisionID = NewDecisionID,
    ApplyDecisionState = ApplyDecisionState, MarkConflict = MarkConflict, ValidRecord = ValidRecord }
