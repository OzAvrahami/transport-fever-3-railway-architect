local network = ug_require "oz_railway_network_architect::/planning/network_planner.lua"
local passed = 0
local function eq(a, b) assert(a == b, tostring(a) .. " ~= " .. tostring(b)) end
local function test(name, fn)
    local ok, why = pcall(fn); assert(ok, name .. ": " .. tostring(why))
    passed = passed + 1; print("PASS network: " .. name)
end
local function evidence(value) return {value = value, source = "synthetic fixture", basis = "synthetic"} end
local function town(id, x, y, capacity)
    return {id = id, name = "Town " .. id, x = x, y = y, residentialCapacity = capacity ~= nil and evidence(capacity) or nil}
end
local function input(towns)
    return {unit = "world_units", snapshotId = "synthetic-1", source = "synthetic anchor fixture", towns = towns, preferences = {}}
end
local function pair()
    return input({town(1, 0, 0, 2000), town(2, 5000, 0, 1500)})
end
local function reason(edge, code)
    for _, why in ipairs(edge.reasons) do if why == code then return true end end
    return false
end
local function decision(result, a, b)
    for _, e in ipairs(result.decisions) do if e.sourceId == a and e.destinationId == b then return e end end
    error("missing decision")
end
local function serialize(v)
    if type(v) ~= "table" then return tostring(v) end
    local keys, out = {}, {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for _, k in ipairs(keys) do out[#out + 1] = tostring(k) .. "=" .. serialize(v[k]) end
    return "{" .. table.concat(out, ",") .. "}"
end
local function example()
    local raw = input({town(1, 0, 0, 2500), town(2, -4000, 0, 1800), town(3, 4000, 0, 2000),
        town(4, 0, 2500, 400), town(5, 200, 0, 50), town(6, 13000, 6000, 1200),
        town(7, 17000, 6000, 1400), town(8, 14000, 7000)})
    for i, t in ipairs(raw.towns) do t.region = evidence(i <= 5 and "west" or "east") end
    raw.pairs = {{a = 3, b = 4, transport = {mode = "road", adequacy = 0.9, source = "synthetic service assessment", basis = "synthetic"}}}
    raw.rail = {source = "synthetic physical graph", basis = "synthetic",
        nodes = {{id = 900, x = -4000, y = 0}, {id = 901, x = 4000, y = 0}},
        segments = {{id = 990, node0 = 900, node1 = 901}}}
    raw.industries = {source = "synthetic inventory", basis = "synthetic", records = {
        {id = 100, x = 100, y = 100, resource = "synthetic_logging"},
        {id = 101, x = 300, y = 100, resource = "synthetic_sawmill"}}}
    return raw
end

test("two sufficiently sized towns produce a conditional mainline study, not a buildable route", function()
    local r = network.plan(pair()); eq(r.status, "ok"); eq(#r.recommendations, 1)
    local e = r.recommendations[1]; eq(e.classification, "mainline"); eq(e.distance, 5000)
    eq(e.constructionStatus, "unverified"); eq(e.evidence.demandSupport, nil)
    assert(reason(e, "capacity_proxy_justifies_conditional_study")); eq(r.stats.astarSearches, 0)
end)
test("empty and single-town inputs succeed without invented links", function()
    eq(#network.plan(input({})).recommendations, 0)
    local r = network.plan(input({town(1, 0, 0)})); eq(r.status, "ok")
    eq(r.towns[1].status, "no_new_rail_recommended_now"); eq(r.towns[1].reasons[1].reason, "no_other_towns")
end)
test("three through ten town networks respect forest, degree and pair accounting", function()
    for n = 3, 10 do
        local ts = {}; for i = 1, n do ts[i] = town(i, i * 2000, 0, 1500) end
        local r = network.plan(input(ts)); eq(r.status, "ok"); eq(#r.recommendations, n - 1)
        eq(#r.decisions, n * (n - 1) / 2)
        for _, t in ipairs(r.towns) do assert(t.degree <= 3) end
        for _, e in ipairs(r.recommendations) do eq(e.classification, "mainline") end
    end
end)
test("example has a mainline, useful branch, potential hub and disconnected component", function()
    local r = network.plan(example()); eq(r.status, "ok"); eq(#r.recommendations, 4)
    eq(decision(r, 1, 2).classification, "mainline"); eq(decision(r, 1, 3).classification, "mainline")
    eq(decision(r, 1, 4).classification, "branch"); eq(decision(r, 6, 7).classification, "mainline")
    eq(#r.hubs, 1); eq(r.hubs[1].townId, 1); eq(r.hubs[1].status, "potential_interchange")
    eq(#r.components, 4); eq(r.towns[5].status, "no_new_rail_recommended_now")
    eq(r.towns[8].status, "no_new_rail_recommended_now")
    print("NETWORK_EXAMPLE conditional studies; synthetic evidence; no alignment/cost validation")
    for _, e in ipairs(r.recommendations) do
        print(string.format("priority=%d %d->%d %s distance=%.0f score=%.4f", e.priority, e.sourceId, e.destinationId, e.classification, e.distance, e.score.total))
    end
    for _, ids in ipairs({{1,5},{2,3},{3,4},{1,6},{6,8}}) do
        local e = decision(r, ids[1], ids[2]); print(e.id .. " " .. e.status .. " " .. e.reasons[#e.reasons])
    end
end)
test("nearby towns and coincident anchors are not automatically connected", function()
    local raw = pair(); raw.towns[2].x = 200
    local e = network.plan(raw).decisions[1]; eq(e.status, "rejected"); assert(reason(e, "short_distance_compare_road_first"))
    raw.towns[2].x = 0; assert(reason(network.plan(raw).decisions[1], "coincident_anchors"))
end)
test("missing demand and population proxy are unknown; explicit zero stays zero", function()
    local raw = pair(); raw.towns[1].residentialCapacity, raw.towns[2].residentialCapacity = nil, nil
    local e = network.plan(raw).decisions[1]
    assert(reason(e, "insufficient_evidence_not_zero_demand")); eq(e.evidence.residentialCapacitySource, nil)
    raw.pairs = {{a = 1, b = 2, demandSupport = evidence(0)}}
    e = network.plan(raw).decisions[1]; eq(e.evidence.demandSupport.value, 0)
    assert(reason(e, "supplied_demand_support_too_low"))
    raw.pairs = nil; raw.towns[1].residentialCapacity, raw.towns[2].residentialCapacity = evidence(0), evidence(0)
    assert(reason(network.plan(raw).decisions[1], "capacity_proxy_too_small_without_demand_evidence"))
end)
test("explicit pair support can justify a study with missing town sizes", function()
    local raw = input({town(1, 0, 0), town(2, 5000, 0)})
    raw.pairs = {{a = 2, b = 1, demandSupport = evidence(0.9)}}
    local e = network.plan(raw).recommendations[1]; assert(e); eq(e.score.support, 0.9)
    eq(e.evidence.demandSupport.basis, "synthetic")
end)
test("large capacity cannot override explicit low demand support", function()
    local raw = pair(); raw.pairs = {{a = 1, b = 2, demandSupport = evidence(0.1)}}
    eq(#network.plan(raw).recommendations, 0)
end)
test("known difficult geography, exclusions and service adequacy defer connections", function()
    local raw = pair()
    raw.pairs = {{a = 1, b = 2, geography = {difficulty = 0.9, source = "test", basis = "assumption"}}}
    assert(reason(network.plan(raw).decisions[1], "geographic_difficulty_exceeds_preference"))
    raw.pairs[1].geography.blocked = true
    assert(reason(network.plan(raw).decisions[1], "excluded_by_geographic_assessment"))
    raw.pairs[1] = {a = 1, b = 2, transport = {mode = "road", adequacy = 0.9, source = "test", basis = "assumption"}}
    assert(reason(network.plan(raw).decisions[1], "existing_transport_assessed_adequate"))
end)
test("unknown terrain is labeled as an assumption, not flat surveyed geography", function()
    local e = network.plan(pair()).recommendations[1]
    eq(e.evidence.geography, nil); eq(e.score.difficultyAssumed, true); eq(e.score.difficultyUsed, 0.2)
    local raw = pair(); raw.preferences.unknownDifficulty = 1; raw.preferences.minScore = 0.8
    eq(#network.plan(raw).recommendations, 0)
end)
test("separate supplied regions remain disconnected unless preference explicitly permits study", function()
    local raw = pair(); raw.towns[1].region, raw.towns[2].region = evidence("A"), evidence("B")
    assert(reason(network.plan(raw).decisions[1], "separate_regions_require_further_study"))
    raw.preferences.allowCrossRegion = true; eq(#network.plan(raw).recommendations, 1)
end)
test("same physical rail component prompts reuse review without operational route claims", function()
    local r = network.plan(example()); local e = decision(r, 2, 3)
    eq(e.status, "deferred"); eq(e.infrastructure.samePhysicalComponent, true)
    assert(reason(e, "inspect_existing_physical_rail_before_new_corridor"))
    eq(e.infrastructure.source.nodeId, 900); eq(e.infrastructure.destination.nodeId, 901)
    eq(e.infrastructure.operationalRoute, nil)
    eq(decision(r, 1, 2).status, "recommended")
end)
test("disconnected and isolated rail nodes do not invent an existing through connection", function()
    local raw = pair(); raw.rail = {source = "test", basis = "synthetic",
        nodes = {{id = 1, x = 0, y = 0}, {id = 2, x = 5000, y = 0}}, segments = {}}
    local e = network.plan(raw).recommendations[1]; assert(e); eq(e.infrastructure.source, nil)
    raw.rail.nodes[3], raw.rail.nodes[4] = {id = 3, x = 50, y = 0}, {id = 4, x = 5050, y = 0}
    raw.rail.segments = {{id = 1, node0 = 1, node1 = 3}, {id = 2, node0 = 2, node1 = 4}}
    e = network.plan(raw).recommendations[1]; eq(e.infrastructure.samePhysicalComponent, false)
end)
test("industry inventory is context, not invented cargo flow or an automatic branch", function()
    local raw = example(); local with = network.plan(raw); raw.industries = nil
    eq(serialize(with.recommendations), serialize(network.plan(raw).recommendations))
    eq(#with.industries, 2)
    for _, i in ipairs(with.industries) do eq(i.status, "deferred"); eq(i.nearbyTownId, i.id == 100 and 1 or 5); eq(i.reasons[1], "industry_presence_not_freight_demand") end
end)
test("duplicate names do not merge entities or decisions", function()
    local raw = pair(); raw.towns[1].name, raw.towns[2].name = "Twin", "Twin"
    local r = network.plan(raw); eq(#r.towns, 2); eq(r.recommendations[1].id, "1:2")
end)
test("input permutations, integer representations and repeated runs produce identical results", function()
    local raw = example(); local expected = serialize(network.plan(raw)); local untouched = serialize(raw)
    for _ = 1, 5 do eq(serialize(network.plan(raw)), expected) end; eq(serialize(raw), untouched)
    local function reverse(t) for i = 1, math.floor(#t / 2) do t[i], t[#t-i+1] = t[#t-i+1], t[i] end end
    reverse(raw.towns); reverse(raw.rail.nodes); reverse(raw.industries.records)
    raw.pairs[1].a, raw.pairs[1].b = raw.pairs[1].b, raw.pairs[1].a
    eq(serialize(network.plan(raw)), expected)
    local p = pair(); local a = network.plan(p); p.towns[1].id = 1.0
    eq(serialize(network.plan(p)), serialize(a))
end)
test("degree and edge budgets leave justified disconnected components", function()
    local raw = example(); raw.preferences.maxEdges = 1
    local r = network.plan(raw); eq(#r.recommendations, 1)
    raw.preferences.maxEdges, raw.preferences.maxDegree = 32, 1
    r = network.plan(raw); for _, t in ipairs(r.towns) do assert(t.degree <= 1) end
    assert(reason(decision(r, 1, 3), "town_degree_preference"))
    raw.preferences.maxEdges = 0; eq(#network.plan(raw).recommendations, 0)
end)
test("higher geography weighting can choose a different forest without running A*", function()
    local raw = input({town(1, 0, 0, 1500), town(2, 2000, 0, 1500), town(3, 4000, 0, 1500)})
    raw.pairs = {{a = 1, b = 2, geography = {difficulty = 0.7, source = "test", basis = "synthetic"}},
        {a = 1, b = 3, geography = {difficulty = 0, source = "test", basis = "synthetic"}},
        {a = 2, b = 3, geography = {difficulty = 0, source = "test", basis = "synthetic"}}}
    raw.preferences.geographyWeight = 0
    eq(decision(network.plan(raw), 1, 3).status, "deferred")
    raw.preferences.geographyWeight = 0.5
    local r = network.plan(raw); eq(decision(r, 1, 3).status, "recommended"); eq(decision(r, 1, 2).status, "deferred")
    eq(r.stats.astarSearches, 0)
end)
test("128-town stress remains within documented pair, rail and traversal budgets", function()
    local ts = {}; for i = 1, 128 do ts[i] = town(i, ((i-1)%16)*2000, math.floor((i-1)/16)*2000, 1500) end
    local raw = input(ts); raw.preferences.maxDistance, raw.preferences.maxEdges, raw.preferences.maxDegree = 100000, 127, 8
    raw.rail = {source = "test", basis = "synthetic", nodes = {}, segments = {}}
    for i = 1, 4096 do raw.rail.nodes[i] = {id = i, x = -100000-i, y = 0} end
    for i = 1, 8192 do raw.rail.segments[i] = {id = i, node0 = ((i-1)%4095)+1, node1 = ((i-1)%4095)+2} end
    local r = network.plan(raw); eq(r.status, "ok"); eq(r.stats.pairs, 8128)
    eq(r.stats.railNodeComparisons, 524288); assert(r.stats.backboneVisits <= 16384)
    assert(#r.recommendations <= 127); eq(r.stats.astarSearches, 0)
    print(string.format("NETWORK_STRESS towns=128 pairs=%d rail_comparisons=%d backbone_visits=%d selected=%d", r.stats.pairs, r.stats.railNodeComparisons, r.stats.backboneVisits, #r.recommendations))
end)
test("oversize, duplicate IDs, malformed provenance and unknown references fail before selection", function()
    local cases = {
        function(r) r.preferences.maxPairs = 0 end,
        function(r) r.preferences.maxTowns = 1 end,
        function(r) r.towns[2].id = 1 end,
        function(r) r.towns[1].x = 0/0 end,
        function(r) r.towns[1].residentialCapacity.source = nil end,
        function(r) r.towns[1].residentialCapacity.value = 1.5 end,
        function(r) r.towns[1].population = 1000 end,
        function(r) r.pairs = {{a = 1, b = 99}} end,
        function(r) r.pairs = {{a = 1, b = 2}, {a = 2, b = 1}} end,
        function(r) r.preferences.maxDegree = 129 end,
        function(r) r.preferences.minDistance = 99999 end,
        function(r) r.pairs = {{a = 1, b = 2, demandSupport = evidence(-1)}} end,
        function(r) r.rail = {source = "test", basis = "synthetic", nodes = {}, segments = {{id = 1, node0 = 1, node1 = 2}}} end,
    }
    for _, damage in ipairs(cases) do
        local raw = pair(); damage(raw); local r = network.plan(raw)
        assert(r.status == "input_limit" or r.status == "invalid_input"); eq(#r.recommendations, 0); assert(r.error.path)
    end
end)
test("all decisions explain selection or omission and scores use transparent common arithmetic", function()
    local r = network.plan(example())
    for _, e in ipairs(r.decisions) do
        assert(#e.reasons > 0 and #e.limitations > 0); assert(e.distance >= 0); assert(e.evidence.anchors)
        if e.score then eq(e.score.total, e.score.support - e.score.distancePenalty - e.score.geographyPenalty) end
        if e.status == "recommended" then assert(e.priority and e.classification); eq(e.relativePriority, e.score.total) end
        assert(e.status ~= "eligible")
    end
end)
test("malformed optional records are rejected rather than treated as missing evidence", function()
    for _, key in ipairs({"preferences", "pairs", "rail", "industries"}) do
        local raw = pair(); raw[key] = false; eq(network.plan(raw).status, "invalid_input")
    end
    for _, key in ipairs({"geography", "transport", "demandSupport"}) do
        local raw = pair(); raw.pairs = {{a = 1, b = 2, [key] = false}}
        eq(network.plan(raw).status, "invalid_input")
    end
    local raw = pair(); raw.towns[1].name = false; eq(network.plan(raw).status, "invalid_input")
end)
test("hard town, industry and rail-array caps cannot be raised or silently truncated", function()
    local raw = input({})
    for i = 1, 129 do raw.towns[i] = town(i, i * 1000, 0, 1500) end
    eq(network.plan(raw).status, "input_limit")
    raw = pair(); raw.preferences.maxTowns = 129; eq(network.plan(raw).status, "invalid_input")
    raw = pair(); raw.industries = {source = "test", basis = "synthetic", records = {}}
    for i = 1, 513 do raw.industries.records[i] = {id = i, x = 0, y = 0} end
    eq(network.plan(raw).status, "input_limit")
    raw = pair(); raw.rail = {source = "test", basis = "synthetic", nodes = {}, segments = {}}
    for i = 1, 4097 do raw.rail.nodes[i] = {id = i, x = 0, y = 0} end
    eq(network.plan(raw).status, "input_limit")
    raw.rail.nodes = {{id = 1, x = 0, y = 0}}
    for i = 1, 8193 do raw.rail.segments[i] = {id = i, node0 = 1, node1 = 1} end
    eq(network.plan(raw).status, "input_limit")
end)
test("explicit handoff feeds unchanged hierarchical planner with fresh synthetic terrain", function()
    local r = network.plan(pair()); local handoff = assert(network.corridorRequest(r, "1:2"))
    eq(handoff.sourceId, 1); eq(handoff.destinationId, 2); eq(handoff.pair.destination.x, 5000)
    eq(network.corridorRequest(r, "2:99"), nil)
    local hierarchy = ug_require "oz_railway_network_architect::/planning/corridor_hierarchy.lua"
    local job = hierarchy.start(handoff.pair, {minX = -1024, maxX = 7000, minY = -2048, maxY = 2048})
    for _ = 1, 3000 do
        if job.finished then break end
        hierarchy.step(job, function() return {valid = true, height = 0, water = false} end)
    end
    eq(job.finished, true); eq(job.result.status, "ok"); eq(job.result.candidates[1].sourceId, 1)
    eq(job.result.candidates[1].constructionStatus, "unverified")
end)
test("pure topology has no engine access, mutations, filesystem or hidden corridor execution", function()
    local oldApi, oldIo = api, io
    api = setmetatable({}, {__index = function() error("unexpected engine access") end})
    io = setmetatable({}, {__index = function() error("unexpected filesystem access") end})
    local r = network.plan(example()); eq(r.status, "ok"); eq(r.stats.astarSearches, 0)
    api, io = oldApi, oldIo
end)
print("PASS " .. passed .. " network topology tests (synthetic only)")
