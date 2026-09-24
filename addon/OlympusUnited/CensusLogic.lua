local _, OU = ...

local Logic = {}
OU.CensusLogic = Logic

Logic.CONSTANTS = {
    ELECTION_WINDOW = 5,
    LEASE_RENEW = 60,
    LEASE_TIMEOUT = 120,
    SUMMARY_REFRESH = 900,
    FRESH_SECONDS = 1200,
    EXPIRE_SECONDS = 2700,
    REQUEST_COOLDOWN = 600,
    ROUTE_TTL = 360,
    PAGE_INTERVAL = 0.25,
    TICK_INTERVAL = 30,
    MAX_NAMES = 1000,
    MAX_PAGES = 1000,
    MAX_CANDIDATES = 64,
    MAX_SUMMARIES = 32,
    MAX_ROUTES = 64,
    MAX_COOLDOWNS = 64,
    MAX_PAGE_RATE = 64,
    MAX_ASSEMBLIES = 8,
    MAX_ASSEMBLY_BYTES = 128 * 1024,
    CANDIDATE_TTL = 125,
    LEASE_RETENTION = 240,
    SUMMARY_RETENTION = 86400,
    PAGE_RATE_TTL = 420,
    ASSEMBLY_COMPLETE_TTL = 600,
    ASSEMBLY_ERROR_TTL = 120,
}

function Logic.NormalizeGuild(value)
    return OU.Util.NormalizeGuild(value)
end

local function NumberIn(value, low, high)
    local number = tonumber(value)
    if not number or number ~= math.floor(number) or number < low or number > high then return nil end
    return number
end

function Logic.CompareLease(left, right)
    if not left then return right and -1 or 0 end
    if not right then return 1 end
    local lt, rt = NumberIn(left.term, 0, 9999999999), NumberIn(right.term, 0, 9999999999)
    local ls, rs = NumberIn(left.leaseStartedAt, 0, 9999999999), NumberIn(right.leaseStartedAt, 0, 9999999999)
    local lr, rr = OU.Util.NormalizeName(left.reporter), OU.Util.NormalizeName(right.reporter)
    if not (lt and rt and ls and rs and lr and rr) then return 0 end
    if lt ~= rt then return lt > rt and 1 or -1 end
    if ls ~= rs then return ls < rs and 1 or -1 end
    if lr ~= rr then return lr < rr and 1 or -1 end
    local lq = NumberIn(left.leaseSeq, 0, 999999) or 0
    local rq = NumberIn(right.leaseSeq, 0, 999999) or 0
    if lq == rq then return 0 end
    return lq > rq and 1 or -1
end

function Logic.LeaseActive(lease, now)
    return type(lease) == "table" and tonumber(lease.receivedAt) ~= nil
        and (tonumber(now) or 0) - lease.receivedAt <= Logic.CONSTANTS.LEASE_TIMEOUT
end

function Logic.CompareSummary(left, right)
    if not left then return right and -1 or 0 end
    if not right then return 1 end
    for _, key in ipairs({ "term", "revision", "capturedAt" }) do
        local a, b = tonumber(left[key]) or -1, tonumber(right[key]) or -1
        if a ~= b then return a > b and 1 or -1 end
    end
    local a = OU.Util.NormalizeName(left.reporter) or "~"
    local b = OU.Util.NormalizeName(right.reporter) or "~"
    if a == b then return 0 end
    return a < b and 1 or -1
end

function Logic.Freshness(summary, now)
    if type(summary) ~= "table" or tonumber(summary.capturedAt) == nil then return "unavailable", nil end
    local age = math.max(0, (tonumber(now) or 0) - summary.capturedAt)
    if age <= Logic.CONSTANTS.FRESH_SECONDS then return "fresh", age end
    if age <= Logic.CONSTANTS.EXPIRE_SECONDS then return "stale", age end
    return "expired", age
end

