-- Pure normalized-input boundary. No TF3 APIs, guessed metrics or implicit zeroes.
local input = {}
local function fail(path, message, code) error({code = code or "invalid_input", path = path, message = message}, 0) end
local function record(v, path, keys)
    if type(v) ~= "table" or getmetatable(v) then fail(path, "plain table required") end
    for k in pairs(v) do if keys[k] == nil then fail(path, "unsupported field: " .. tostring(k)) end end
    return v
end
local function num(v, path, low, high, integer)
    if type(v) ~= "number" or v ~= v or v < low or v > high or (integer and v % 1 ~= 0) then fail(path, "finite number outside allowed range") end
    return v
end
local function str(v, path)
    if type(v) ~= "string" or #v == 0 or #v > 160 or v:find("[%c]") then fail(path, "nonempty text up to 160 bytes required") end
    return v
end
local function array(v, path, limit)
    if type(v) ~= "table" or getmetatable(v) then fail(path, "plain array required") end
    local count = 0
    for k in pairs(v) do
        count = count + 1
        if count > limit then fail(path, "array limit exceeded", "input_limit") end
        num(k, path .. ".index", 1, limit, true)
    end
    for i = 1, count do if v[i] == nil then fail(path, "dense array required") end end
    return count
end
local function id(v, path) return math.floor(num(v, path, 0, 2147483647, true)) end
local function evidence(v, path)
    local basis = v.basis
    if basis ~= "observed" and basis ~= "assumption" and basis ~= "synthetic" then fail(path .. ".basis", "observed, assumption or synthetic required") end
    return {source = str(v.source, path .. ".source"), basis = basis}
end
local function metric(v, path, maximum, isLabel)
    if v == nil then return nil end
    record(v, path, {value = true, source = true, basis = true})
    local r = evidence(v, path)
    r.value = isLabel and str(v.value, path .. ".value") or num(v.value, path .. ".value", 0, maximum)
    return r
end
local defaults = {minDistance = 1000, maxDistance = 20000, minCapacity = 200, majorCapacity = 1000,
    minDemandSupport = 0.4, maxDifficulty = 0.8, adequateTransport = 0.8,
    unknownDifficulty = 0.2, distanceWeight = 0.25, geographyWeight = 0.5,
    minScore = 0.25, railRadius = 300, industryRadius = 1000, maxDegree = 3,
    maxEdges = 32, maxTowns = 128, maxPairs = 8128, allowCrossRegion = false}
local ranges = {minDistance = {0, 1e6}, maxDistance = {1, 1e6}, minCapacity = {0, 1e7},
    majorCapacity = {1, 1e7}, minDemandSupport = {0, 1}, maxDifficulty = {0, 1},
    adequateTransport = {0, 1}, unknownDifficulty = {0, 1}, distanceWeight = {0, 10},
    geographyWeight = {0, 10}, minScore = {0, 1}, railRadius = {0, 10000},
    industryRadius = {0, 10000}, maxDegree = {1, 8, true}, maxEdges = {0, 127, true},
    maxTowns = {1, 128, true}, maxPairs = {0, 8128, true}}
