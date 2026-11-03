local planner = require "planning.corridor_planner"
local grid = require "planning.corridor_grid"
local fixtures = require "tests.corridor_fixtures"
local passed = 0
local function equal(actual, expected)
    assert(actual == expected, "expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function near(actual, expected)
    assert(math.abs(actual - expected) <= 1e-8 * math.max(1, math.abs(expected)),
        "expected approximately " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function serialize(value)
    if type(value) ~= "table" then return tostring(value) end
    local keys, parts = {}, {}
    for key in pairs(value) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for _, key in ipairs(keys) do parts[#parts + 1] = tostring(key) .. "=" .. serialize(value[key]) end
    return "{" .. table.concat(parts, ",") .. "}"
end
local function contains(array, value)
    for _, item in ipairs(array) do if item == value then return true end end
    return false
end
local function test(name, run)
    local ok, reason = pcall(run)
    assert(ok, name .. ": " .. tostring(reason))
    passed = passed + 1
    print("PASS planning: " .. name)
end
local function byProfile(result, name)
    for _, candidate in ipairs(result.candidates) do
        if contains(candidate.generatedBy, name) then return candidate end
    end
    error("missing retained profile " .. name)
end

test("flat map and straight connection", function()
    local input = fixtures.flat(6, 3)
    local result = planner.plan(input)
    equal(result.status, "ok"); equal(result.complete, true); equal(#result.candidates, 1)
    local c = result.candidates[1]
    equal(#c.waypoints, 6); near(c.length, 50); near(c.score.total, 50)
    equal(c.elevationGain, 0); equal(c.maxGradient, 0)
    for index, waypoint in ipairs(c.waypoints) do
        equal(waypoint.x, (index - 1) * 10); equal(waypoint.y, 10); equal(waypoint.z, 0)
    end
end)
test("mountain obstructs direct route under illustrative gradient cap", function()
    local input = fixtures.mountain()
    local result = planner.plan(input)
    equal(result.status, "ok")
    for _, c in ipairs(result.candidates) do
        assert(c.length > 80); assert(c.maxGradient <= 0.25)
        for _, p in ipairs(c.waypoints) do equal(p.z, 0) end
    end
end)
test("valley is preferable under terrain scoring", function()
    local result = planner.plan(fixtures.valley())
    local distance, terrain = byProfile(result, "distance"), byProfile(result, "terrain")
    assert(terrain.length > distance.length); assert(terrain.cumulativeElevationChange < distance.cumulativeElevationChange)
    equal(terrain.maxGradient, 0)
end)
test("water barrier penalized or excluded without bridge claims", function()
    local input = fixtures.water()
    local result = planner.plan(input)
    equal(result.status, "ok")
    local c = result.candidates[1]
    equal(c.touchesWater, true); equal(c.waterRuns, 1); equal(#c.waterTransitions, 2)
    equal(c.waterSegments, 2); near(c.waterExposure, 20); near(c.score.water, 40)
    equal(c.constructionStatus, "unverified")
    assert(contains(c.warnings, "water_crossing_structure_unverified"))
    input.constraints = {waterPolicy = "exclude"}
    result = planner.plan(input)
    equal(result.status, "unreachable"); equal(#result.candidates, 0); equal(result.complete, true)
    -- A dry gap makes a detour possible; soft water weights should also prefer it.
    fixtures.cell(input, 4, 1).water = false
    equal(planner.plan(input).status, "ok")
    input.constraints = {waterPolicy = "penalize"}
    result = planner.plan(input)
    assert(byProfile(result, "distance").waterExposure > 0)
    equal(byProfile(result, "terrain").waterExposure, 0)
end)
test("long route around steep terrain versus uncapped distance profile", function()
    local input = fixtures.mountain()
    fixtures.cell(input, 5, 4).height = 5
    local capped = planner.plan(input)
    input.constraints = {}
    local uncapped = planner.plan(input)
    assert(capped.candidates[1].length > byProfile(uncapped, "distance").length)
    assert(byProfile(uncapped, "distance").maxGradient > 0.25)
end)
test("completely unreachable destination", function()
    local input = fixtures.flat(7, 5)
    for row = 1, 5 do fixtures.cell(input, 4, row).blocked = true end
    local result = planner.plan(input)
    equal(result.status, "unreachable"); equal(#result.candidates, 0)
    for _, profile in ipairs(result.profiles) do equal(profile.reason, "open_set_exhausted") end
end)
test("identical endpoints return a single zero-length candidate", function()
    local input = fixtures.flat(3, 3)
    input.destination = {x = input.start.x, y = input.start.y}
    local result = planner.plan(input)
    equal(#result.candidates, 1); equal(#result.candidates[1].waypoints, 1)
    equal(result.candidates[1].length, 0); equal(result.candidates[1].score.total, 0)
    equal(result.stats.expansions, 3)
    fixtures.cell(input, 1, 2).blocked = true
    equal(planner.plan(input).status, "unreachable")
end)
test("missing height or water excluded; invalid heights rejected", function()
    local input = fixtures.flat(5, 3)
    fixtures.cell(input, 3, 2).height = nil
    fixtures.cell(input, 2, 1).water = nil
    local result = planner.plan(input)
    equal(result.status, "ok"); equal(result.unknownCells, 2)
    for _, c in ipairs(result.candidates) do
        assert(not contains(c.sampleIds, 8)); assert(not contains(c.sampleIds, 2))
    end
    for _, invalid in ipairs({0/0, math.huge, -math.huge, "0", false}) do
        fixtures.cell(input, 3, 2).height = invalid
        local rejected = planner.plan(input)
        equal(rejected.status, "invalid_input"); equal(rejected.error.path, "grid.cells[8].height")
    end
end)
test("deterministic repeated planning without mutating input", function()
    local input = fixtures.comparison()
    local before = serialize(input)
    local expected = serialize(planner.plan(input))
    for _ = 1, 10 do equal(serialize(planner.plan(input)), expected) end
    equal(serialize(input), before)
end)
test("duplicate and similar alternatives are not fabricated", function()
    local input = fixtures.flat(8, 4)
    local result = planner.plan(input)
    equal(#result.candidates, 1); equal(#result.candidates[1].generatedBy, 3)
    equal(result.profiles[2].disposition, "duplicate")
    input = fixtures.comparison()
    input.minDifference = 1
    result = planner.plan(input)
    assert(#result.candidates < 3)
    local similar = false
    for _, profile in ipairs(result.profiles) do if profile.disposition == "similar" then similar = true end end
    assert(similar)
end)
test("cell and expansion limits cannot masquerade as unreachable", function()
    local input = fixtures.flat(5, 5)
    input.limits = {maxCells = 24}
    equal(planner.plan(input).status, "input_limit")
    input.limits = {maxExpansions = 1}
    local result = planner.plan(input)
    equal(result.status, "search_limit"); equal(result.complete, false)
    equal(result.stats.expansions, 1); equal(#result.candidates, 0)
    input.limits = {maxExpansions = 5}
    result = planner.plan(input)
    equal(result.status, "search_limit"); equal(result.complete, false)
    equal(#result.candidates, 1); equal(result.stats.expansions, 5)
    input.grid.columns, input.grid.rows = 256, 256
    input.limits = nil
    equal(planner.plan(input).status, "input_limit")
end)
test("three profiles produce distinct choices and common ranking", function()
    local result = planner.plan(fixtures.comparison())
    equal(#result.candidates, 3)
    local d, t, b = byProfile(result, "distance"), byProfile(result, "terrain"), byProfile(result, "balanced")
    assert(d.length < b.length and b.length < t.length)
    assert(d.maxGradient > b.maxGradient and b.maxGradient > t.maxGradient)
    equal(result.candidates[1].id, b.id)
    for rank, c in ipairs(result.candidates) do
        equal(c.rank, rank)
        near(c.score.total, c.score.distance + c.score.gradient + c.score.waterObstacle)
        near(c.score.gradient, c.gradientExposure * 8)
        if rank > 1 then assert(c.score.total >= result.candidates[rank - 1].score.total) end
    end
end)
test("configurable search and ranking weights have independent effects", function()
    local input = fixtures.comparison()
    input.rankingWeights = {gradient = 0, water = 0, obstacle = 0}
    local result = planner.plan(input)
    equal(result.candidates[1].id, "corridor_distance"); equal(#result.candidates, 3)
    input.profiles = {terrain = {gradient = 0, water = 0, obstacle = 0},
        balanced = {gradient = 0, water = 0, obstacle = 0}}
    result = planner.plan(input)
    equal(#result.candidates, 1); equal(#result.candidates[1].generatedBy, 3)
    input.rankingWeights = nil
    result = planner.plan(input)
    equal(result.rankingWeights.gradient, 8)
end)
test("rectangular diagonal distance and explicit cardinal-only movement", function()
    local input = fixtures.flat(3, 3)
    input.grid.spacingY, input.grid.originX, input.grid.originY = 20, -100, -50
    input.start, input.destination = {x = -100, y = -50}, {x = -80, y = -10}
    local result = planner.plan(input)
    near(result.candidates[1].length, 2 * math.sqrt(500))
    input.constraints = {allowDiagonal = false}
    near(planner.plan(input).candidates[1].length, 60)
end)
test("fine grid at large world offsets retains valid sample endpoints", function()
    local input = fixtures.flat(3, 1)
    input.grid.originX, input.grid.originY = -1e9, 1e9
    input.grid.spacingX = 0.001
    input.start = {x = -1e9, y = 1e9}
    input.destination = {x = input.grid.originX + 2 * input.grid.spacingX, y = 1e9}
    local result = planner.plan(input)
    equal(result.status, "ok"); near(result.candidates[1].length, 0.002)
    equal(result.candidates[1].waypoints[3].x, input.destination.x)
end)
test("no diagonal corner cutting across blocked, unknown, water or steep side samples", function()
    for _, kind in ipairs({"blocked", "unknown", "water", "steep"}) do
        local input = fixtures.flat(2, 2)
        input.start, input.destination = {x = 0, y = 0}, {x = 10, y = 10}
        for _, id in ipairs({2, 3}) do
            local cell = input.grid.cells[id]
            if kind == "blocked" then cell.blocked = true
            elseif kind == "unknown" then cell.height = nil
            elseif kind == "water" then cell.water = true
            else cell.height = 10 end
        end
        input.constraints = {waterPolicy = "exclude", maxGradient = 0.2}
        equal(planner.plan(input).status, "unreachable")
    end
    local input = fixtures.flat(2, 2)
    input.start, input.destination = {x = 0, y = 0}, {x = 10, y = 10}
    input.grid.cells[2].blocked = true
    near(planner.plan(input).candidates[1].length, 20) -- Must use the open cardinal detour.
end)
test("elevation gain/loss and rise/run are physically scaled", function()
    local input = fixtures.flat(3, 1)
    input.grid.cells[1].height, input.grid.cells[2].height, input.grid.cells[3].height = -2, 1, -1
    local c = planner.plan(input).candidates[1]
    equal(c.elevationGain, 3); equal(c.elevationLoss, 2); equal(c.cumulativeElevationChange, 5)
    near(c.maxGradient, 0.3); near(c.length, math.sqrt(109) + math.sqrt(104))
    near(c.gradientExposure, 1.3)
end)
test("soft obstacle penalty affects choices and score breakdown", function()
    local input = fixtures.flat(7, 5)
    fixtures.cell(input, 4, 3).obstaclePenalty = 10
    local result = planner.plan(input)
    assert(byProfile(result, "distance").obstacleExposure > 0)
    equal(byProfile(result, "terrain").obstacleExposure, 0)
    for _, c in ipairs(result.candidates) do near(c.score.obstacle, c.obstacleExposure * 2) end
end)
test("invalid configuration and off-grid endpoints fail explicitly", function()
    for _, bad in ipairs({false, "grid", 10}) do equal(planner.plan(bad).status, "invalid_input") end
    local mutations = {
        function(i) i.constraints = false end,
        function(i) i.profiles = false end,
        function(i) i.profiles = {terrain = {distance = 0}} end,
        function(i) i.rankingWeights = {water = -1} end,
        function(i) i.limits = {maxExpansions = false} end,
        function(i) i.constraints = {maxGradient = math.huge} end,
        function(i) i.grid.spacingX = 0 end,
        function(i) i.grid.cells[1].obstaclePenalty = false end,
        function(i) i.grid.cells[1].water = "false" end,
        function(i) i.grid.cells[1].blocked = 0 end,
        function(i) i.grid.cells[1] = nil end,
        function(i) i.start.x = 1 end,
        function(i) i.destination.x = 1000 end,
        function(i) i.constraints = {maxGradent = 0.1} end,
        function(i) setmetatable(i.grid.cells, {__pairs = function() error("must not execute") end}) end,
    }
    for _, mutate in ipairs(mutations) do
        local input = fixtures.flat(4, 4); mutate(input)
        equal(planner.plan(input).status, "invalid_input")
    end
end)
test("infrastructure hints require provenance and never grant connectivity or discounts", function()
    local input = fixtures.flat(4, 4)
    local before = planner.plan(input).candidates[1].score.total
    input.infrastructureHints = {{id = "synthetic_node", x = 10, y = 10, verified = true, source = "fixture"}}
    local result = planner.plan(input)
    equal(result.infrastructureHintCount, 1); equal(result.candidates[1].score.total, before)
    assert(contains(result.warnings, "infrastructure_hints_not_used_for_routing"))
    input.infrastructureHints[1].verified = false
    equal(planner.plan(input).status, "invalid_input")
end)

-- Independent O(V^2) shortest-path selection validates A* priorities/heap on small graphs.
-- Uses the shared transition contract; geometric formulas have separate analytic tests above.
local function referenceDistance(model, weights)
    if not model.cells[model.start].traversable or not model.cells[model.destination].traversable then return nil end
    local dist, done = {[model.start] = 0}, {}
    for _ = 1, #model.cells do
        local best
        for id = 1, #model.cells do
            if not done[id] and dist[id] ~= nil and (best == nil or dist[id] < dist[best]) then best = id end
        end
        if best == nil then return nil end
        if best == model.destination then return dist[best] end
        done[best] = true
        for id = 1, #model.cells do
            if not done[id] then
                local step = grid.step(model, best, id)
                if step then
                    local candidate = dist[best] + grid.score(step, weights).total
                    if dist[id] == nil or candidate < dist[id] then dist[id] = candidate end
                end
            end
        end
    end
end
test("A* matches reference shortest-path scores on varied small grids", function()
    for seed = 1, 16 do
        local input = fixtures.flat(5, 5)
        for id, cell in ipairs(input.grid.cells) do
            cell.height = ((id * 17 + seed * 13) % 11) - 5
            cell.water = (id * seed) % 7 == 0
            cell.blocked = (id + seed) % 9 == 0
            cell.obstaclePenalty = (id + seed) % 3
        end
        local model, result = grid.validate(input), planner.plan(input)
        for index, profile in ipairs(model.profiles) do
            local expected = referenceDistance(model, profile.weights)
            if expected == nil then equal(result.profiles[index].status, "unreachable")
            else near(result.profiles[index].searchScore, expected) end
        end
    end
end)
test("maximum supported grid stays within expansion and heap bounds", function()
    local input = fixtures.flat(128, 128)
    local result = planner.plan(input)
    equal(result.status, "ok"); equal(result.stats.cells, 16384)
    assert(result.stats.expansions <= 49152); assert(result.stats.peakOpen <= 16384)
    -- Isolate the valid destination while leaving almost the entire grid reachable.
    for row = 63, 65 do fixtures.cell(input, 127, row).blocked = true end
    fixtures.cell(input, 128, 63).blocked, fixtures.cell(input, 128, 65).blocked = true, true
    result = planner.plan(input)
    equal(result.status, "unreachable"); equal(result.complete, true)
    equal(result.stats.expansions, 49134); assert(result.stats.peakOpen <= 16384)
    print(string.format("STRESS cells=%d expansions=%d peak_open=%d", result.stats.cells, result.stats.expansions, result.stats.peakOpen))
end)

print("SYNTHETIC COMPARISON: ridge fixture; length and scores are planning values")
for _, c in ipairs(planner.plan(fixtures.comparison()).candidates) do
    print(string.format("rank=%d id=%s length=%.6f gain=%.3f loss=%.3f max_gradient=%.6f distance_score=%.6f gradient_score=%.6f water_obstacle_score=%.6f total=%.6f",
        c.rank, c.id, c.length, c.elevationGain, c.elevationLoss, c.maxGradient,
        c.score.distance, c.score.gradient, c.score.waterObstacle, c.score.total))
end
print("PASS " .. passed .. " corridor planning tests (synthetic only)")