function Logic.Totals(summaries, now)
    local result = { members = 0, online = 0, onlineKnown = true, current = 0, stale = 0, expired = 0, rows = {} }
    local best = {}
    for _, summary in pairs(summaries or {}) do
        local key = Logic.NormalizeGuild(summary.guildKey or summary.guildDisplay)
        if key and (not best[key] or Logic.CompareSummary(summary, best[key]) > 0) then best[key] = summary end
    end
    for key, summary in pairs(best) do
        local state, age = Logic.Freshness(summary, now)
        result.rows[#result.rows + 1] = { key = key, summary = summary, state = state, age = age }
        if state == "expired" then
            result.expired = result.expired + 1
        else
            result.members = result.members + (tonumber(summary.total) or 0)
            if summary.online == nil then result.onlineKnown = false
            else result.online = result.online + (tonumber(summary.online) or 0) end
            if state == "fresh" then result.current = result.current + 1 else result.stale = result.stale + 1 end
        end
    end
    local roman = { I = 1, V = 5, X = 10, L = 50, C = 100, D = 500, M = 1000 }
    local function sortKey(value)
        value = tostring(value or "")
        local stem, digits = value:match("^(.-)%s+(%d+)$")
        if digits then return stem:lower(), tonumber(digits), value:lower() end
        local romanStem, word = value:match("^(.-)%s+([IVXLCDMivxlcdm]+)$")
        if romanStem and (word == word:upper() or word == word:lower()) then
            local total, previous = 0, 0
            for index = #word, 1, -1 do
                local number = roman[word:sub(index, index):upper()]
                if number < previous then total = total - number else total = total + number end
                previous = number
            end
            return romanStem:lower(), total, value:lower()
        end
        return value:lower(), 0, value:lower()
    end
    table.sort(result.rows, function(a, b)
        local abase, an, araw = sortKey(a.summary.guildDisplay or a.key)
        local bbase, bn, braw = sortKey(b.summary.guildDisplay or b.key)
        if abase ~= bbase then return abase < bbase end
        if an ~= bn then return an < bn end
        return araw < braw
    end)
    return result
end

local DIGITS = "0123456789abcdefghijklmnopqrstuvwxyz"
function Logic.Base36(number)
    number = math.max(0, math.floor(tonumber(number) or 0))
    if number == 0 then return "0" end
    local out = ""
    while number > 0 do
        local rem = number % 36
        out = DIGITS:sub(rem + 1, rem + 1) .. out
        number = math.floor(number / 36)
    end
    return out
end

local function PadBase36(number, width)
    local value = Logic.Base36(number)
    while #value < width do value = "0" .. value end
    return value
end

function Logic.RequesterToken(name)
    local normalized = OU.Util.NormalizeName(name) or "unknown"
    local hash = 0
    for index = 1, #normalized do hash = (hash * 33 + normalized:byte(index)) % 2176782336 end
    return PadBase36(hash, 6)
end

function Logic.RequestID(requester, now, counter)
    local stamp = math.floor(tonumber(now) or 0) % 10000000000
    local sequence = math.floor(tonumber(counter) or 0) % 1296
    return ("q-%s-%s-%s"):format(Logic.RequesterToken(requester), Logic.Base36(stamp), PadBase36(sequence, 2))
end

function Logic.PageEnvelopeID(requestId, pageIndex)
    return "p-" .. tostring(requestId) .. "-" .. Logic.Base36(pageIndex)
end

local function ValidateNames(names)
    if type(names) ~= "table" or #names > Logic.CONSTANTS.MAX_NAMES then return nil, "invalid names" end
    local clean, seen = {}, {}
    for _, value in ipairs(names) do
        if not OU.Util.IsPlainString(value) then return nil, "invalid name" end
        local name = OU.Util.Trim(value):gsub("%s+", " ")
        local key = OU.Util.NormalizeRosterName(name)
        if not key or seen[key] then return nil, "duplicate name" end
        if #OU.Protocol._Test.Escape(name) > 48 then return nil, "name too long" end
        seen[key] = true
        clean[#clean + 1] = name
    end
    return clean
end

function Logic.BuildPages(requestId, names, origin)
    local clean, err = ValidateNames(names)
    if not clean then return nil, err end
    local pages = {}
    if #clean == 0 then pages[1] = {} end
    for _, name in ipairs(clean) do
        local page = pages[#pages]
        if not page then page = {}; pages[1] = page end
        local trial = {}
        for i, existing in ipairs(page) do trial[i] = existing end
        trial[#trial + 1] = name
        local fields = { requestId, #pages, Logic.CONSTANTS.MAX_PAGES, #clean }
        for _, item in ipairs(trial) do fields[#fields + 1] = item end
        local payload = OU.Protocol.Encode("CPAGE", Logic.PageEnvelopeID(requestId, #pages), fields, origin, 0)
        if payload then
            page[#page + 1] = name
        else
            page = { name }
            pages[#pages + 1] = page
            fields = { requestId, #pages, Logic.CONSTANTS.MAX_PAGES, #clean, name }
            if not OU.Protocol.Encode("CPAGE", Logic.PageEnvelopeID(requestId, #pages), fields, origin, 0) then
                return nil, "name does not fit"
            end
        end
    end
    if #pages > Logic.CONSTANTS.MAX_PAGES then return nil, "too many pages" end
    for index, page in ipairs(pages) do
        local fields = { requestId, index, #pages, #clean }
        for _, name in ipairs(page) do fields[#fields + 1] = name end
        local payload, encodeErr = OU.Protocol.Encode("CPAGE", Logic.PageEnvelopeID(requestId, index), fields, origin, 0)
        if not payload then return nil, encodeErr end
    end
    return pages
end

function Logic.NewAssembly(requestId, reporter, totalNames, pageCount, now)
    totalNames = NumberIn(totalNames, 0, Logic.CONSTANTS.MAX_NAMES)
    pageCount = NumberIn(pageCount, 1, Logic.CONSTANTS.MAX_PAGES)
    if not totalNames or not pageCount then return nil, "invalid assembly" end
    return { requestId = requestId, reporter = reporter, totalNames = totalNames, pageCount = pageCount,
        pages = {}, received = 0, startedAt = now, expiresAt = (now or 0) + Logic.CONSTANTS.ROUTE_TTL }
end

function Logic.ApplyPage(assembly, pageIndex, pageCount, totalNames, names, now)
    if type(assembly) ~= "table" or (tonumber(now) or 0) > (assembly.expiresAt or 0) then return nil, "expired" end
    pageIndex = NumberIn(pageIndex, 1, Logic.CONSTANTS.MAX_PAGES)
    pageCount = NumberIn(pageCount, 1, Logic.CONSTANTS.MAX_PAGES)
    totalNames = NumberIn(totalNames, 0, Logic.CONSTANTS.MAX_NAMES)
    if not pageIndex or pageCount ~= assembly.pageCount or totalNames ~= assembly.totalNames or pageIndex > pageCount then
        return nil, "mismatched page"
    end
    local clean, err = ValidateNames(names)
    if not clean then return nil, err end
    if assembly.pages[pageIndex] then return "duplicate" end
    assembly.pages[pageIndex] = clean
    assembly.received = assembly.received + 1
    if assembly.received < assembly.pageCount then return "progress" end
    local all, seen = {}, {}
    for index = 1, assembly.pageCount do
        local page = assembly.pages[index]
        if not page then return nil, "missing page" end
        for _, name in ipairs(page) do
            local key = OU.Util.NormalizeRosterName(name)
            if seen[key] then return nil, "duplicate name" end
            seen[key] = true
            all[#all + 1] = name
        end
    end
    if #all ~= assembly.totalNames then return nil, "name count mismatch" end
    return "complete", all
end

Logic._Test = { NumberIn = NumberIn, ValidateNames = ValidateNames }
