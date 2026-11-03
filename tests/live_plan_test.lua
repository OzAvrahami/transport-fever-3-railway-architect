-- Pure preparation and mocked GUI/engine integration; not a TF3 runtime test.
local flow = ug_require "oz_railway_network_architect::/live_plan_data.lua"
local planner = ug_require "oz_railway_network_architect::/planning/corridor_planner.lua"
local passed = 0
local function equal(a, b) assert(a == b, "expected " .. tostring(b) .. ", got " .. tostring(a)) end
local function test(name, run)
    local ok, reason = pcall(run)
    assert(ok, name .. ": " .. tostring(reason))
    passed = passed + 1; print("PASS live integration: " .. name)
end
local function serialize(value)
    if type(value) ~= "table" then return tostring(value) end
    local keys, parts = {}, {}
    for key in pairs(value) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for _, key in ipairs(keys) do parts[#parts + 1] = tostring(key) .. "=" .. serialize(value[key]) end
    return "{" .. table.concat(parts, ",") .. "}"
end
local bounds = {minX = -2048, maxX = 2048, minY = -1024, maxY = 1024}
local function towns()
    return {{id = 10, name = "Alpha", x = -300, y = -100, z = 7},
        {id = 20, name = "Beta", x = 400, y = 220, z = 5}}
end
test("deterministic closest pair, lexicographic ties, ID validation and deduplication", function()
    local raw = {{id = 30, x = 100, y = 0, z = 1}, {id = 20, x = 0, y = 100, z = 1}, {id = 10, x = 0, y = 0, z = 1}}
    local pair = assert(flow.select(raw, bounds, flow.config()))
    equal(pair.start.id, 10); equal(pair.destination.id, 20); equal(pair.distance, 100)
    local ids, rejected = flow.ids({30, 10, 30, -2, "bad", 20}, 256)
    equal(table.concat(ids, ","), "10,20,30"); equal(rejected, 3)
end)
test("world coordinates convert to exact regular-grid endpoints with reported offsets", function()
    local pair = assert(flow.select(towns(), bounds, flow.config()))
    local layout = assert(flow.layout(pair, bounds, flow.config()))
    equal(layout.columns, 25); equal(layout.rows, 13); equal(layout.spacing, 32)
    equal(layout.start.distance, 0); equal(layout.destination.dx, 4); equal(layout.destination.distance, 4)
    equal(layout.destination.x, pair.destination.x + layout.destination.dx)
    for index = 1, layout.requested do
        local x, y = flow.position(layout, index)
        equal(x % 1, 0); equal(y % 1, 0)
        assert(x > bounds.minX and x < bounds.maxX and y > bounds.minY and y < bounds.maxY)
    end
end)
test("offset rectangular bounds and adaptive resolution remain bounded", function()
    local b = {minX = 900.25, maxX = 6000.75, minY = -4000.5, maxY = -1000.5}
    local ts = {{id = 1, x = 1100.5, y = -3800.2, z = 0}, {id = 2, x = 4200.8, y = -1400.1, z = -2}}
    local layout = assert(flow.layout(assert(flow.select(ts, b, flow.config())), b, flow.config()))
    equal(layout.spacing, 128); assert(layout.columns <= 32 and layout.rows <= 32)
    assert(layout.start.distance <= 96 and layout.destination.distance <= 96)
    local lastX, lastY = flow.position(layout, layout.requested)
    assert(layout.originX > b.minX and lastX < b.maxX and layout.originY > b.minY and lastY < b.maxY)
end)
test("invalid positions, insufficient towns and unrepresentable anchors stop explicitly", function()
    equal(select(2, flow.select({}, bounds, flow.config())), "fewer_than_two_valid_towns")
    equal(select(2, flow.select({towns()[1]}, bounds, flow.config())), "fewer_than_two_valid_towns")
    local ts = towns(); ts[2].x = 0/0
    equal(select(2, flow.select(ts, bounds, flow.config())), "fewer_than_two_valid_towns")
    ts = towns(); ts[2].x, ts[2].y = ts[1].x, ts[1].y
    equal(select(2, flow.select(ts, bounds, flow.config())), "no_distinct_anchor_positions")
    ts = towns(); ts[2].x, ts[2].y = ts[1].x + 1, ts[1].y
    local layout, reason = flow.layout(assert(flow.select(ts, bounds, flow.config())), bounds, flow.config())
    equal(layout, nil); equal(reason, "anchors_snap_to_same_sample")
    ts = {{id = 1, x = -9000, y = 0, z = 0}, {id = 2, x = 9000, y = 0, z = 0}}
    local large = {minX = -10000, maxX = 10000, minY = -1000, maxY = 1000}
    equal(flow.layout(assert(flow.select(ts, large, flow.config())), large, flow.config()), nil)
end)
test("missing samples preserve unknowns while false water and negative heights survive", function()
    local layout = assert(flow.layout(assert(flow.select(towns(), bounds, flow.config())), bounds, flow.config()))
    local session = {layout = layout, samples = {{valid = true, height = -2, water = false}, {valid = false, height = 999, water = false}}}
    local input = flow.input(session, flow.config())
    equal(input.grid.cells[1].height, -2); equal(input.grid.cells[1].water, false)
    equal(input.grid.cells[2].height, nil); equal(input.grid.cells[3].water, nil)
    equal(input.grid.cells[1].blocked, nil); equal(input.grid.cells[1].obstaclePenalty, nil)
end)

-- Mock only documented APIs; actual modules/descriptor/core are loaded below.
local entities, ids, worldId, tick, clock, clockStep, mapBounds, logs, reads, heightReads, sampleMode
local corePlan, defaultConfig = planner.plan, flow.config
local realRequire = ug_require
ug_require = function(resource)
    if resource == "::/scripts/entity_util.tl" then
        return {getPosition = function(id)
            local t = entities[id]
            return t and {x = t.x, y = t.y, z = t.z} or nil
        end}
    end
    return realRequire(resource)
end
local function reset()
    entities = {}; for _, t in ipairs(towns()) do entities[t.id] = t end
    ids, worldId, tick, clock, clockStep = {20, 10}, 99, 10, 1, 0
    mapBounds, logs, reads, heightReads, sampleMode = bounds, {}, 0, 0, "flat"
    planner.plan, flow.config = corePlan, defaultConfig
    api = {type = {ComponentType = {GAME_TIME = "time", TOWN = "town", BOUNDING_VOLUME = "volume"},
        Vec2f = {new = function(x, y) return {x = x, y = y} end}},
        util = {getApplicationTime = function() clock = clock + clockStep; return clock end},
        engine = {
            entityExists = function(id) reads = reads + 1; return id == worldId or entities[id] ~= nil end,
            getComponent = function(id, kind)
                reads = reads + 1
                if id == worldId and kind == "time" then return {tickCount = tick} end
                if entities[id] and kind == "town" then return {} end
                return nil
            end,
            getEntitiesWithComponent = function(kind) reads = reads + 1; equal(kind, "town"); return ids end,
            util = {getWorld = function() reads = reads + 1; return worldId end,
                getEntityName = function(id) return entities[id] and entities[id].name end},
            terrain = {
                getBoundingBox = function() return {min = {x = mapBounds.minX, y = mapBounds.minY}, max = {x = mapBounds.maxX, y = mapBounds.maxY}} end,
                isValidCoordinate = function() return true end,
                getHeightAt = function(p)
                    heightReads = heightReads + 1
                    if sampleMode == "missing" and p.x == -268 then error("synthetic height read failure", 0) end
                    return -2
                end,
                isOnWater = function(p) return sampleMode == "water" and p.x > -32 and p.x < 32 end,
            },
        }}
    debugPrint = function(message) logs[#logs + 1] = message end
end
local function newSession(overrides)
    reset()
    flow.config = function()
        local config = defaultConfig()
        for key, value in pairs(overrides or {}) do config[key] = value end
        return config
    end
    dofile(CONTENT .. "/live_plan.script.lua")
    local callback = data().guiUpdate
    flow.config = defaultConfig
    local saved
    local gui = {get = function() return saved end, set = function(_, value) saved = value end}
    local function step(count) for _ = 1, count or 1 do callback(nil, nil, gui) end end
    local function untilState(predicate)
        for _ = 1, 3000 do
            if predicate(gui:get()) then return end
            step()
        end
        error("session did not reach expected state")
    end
    return gui, step, untilState
end
local function begin(step) step(); tick = tick + 1; step(29) end
local function completed(value) return value and value.finished end
local function hasLog(fragment)
    for _, line in ipairs(logs) do if line:find(fragment, 1, true) then return true end end
    return false
end

test("complete GUI path owns data, uses canonical planner and runs once", function()
    local gui, step, untilState = newSession()
    step(60); equal(heightReads, 0); assert(not hasLog(" START "))
    tick = tick + 1
    untilState(completed)
    local session = gui:get()
    equal(session.status, "ok"); equal(session.pair.start.id, 10); equal(session.pair.destination.id, 20)
    equal(#session.samples, session.layout.requested); equal(session.result.status, "ok")
    local again = corePlan(flow.input(session, defaultConfig()))
    equal(serialize(session.result), serialize(again))
    assert(hasLog("CANDIDATE rank=1")); assert(hasLog("COMPLETE status=ok")); assert(hasLog("obstacles_unaccounted_for"))
    assert(hasLog("data_complete=true"))
    local previousReads, count = reads, #logs
    step(100); equal(reads, previousReads); equal(#logs, count)
    equal(session.townsStartTick, 11); equal(session.terrainEndTick, 11); equal(session.planEndTick, 11)
end)
test("fresh GUI sessions plan again and repeated results stay stable", function()
    local a, stepA, finishA = newSession(); begin(stepA); finishA(completed)
    local expected = serialize(a:get().result)
    local b, stepB, finishB = newSession(); begin(stepB); finishB(completed)
    equal(serialize(b:get().result), expected)
end)
test("empty and single-town live maps are unsupported without terrain reads", function()
    for _, listing in ipairs({{}, {10}}) do
        local gui, step, untilState = newSession(); ids = listing
        begin(step); untilState(completed)
        equal(gui:get().status, "unsupported"); equal(gui:get().reason, "fewer_than_two_valid_towns"); equal(heightReads, 0)
    end
end)
test("native coordinate validity and conversion guard precede terrain reads", function()
    reset()
    local adapter = ug_require "oz_railway_network_architect::/live_plan_api.lua"
    local sample = adapter.sample(bounds, bounds.maxX, 0)
    equal(sample.valid, false); equal(heightReads, 0)
    api.type.Vec2f.new = function(x, y) return {x = x + 0.01, y = y} end
    sample = adapter.sample(bounds, 0, 0)
    equal(sample.height, nil); equal(heightReads, 0); assert(sample.errors[1]:find("native coordinates differ", 1, true))
end)
test("protected missing reads retain API details and force incomplete or unreachable output", function()
    local gui, step, untilState = newSession(); sampleMode = "missing"
    begin(step); untilState(completed)
    equal(gui:get().status, "unreachable") -- Entire height-missing column divides this grid.
    assert(gui:get().failedSamples > 0); assert(gui:get().failedReads > 0)
    assert(hasLog("api.engine.terrain.getHeightAt: synthetic height read failure"))
    assert(hasLog("reason=\"open_set_exhausted\""))
    local second, advance, finish = newSession()
    api.engine.terrain.getHeightAt = function(p)
        heightReads = heightReads + 1
        if p.x == -268 and p.y == -132 then error("one missing corner", 0) end
        return 0
    end
    begin(advance); finish(completed)
    equal(second:get().status, "incomplete"); equal(second:get().result.status, "ok")
    assert(hasLog("data_complete=false"))
end)
test("water exclusion is unreachable while explicitly configured penalties permit sampled routes", function()
    local gui, step, untilState = newSession(); sampleMode = "water"
    begin(step); untilState(completed); equal(gui:get().status, "unreachable")
    local other, advance, finish = newSession({waterPolicy = "penalize"}); sampleMode = "water"
    begin(advance); finish(completed); equal(other:get().status, "ok")
    for _, candidate in ipairs(other:get().result.candidates) do equal(candidate.touchesWater, true) end
end)
test("search limit remains distinct from unreachable", function()
    local gui, step, untilState = newSession({maxExpansions = 1})
    begin(step); untilState(completed)
    equal(gui:get().status, "search_limit"); equal(gui:get().result.complete, false)
    equal(gui:get().result.stats.expansions, 1); equal(#gui:get().result.candidates, 0)
end)
test("world ID and tick invalidation stop before further sampling", function()
    for _, change in ipairs({"id", "tick"}) do
        local gui, step, untilState = newSession(); begin(step)
        untilState(function(s) return s and s.phase == "sampling" end)
        local count = heightReads
        if change == "id" then worldId = 100 else tick = 5 end
        untilState(completed)
        equal(gui:get().status, "invalidated"); equal(heightReads, count); equal(gui:get().result, nil)
    end
end)
test("town movement and bounds changes invalidate captured provenance", function()
    for _, change in ipairs({"town", "bounds"}) do
        local gui, step, untilState = newSession(); begin(step)
        untilState(function(s) return s and s.phase == "planning" end)
        if change == "town" then entities[10].x = entities[10].x + 1
        else mapBounds = {minX = -2048, maxX = 2049, minY = -1024, maxY = 1024} end
        untilState(completed)
        equal(gui:get().status, "invalidated"); equal(gui:get().result, nil)
        assert(not hasLog("CANDIDATE rank="))
    end
end)
test("world change during planner execution discards computed candidates", function()
    local gui, step, untilState = newSession()
    planner.plan = function(input) local result = corePlan(input); worldId = 100; return result end
    begin(step); untilState(completed)
    equal(gui:get().status, "invalidated"); equal(gui:get().result, nil); assert(not hasLog("CANDIDATE rank="))
    planner.plan = corePlan
end)
test("time budget and stale snapshot terminate without publishing candidates", function()
    local gui, step, untilState = newSession(); clockStep = 0.03
    begin(step); untilState(completed)
    equal(gui:get().status, "performance_limit"); equal(gui:get().result, nil)
    assert(hasLog("resumable_search")); assert(not hasLog("CANDIDATE rank="))
    local other, advance, finish = newSession(); begin(advance)
    clock = 100
    finish(completed); equal(other:get().status, "invalidated"); equal(other:get().reason, "snapshot_age_limit_exceeded")
    local third, nextStep, finishThird = newSession(); begin(nextStep)
    clock = 2; nextStep(4); clock = 1.5
    finishThird(completed)
    equal(third:get().status, "invalidated"); equal(third:get().reason, "application_clock_went_backwards")
end)
test("timer unavailable or enumeration failure cannot report success", function()
    local gui, step, untilState = newSession()
    api.util.getApplicationTime = function() return nil end
    begin(step); untilState(completed); equal(gui:get().status, "timing_unavailable"); equal(heightReads, 0)
    local second, advance, finish = newSession()
    api.engine.getEntitiesWithComponent = function() error("synthetic enumeration failure", 0) end
    begin(advance); finish(completed); equal(second:get().status, "error")
    assert(hasLog("api.engine.getEntitiesWithComponent(TOWN): synthetic enumeration failure"))
end)
test("town enumeration is capped and present non-function bindings are not pre-rejected", function()
    reset()
    local adapter = ug_require "oz_railway_network_architect::/live_plan_api.lua"
    api.engine.terrain.getHeightAt = {}
    equal(adapter.check(), nil)
    local sample = adapter.sample(bounds, 0, 0)
    assert(sample.errors[1]:find("api.engine.terrain.getHeightAt", 1, true))
    local many = {}; for id = 1, 257 do many[id] = id end
    local ok, reason = pcall(flow.ids, many, 256)
    equal(ok, false); assert(tostring(reason):find("limit exceeded", 1, true))
end)
test("configuration cannot increase the approved workload caps", function()
    for _, changes in ipairs({{gridLimit = 33}, {maxTowns = 257}, {maxExpansions = 3073},
        {workBudgetSeconds = 1}, {maxSnap = 97}, {waterPolicy = "guess"}}) do
        local gui, step = newSession(changes); step()
        equal(gui:get().status, "unsupported"); equal(reads, 0); equal(heightReads, 0)
    end
end)
print("PASS " .. passed .. " live planning integration tests (mocked engine, not runtime verification)")