function input.key(a, b) return string.format("%d:%d", math.min(a, b), math.max(a, b)) end
function input.validate(raw)
    record(raw, "input", {unit = true, snapshotId = true, source = true, towns = true, pairs = true,
        preferences = true, rail = true, industries = true})
    if raw.unit ~= "world_units" then fail("unit", "world_units required") end
    local m = {snapshotId = str(raw.snapshotId, "snapshotId"), source = str(raw.source, "source"),
        towns = {}, townById = {}, pairs = {}, preferences = {}, industries = {}}
    local preferences = raw.preferences; if preferences == nil then preferences = {} end
    record(preferences, "preferences", defaults)
    for k, fallback in pairs(defaults) do
        local v = preferences[k]; if v == nil then v = fallback end
        if k == "allowCrossRegion" then
            if type(v) ~= "boolean" then fail("preferences." .. k, "boolean required") end
        else v = num(v, "preferences." .. k, table.unpack(ranges[k])) end
        m.preferences[k] = v
    end
    local p = m.preferences
    if p.minDistance >= p.maxDistance or p.minCapacity > p.majorCapacity then fail("preferences", "inconsistent thresholds") end
    local n = array(raw.towns, "towns", p.maxTowns)
    if n * (n - 1) / 2 > p.maxPairs then fail("towns", "pair evaluation limit exceeded", "input_limit") end
    for i, t in ipairs(raw.towns) do
        local path = "towns[" .. i .. "]"
        record(t, path, {id = true, name = true, x = true, y = true, z = true, residentialCapacity = true, region = true})
        local town = {id = id(t.id, path .. ".id"), name = t.name ~= nil and str(t.name, path .. ".name") or nil,
            x = num(t.x, path .. ".x", -1e6, 1e6), y = num(t.y, path .. ".y", -1e6, 1e6),
            z = t.z ~= nil and num(t.z, path .. ".z", -1e6, 1e6) or nil,
            residentialCapacity = metric(t.residentialCapacity, path .. ".residentialCapacity", 1e7),
            region = metric(t.region, path .. ".region", nil, true)}
        if m.townById[town.id] then fail(path, "duplicate town ID") end
        if town.residentialCapacity and town.residentialCapacity.value % 1 ~= 0 then fail(path, "residential capacity must be an integer") end
        m.townById[town.id], m.towns[#m.towns + 1] = town, town
    end
    table.sort(m.towns, function(a, b) return a.id < b.id end)
    local pairsInput = raw.pairs; if pairsInput == nil then pairsInput = {} end
    array(pairsInput, "pairs", p.maxPairs)
    for i, pair in ipairs(pairsInput) do
        local path = "pairs[" .. i .. "]"
        record(pair, path, {a = true, b = true, demandSupport = true, geography = true, transport = true})
        local a, b = id(pair.a, path .. ".a"), id(pair.b, path .. ".b")
        if a == b or not m.townById[a] or not m.townById[b] then fail(path, "distinct known towns required") end
        local key = input.key(a, b)
        if m.pairs[key] then fail(path, "duplicate unordered pair") end
        local r = {demandSupport = metric(pair.demandSupport, path .. ".demandSupport", 1)}
        if pair.geography ~= nil then
            local g = record(pair.geography, path .. ".geography", {difficulty = true, blocked = true, source = true, basis = true})
            r.geography = evidence(g, path .. ".geography")
            r.geography.difficulty = num(g.difficulty, path .. ".geography.difficulty", 0, 1)
            if g.blocked ~= nil and type(g.blocked) ~= "boolean" then fail(path, "blocked must be boolean") end
            r.geography.blocked = g.blocked
        end
        if pair.transport ~= nil then
            local t = record(pair.transport, path .. ".transport", {adequacy = true, mode = true, source = true, basis = true})
            if t.mode ~= "road" and t.mode ~= "rail" and t.mode ~= "other" then fail(path, "unknown transport mode") end
            r.transport = evidence(t, path .. ".transport")
            r.transport.mode, r.transport.adequacy = t.mode, num(t.adequacy, path .. ".transport.adequacy", 0, 1)
        end
        m.pairs[key] = r
    end
    if raw.rail ~= nil then
        record(raw.rail, "rail", {nodes = true, segments = true, source = true, basis = true})
        local rail = evidence(raw.rail, "rail"); rail.nodes, rail.segments, rail.byId = {}, {}, {}
        array(raw.rail.nodes, "rail.nodes", 4096); array(raw.rail.segments, "rail.segments", 8192)
        for i, node in ipairs(raw.rail.nodes) do
            record(node, "rail.node", {id = true, x = true, y = true})
            local nodeId = id(node.id, "rail.node.id")
            if rail.byId[nodeId] then fail("rail.nodes", "duplicate node ID") end
            local copy = {id = nodeId, x = num(node.x, "rail.node.x", -1e6, 1e6), y = num(node.y, "rail.node.y", -1e6, 1e6)}
            rail.byId[nodeId], rail.nodes[i] = copy, copy
        end
        local seen = {}
        for i, edge in ipairs(raw.rail.segments) do
            record(edge, "rail.segment", {id = true, node0 = true, node1 = true})
            local eid, a, b = id(edge.id, "rail.segment.id"), id(edge.node0, "rail.segment.node0"), id(edge.node1, "rail.segment.node1")
            if seen[eid] or not rail.byId[a] or not rail.byId[b] then fail("rail.segments", "duplicate edge or missing node") end
            rail.segments[i], seen[eid] = {id = eid, node0 = a, node1 = b}, true
        end
        table.sort(rail.nodes, function(a, b) return a.id < b.id end)
        table.sort(rail.segments, function(a, b) return a.id < b.id end)
        m.rail = rail
    end
    if raw.industries ~= nil then
        record(raw.industries, "industries", {records = true, source = true, basis = true})
        m.industryEvidence = evidence(raw.industries, "industries")
        array(raw.industries.records, "industries.records", 512)
        local seen = {}
        for i, ind in ipairs(raw.industries.records) do
            record(ind, "industry", {id = true, x = true, y = true, resource = true})
            local iid = id(ind.id, "industry.id")
            if seen[iid] then fail("industries", "duplicate industry ID") end
            seen[iid] = true
            m.industries[i] = {id = iid, x = num(ind.x, "industry.x", -1e6, 1e6),
                y = num(ind.y, "industry.y", -1e6, 1e6), resource = ind.resource ~= nil and str(ind.resource, "industry.resource") or nil}
        end
        table.sort(m.industries, function(a, b) return a.id < b.id end)
    end
    return m
end
return input
