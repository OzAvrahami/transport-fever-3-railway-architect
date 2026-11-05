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
local corePlan, coreStep, defaultConfig = planner.plan, planner.step, flow.config
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
    planner.plan, planner.step, flow.config = corePlan, coreStep, defaultConfig
    api = {type = {ComponentType = {GAME_TIME = "time", TOWN = "town", BOUNDING_VOLUME = "volume"},
        Vec2f = {new = function(x, y) return {x = x, y = y} end}},
        util = {getApplicationTime = function() clock = clock + clockStep; return clock end},
        engine = {
            system = {gameScriptSystem = {getEntityForGameScript = function(name)
                equal(name, "oz_railway_network_architect" .. "::/live_plan.gs")
                return 800
            end}},
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
local function newSession(overrides, deliveryGate)
    reset()
    flow.config = function()
        local config = defaultConfig()
        for key, value in pairs(overrides or {}) do config[key] = value end
        return config
    end
    -- Resource modules are loaded once per runtime; isolate config between test games.
    package.loaded["live_plan_request"] = nil
    package.loaded["station_plan_request"] = nil
    package.loaded["network_batch"] = nil
    -- Resolve the actual descriptor exports, rather than assuming registration.
    dofile(CONTENT .. "/live_plan.gs.lua")
    local descriptor = data()
    local loaded = {}
    local function resolve(reference)
        local prefix = "oz_railway_network_architect" .. "::/"
        local path, export = reference:match("^" .. prefix .. "(.+)@(%w+)$")
        assert(path and export, "invalid Game Script reference")
        if not loaded[path] then dofile(CONTENT .. "/" .. path .. ".lua"); loaded[path] = data() end
        return assert(loaded[path][export], "missing Game Script callback export")
    end
    local callbacks = {update = resolve(descriptor.updateScript.fileName),
        guiUpdate = resolve(descriptor.guiUpdateScript.fileName),
        guiHandleEvent = resolve(descriptor.guiHandleEventScript.fileName)}
    flow.config = defaultConfig
    local saved
    local gui = {get = function() return saved end, set = function(_, value) saved = value end}
    -- Shipped company initialization subscribes engine state to GUI event names.
    -- Model that prerequisite, not the unavailable native dispatcher internals.
    local subscriptions = {}
    local engineState = {
        hasEventSubscriptions = function() return next(subscriptions) ~= nil end,
        subscribeToEvent = function(_, name) subscriptions[name] = (subscriptions[name] or 0) + 1 end,
    }
    callbacks.subscriptions, callbacks.engineState = subscriptions, engineState
    local function step(count)
        for _ = 1, count or 1 do
            if callbacks.update then callbacks.update(nil, engineState, 0) end
            callbacks.guiUpdate(nil, nil, gui)
        end
    end
    local function untilState(predicate)
        for _ = 1, 3000 do
            if predicate(gui:get()) then return end
            step()
        end
        error("session did not reach expected state: " .. table.concat(logs, "\n", math.max(1,#logs-20)))
    end
    local function event(name, param)
        return callbacks.guiHandleEvent(nil, nil, gui, "test", "oz_railway_network_architect.plan",
            "oz_railway_network_architect.plan." .. name, param or {})
    end
    api.gui = {fireGuiScriptEvent = function(id, name, param)
        -- Documented seven-argument callback and synchronous result. Native
        -- broadcast/aggregation internals are unknown: this is one handler only.
        -- Tests may deny delivery BEFORE handler invocation. A gate is a fault
        -- model, not a claimed reconstruction of TF3's component-ID resolver.
        if not subscriptions[name] then return nil end
        if deliveryGate and not deliveryGate(id, name) then return nil end
        return callbacks.guiHandleEvent(nil, nil, gui, "test", id, name, param)
    end}
    return gui, step, untilState, event, callbacks
end
local function ready(step, untilState)
    step(); tick = tick + 1
    untilState(function(s) return s and (s.status == "idle" or s.status == "unsupported" or s.status == "error") end)
end
local function submit(gui, event, sourceId, destinationId)
    local s = gui:get()
    return event("plan", {world = s.world, epoch = s.epoch, requestId = s.requestId + 1,
        sourceId = sourceId or 10, destinationId = destinationId or 20})
end
local function completed(s) return s and s.request and s.request.finished end
local function hasLog(fragment)
    for _, line in ipairs(logs) do if line:find(fragment, 1, true) then return true end end
    return false
end
local function logCount(fragment)
    local count = 0
    for _, line in ipairs(logs) do if line:find(fragment, 1, true) then count = count + 1 end end
    return count
end

test("no automatic plan on map load, status polls or idle callbacks", function()
    local gui, step, untilState, event = newSession()
    step(60); equal(heightReads, 0); equal(gui:get().ready, nil)
    tick = tick + 1
    untilState(function(s) return s and s.status == "idle" end)
    step(400); for _ = 1, 5 do event("status") end
    equal(heightReads, 0); equal(gui:get().request, nil); equal(logCount("REQUEST_START"), 0)
    equal(event("status").message, "No request submitted. Select two towns and press Plan.")
end)

test("explicit pair preserves direction, canonical core, data and single execution", function()
    local gui, step, untilState, event = newSession(); ready(step, untilState)
    equal(submit(gui, event, 20, 10).accepted, true)
    untilState(completed)
    local session = gui:get().request
    equal(session.status, "ok"); equal(session.pair.start.id, 20); equal(session.pair.destination.id, 10)
    local expected = corePlan(flow.input(session, defaultConfig()))
    equal(#session.result.candidates, #expected.candidates)
    for index, c in ipairs(expected.candidates) do
        local actual, geometry = session.result.candidates[index], {}
        equal(actual.sourceId, 20); equal(actual.destinationId, 10); equal(actual.refinedSections, 1)
        equal(actual.sampling.fineSpacing, session.layout.spacing)
        for key in pairs(c) do geometry[key] = actual[key] end
        equal(serialize(geometry), serialize(c)) -- Canonical geometry/scoring remains identical.
    end
    local count = heightReads; step(300); equal(heightReads, count)
    equal(logCount("REQUEST_START"), 1); equal(logCount("COMPLETE status="), 1)
    assert(hasLog("data_complete=true")); assert(hasLog("ENDPOINT_VALIDATION status=ok"))
end)

test("duplicate names remain two numeric IDs and identical IDs are rejected", function()
    local gui, step, untilState, event = newSession()
    entities[10].name, entities[20].name = "Same", "Same"
    ready(step, untilState)
    local townsView = event("status").towns
    equal(#townsView, 2); equal(townsView[1].name, townsView[2].name)
    equal(townsView[1].id, 10); equal(townsView[2].id, 20)
    equal(submit(gui, event, 10, 10).reason, "same_town"); equal(gui:get().request, nil)
    equal(submit(gui, event).accepted, true); untilState(completed)
end)

test("stale or malformed selections never fall back to nearest towns", function()
    local gui, step, untilState, event = newSession(); ready(step, untilState)
    equal(submit(gui, event, "10", 20).reason, "invalid_selected_ids")
    equal(submit(gui, event, 30, 20).reason, "selection_not_in_town_list")
    entities[10] = nil
    equal(submit(gui, event).reason, "selected_town_unavailable")
    equal(heightReads, 0); equal(gui:get().request, nil)
    assert(hasLog("ENDPOINT_ERROR id=10 detail=api.engine.entityExists"))
end)

test("one click token cannot replay, busy clicks rejected, sequential requests sample fresh", function()
    local gui, step, untilState, event = newSession(); ready(step, untilState)
    local s = gui:get(); local param = {world = s.world, epoch = s.epoch, requestId = 1, sourceId = 10, destinationId = 20}
    equal(event("plan", param).accepted, true)
    equal(event("plan", param).reason, "busy"); equal(event("refresh").reason, "busy")
    untilState(completed)
    equal(event("plan", param).reason, "duplicate_or_stale_request")
    local count, result = heightReads, serialize(gui:get().request.result)
    equal(submit(gui, event).accepted, true); untilState(completed)
    assert(heightReads > count); equal(logCount("REQUEST_START"), 2)
    equal(serialize(gui:get().request.result), result)
end)

test("world and tick changes invalidate request and stale selection tokens", function()
    for _, change in ipairs({"id", "tick"}) do
        local gui, step, untilState, event = newSession(); ready(step, untilState)
        local old = event("status"); submit(gui, event)
        untilState(function(s) return s.request and s.request.phase == "sampling" end)
        local count = heightReads
        if change == "id" then worldId = 100 else tick = 5 end
        step(4)
        equal(heightReads, count); equal(gui:get().request, nil); assert(gui:get().epoch > old.epoch)
        equal(event("plan", {world = old.world, epoch = old.epoch}).reason, "stale_session")
    end
end)

test("reactPostInit resets selections/results and fresh map requires a new explicit request", function()
    local gui, step, untilState, event, callbacks = newSession(); ready(step, untilState)
    submit(gui, event); untilState(completed); local before = gui:get().epoch
    callbacks.guiHandleEvent(nil, nil, gui, "test", "gameUI", "reactPostInit", {})
    equal(gui:get().request, nil); assert(gui:get().epoch > before)
    ready(step, untilState); local count = heightReads; step(100); equal(heightReads, count)
    submit(gui, event); untilState(completed); equal(gui:get().request.status, "ok")
end)

test("empty and single-town maps expose unsupported status without sampling", function()
    for _, listing in ipairs({{}, {10}}) do
        local gui, step, untilState, event = newSession(); ids = listing
        ready(step, untilState)
        equal(event("status").canPlan, false); equal(gui:get().status, "unsupported"); equal(heightReads, 0)
    end
end)

test("native coordinate validity and conversion guard precede terrain reads", function()
    reset(); local adapter = ug_require "oz_railway_network_architect::/live_plan_api.lua"
    equal(adapter.sample(bounds, bounds.maxX, 0).valid, false); equal(heightReads, 0)
    api.type.Vec2f.new = function(x, y) return {x = x + 0.01, y = y} end
    local sample = adapter.sample(bounds, 0, 0)
    equal(sample.height, nil); equal(heightReads, 0); assert(sample.errors[1]:find("native coordinates differ", 1, true))
end)

test("failed samples preserve API errors and incomplete or unreachable results", function()
    local gui, step, untilState, event = newSession(); sampleMode = "missing"
    ready(step, untilState); submit(gui, event); untilState(completed)
    equal(gui:get().request.status, "unreachable"); assert(gui:get().request.failedSamples > 0)
    assert(hasLog("api.engine.terrain.getHeightAt: synthetic height read failure"))
    local second, advance, finish, send = newSession()
    api.engine.terrain.getHeightAt = function(p)
        if p.x == -268 and p.y == -132 then error("one missing corner", 0) end
        return 0
    end
    ready(advance, finish); submit(second, send); finish(completed)
    equal(second:get().request.status, "incomplete"); assert(hasLog("data_complete=false"))
end)

test("water exclusion and controlled penalize setting keep accepted behavior", function()
    for _, policy in ipairs({"exclude", "penalize"}) do
        local gui, step, untilState, event = newSession({waterPolicy = policy}); sampleMode = "water"
        ready(step, untilState); submit(gui, event); untilState(completed)
        equal(gui:get().request.status, policy == "exclude" and "unreachable" or "ok")
        if policy == "penalize" then assert(gui:get().request.result.candidates[1].touchesWater) end
    end
end)

test("search limit remains distinct and next request is allowed", function()
    local gui, step, untilState, event = newSession({maxExpansions = 1})
    ready(step, untilState); submit(gui, event); untilState(completed)
    equal(gui:get().request.status, "search_limit"); equal(gui:get().request.result.stats.expansions, 1)
    equal(submit(gui, event).accepted, true)
end)

test("town movement or bounds changes during collection invalidate plan", function()
    for _, change in ipairs({"town", "bounds"}) do
        local gui, step, untilState, event = newSession(); ready(step, untilState); submit(gui, event)
        untilState(function(s) return s.request and s.request.phase == "planning" end)
        if change == "town" then entities[10].x = entities[10].x + 1
        else mapBounds = {minX = -2048, maxX = 2049, minY = -1024, maxY = 1024} end
        untilState(completed); equal(gui:get().request.status, "invalidated"); equal(gui:get().request.result, nil)
    end
end)

test("world change during search discards calculated candidates", function()
    local gui, step, untilState, event = newSession(); ready(step, untilState)
    planner.step = function(job, limit) local r = coreStep(job, limit); worldId = 100; return r end
    submit(gui, event); untilState(completed)
    equal(gui:get().request.status, "invalidated"); equal(gui:get().request.result, nil)
    assert(not hasLog("CANDIDATE rank=")); planner.step = coreStep
end)

test("zero work-clock readings report insufficient resolution, not zero cost", function()
    local gui, step, untilState, event = newSession(); ready(step, untilState)
    submit(gui, event); untilState(completed)
    equal(gui:get().request.maxWorkSeconds, 0)
    assert(hasLog("work_measurement=insufficient_resolution")); assert(hasLog("zero_is_not_zero_cost=true"))
end)

test("performance budget, snapshot age and clock reversal remain bounded", function()
    local gui, step, untilState, event = newSession(); ready(step, untilState); submit(gui, event)
    clockStep = 0.03; untilState(completed)
    equal(gui:get().request.status, "performance_limit"); equal(gui:get().request.result, nil)
    assert(not hasLog("CANDIDATE rank="))
    for _, backwards in ipairs({false, true}) do
        local other, advance, finish, send = newSession(); ready(advance, finish); submit(other, send)
        advance(4); clock = 2; advance(4); clock = backwards and 1.5 or 100
        finish(completed); equal(other:get().request.status, "invalidated")
        equal(other:get().request.reason, backwards and "application_clock_went_backwards" or "snapshot_age_limit_exceeded")
    end
end)

test("timer and enumeration errors are safe; Refresh towns can recover", function()
    local gui, step, untilState, event = newSession()
    api.util.getApplicationTime = function() return nil end
    ready(step, untilState); equal(gui:get().status, "error"); equal(heightReads, 0)
    local second, advance, finish, send = newSession()
    api.engine.getEntitiesWithComponent = function() error("synthetic enumeration failure", 0) end
    ready(advance, finish); equal(second:get().status, "error"); assert(hasLog("api.engine.getEntitiesWithComponent(TOWN)"))
    api.engine.getEntitiesWithComponent = function() return {10, 20} end
    equal(send("refresh").accepted, true)
    finish(function(s) return s.status == "idle" end); equal(send("status").canPlan, true)
end)

test("enumeration caps, callable binding assumptions and config limits stay enforced", function()
    reset(); local adapter = ug_require "oz_railway_network_architect::/live_plan_api.lua"
    api.engine.terrain.getHeightAt = {}; equal(adapter.check(), nil)
    assert(adapter.sample(bounds, 0, 0).errors[1]:find("api.engine.terrain.getHeightAt", 1, true))
    local many = {}; for id = 1, 257 do many[id] = id end
    equal(pcall(flow.ids, many, 256), false)
    for _, config in ipairs({{gridLimit = 33}, {maxTowns = 257}, {maxExpansions = 3073}, {workBudgetSeconds = 1}}) do
        local gui, step = newSession(config); step(); equal(gui:get().status, "error"); equal(heightReads, 0)
    end
end)

-- Exercise the real GUI recipe with a minimal hook/component mock, not a native UI claim.
local integrationRequire = ug_require
-- Ordinary plugin recipes must return a layout; wrapped native Window recipes
-- have a separate contract. BoxLayout may itself contain leaf widgets.
local function requirePluginLayout(root)
    assert(root and root.nodeType == "layout", "Recipe child must be a layout")
    return root
end
local function mountUI(playerView)
    local active
    local launcherContext = {hooks = {}, cursor = 0}
    local window, windowRecipe
    local controls = {adds = 0, removes = 0, focusReturns = 0, expired = false, available = true,
        autoJoin = true, events = {}, joins = {}}
    local context = "main"
    local function inContext(nextContext, fn)
        local previous = context; context = nextContext
        local ok, result = pcall(fn)
        context = previous
        if not ok then error(result, 0) end
        return result
    end
    controls.inContext = inContext
    local dispatch = api.gui.fireGuiScriptEvent
    api.gui.fireGuiScriptEvent = function(id, name, request)
        assert(context ~= "restricted", "API is currently restricted: api.gui.fireGuiScriptEvent")
        equal(context, "join") -- this mod routes even user actions through a join
        controls.events[#controls.events + 1] = {id = id, name = name, request = request}
        if controls.onDispatch then controls.onDispatch() end
        local result = dispatch(id, name, request)
        if controls.resultFilter then return controls.resultFilter(result) end
        return result
    end
    controls.flush = function()
        local count = 0
        while #controls.joins > 0 do
            count = count + 1; assert(count <= 10, "event storm")
            inContext("join", table.remove(controls.joins, 1))
        end
    end
    local function hook(initial)
        active.cursor = active.cursor + 1
        if not active.hooks[active.cursor] then
            local value, owner = initial, active
            active.hooks[active.cursor] = {old = function() return value end, get = function() return value end,
                hasExpired = function() return owner.expired == true end,
                set = function(_, nextValue)
                    assert(not owner.expired, "updating expired UI state"); value = nextValue
                end}
        end
        return active.hooks[active.cursor]
    end
    local extension = {id = "::MainModButtonAreaExtension"}
    local built = {type = {Orientation = {Vertical = "vertical", Horizontal = "horizontal"},
        ScrollBarPolicy = {AlwaysOff = "off", Simple = "simple"}}}
    for _, kind in ipairs({"Button", "TextView", "ComboBox", "ComboBoxItem", "BoxLayout", "Window", "ScrollArea", "Component"}) do
        built[kind] = function(params)
            return {kind = kind, params = params, nodeType = kind == "BoxLayout" and "layout" or "widget"}
        end
    end
    local reactMock = {useState = hook, useRef = hook,
        RegisterPluginRecipe = function(point, name, fn)
            equal(point, extension); equal(name, "OzRailwayNetworkArchitect")
            return function(...) return requirePluginLayout(fn(...)) end
        end,
        RegisterWrapperRecipe = function(name, wrapped, fn)
            equal(name, "OzRailwayNetworkArchitectWindow"); equal(wrapped, built.Window)
            windowRecipe = fn; return fn
        end,
        onMount = function(fn) active.mounted = fn end,
        onUnmount = function(fn) active.unmounted = fn end,
        onStepTimer = function(fn, interval, jitter)
            equal(interval, 0.5); equal(jitter, false); active.timer = fn
        end,
        enqueueJoin = function(fn, scope)
            assert(scope:find("RNA:PLAN:4B2:", 1, true) or scope=="RNA:ROUTE:close"); controls.joins[#controls.joins + 1] = fn
        end,
        iaHandler = function(fn) return fn end,
        useInputAction = function(name, fn) equal(name, "IA_MENU_BACK"); active.back = fn end,
        fireEvent = function(target, name)
            equal(target, nil); equal(name, "focusMainModButtonArea"); controls.focusReturns = controls.focusReturns + 1
        end,
    }
    local windowApi = {
        addSingletonWindow = function(recipe, params)
            params.development = not playerView -- Preserve all legacy feature regressions; production launcher never sets this.
            equal(recipe, windowRecipe)
            controls.adds = controls.adds + 1
            controls.windowInitial = {x = params.initialX, y = params.initialY}
            window = {recipe = recipe, params = params, ctx = window and window.ctx or {hooks = {}, cursor = 0}}
        end,
        removeAllWindows = function(recipe)
            equal(recipe, windowRecipe); controls.removes = controls.removes + 1
            local previous = window; window = nil
            if previous and previous.ctx.unmounted then previous.ctx.unmounted() end
            if previous then previous.ctx.expired = true end
        end,
    }
    local container = {hasExpired = function() return controls.expired end,
        get = function()
            assert(not controls.expired, "expired native container dereferenced")
            return {getApi = function() return windowApi end}
        end}
    ug_require = function(path)
        if path == "::/gui/main/react.lua" then return reactMock end
        if path == "::/gui/main/builtin.lua" then return built end
        if path == "::/gui/main/main_mod_button_area.tl" then return {MainModButtonAreaExtension = extension} end
        if path == "::/gui/main/game_react_globals.tl" then
            return {getDefaultWindowContainer = function() return controls.available and container or nil end}
        end
        return integrationRequire(path)
    end
    dofile(CONTENT .. "/live_plan_ui.script.lua")
    local exports = data()
    dofile(CONTENT .. "/live_plan_ui.res.lua")
    local descriptor = data()
    equal(descriptor.type, "react-plugin ::MainModButtonAreaExtension")
    equal(descriptor.data.filePath, "oz_railway_network_architect::/live_plan_ui.script@RailwayNetworkArchitect")
    local function renderRecipe(ctx, recipe, params)
        return inContext("restricted", function()
            active = ctx; ctx.cursor = 0
            local tree = recipe(params)
            if not ctx.didMount then
                ctx.didMount = true
                if ctx.mounted then ctx.mounted() end
                active = ctx; ctx.cursor = 0; tree = recipe(params)
            end
            return tree
        end)
    end
    local function render()
        local launcher = renderRecipe(launcherContext, exports.RailwayNetworkArchitect)
        local panel = window and renderRecipe(window.ctx, window.recipe, window.params) or nil
        if controls.autoJoin then
            controls.flush()
            if window then panel = renderRecipe(window.ctx, window.recipe, window.params) end
        end
        controls.pluginRoot, controls.launcher, controls.panel = launcher, launcher.params.children[1], panel
        return {kind = "TestRoots", params = {children = {launcher, panel}}}
    end
    controls.back = function() assert(window); window.ctx.back() end
    controls.detachWindow = function()
        local previous = window; window = nil
        if previous and previous.ctx.unmounted then previous.ctx.unmounted() end
        if previous then previous.ctx.expired = true end
    end
    controls.expireWindow = function() window.ctx.expired = true end
    controls.unmountLauncher = function()
        launcherContext.unmounted(); launcherContext.expired = true
    end
    controls.oldDetach = function() return window.ctx.unmounted end
    local tree = render()
    return render, function()
        if window and window.ctx.timer then inContext("restricted", window.ctx.timer) end
        if controls.autoJoin then controls.flush() end
    end, tree, controls
end

local function find(tree, kind, label)
    local found = {}
    local function visit(node)
        if type(node) ~= "table" then return end
        if node.kind == kind and (not label or (node.params.content and node.params.content.params.text == label)) then
            found[#found + 1] = node
        end
        if node.kind then
            visit(node.params.content)
            visit(node.params.layout)
            for _, child in ipairs(node.params.children or node.params.items or {}) do visit(child) end
        end
    end
    visit(tree); return found
end

local function modeCombo(tree)
    for _, combo in ipairs(find(tree, "ComboBox")) do
        if combo.params.items[1] and combo.params.items[1].params.value == "standard" then return combo end
    end
end
-- Existing town/candidate/link assertions address their own controls, independent
-- of the new mode selector. Mode registration/options are tested separately below.
local function planningCombos(tree)
    local result = {}
    for _, combo in ipairs(find(tree, "ComboBox")) do
        if combo ~= modeCombo(tree) then result[#result + 1] = combo end
    end
    return result
end

test("launcher plugin requires a horizontal layout root containing exactly one Button", function()
    local gui, step, untilState = newSession(); ready(step, untilState)
    local render, poll, tree, controls = mountUI()
    local root = controls.pluginRoot
    equal(root.kind, "BoxLayout"); equal(root.nodeType, "layout")
    equal(root.params.orientation, "horizontal"); equal(#root.params.children, 1)
    equal(root.params.children[1].kind, "Button"); equal(controls.launcher.nodeType, "widget")
    equal(requirePluginLayout(root), root)
    local ok, reason = pcall(requirePluginLayout, controls.launcher)
    equal(ok, false); assert(tostring(reason):find("Recipe child must be a layout", 1, true))
    equal(controls.panel, nil); equal(heightReads, 0)
end)

test("registered UI routes selection and one click through the real handler", function()
    local gui, step, untilState, event = newSession()
    entities[10].name, entities[20].name = "Twin", "Twin"
    ready(step, untilState)
    local render, poll, tree = mountUI()
    equal(logCount("UI_INIT"), 1); equal(heightReads, 0)
    find(tree, "Button", "Railway Network Architect")[1].params.onClick()
    tree = render()
    local combos = planningCombos(tree)
    equal(#combos, 2)
    equal(combos[1].params.items[2].params.content.params.text, "Twin [#10]")
    equal(combos[1].params.items[3].params.content.params.text, "Twin [#20]")
    combos[1].params.onValueChange("10")
    tree = render(); combos = planningCombos(tree)
    equal(combos[2].params.items[2].params.available, false)
    combos[2].params.onValueChange("10")
    tree = render(); equal(find(tree, "Button", "Plan")[1].params.meta.enabled, false)
    planningCombos(tree)[2].params.onValueChange("20")
    tree = render(); local button = find(tree, "Button", "Plan")[1]
    equal(button.params.meta.enabled, true)
    button.params.onClick(); button.params.onClick()
    tree = render() -- queued user action joins before the Game Script processes it
    equal(logCount("REQUEST_START"), 1)
    tree = render(); equal(find(tree, "Button", "Plan")[1].params.meta.enabled, false)
    untilState(completed); poll(); tree = render()
    equal(find(tree, "Button", "Plan")[1].params.meta.enabled, true)
    find(tree, "Button", "Plan")[1].params.onClick(); render(); untilState(completed)
    equal(logCount("REQUEST_START"), 2)
end)

test("UI session change clears selections and broken transport displays an error", function()
    local gui, step, untilState, event, callbacks = newSession(); ready(step, untilState)
    local render, poll, tree = mountUI()
    find(tree, "Button", "Railway Network Architect")[1].params.onClick()
    tree = render(); planningCombos(tree)[1].params.onValueChange("10")
    tree = render(); planningCombos(tree)[2].params.onValueChange("20")
    callbacks.guiHandleEvent(nil, nil, gui, "test", "gameUI", "reactPostInit", {})
    poll(); tree = render()
    for _, combo in ipairs(planningCombos(tree)) do equal(combo.params.value, "") end
    api.gui.fireGuiScriptEvent = function() error("transport failed", 0) end
    poll(); tree = render()
    local found = false
    for _, textNode in ipairs(find(tree, "TextView")) do
        if textNode.params.text:find("Interface error: transport failed", 1, true) then found = true end
    end
    equal(found, true); equal(heightReads, 0)
end)

test("launcher is a single button and form is a native window with verified focus/close options", function()
    local gui, step, untilState = newSession(); ready(step, untilState)
    local render, poll, tree, controls = mountUI()
    equal(controls.launcher.kind, "Button"); equal(#find(controls.launcher, "ComboBox"), 0)
    equal(controls.panel, nil); equal(controls.adds, 0); equal(heightReads, 0)
    controls.launcher.params.onClick(); tree = render()
    equal(controls.adds, 1); equal(controls.panel.kind, "Window")
    equal(#find(controls.launcher, "ComboBox"), 0); equal(#find(controls.panel, "ComboBox"), 3)
    local properties = controls.panel.params
    equal(properties.closable, true); equal(properties.movable, true)
    equal(properties.autoFocusOnBecomingVisible, true); equal(properties.autoVisibilityOnFocusChange, false)
    equal(properties.id, "oz_railway_network_architect.plan.window")
    controls.launcher.params.onClick(); tree = render(); equal(controls.panel, nil)
    equal(controls.removes, 1); equal(controls.focusReturns, 1)
    controls.launcher.params.onClick(); tree = render(); controls.panel.params.onClose()
    tree = render(); equal(controls.panel, nil); equal(controls.focusReturns, 2)
    controls.launcher.params.onClick(); tree = render(); controls.back()
    tree = render(); equal(controls.panel, nil); equal(controls.focusReturns, 3)
    poll(); equal(heightReads, 0); equal(logCount("REQUEST_START"), 0)
end)

test("reopening preserves selection, closing never cancels planning, and refresh still clears selection", function()
    local gui, step, untilState = newSession(); ready(step, untilState)
    local render, poll, tree, controls = mountUI()
    controls.launcher.params.onClick(); tree = render()
    planningCombos(tree)[1].params.onValueChange("10"); tree = render()
    planningCombos(tree)[2].params.onValueChange("20"); tree = render()
    controls.panel.params.onClose(); tree = render()
    controls.launcher.params.onClick(); tree = render()
    equal(planningCombos(tree)[1].params.value, "10"); equal(planningCombos(tree)[2].params.value, "20")
    find(tree, "Button", "Plan")[1].params.onClick()
    render() -- only an already dispatched request continues after closing
    controls.panel.params.onClose(); tree = render(); untilState(completed)
    equal(gui:get().request.status, "ok")
    controls.launcher.params.onClick(); tree = render()
    equal(find(tree, "Button", "Plan")[1].params.meta.enabled, true)
    equal(logCount("REQUEST_START"), 1)
    find(tree, "Button", "Refresh towns")[1].params.onClick(); tree = render()
    for _, combo in ipairs(planningCombos(tree)) do equal(combo.params.value, "") end
end)

test("closed-window session reset clears restored selection before new request", function()
    local gui, step, untilState, event, callbacks = newSession(); ready(step, untilState)
    local render, poll, tree, controls = mountUI()
    controls.launcher.params.onClick(); tree = render()
    planningCombos(tree)[1].params.onValueChange("10"); tree = render()
    planningCombos(tree)[2].params.onValueChange("20"); tree = render()
    controls.panel.params.onClose(); tree = render()
    callbacks.guiHandleEvent(nil, nil, gui, "test", "gameUI", "reactPostInit", {})
    ready(step, untilState)
    controls.launcher.params.onClick(); tree = render()
    for _, combo in ipairs(planningCombos(tree)) do equal(combo.params.value, "") end
    equal(find(tree, "Button", "Plan")[1].params.meta.enabled, false)
    equal(heightReads, 0); equal(logCount("REQUEST_START"), 0)
end)

test("window and launcher teardown are scoped, and delayed old detach cannot close a reopened window", function()
    local gui, step, untilState = newSession(); ready(step, untilState)
    local render, poll, tree, controls = mountUI()
    controls.launcher.params.onClick(); tree = render()
    local oldDetach = controls.oldDetach()
    controls.launcher.params.onClick(); tree = render()
    controls.launcher.params.onClick(); tree = render()
    oldDetach(); tree = render()
    equal(controls.launcher.params.content.params.text, "Close Railway Network Architect")
    equal(controls.panel.kind, "Window")
    controls.detachWindow(); tree = render()
    equal(controls.launcher.params.content.params.text, "Railway Network Architect")
    controls.launcher.params.onClick(); tree = render()
    local previous = controls.removes
    controls.unmountLauncher(); equal(controls.removes, previous + 1)
    equal(heightReads, 0)
end)

test("missing or expired native container fails without speculative fallback or planning", function()
    local gui, step, untilState = newSession(); ready(step, untilState)
    local render, poll, tree, controls = mountUI()
    controls.available = false; controls.launcher.params.onClick(); tree = render()
    equal(controls.adds, 0); equal(controls.panel, nil)
    equal(controls.launcher.params.meta.tooltip, "Unable to open Railway Network Architect. See the game log.")
    controls.available = true; controls.launcher.params.onClick(); tree = render()
    equal(controls.adds, 1)
    controls.expired = true; controls.unmountLauncher()
    equal(controls.removes, 0); equal(heightReads, 0)
    assert(hasLog("UI_ERROR detail=game_react_globals.getDefaultWindowContainer"))
end)

test("restricted mount and timer only enqueue; main-thread joins coalesce status requests", function()
    local gui, step, untilState = newSession(); ready(step, untilState)
    local render, poll, tree, controls = mountUI()
    controls.autoJoin = false
    local ok, reason = pcall(function()
        controls.inContext("restricted", function() api.gui.fireGuiScriptEvent("test", "test", {}) end)
    end)
    equal(ok, false); assert(tostring(reason):find("API is currently restricted", 1, true))
    equal(#controls.events, 0); equal(#controls.joins, 0)
    controls.launcher.params.onClick(); tree = render()
    equal(#controls.events, 0); equal(#controls.joins, 1)
    for _ = 1, 20 do poll() end
    equal(#controls.joins, 1); equal(#controls.events, 0)
    controls.flush(); tree = render()
    equal(#controls.events, 1); assert(controls.events[1].name:match("%.status$"))
    equal(#planningCombos(tree)[1].params.items, 3)
    poll(); equal(#controls.events, 1); controls.flush()
    poll(); controls.flush(); equal(#controls.events, 3)
    equal(logCount("UI_ERROR"), 0); equal(logCount("REQUEST_START"), 0); equal(heightReads, 0)
end)

test("Plan and Refresh each dispatch once in joins with queued-click protection", function()
    local gui, step, untilState = newSession(); ready(step, untilState)
    local render, poll, tree, controls = mountUI()
    controls.launcher.params.onClick(); tree = render()
    planningCombos(tree)[1].params.onValueChange("10"); tree = render()
    planningCombos(tree)[2].params.onValueChange("20"); tree = render()
    controls.autoJoin = false
    local button = find(tree, "Button", "Plan")[1]
    for _ = 1, 10 do button.params.onClick() end
    equal(#controls.joins, 1); equal(logCount("REQUEST_START"), 0)
    controls.flush(); equal(logCount("REQUEST_START"), 1)
    equal(controls.events[2].request.sourceId, 10); equal(controls.events[2].request.destinationId, 20)
    button.params.onClick(); equal(#controls.joins, 0)
    untilState(completed); poll(); controls.flush(); tree = render()
    local refresh = find(tree, "Button", "Refresh towns")[1]
    refresh.params.onClick(); refresh.params.onClick()
    equal(#controls.joins, 1); controls.flush(); tree = render()
    equal(logCount("ROUTE_PROBE_BEGIN"), 0)
    assert(controls.events[#controls.events].name:match("%.refresh$"))
    for _, combo in ipairs(planningCombos(tree)) do equal(combo.params.value, "") end
    equal(logCount("REQUEST_START"), 1)
end)

test("unmount cancels pending dispatch and stale handlers cannot update a reopened form", function()
    local gui, step, untilState = newSession(); ready(step, untilState)
    local render, poll, tree, controls = mountUI(); controls.autoJoin = false
    controls.launcher.params.onClick(); tree = render()
    local oldSelection = planningCombos(tree)[1].params.onValueChange
    local oldRefresh = find(tree, "Button", "Refresh towns")[1].params.onClick
    controls.detachWindow(); tree = render()
    controls.launcher.params.onClick(); tree = render()
    equal(#controls.joins, 2)
    oldSelection("10"); oldRefresh()
    controls.flush(); tree = render()
    equal(#controls.events, 1); equal(planningCombos(tree)[1].params.value, "")
    equal(logCount("REQUEST_START"), 0); equal(heightReads, 0)
end)

test("expired state, launcher or native container discards queued work without dispatch", function()
    for _, expiry in ipairs({"state", "container", "launcher"}) do
        local gui, step, untilState = newSession(); ready(step, untilState)
        local render, poll, tree, controls = mountUI(); controls.autoJoin = false
        controls.launcher.params.onClick(); render()
        if expiry == "state" then controls.expireWindow()
        elseif expiry == "launcher" then controls.unmountLauncher()
        else controls.expired = true end
        controls.flush(); equal(#controls.events, 0); equal(heightReads, 0)
    end
end)

test("closing before a queued Plan joins cancels dispatch, not an accepted planner request", function()
    local gui, step, untilState = newSession(); ready(step, untilState)
    local render, poll, tree, controls = mountUI()
    controls.launcher.params.onClick(); tree = render()
    planningCombos(tree)[1].params.onValueChange("10"); tree = render()
    planningCombos(tree)[2].params.onValueChange("20"); tree = render()
    find(tree, "Button", "Plan")[1].params.onClick()
    equal(#controls.joins, 1)
    controls.panel.params.onClose(); controls.flush()
    equal(#controls.events, 1); equal(logCount("REQUEST_START"), 0); equal(heightReads, 0)
end)

test("unmount during dispatch prevents response application to expired hooks", function()
    local gui, step, untilState = newSession(); ready(step, untilState)
    local render, poll, tree, controls = mountUI(); controls.autoJoin = false
    controls.launcher.params.onClick(); render()
    controls.onDispatch = controls.detachWindow
    controls.flush(); render()
    equal(#controls.events, 1); equal(controls.panel, nil)
    equal(logCount("UI_ERROR"), 0); equal(heightReads, 0)
end)

test("transport failure is visible, pauses polling, and only explicit Refresh retries", function()
    local gui, step, untilState = newSession(); ready(step, untilState)
    local render, poll, tree, controls = mountUI()
    controls.launcher.params.onClick(); tree = render()
    controls.onDispatch = function() error("native transport unavailable", 0) end
    poll(); tree = render(); equal(#controls.events, 2); equal(logCount("UI_ERROR"), 1)
    local visible = false
    for _, node in ipairs(find(tree, "TextView")) do
        if node.params.text:find("native transport unavailable", 1, true)
            and node.params.text:find("Polling paused", 1, true) then visible = true end
    end
    equal(visible, true)
    for _ = 1, 20 do poll() end
    equal(#controls.events, 2); equal(logCount("UI_ERROR"), 1)
    controls.onDispatch = nil
    find(tree, "Button", "Refresh towns")[1].params.onClick(); tree = render()
    equal(#controls.events, 3); poll(); equal(#controls.events, 4)
    equal(logCount("REQUEST_START"), 0); equal(heightReads, 0)
end)

test("native window uses scoped bounded stylesheet, wrapping and scrollable form", function()
    local gui, step, untilState = newSession(); ready(step, untilState)
    local render, poll, tree, controls = mountUI()
    controls.launcher.params.onClick(); tree = render()
    equal(controls.panel.params.meta.class, "rna-planner-window")
    local scroll = controls.panel.params.content
    equal(scroll.kind, "ScrollArea"); equal(scroll.params.horizontalPolicy, "off")
    equal(scroll.params.verticalPolicy, "simple"); equal(scroll.params.content.kind, "Component")
    local layout = scroll.params.content.params.layout
    equal(layout.kind, "BoxLayout"); equal(layout.params.orientation, "vertical")
    equal(layout.params.meta.class, "rna-planner-form")
    local styles = {}
    local env = {require = function(path)
        equal(path, "::/gui/main/stylesheetutil.lua")
        return {makeAdder = function(result)
            return function(selector, properties)
                assert(selector:find("!rna-planner-", 1, true)); styles[selector] = properties
                result[#result + 1] = {selector = selector, styleSheet = properties}
            end
        end}
    end}
    assert(loadfile(CONTENT .. "/live_plan_ui.css.lua", "t", env))()
    equal(#env.data(), 7)
    local windowStyle = styles["Window!rna-planner-window"]
    equal(windowStyle.size[1], 520); equal(windowStyle.size[2], 360)
    equal(serialize(windowStyle.anchorPoint), serialize({0.5, 0.5}))
    equal(serialize(windowStyle.gravity), serialize({0.5, 0.5}))
    equal(windowStyle.transform, nil); equal(windowStyle.margin, nil)
    local contentStyle = styles["Window!rna-planner-window Window::Content"]
    equal(serialize(contentStyle.padding), serialize({20, 20, 20, 20}))
    equal(styles["BoxLayout!rna-planner-form"].padding, nil) -- no ineffective/double inset
    equal(styles["BoxLayout!rna-planner-form > Button"].gravity[1], 0)
    equal(styles["ComboBox!rna-planner-town"].minSize[1], -1) -- may shrink
    equal(styles["ComboBox!rna-planner-town"].gravity[1], -1)
    -- Stylesheet capacity check only, not native glyph/layout measurement.
    -- Native builtin.css.lua:1635-1636 gives vertical scrollbar width 8.
    local availableWidth = windowStyle.minSize[1] - contentStyle.padding[2] - contentStyle.padding[4] - 8
    assert(styles["ComboBox!rna-planner-town"].maxSize[1] <= availableWidth)
    assert(styles["TextView!rna-planner-text"].maxSize[1] <= availableWidth)
    for selector in pairs(styles) do assert(not selector:find("Title", 1, true)) end
    equal(windowStyle.maxSize[1], 520); equal(windowStyle.maxSize[2], "80vh")
    equal(styles["TextView!rna-planner-text"].textAutoWrap, true)
    equal(styles["TextView!rna-planner-text"].maxSize[1], 440)
    equal(styles["BoxLayout!rna-planner-form"].innerSpacing[2], 8)
    equal(styles["ComboBox!rna-planner-town"].minSize[2], 32)
    equal(logCount("REQUEST_START"), 0)
end)

test("descriptor-resolved event handler receives original ID/name and returns owner town data", function()
    local gui, step, untilState, event, callbacks = newSession(); ready(step, untilState)
    local id = "oz_railway_network_architect.plan"
    local payload = {_rnaTrace = {id = "w1:e1", enabled = true}}
    local received, original = nil, callbacks.guiHandleEvent
    callbacks.guiHandleEvent = function(params, engine, owner, src, wireId, wireName, wireParam)
        received = {owner = owner, id = wireId, name = wireName, param = wireParam}
        return original(params, engine, owner, src, wireId, wireName, wireParam)
    end
    local result = api.gui.fireGuiScriptEvent(id, id .. ".status", payload)
    equal(received.owner, gui); equal(received.id, id); equal(received.name, id .. ".status")
    equal(received.param, payload); equal(result.status, "idle"); equal(result._rnaTraceId, "w1:e1")
    equal(result.towns[1].id, 10); equal(result.towns[1].name, entities[10].name)
    equal(result.towns[2].id, 20); equal(#result.towns, #gui:get().towns)
    equal(logCount("COMM HANDLER_ENTRY"), 1); equal(logCount("COMM HANDLER_RESPONSE"), 1)
    equal(api.gui.fireGuiScriptEvent("wrong", id .. ".status", payload), nil)
    assert(hasLog("HANDLER_ROUTE accepted=false reason=event_id"))
    equal(api.gui.fireGuiScriptEvent(id, "status", payload), nil)
    -- Also unit-test defensive filtering separately from subscription-gated delivery.
    equal(original(nil, nil, gui, "test", id, "status", payload), nil)
    assert(hasLog("HANDLER_ROUTE accepted=false reason=event_name_prefix"))
    equal(api.gui.fireGuiScriptEvent(id, id .. ".unknown", payload), nil)
    equal(original(nil, nil, gui, "test", id, id .. ".unknown", payload), nil)
    assert(hasLog("HANDLER_ROUTE accepted=false reason=event_action"))
    equal(api.gui.fireGuiScriptEvent(id, id .. ".status", nil).status, "idle")
    assert(hasLog("param_type=nil trace=unavailable"))
    for _ = 1, 20 do api.gui.fireGuiScriptEvent(id, id .. ".status", nil) end
    equal(logCount("COMM HANDLER_ENTRY"), 8)
    equal(logCount("REQUEST_START"), 0); equal(heightReads, 0)
end)

test("nil handler or discarded return is diagnosed without fabricated towns or repeated errors", function()
    for _, mode in ipairs({"handler_nil", "propagation_nil"}) do
        local gui, step, untilState, event, callbacks = newSession(); ready(step, untilState)
        local original = callbacks.guiHandleEvent
        if mode == "handler_nil" then callbacks.guiHandleEvent = function() return nil end end
        local render, poll, tree, controls = mountUI()
        if mode == "propagation_nil" then controls.resultFilter = function() return nil end end
        controls.launcher.params.onClick(); tree = render()
        equal(logCount("COMM GUI_DISPATCH"), 1); equal(logCount("COMM GUI_RESULT type=nil"), 1)
        equal(logCount("COMM HANDLER_RESPONSE"), mode == "handler_nil" and 0 or 1)
        assert(hasLog("planner response unavailable; response_type=nil"))
        equal(#planningCombos(tree)[1].params.items, 1)
        for _ = 1, 20 do poll() end
        equal(logCount("UI_ERROR"), 1); equal(#controls.events, 1)
        callbacks.guiHandleEvent = original; controls.resultFilter = nil
        find(tree, "Button", "Refresh towns")[1].params.onClick(); tree = render() -- diagnostic only
        find(tree, "Button", "Refresh towns")[1].params.onClick(); render()
        untilState(function(s) return s.status == "idle" end); poll(); tree = render()
        equal(#planningCombos(tree)[1].params.items, 3)
        equal(logCount("REQUEST_START"), 0); equal(heightReads, 0)
    end
end)

test("malformed native responses report precise validation failures and cannot populate the form", function()
    local cases = {
        {function() return false end, "response_type=boolean"},
        {function() return {} end, "towns_type=nil"},
        {function(v) v.towns = nil; return v end, "towns_type=nil"},
        {function(v) v.epoch = nil; return v end, "invalid_epoch=nil"},
        {function(v) v.requestId = nil; return v end, "invalid_request_or_catalog_version"},
        {function(v) v.status = nil; return v end, "invalid_status_or_message"},
        {function(v) v.busy = nil; return v end, "invalid_busy_or_canPlan"},
        {function(v) v.towns = {bad = {id = 10, name = "bad"}}; return v end, "towns response is not an array"},
        {function(v) v.towns = {[2] = v.towns[2]}; return v end, "malformed town record index=1"},
        {function(v) v.towns[1].id = nil; return v end, "malformed town record index=1"},
    }
    for _, case in ipairs(cases) do
        local gui, step, untilState = newSession(); ready(step, untilState)
        local render, poll, tree, controls = mountUI(); controls.resultFilter = case[1]
        controls.launcher.params.onClick(); tree = render()
        assert(hasLog(case[2]), case[2]); equal(logCount("UI_ERROR"), 1)
        equal(#planningCombos(tree)[1].params.items, 1)
        poll(); equal(#controls.events, 1); equal(heightReads, 0)
    end
end)

test("trace IDs correlate dispatch and response, remain distinct on reopen, and logging is capped", function()
    local gui, step, untilState = newSession(); ready(step, untilState)
    local render, poll, tree, controls = mountUI()
    controls.launcher.params.onClick(); render()
    local first = controls.events[1].request._rnaTrace.id
    assert(hasLog("response_trace=" .. first))
    controls.panel.params.onClose(); render(); controls.launcher.params.onClick(); render()
    local second = controls.events[2].request._rnaTrace.id
    assert(first ~= second); assert(hasLog("response_trace=" .. second))
    for _ = 1, 30 do poll() end
    equal(logCount("COMM GUI_DISPATCH"), 8); equal(logCount("COMM HANDLER_ENTRY"), 8)
    equal(logCount("COMM HANDLER_ROUTE"), 8); equal(logCount("COMM HANDLER_RESPONSE"), 8)
    equal(logCount("COMM GUI_RESULT"), 8); equal(logCount("UI_ERROR"), 0)
    equal(logCount("REQUEST_START"), 0)
end)

test("event transport preserves rejected and stale requests with actual owner status", function()
    local gui, step, untilState = newSession(); ready(step, untilState)
    local id = "oz_railway_network_architect.plan"
    local state = api.gui.fireGuiScriptEvent(id, id .. ".status", {})
    local params = {world = state.world, epoch = state.epoch + 1, requestId = state.requestId + 1,
        sourceId = 10, destinationId = 20, _rnaTrace = {id = "w1:e2", enabled = true}}
    local rejected = api.gui.fireGuiScriptEvent(id, id .. ".plan", params)
    equal(rejected.reason, "stale_session"); equal(rejected.status, "idle"); equal(rejected.accepted, false)
    equal(rejected._rnaTraceId, "w1:e2"); equal(logCount("REQUEST_START"), 0)
    params.epoch = state.epoch
    equal(api.gui.fireGuiScriptEvent(id, id .. ".plan", params).accepted, true)
    equal(api.gui.fireGuiScriptEvent(id, id .. ".plan", params).reason, "busy")
    untilState(completed)
    equal(api.gui.fireGuiScriptEvent(id, id .. ".plan", params).reason, "duplicate_or_stale_request")
    equal(logCount("REQUEST_START"), 1)
end)

test("new native windows start centered and retain movable bounded content across reopen", function()
    local gui, step, untilState = newSession(); ready(step, untilState)
    local render, poll, tree, controls = mountUI()
    for _ = 1, 2 do
        controls.launcher.params.onClick(); render()
        local properties = controls.panel.params
        equal(properties.initialX, 0.5); equal(properties.initialY, 0.5)
        equal(controls.windowInitial.x, 0.5); equal(controls.windowInitial.y, 0.5)
        equal(properties.movable, true); equal(properties.autoFocusOnBecomingVisible, true)
        equal(properties.meta.class, "rna-planner-window")
        poll(); render(); equal(controls.adds, controls.removes + 1)
        properties.onClose(); render(); equal(controls.panel, nil)
    end
    equal(controls.adds, 2); equal(controls.removes, 2); equal(logCount("REQUEST_START"), 0)
end)

local function tenTownFixture()
    entities, ids = {}, {}
    for index = 1, 10 do
        local id = index * 10
        entities[id] = {id = id, name = "Fixture town " .. index, x = index * 60, y = 0, z = 5}
        ids[11 - index] = id -- Deliberately reverse enumeration order.
    end
end

test("registered owner returns all ten fixture towns and refresh recollects actual fixture data", function()
    local gui, step, untilState = newSession(); tenTownFixture(); ready(step, untilState)
    local id = "oz_railway_network_architect.plan"
    local function status() return api.gui.fireGuiScriptEvent(id, id .. ".status", {}) end
    local initial = status(); equal(initial.status, "idle"); equal(#initial.towns, 10)
    for index, town in ipairs(initial.towns) do
        equal(town.id, index * 10); equal(town.name, entities[town.id].name)
    end
    entities[100].name = "Updated fixture town"
    local refresh = api.gui.fireGuiScriptEvent(id, id .. ".refresh", {})
    equal(refresh.accepted, true); equal(refresh.status, "loading")
    equal(#refresh.towns, 0) -- Existing contract: collection is batched, not synchronous.
    untilState(function(s) return s.status == "idle" end)
    local refreshed = status(); equal(#refreshed.towns, 10)
    equal(refreshed.towns[10].name, "Updated fixture town")
    assert(refreshed.listVersion > initial.listVersion)
    equal(logCount("REQUEST_START"), 0); equal(heightReads, 0)
end)

test("denied delivery reproduces nil with no handler entry and does not silently populate the UI", function()
    -- Explicit hypothesis under test, NOT a verified native routing rule.
    local gui, step, untilState = newSession(nil, function(id) return id == "" end)
    tenTownFixture(); ready(step, untilState); equal(#gui:get().towns, 10)
    local render, poll, tree, controls = mountUI()
    controls.launcher.params.onClick(); tree = render()
    equal(logCount("COMM GUI_DISPATCH"), 1); equal(logCount("COMM GUI_RESULT type=nil"), 1)
    equal(logCount("COMM HANDLER_ENTRY"), 0)
    equal(#planningCombos(tree)[1].params.items, 1)
    for _ = 1, 20 do poll() end
    equal(#controls.events, 1); equal(logCount("UI_ERROR"), 1)
    find(tree, "Button", "Refresh towns")[1].params.onClick(); render()
    equal(#controls.events, 2); equal(logCount("COMM HANDLER_ENTRY"), 0)
    tree = render(); equal(#planningCombos(tree)[1].params.items, 1) -- not applied as fallback data
    equal(#gui:get().towns, 10); equal(logCount("REQUEST_START"), 0); equal(heightReads, 0)
end)

test("empty component ID alone still fails the current owner filter and must not be a silent fallback", function()
    local gui, step, untilState = newSession(nil, function(id) return id == "" end)
    tenTownFixture(); ready(step, untilState)
    local result = api.gui.fireGuiScriptEvent("", "oz_railway_network_architect.plan.status",
        {_rnaTrace = {id = "empty-id-design-check", enabled = true}})
    equal(result, nil); equal(logCount("COMM HANDLER_ENTRY"), 1)
    assert(hasLog("HANDLER_ROUTE accepted=false reason=event_id"))
    equal(logCount("COMM HANDLER_RESPONSE"), 0); equal(#gui:get().towns, 10)
    equal(logCount("REQUEST_START"), 0); equal(heightReads, 0)
end)

test("missing engine subscriptions reproduces idle ten-town owner with nil UI response; activation restores delivery", function()
    local gui, step, untilState, _, callbacks = newSession(); tenTownFixture()
    local activate = callbacks.update; callbacks.update = nil -- Previous descriptor had no updateScript.
    ready(step, untilState); equal(#gui:get().towns, 10)
    local render, poll, tree, controls = mountUI(); controls.launcher.params.onClick(); tree = render()
    equal(logCount("COMM HANDLER_ENTRY"), 0); assert(hasLog("GUI_RESULT type=nil"))
    for _ = 1, 20 do poll() end
    equal(#controls.events, 1); equal(logCount("UI_ERROR"), 1)
    callbacks.update = activate; step()
    find(tree, "Button", "Refresh towns")[1].params.onClick(); tree = render()
    equal(#controls.events, 2); equal(controls.events[2].name, "oz_railway_network_architect.plan.refresh")
    equal(gui:get().status, "loading")
    untilState(function(s) return s.status == "idle" end); poll(); tree = render()
    equal(#planningCombos(tree)[1].params.items, 11)
    equal(logCount("EVENT_SUBSCRIPTIONS_READY"), 1); assert(hasLog("HANDLER_RESPONSE type=table"))
    equal(logCount("REQUEST_START"), 0); equal(heightReads, 0)
end)

test("registration subscribes exactly five names once even for zero dt; no engine data access", function()
    local _, _, _, _, callbacks = newSession()
    local beforeReads = reads
    for _ = 1, 30 do callbacks.update(nil, callbacks.engineState, 0) end
    local expected = {['oz_railway_network_architect.plan.status'] = 1,
        ['oz_railway_network_architect.plan.refresh'] = 1,
        ['oz_railway_network_architect.plan.plan'] = 1,
        ['oz_railway_network_architect.plan.analyzeNetwork'] = 1, reactPostInit = 1}
    equal(serialize(callbacks.subscriptions), serialize(expected))
    equal(reads, beforeReads); equal(heightReads, 0); equal(logCount("EVENT_SUBSCRIPTIONS_READY"), 1)
    -- engineState intentionally has no get/set or command API: registration cannot persist planner state.
end)

test("unsubscribed event never enters handler even when component ID matches", function()
    local gui, step, untilState = newSession(); ready(step, untilState)
    local id = "oz_railway_network_architect.plan"
    equal(api.gui.fireGuiScriptEvent(id, id .. ".unknown", {}), nil)
    equal(logCount("COMM HANDLER_ENTRY"), 0); equal(gui:get().requestId, 0)
end)

test("subscribed reactPostInit resets GUI session and requires fresh world readiness", function()
    local gui, step, untilState = newSession(); ready(step, untilState)
    local epoch = gui:get().epoch
    equal(api.gui.fireGuiScriptEvent("gameUI", "reactPostInit", {}), nil)
    equal(gui:get().epoch, epoch + 1); equal(gui:get().status, "waiting")
    equal(#gui:get().towns, 0); equal(gui:get().request, nil)
    step(); tick = tick + 1; untilState(function(s) return s.status == "idle" end)
    equal(logCount("EVENT_SUBSCRIPTIONS_READY"), 1); equal(logCount("REQUEST_START"), 0)
end)

test("new script state registers again without sharing subscriptions or request state", function()
    local _, step, untilState, _, first = newSession(); ready(step, untilState)
    local gui, nextStep, nextUntil, _, second = newSession()
    assert(first.subscriptions ~= second.subscriptions); equal(next(second.subscriptions), nil)
    ready(nextStep, nextUntil)
    equal(logCount("EVENT_SUBSCRIPTIONS_READY"), 1); equal(gui:get().requestId, 0)
    equal(second.subscriptions['oz_railway_network_architect.plan.plan'], 1)
end)

test("Refresh performs one normal request per click with no remaining routing probe", function()
    local gui, step, untilState = newSession(); tenTownFixture(); ready(step, untilState)
    local render, poll, tree, controls = mountUI(); controls.launcher.params.onClick(); tree = render()
    controls.autoJoin = false
    local refresh = find(tree, "Button", "Refresh towns")[1]
    for _ = 1, 10 do refresh.params.onClick() end
    equal(#controls.joins, 1); controls.flush(); tree = render()
    equal(#controls.events, 2); equal(controls.events[2].name, "oz_railway_network_architect.plan.refresh")
    equal(controls.events[2].request._rnaRoutingProbe, nil)
    equal(logCount("ROUTE_PROBE_BEGIN"), 0); equal(logCount("REQUEST_START"), 0)
    untilState(function(s) return s.status == "idle" end); poll(); controls.flush(); tree = render()
    equal(#planningCombos(tree)[1].params.items, 11)
end)

test("registration lookup uses exact gs resource name once without exposing engine state", function()
    local gui, step, untilState = newSession(); ready(step, untilState); step(100)
    equal(logCount("REGISTRATION_LOOKUP"), 1)
    assert(hasLog("status=resolved entity=800")); equal(gui:get().request, nil)
end)

test("registration lookup failure is bounded and does not replace owner data", function()
    local gui, step, untilState = newSession()
    api.engine.system.gameScriptSystem.getEntityForGameScript = function() error("lookup failed", 0) end
    ready(step, untilState); step(100)
    equal(logCount("REGISTRATION_LOOKUP"), 1); assert(hasLog("getEntityForGameScript: lookup failed"))
    equal(gui:get().status, "idle"); equal(#gui:get().towns, 2); equal(heightReads, 0)
end)

test("distant towns refine through working event transport without changing selection UI", function()
    local gui, step, untilState = newSession()
    mapBounds = {minX = -4096, maxX = 4096, minY = -2048, maxY = 2048}
    entities[10].x, entities[10].y, entities[10].name = -804, -624, "Morley"
    entities[20].x, entities[20].y, entities[20].name = 3676, -1268, "Winterton"
    ready(step, untilState)
    local render, poll, tree, controls = mountUI(); controls.launcher.params.onClick(); tree = render()
    planningCombos(tree)[1].params.onValueChange("10"); tree = render()
    planningCombos(tree)[2].params.onValueChange("20"); tree = render()
    find(tree, "Button", "Plan")[1].params.onClick(); render()
    untilState(completed); poll(); tree = render()
    equal(gui:get().request.status, "ok")
    equal(gui:get().request.reason, "refined_routes_validated")
    local expected = "Completed. Candidates: 1. Details in log."
    local function messageVisible()
        for _, node in ipairs(find(tree, "TextView")) do
            if node.params.text == expected then return true end
        end
        return false
    end
    equal(gui:get().message, expected); equal(messageVisible(), true)
    equal(planningCombos(tree)[1].params.value, "10"); equal(planningCombos(tree)[2].params.value, "20")
    assert(hasLog("[RNA:PLAN:4B3] SUMMARY status=ok"))
    assert(heightReads > 0); equal(#gui:get().request.result.candidates, 1); equal(logCount("REQUEST_START"), 1)
    controls.panel.params.onClose(); render(); controls.launcher.params.onClick(); tree = render()
    equal(messageVisible(), true); equal(logCount("REQUEST_START"), 1)
end)

test("boundary-margin unsupported case is not mislabeled as distant or impossible", function()
    local gui, step, untilState, event = newSession()
    mapBounds = {minX = -100, maxX = 100, minY = -100, maxY = 100}
    entities[10].x, entities[10].y = 0, 0
    entities[20].x, entities[20].y = 99.5, 0
    ready(step, untilState); equal(submit(gui, event).accepted, true); untilState(completed)
    equal(gui:get().request.reason, "fine_endpoint_approximation_exceeds_limit")
    equal(gui:get().request.status, "unsupported")
    assert(not gui:get().message:find("too far apart", 1, true))
    assert(not gui:get().message:find("impossible", 1, true)); equal(heightReads, 0)
end)

test("long communication errors remain in the wrapped padded scroll form", function()
    local gui, step, untilState = newSession(); ready(step, untilState)
    local render, poll, tree, controls = mountUI()
    controls.onDispatch = function() error(string.rep("Long diagnostic detail ", 40), 0) end
    controls.launcher.params.onClick(); tree = render()
    local seen = false
    for _, node in ipairs(find(tree, "TextView")) do
        if node.params.text:find("Long diagnostic detail", 1, true) then
            seen = true; equal(node.params.meta.class, "rna-planner-text")
            assert(#node.params.text < 600)
        end
    end
    equal(seen, true); equal(controls.panel.params.content.kind, "ScrollArea")
    for _ = 1, 20 do poll() end
    equal(logCount("UI_ERROR"), 1); equal(logCount("REQUEST_START"), 0)
end)

test("long request exposes bounded progress and cancels on world, town, bounds or reload changes", function()
    for _, mode in ipairs({"world", "town", "bounds", "reload"}) do
        local gui, step, untilState, event = newSession()
        mapBounds = {minX = -1024, maxX = 10000, minY = -2048, maxY = 2048}
        entities[10].x, entities[10].y = 0, 0; entities[20].x, entities[20].y = 8192, 0
        ready(step, untilState); submit(gui, event)
        untilState(function(s) return s.request and s.request.hierarchy and s.request.hierarchy.phase == "fine_sampling" end)
        local old = gui:get().request
        assert(gui:get().message:find("Long-distance planning:", 1, true))
        local before = heightReads
        if mode == "world" then worldId = 100
        elseif mode == "town" then entities[20].x = 8193
        elseif mode == "bounds" then mapBounds = {minX = -1024, maxX = 10001, minY = -2048, maxY = 2048}
        else api.gui.fireGuiScriptEvent("gameUI", "reactPostInit", {}) end
        step()
        equal(old.finished, true); equal(old.status, "invalidated"); equal(old.result, nil)
        equal(old.hierarchy.cache, nil); equal(heightReads, before)
        equal(logCount("REQUEST_START"), 1)
    end
end)

test("long requests retain freshness and measured work limits", function()
    for _, mode in ipairs({"age", "performance"}) do
        local gui, step, untilState, event = newSession()
        mapBounds = {minX = -1024, maxX = 10000, minY = -2048, maxY = 2048}
        entities[10].x, entities[10].y = 0, 0; entities[20].x, entities[20].y = 8192, 0
        ready(step, untilState); submit(gui, event)
        untilState(function(s) return s.request and s.request.hierarchy ~= nil end)
        if mode == "age" then clock = clock + 61 else clockStep = 0.03 end
        untilState(completed)
        equal(gui:get().request.status, mode == "age" and "invalidated" or "performance_limit")
        equal(gui:get().request.result, nil); equal(gui:get().request.hierarchy.cache, nil)
    end
end)

local preview = ug_require "oz_railway_network_architect::/live_plan_preview.lua"
local function panelText(tree)
    local lines = {}
    for _, node in ipairs(find(tree, "TextView")) do lines[#lines + 1] = node.params.text end
    return table.concat(lines, "\n")
end

test("completed real planner result reaches panel summary through unchanged status transport", function()
    local gui, step, untilState, event = newSession(); ready(step, untilState)
    local render, poll, tree, controls = mountUI(); controls.launcher.params.onClick(); tree = render()
    assert(panelText(tree):find("in-panel only; not a map overlay", 1, true))
    equal(#planningCombos(tree), 2); equal(heightReads, 0)
    planningCombos(tree)[1].params.onValueChange("10"); tree = render()
    planningCombos(tree)[2].params.onValueChange("20"); tree = render()
    find(tree, "Button", "Plan")[1].params.onClick(); tree = render()
    equal(#planningCombos(tree), 2)
    untilState(completed); poll(); tree = render()
    equal(#planningCombos(tree), 3)
    local state = gui:get(); local summary = assert(state.request.preview)
    equal(summary.candidates[1].start.z, -2)
    equal(summary.candidates[1].destination.x, state.request.result.candidates[1].waypoints[#state.request.result.candidates[1].waypoints].x)
    assert(panelText(tree):find("Construction feasibility: unverified", 1, true))
    assert(panelText(tree):find("No path is drawn", 1, true))
    local sampled, expansions = heightReads, state.request.result.stats.expansions
    for _ = 1, 20 do poll(); render() end
    equal(heightReads, sampled); equal(state.request.result.stats.expansions, expansions)
    equal(logCount("PANEL_SUMMARY"), 1); equal(logCount("REQUEST_START"), 1)
    equal(state.request.preview, summary) -- built once, not rebuilt by polling
    equal(summary.candidates[1].waypoints, nil)
end)

test("candidate switching is local and preserves distinct canonical alternatives", function()
    local gui, step, untilState = newSession(); ready(step, untilState)
    -- Actual canonical three-route fixture; only the native owner envelope is mocked.
    local input = require("tests.corridor_fixtures").comparison()
    input.grid.spacingX, input.grid.spacingY = 32, 32
    for _, role in ipairs({"start", "destination"}) do input[role].x = input[role].x * 3.2; input[role].y = input[role].y * 3.2 end
    for _, cell in ipairs(input.grid.cells) do cell.height = cell.height * 3.2 end
    local result = corePlan(input); equal(#result.candidates, 3); result.snapshot = {world = worldId}
    for _, c in ipairs(result.candidates) do
        c.sourceId, c.destinationId, c.searchStatus, c.refinedSections = 10, 20, "complete", 1
        c.sampling = {fineSpacing = 32}; c.endpoints = {
            start = {x = input.start.x, y = input.start.y, distance = 0},
            destination = {x = input.destination.x, y = input.destination.y, distance = 0}}
    end
    local state = gui:get(); state.status, state.requestId = "ok", 1
    state.request = {finished = true, status = "ok", world = worldId, requestId = 1, sourceId = 10, destinationId = 20,
        result = result, pair = {start = {id = 10, name = "Twin", x = input.start.x, y = input.start.y},
            destination = {id = 20, name = "Twin", x = input.destination.x, y = input.destination.y}}}
    state.request.preview = assert(preview.build(state))
    local render, poll, tree, controls = mountUI(); controls.launcher.params.onClick(); tree = render()
    local count = #controls.events
    for i = 1, 3 do
        local c = result.candidates[i]
        planningCombos(tree)[3].params.onValueChange(c.id); tree = render()
        equal(planningCombos(tree)[3].params.value, c.id)
        assert(panelText(tree):find(string.format("Approximate length: %.1f", c.length), 1, true))
        equal(#controls.events, count); equal(heightReads, 0)
    end
    planningCombos(tree)[3].params.onValueChange("nonexistent"); tree = render()
    equal(planningCombos(tree)[3].params.value, result.candidates[3].id)
    equal(logCount("REQUEST_START"), 0)
end)

test("long-distance panel uses full refined result without shipping or redrawing waypoint arrays", function()
    local gui, step, untilState, event = newSession()
    mapBounds = {minX = -1024, maxX = 17408, minY = -2048, maxY = 2048}
    entities[10].x, entities[10].y = 0, 0; entities[20].x, entities[20].y = 16000, 0
    ready(step, untilState); submit(gui, event); untilState(completed)
    local c = assert(gui:get().request.preview).candidates[1]
    equal(c.length, 16000); assert(c.sections > 1); equal(c.spacing, 64)
    equal(c.start.x, 0); equal(c.destination.x, 16000)
    local render, poll, tree, controls = mountUI(); controls.launcher.params.onClick(); tree = render()
    assert(panelText(tree):find("16000.0 world units", 1, true)); equal(c.waypoints, nil)
    local sampled = heightReads; for _ = 1, 10 do render() end; equal(heightReads, sampled)
end)

test("unsupported, unreachable, incomplete and search-limit results never expose a summary", function()
    for _, mode in ipairs({"unsupported", "unreachable", "incomplete", "search_limit"}) do
        local gui, step, untilState, event = newSession(mode == "search_limit" and {maxExpansions = 1} or nil)
        if mode == "unsupported" then entities[10].x, entities[10].y, entities[20].x, entities[20].y = 0, 0, 1, 0
        elseif mode == "unreachable" then sampleMode = "water"
        elseif mode == "incomplete" then sampleMode = "missing" end
        ready(step, untilState); submit(gui, event); untilState(completed)
        assert(gui:get().status ~= "ok"); equal(event("status").preview, nil)
        local render, poll, tree, controls = mountUI(); controls.launcher.params.onClick(); tree = render()
        equal(#planningCombos(tree), 2)
        assert(panelText(tree):find("No eligible corridor summary", 1, true))
    end
end)

test("new request replaces summary and stale candidate callbacks cannot restore prior data", function()
    local gui, step, untilState, event = newSession(); ready(step, untilState)
    submit(gui, event); untilState(completed)
    local render, poll, tree, controls = mountUI(); controls.launcher.params.onClick(); tree = render()
    local oldChoice = planningCombos(tree)[3].params.onValueChange
    submit(gui, event, 20, 10); poll(); tree = render(); equal(#planningCombos(tree), 2)
    oldChoice("corridor_distance"); tree = render(); equal(#planningCombos(tree), 2)
    untilState(completed); poll(); tree = render()
    local summary = gui:get().request.preview
    equal(summary.requestId, 2); equal(summary.source.id, 20); equal(summary.destination.id, 10)
    local selected = planningCombos(tree)[3].params.value
    oldChoice("nonexistent"); tree = render(); equal(planningCombos(tree)[3].params.value, selected)
    equal(logCount("PANEL_SUMMARY"), 2); equal(logCount("REQUEST_START"), 2)
end)

test("world changes, reload and Refresh clear summaries through existing lifecycle", function()
    for _, mode in ipairs({"world", "reload", "refresh"}) do
        local gui, step, untilState, event, callbacks = newSession(); ready(step, untilState)
        submit(gui, event); untilState(completed)
        local render, poll, tree, controls = mountUI(); controls.launcher.params.onClick(); tree = render()
        equal(#planningCombos(tree), 3)
        if mode == "world" then worldId = 100
        elseif mode == "reload" then callbacks.guiHandleEvent(nil, nil, gui, "test", "gameUI", "reactPostInit", {})
        else find(tree, "Button", "Refresh towns")[1].params.onClick(); render() end
        poll(); tree = render(); equal(#planningCombos(tree), 2)
        equal(gui:get().request, nil); equal(logCount("REQUEST_START"), 1)
    end
end)

test("reopen waits for fresh response and unmounted callbacks cannot restore a summary", function()
    local gui, step, untilState, event = newSession(); ready(step, untilState)
    submit(gui, event); untilState(completed)
    local render, poll, tree, controls = mountUI(); controls.launcher.params.onClick(); tree = render()
    local oldChoice = planningCombos(tree)[3].params.onValueChange
    controls.panel.params.onClose(); render(); equal(controls.panel, nil)
    controls.autoJoin = false; controls.launcher.params.onClick(); tree = render()
    equal(#planningCombos(tree), 2)
    oldChoice("corridor_distance"); equal(#planningCombos(render()), 2)
    controls.flush(); tree = render(); equal(#planningCombos(tree), 3)
    controls.unmountLauncher(); render(); equal(controls.panel, nil)
    equal(logCount("REQUEST_START"), 1)
end)

test("malformed preview pauses polling and explicit refresh recovers without stale data", function()
    local gui, step, untilState, event = newSession(); ready(step, untilState)
    submit(gui, event); untilState(completed)
    local render, poll, tree, controls = mountUI(); controls.launcher.params.onClick(); tree = render()
    controls.resultFilter = function(value) value.preview = {kind = "panel_summary"}; return value end
    poll(); tree = render(); equal(#planningCombos(tree), 2)
    assert(panelText(tree):find("invalid corridor summary", 1, true))
    local count = #controls.events; for _ = 1, 10 do poll(); render() end; equal(#controls.events, count)
    controls.resultFilter = nil
    find(tree, "Button", "Refresh towns")[1].params.onClick(); render()
    untilState(function(s) return s.status == "idle" end); poll(); tree = render()
    equal(#planningCombos(tree), 2); equal(logCount("REQUEST_START"), 1)
end)

test("consumed rejected click token cannot expose summary under a different request ID", function()
    local gui, step, untilState, event = newSession(); ready(step, untilState)
    submit(gui, event); untilState(completed); assert(event("status").preview)
    local rejected = submit(gui, event, 10, 10)
    equal(rejected.reason, "same_town"); equal(rejected.preview, nil)
    equal(gui:get().request.preview.requestId, 1); equal(rejected.requestId, 2)
    local render, poll, tree, controls = mountUI(); controls.launcher.params.onClick(); tree = render()
    equal(#planningCombos(tree), 2); equal(logCount("UI_ERROR"), 0)
end)

-- Phase 5B.1: reuse the real owner, registration, read adapters and restricted React harness.
local function networkFixture(count)
    entities, ids = {}, {}
    mapBounds = {minX = -50000, minY = -50000, maxX = 50000, maxY = 50000}
    for i = 1, count or 4 do
        local points = {{0, 0}, {-4000, 0}, {4000, 0}, {0, 2500}, {200, 0}}
        local xy = points[i] or {i * 1100, 10000}
        entities[i] = {id = i, name = "Twin", x = xy[1], y = xy[2], z = -2, capacity = i == 4 and 400 or (i == 5 and 50 or 2000)}
        ids[#ids + 1] = i
    end
    local native = {industryIds = {}, components = {}, trackMap = {}, capacityReads = 0}
    local oldExists, oldComponent, oldIds = api.engine.entityExists, api.engine.getComponent, api.engine.getEntitiesWithComponent
    api.type.ComponentType.INDUSTRY, api.type.ComponentType.CONSTRUCTION = "industry", "construction"
    api.type.ComponentType.BASE_EDGE, api.type.ComponentType.BASE_NODE = "edge", "node"
    api.type["enum"] = {LandUseType = {RESIDENTIAL = 2}, RoadType = {TRACK = "track"}}
    api.engine.entityExists = function(id) return native.components[id] ~= nil or oldExists(id) end
    api.engine.getComponent = function(id, kind)
        return native.components[id] and native.components[id][kind] or oldComponent(id, kind)
    end
    api.engine.getEntitiesWithComponent = function(kind)
        if kind == "industry" then return native.industryIds end
        return oldIds(kind)
    end
    -- Deliberately callable table: production must never demand type == function.
    api.engine.util.town = {getTownCapacityUsage = setmetatable({}, {__call = function(_, id)
        native.capacityReads = native.capacityReads + 1
        return {[1] = {capacity = 999999}, [3] = {capacity = entities[id] and entities[id].capacity}}
    end})}
    api.engine.system.streetSystem = {getNode2TrackEdgeMap = function() return native.trackMap end}
    return native
end
local function analyze(gui, event, mode)
    local s = gui:get()
    return event("analyzeNetwork", {world = s.world, epoch = s.epoch, requestId = s.networkRequestId + 1, mode = mode})
end
local function networkDone(s) return s and s.network and s.network.finished end
local function runNetwork(count, setup)
    local gui, step, untilState, event, callbacks = newSession()
    local native = networkFixture(count)
    if setup then setup(native) end
    ready(step, untilState); assert(analyze(gui, event).accepted); untilState(networkDone)
    return gui, step, untilState, event, native, callbacks
end

test("network: native snapshot uses symbolic capacity index, plain provenance and no terrain reads", function()
    local gui = runNetwork(4)
    local r = gui:get().network
    equal(r.status, "ok"); equal(r.result.stats.pairs, 6); equal(r.result.stats.astarSearches, 0)
    equal(heightReads, 0); equal(r.missingCapacity, 0)
    equal(#r.result.recommendations, 3); equal(#r.result.hubs, 1)
    local main, branch = 0, 0
    for _, e in ipairs(r.result.recommendations) do
        if e.classification == "mainline" then main = main + 1 else branch = branch + 1 end
        equal(e.evidence.residentialCapacitySource.basis, "observed")
        equal(e.evidence.demandSupport, nil); equal(e.evidence.geography, nil)
        equal(e.constructionStatus, "unverified")
    end
    equal(main, 2); equal(branch, 1); equal(r.result.towns[1].name, r.result.towns[2].name)
    equal(r.result.recommendations[1].evidence.residentialCapacitySource.value, 2000)
    assert(r.summary.lines[1]:find("Mainlines: 2 | Branches: 1", 1, true))
    equal(r.input, nil); equal(r.edges, nil)
end)

test("network: missing capacity is unknown and explicit zero stays zero", function()
    local gui = runNetwork(3, function() entities[1].capacity = nil; entities[2].capacity = 0 end)
    local r = gui:get().network
    equal(r.status, "ok"); equal(r.missingCapacity, 1); equal(#r.result.recommendations, 0)
    equal(r.result.decisions[1].evidence.residentialCapacitySource, nil)
    equal(r.result.decisions[1].evidence.residentialCapacityDestination.value, 0)
    assert(r.summary.lines[5]:find("not demand", 1, true))
end)

test("network: empty and single-town maps complete without invented connections", function()
    for _, count in ipairs({0, 1}) do
        local gui = runNetwork(count)
        equal(gui:get().network.status, "ok"); equal(#gui:get().network.result.towns, count)
        equal(#gui:get().network.result.recommendations, 0)
    end
end)

test("network: near small towns deliberately stay unconnected", function()
    local gui = runNetwork(5)
    local r = gui:get().network.result
    equal(r.towns[5].degree, 0); equal(r.towns[5].status, "no_new_rail_recommended_now")
    local found = false
    for _, d in ipairs(r.decisions) do if d.id == "1:5" then
        equal(d.reasons[1], "short_distance_compare_road_first"); found = true
    end end
    assert(found)
end)

local function railFixture(n)
    n.trackMap = {[100] = {900}, [101] = {900}}
    n.components[100] = {node = {position = {x = 0, y = 0, z = 0}}}
    n.components[101] = {node = {position = {x = -4000, y = 0, z = 0}}}
    n.components[900] = {edge = {node0 = 100, node1 = 101, roadType = "track", roadTemplate = "verified-fixture-track",
        position0 = {x = 0, y = 0, z = 0}, position1 = {x = -4000, y = 0, z = 0}}}
end
test("network: physical rail proximity defers reuse inspection without service claims", function()
    local gui = runNetwork(2, railFixture)
    local r = gui:get().network.result
    equal(#r.recommendations, 0)
    equal(r.decisions[1].reasons[1], "inspect_existing_physical_rail_before_new_corridor")
    equal(r.decisions[1].infrastructure.source.nodeId, 100)
    equal(r.decisions[1].infrastructure.destination.nodeId, 101)
end)

test("network: broken rail graph is omitted with precise diagnostics, never silently complete", function()
    local gui = runNetwork(2, function(n) railFixture(n); n.components[101] = nil end)
    local r = gui:get().network
    equal(r.status, "ok"); assert(r.warningCount > 0)
    equal(r.result.decisions[1].infrastructure.provenance, nil)
    assert(hasLog("partial_rail_inventory_omitted")); assert(hasLog("api.engine.entityExists(101)"))
end)

test("network: industry construction origin/resource collected but never creates freight edges", function()
    local gui = runNetwork(2, function(n)
        n.industryIds = {700, 701}
        n.components[700] = {industry = {construction = 800, level = 0}}
        n.components[701] = {industry = {construction = 801, level = 0}}
        n.components[800] = {construction = {fileName = "synthetic_logging", transf = {getTransl = function() return {x = 0, y = 10, z = -3} end}}}
    end)
    local r = gui:get().network
    equal(r.status, "ok"); equal(#r.result.industries, 1)
    equal(r.result.industries[1].resource, "synthetic_logging"); equal(r.result.industries[1].status, "deferred")
    assert(r.warningCount > 0); equal(#r.result.recommendations, 1)
end)

test("network: separated distant groups do not force national connectivity", function()
    local gui = runNetwork(4, function()
        entities[3].x, entities[3].y = 30000, 20000
        entities[4].x, entities[4].y = 34000, 20000
    end)
    equal(#gui:get().network.result.components, 2)
end)

test("network: deterministic repeated snapshots preserve policy and bounded UI data", function()
    local gui, _, untilState, event = runNetwork(5)
    local first = serialize(gui:get().network.result.decisions)
    assert(analyze(gui, event).accepted); untilState(networkDone)
    equal(serialize(gui:get().network.result.decisions), first)
    local response = event("status")
    assert(response.networkSummary); equal(response.networkSummary.result, nil)
    equal(response.networkSummary.rail, nil); equal(response.networkRequestId, 2)
end)

test("network: explicit click only; request replay and corridor concurrency rejected", function()
    local gui, step, untilState, event = newSession(); local n = networkFixture(4)
    ready(step, untilState); step(100); event("status")
    equal(gui:get().network, nil); equal(n.capacityReads, 0)
    local s = gui:get(); local token = {world = s.world, epoch = s.epoch, requestId = 1}
    assert(event("analyzeNetwork", token).accepted)
    equal(event("analyzeNetwork", token).reason, "busy")
    equal(submit(gui, event, 1, 2).reason, "busy")
    equal(event("refresh").reason, "busy")
    untilState(networkDone)
    equal(event("analyzeNetwork", token).reason, "duplicate_or_stale_network_request")
    equal(logCount("START world="), 1)
    assert(submit(gui, event, 1, 2).accepted)
    equal(analyze(gui, event).reason, "busy")
end)

test("network: stale request, world change and reactPostInit invalidate independent state", function()
    local gui, step, untilState, event, cb = newSession(); networkFixture(3); ready(step, untilState)
    equal(event("analyzeNetwork", {world = -1, epoch = gui:get().epoch, requestId = 1}).reason, "stale_session")
    assert(analyze(gui, event).accepted); step(3); local old = gui:get().network
    worldId = 100; step(); equal(old.status, "invalidated"); equal(old.result, nil); equal(gui:get().network, nil)
    ready(step, untilState); assert(analyze(gui, event).accepted); step(3); old = gui:get().network
    cb.guiHandleEvent(nil, nil, gui, "native", "gameUI", "reactPostInit", {})
    equal(old.status, "invalidated"); equal(gui:get().networkRequestId, 0)
end)

test("network: changed anchors, index and bounds stop stale snapshot publication", function()
    for _, change in ipairs({function() entities[1].x = 1 end,
        function() ids[#ids + 1] = 123 end,
        function() mapBounds.maxX = 49000 end}) do
        local gui, step, untilState, event = newSession(); networkFixture(2); ready(step, untilState)
        analyze(gui, event)
        untilState(function(s) return s.network.phase == "verify_towns" end)
        change(); untilState(networkDone)
        equal(gui:get().network.status, "error"); equal(gui:get().network.summary, nil)
    end
end)

test("network: town and pair caps abort oversized analysis rather than truncate", function()
    local gui = runNetwork(33)
    equal(gui:get().network.status, "unsupported"); equal(gui:get().network.summary, nil)
    assert(gui:get().network.message:find("limit", 1, true))
    gui = runNetwork(32)
    equal(gui:get().network.status, "ok"); equal(gui:get().network.result.stats.pairs, 496)
    assert(#gui:get().network.summary.links <= 55)
end)

test("network: read batches, age and observed work limits stay bounded", function()
    local gui, step, untilState, event = newSession(); local n = networkFixture(12); ready(step, untilState)
    analyze(gui, event); step(); equal(n.capacityReads, 0)
    step(); equal(n.capacityReads, 4); step(); equal(n.capacityReads, 8)
    clock = clock + 61; step(); equal(gui:get().network.status, "invalidated")
    clockStep = 0; analyze(gui, event); clockStep = 0.1; step()
    equal(gui:get().network.status, "performance_limit"); equal(gui:get().network.summary, nil)
    equal(logCount("COMPLETE status=ok"), 0)
end)

test("network: optional native reads fail visibly without inventing size or industries", function()
    local gui = runNetwork(2, function()
        api.engine.util.town.getTownCapacityUsage = nil
        api.engine.system.streetSystem.getNode2TrackEdgeMap = function() error("native track read failed") end
    end)
    local r = gui:get().network
    equal(r.status, "ok"); equal(#r.result.recommendations, 0); equal(r.missingCapacity, 2)
    assert(hasLog("getTownCapacityUsage")); assert(hasLog("native track read failed"))
end)

test("network: UI click uses subscribed join dispatch, real result and inspectable ID links", function()
    local gui, step, untilState = newSession(); networkFixture(5); ready(step, untilState)
    local render, poll, tree, controls = mountUI()
    find(tree, "Button", "Railway Network Architect")[1].params.onClick(); tree = render()
    equal(gui:get().network, nil)
    local combos = planningCombos(tree)
    combos[1].params.onValueChange("1"); combos[2].params.onValueChange("2"); tree = render()
    local button = find(tree, "Button", "Analyze Network")[1]
    assert(button.params.meta.enabled); button.params.onClick(); button.params.onClick(); tree = render()
    equal(gui:get().networkRequestId, 1); equal(find(tree, "Button", "Plan")[1].params.meta.enabled, false)
    untilState(networkDone); poll(); tree = render()
    combos = planningCombos(tree); equal(#combos, 3)
    equal(combos[1].params.value, "1"); equal(combos[2].params.value, "2")
    equal(combos[3].params.value, gui:get().network.summary.links[1].id)
    local last = gui:get().network.summary.links[#gui:get().network.summary.links]
    combos[3].params.onValueChange(last.id); tree = render()
    equal(planningCombos(tree)[3].params.value, last.id)
    equal(heightReads, 0); equal(logCount("START world="), 1)
    assert(controls.events[#controls.events].name:find("status", 1, true))
end)

test("network: refresh, transport failure and close/reopen do not restore stale summaries", function()
    local gui, _, _, event = runNetwork(3)
    local render, poll, tree, controls = mountUI()
    find(tree, "Button", "Railway Network Architect")[1].params.onClick(); tree = render()
    equal(#planningCombos(tree), 3)
    controls.resultFilter = function() return nil end; poll(); tree = render()
    equal(#planningCombos(tree), 2)
    controls.resultFilter = nil
    find(tree, "Button", "Refresh towns")[1].params.onClick(); tree = render()
    equal(gui:get().network, nil); equal(#planningCombos(tree), 2)
    controls.panel.params.onClose(); tree = render()
    find(tree, "Button", "Railway Network Architect")[1].params.onClick(); tree = render()
    equal(#planningCombos(tree), 2); equal(event("status").networkSummary, nil)
end)

test("network: malformed response stops polling and stale link callbacks are ignored", function()
    local gui, _, _, event = runNetwork(3)
    local render, poll, tree, controls = mountUI()
    find(tree, "Button", "Railway Network Architect")[1].params.onClick(); tree = render()
    local oldChoice = planningCombos(tree)[3].params.onValueChange
    controls.resultFilter = function(value) value.networkSummary = {epoch = -1}; return value end
    poll(); tree = render(); local count = #controls.events; poll(); poll()
    equal(#controls.events, count); equal(#planningCombos(tree), 2)
    oldChoice("1:2"); tree = render(); equal(#planningCombos(tree), 2)
    controls.resultFilter = nil; event("refresh")
    find(tree, "Button", "Refresh towns")[1].params.onClick(); render()
    equal(gui:get().network, nil)
end)

test("network: GUI state copying preserves the continuation without table identity assumptions", function()
    local gui, step, untilState, event = newSession(); networkFixture(5)
    local set = gui.set
    local function copy(v)
        if type(v) ~= "table" then assert(type(v) ~= "function"); return v end
        local out = {}; for k, item in pairs(v) do out[k] = copy(item) end; return out
    end
    gui.set = function(self, value) set(self, copy(value)) end
    ready(step, untilState); analyze(gui, event); untilState(networkDone)
    equal(gui:get().network.status, "ok"); equal(#gui:get().network.result.recommendations, 3)
end)

test("network: optional input size limits omit whole context with visible warnings", function()
    local gui = runNetwork(2, function(n)
        for i = 1, 129 do n.industryIds[i] = 1000 + i end
        for i = 1, 4097 do n.trackMap[10000 + i] = {20000 + i} end
    end)
    local r = gui:get().network
    equal(r.status, "ok"); equal(#r.result.industries, 0)
    equal(r.snapshot.railNodes, nil); assert(r.warningCount >= 2)
    assert(hasLog("industries omitted")); assert(hasLog("rail omitted"))
end)

test("network: final work-limit failure cannot publish a successful summary", function()
    local gui, step, untilState, event = newSession(); networkFixture(4); ready(step, untilState)
    analyze(gui, event); untilState(function(s) return s.network.phase == "summary" end)
    clockStep = 0.1; step()
    equal(gui:get().network.status, "performance_limit"); equal(gui:get().network.summary, nil)
    equal(gui:get().network.snapshot, nil); equal(logCount("COMPLETE status=ok"), 0)
end)

test("network: rail reads are sliced, maximum supported graph remains bounded", function()
    local gui, step, untilState, event = newSession(); local n = networkFixture(32)
    for i = 1, 4096 do
        n.components[10000 + i] = {node = {position = {x = i * 10, y = 15000, z = 0}}}
        n.trackMap[10000 + i] = {}
    end
    for i = 1, 8192 do
        local a, b = 10001 + ((i - 1) % 4096), 10001 + (i % 4096)
        n.components[20000 + i] = {edge = {node0 = a, node1 = b, roadType = "track", roadTemplate = "synthetic",
            position0 = n.components[a].node.position, position1 = n.components[b].node.position}}
        table.insert(n.trackMap[a], 20000 + i); table.insert(n.trackMap[b], 20000 + i)
    end
    local oldComponent = api.engine.getComponent
    local edgeReads, nodeReads = 0, 0
    api.engine.getComponent = function(id, kind)
        if kind == "edge" then edgeReads = edgeReads + 1 elseif kind == "node" then nodeReads = nodeReads + 1 end
        return oldComponent(id, kind)
    end
    ready(step, untilState); analyze(gui, event)
    local started, steps = os.clock(), 0
    while not networkDone(gui:get()) do
        edgeReads, nodeReads = 0, 0; step(); steps = steps + 1
        assert(edgeReads <= 16 and nodeReads <= 16); assert(steps < 900)
    end
    local r = gui:get().network
    equal(r.status, "ok"); equal(r.snapshot.railNodes, 4096); equal(r.snapshot.railSegments, 8192)
    equal(r.result.stats.railNodeComparisons, 131072); equal(r.result.stats.pairs, 496)
    print(string.format("NETWORK MOCK STRESS callbacks=%d cpu_seconds=%.6f nodes=4096 segments=8192 pairs=496 (not native timing)", steps, os.clock() - started))
end)

test("handoff audit: network analysis after completed corridor never sends a busy corridor preview", function()
    local gui, _, untilState, event = runNetwork(4)
    assert(submit(gui, event, 1, 4).accepted); untilState(completed)
    assert(event("status").preview)
    assert(analyze(gui, event).accepted)
    local value = event("status")
    equal(value.busy, true); equal(value.preview, nil)
    local render, _, tree = mountUI()
    find(tree, "Button", "Railway Network Architect")[1].params.onClick(); render()
    equal(logCount("UI_ERROR"), 0)
end)

local function studyToken(gui, edgeId)
    local s = gui:get()
    return {world = s.world, epoch = s.epoch, requestId = s.requestId + 1,
        network = {requestId = s.networkRequestId, snapshotId = s.network.result.snapshotId, edgeId = edgeId}}
end
local function study(gui, event, edgeId) return event("plan", studyToken(gui, edgeId)) end

test("handoff: mainline and branch use canonical endpoints and preserve independent evidence", function()
    for _, example in ipairs({{"1:2", "mainline", 2}, {"1:4", "branch", 4}}) do
        local gui, _, untilState, event = runNetwork(4)
        local original = serialize(gui:get().network.result)
        local response = study(gui, event, example[1]); assert(response.accepted, response.reason)
        equal(heightReads, 0); equal(gui:get().request.sourceId, 1); equal(gui:get().request.destinationId, example[3])
        equal(gui:get().request.networkOrigin.classification, example[2])
        equal(gui:get().request.networkOrigin.evidence.demandSupport, nil)
        untilState(completed); equal(gui:get().request.status, "ok")
        assert(heightReads > 0); assert(event("status").preview)
        equal(event("status").preview.source.id, 1); equal(event("status").preview.destination.id, example[3])
        equal(serialize(gui:get().network.result), original)
        equal(gui:get().request.networkOrigin.constructionStatus, "unverified")
        assert(event("status").corridorOrigin.lines[4]:find("unverified", 1, true))
    end
end)

test("handoff: deferred, rejected, unknown and malformed selections never sample terrain", function()
    local gui, _, _, event = runNetwork(5)
    for _, edge in ipairs({"1:5", "2:3", "999:1000"}) do
        local response = study(gui, event, edge)
        equal(response.accepted, false); equal(response.reason, "edge_not_recommended")
    end
    local token = studyToken(gui, "1:2"); token.network = false
    equal(event("plan", token).accepted, false); equal(heightReads, 0); equal(gui:get().request, nil)
end)

test("handoff: busy, replay, sequential studies and manual requests share one corridor token", function()
    local gui, _, untilState, event = runNetwork(4)
    local token = studyToken(gui, "1:4")
    assert(event("plan", token).accepted); equal(event("plan", token).reason, "busy")
    equal(analyze(gui, event).reason, "busy"); untilState(completed)
    equal(event("plan", token).reason, "duplicate_or_stale_request")
    assert(study(gui, event, "1:2").accepted); untilState(completed)
    equal(gui:get().requestId, 2); equal(logCount("[RNA:HANDOFF:5B2] START"), 2)
    assert(submit(gui, event, 4, 1).accepted); untilState(completed)
    equal(gui:get().request.networkOrigin, nil); equal(event("status").corridorOrigin, nil)
    equal(gui:get().request.sourceId, 4); equal(gui:get().request.destinationId, 1)
end)

test("handoff: old network request and snapshot identities cannot select a replacement result", function()
    local gui, _, untilState, event = runNetwork(4)
    local old = studyToken(gui, "1:2")
    assert(analyze(gui, event).accepted); untilState(networkDone)
    equal(event("plan", old).accepted, false)
    local token = studyToken(gui, "1:2"); token.network.snapshotId = "wrong"
    equal(event("plan", token).accepted, false); equal(heightReads, 0)
    equal(gui:get().request, nil)
end)

test("handoff: age, reversed clock and unavailable timing reject with no automatic refresh", function()
    for _, mode in ipairs({"expired", "backwards", "missing"}) do
        local gui, _, _, event = runNetwork(4)
        if mode == "expired" then clock = clock + 61
        elseif mode == "backwards" then clock = 0
        else api.util.getApplicationTime = function() return nil end end
        equal(event("status").canStudy, false)
        equal(study(gui, event, "1:2").accepted, false); equal(heightReads, 0)
        equal(gui:get().networkRequestId, 1); equal(gui:get().request, nil)
    end
end)

test("handoff: deleted entities and removed TOWN components are rejected", function()
    for _, mode in ipairs({"deleted", "component"}) do
        local gui, _, _, event = runNetwork(4)
        if mode == "deleted" then entities[2] = nil else
            local component = api.engine.getComponent
            api.engine.getComponent = function(id, kind)
                if id == 2 and kind == "town" then return nil end
                return component(id, kind)
            end
        end
        equal(study(gui, event, "1:2").accepted, false); equal(heightReads, 0)
    end
end)

test("handoff: position, capacity, index and bounds changes reject stale recommendations", function()
    for _, change in ipairs({function() entities[2].x = -3999 end,
        function() entities[2].capacity = 2001 end,
        function() entities[2].capacity = nil end,
        function() ids[#ids + 1] = 123 end,
        function() mapBounds.maxX = 49000 end}) do
        local gui, _, _, event = runNetwork(4); change()
        local response = study(gui, event, "1:2")
        equal(response.accepted, false); assert(response.reason:find("network_", 1, true))
        equal(heightReads, 0); equal(gui:get().request, nil)
    end
end)

test("handoff: world reload clears provenance and stale request cannot launch work", function()
    local gui, step, untilState, event, _, cb = runNetwork(4)
    local token = studyToken(gui, "1:2")
    assert(event("plan", token).accepted); step(20); local old = gui:get().request
    cb.guiHandleEvent(nil, nil, gui, "native", "gameUI", "reactPostInit", {})
    equal(old.status, "invalidated"); equal(gui:get().request, nil); equal(gui:get().network, nil)
    equal(event("status").corridorOrigin, nil); equal(event("plan", token).reason, "stale_session")
end)

test("handoff: 8000-unit recommendation uses existing hierarchy and fresh terrain", function()
    local gui, _, untilState, event = runNetwork(2, function() entities[2].x = -8000 end)
    equal(heightReads, 0); assert(study(gui, event, "1:2").accepted); untilState(completed)
    equal(gui:get().request.status, "ok"); assert(gui:get().request.hierarchy)
    assert(event("status").preview.candidates[1].sections > 1)
    equal(gui:get().request.networkOrigin.directDistance, 8000)
end)

test("handoff: unsupported, unreachable and search-limit remain accurate without summaries or retries", function()
    for _, mode in ipairs({"unsupported", "unreachable", "search_limit"}) do
        local gui, step, untilState, event = newSession(mode == "search_limit" and {maxExpansions = 1} or nil)
        networkFixture(2)
        entities[2].x, entities[2].y = 0, 1500
        if mode == "unsupported" then
            mapBounds = {minX = 10, maxX = 20, minY = -100, maxY = 1600}
            entities[1].x, entities[2].x = 15, 15
        elseif mode == "unreachable" then api.engine.terrain.isOnWater = function(p) return p.y > 400 and p.y < 800 end end
        ready(step, untilState); analyze(gui, event); untilState(networkDone)
        assert(study(gui, event, "1:2").accepted); untilState(completed)
        equal(gui:get().request.status, mode); equal(event("status").preview, nil)
        assert(event("status").corridorOrigin.lines[1]:find(mode, 1, true))
        local count = heightReads; step(100); equal(heightReads, count)
        equal(logCount("[RNA:HANDOFF:5B2] START"), 1)
    end
end)

test("handoff: changed world during validation and work budget breach never start a corridor", function()
    for _, mode in ipairs({"world", "budget"}) do
        local gui, _, _, event = runNetwork(4)
        if mode == "world" then
            local capacity = api.engine.util.town.getTownCapacityUsage
            api.engine.util.town.getTownCapacityUsage = function(id) worldId = 100; return capacity(id) end
        else clockStep = 0.1 end
        local response = study(gui, event, "1:2")
        equal(response.accepted, false); equal(heightReads, 0); equal(gui:get().request, nil)
    end
end)

test("handoff: UI recommendation selection, duplicate names and one click reach subscribed plan handler", function()
    local gui, _, untilState = runNetwork(4)
    local render, poll, tree, controls = mountUI(); controls.launcher.params.onClick(); tree = render()
    local combos = planningCombos(tree)
    combos[1].params.onValueChange("3"); combos[2].params.onValueChange("2")
    combos[3].params.onValueChange("1:4"); tree = render()
    assert(panelText(tree):find("Twin [#1] -> Twin [#4]", 1, true))
    assert(panelText(tree):find("Direct distance 2500", 1, true)); equal(heightReads, 0)
    local button = find(tree, "Button", "Study Corridor")[1]
    equal(button.params.meta.enabled, true); button.params.onClick(); button.params.onClick(); tree = render()
    equal(gui:get().request.sourceId, 1); equal(gui:get().request.destinationId, 4)
    equal(logCount("[RNA:HANDOFF:5B2] START"), 1)
    equal(controls.events[#controls.events].name, "oz_railway_network_architect.plan.plan")
    untilState(completed); poll(); tree = render()
    equal(planningCombos(tree)[1].params.value, "3"); equal(planningCombos(tree)[2].params.value, "2")
    assert(panelText(tree):find("branch #1 -> #4", 1, true)); assert(panelText(tree):find("economic feasibility unverified", 1, true))
    local before = heightReads
    planningCombos(tree)[3].params.onValueChange(gui:get().request.preview.candidates[1].id)
    render(); poll(); equal(heightReads, before)
end)

test("handoff: deferred selection, empty results and expired snapshots disable Study Corridor", function()
    local gui, _, _, event = runNetwork(5)
    local render, poll, tree, controls = mountUI(); controls.launcher.params.onClick(); tree = render()
    planningCombos(tree)[3].params.onValueChange("1:5"); tree = render()
    local button = find(tree, "Button", "Study Corridor")[1]
    equal(button.params.meta.enabled, false); button.params.onClick(); render(); equal(gui:get().request, nil)
    planningCombos(tree)[3].params.onValueChange("1:2"); tree = render()
    clock = clock + 61; poll(); tree = render()
    equal(find(tree, "Button", "Study Corridor")[1].params.meta.enabled, false)
    assert(panelText(tree):find("Analyze Network again", 1, true))
    event("refresh"); poll(); tree = render()
    equal(find(tree, "Button", "Study Corridor")[1].params.meta.enabled, false)
end)

test("handoff: expired window and replaced snapshot callbacks cannot launch obsolete studies", function()
    local gui, _, untilState, event = runNetwork(4)
    local render, poll, tree, controls = mountUI(); controls.launcher.params.onClick(); tree = render()
    local oldClick = find(tree, "Button", "Study Corridor")[1].params.onClick
    analyze(gui, event); untilState(networkDone); poll(); render()
    oldClick(); render(); equal(gui:get().request, nil)
    tree = render(); local click = find(tree, "Button", "Study Corridor")[1].params.onClick
    controls.autoJoin = false; click(); controls.panel.params.onClose(); controls.flush()
    equal(gui:get().request, nil)
    controls.autoJoin = true; tree = render(); controls.launcher.params.onClick(); tree = render()
    equal(find(tree, "Button", "Study Corridor")[1].params.meta.enabled, true)
    equal(heightReads, 0)
end)

test("handoff: independent origin survives network replacement and copied GUI state", function()
    local gui, _, untilState, event = runNetwork(4)
    local set = gui.set
    local function copy(v)
        if type(v) ~= "table" then assert(type(v) ~= "function"); return v end
        local out = {}; for k, item in pairs(v) do out[k] = copy(item) end; return out
    end
    gui.set = function(self, value) set(self, copy(value)) end
    assert(study(gui, event, "1:4").accepted); untilState(completed)
    local original = serialize(gui:get().request.networkOrigin)
    assert(analyze(gui, event).accepted); untilState(networkDone)
    equal(gui:get().networkRequestId, 2)
    equal(serialize(gui:get().request.networkOrigin), original)
    equal(event("status").corridorOrigin.lines[1]:find("network #1", 1, true) ~= nil, true)
    assert(event("status").preview)
end)

local function editToken(gui, action, edgeId)
    local s, w = gui:get(), gui:get().worklist
    return {world = s.world, epoch = s.epoch, worklist = {snapshotId = w.snapshotId,
        networkRequestId = w.networkRequestId, revision = w.revision, action = action, edgeId = edgeId}}
end
local function editNetwork(gui, event, action, edgeId) return event("plan", editToken(gui, action, edgeId)) end

test("worklist: live result creates an independent session worklist without A*", function()
    local gui, _, _, event = runNetwork(5)
    local s = gui:get(); equal(s.worklist.revision, 0); equal(s.worklist.graph.included, 3)
    equal(s.worklist.graph.unconnected[1], 5); equal(s.worklist.graph.hubs[1], 1)
    equal(s.worklist.snapshotId, s.network.result.snapshotId); equal(heightReads, 0)
    equal(event("status").worklist.entries[3].classification, "branch")
    equal(logCount("REQUEST_START"), 0); equal(logCount("[RNA:WORKLIST:5C1] CREATE"), 1)
end)

test("worklist: sequential include exclude mark restore and reset preserve original evidence", function()
    local gui, _, _, event = runNetwork(5)
    local original = serialize(gui:get().network.result); local originalSummary = serialize(gui:get().network.summary)
    assert(editNetwork(gui, event, "exclude", "1:4").accepted)
    equal(gui:get().worklist.graph.included, 2); equal(#gui:get().worklist.graph.hubs, 0)
    assert(editNetwork(gui, event, "mark_study", "1:4").accepted)
    equal(gui:get().worklist.overrides['1:4'].included, false)
    equal(gui:get().worklist.overrides['1:4'].furtherStudy, true)
    assert(editNetwork(gui, event, "include", "1:4").accepted)
    equal(gui:get().worklist.graph.included, 3)
    equal(gui:get().worklist.overrides['1:4'].provenance.actor, "user")
    assert(editNetwork(gui, event, "restore", "1:4").accepted)
    equal(gui:get().worklist.graph.overrides, 0)
    assert(editNetwork(gui, event, "exclude", "1:2").accepted)
    assert(editNetwork(gui, event, "reset_all").accepted)
    equal(gui:get().worklist.revision, 6); equal(gui:get().worklist.graph.included, 3)
    equal(serialize(gui:get().network.result), original); equal(serialize(gui:get().network.summary), originalSummary)
    equal(gui:get().requestId, 0); equal(gui:get().networkRequestId, 1); equal(heightReads, 0)
end)

test("worklist: replay and stale revision or snapshot operations are atomic", function()
    local gui, _, _, event = runNetwork(4)
    local token = editToken(gui, "exclude", "1:2"); assert(event("plan", token).accepted)
    local previous = serialize(gui:get().worklist)
    equal(event("plan", token).reason, "duplicate_or_stale_worklist_revision")
    token = editToken(gui, "include", "1:2"); token.worklist.snapshotId = "obsolete"
    equal(event("plan", token).reason, "stale_worklist_snapshot")
    token = editToken(gui, "include", "1:2"); token.worklist.networkRequestId = 20
    equal(event("plan", token).reason, "stale_worklist_snapshot")
    token = editToken(gui, "include", "1:2"); token.world = -1
    equal(event("plan", token).reason, "stale_session")
    equal(serialize(gui:get().worklist), previous); equal(heightReads, 0)
end)

test("worklist: busy corridor and network jobs reject edits without consuming revision", function()
    local gui, _, untilState, event = runNetwork(4)
    local token = editToken(gui, "exclude", "1:2")
    assert(study(gui, event, "1:4").accepted)
    equal(event("plan", token).reason, "busy"); equal(gui:get().worklist.revision, 0)
    untilState(completed); assert(event("plan", token).accepted)
    token = editToken(gui, "include", "1:2")
    assert(analyze(gui, event).accepted); equal(gui:get().worklist, nil)
    equal(event("plan", token).reason, "busy"); untilState(networkDone)
    equal(event("plan", token).reason, "stale_worklist_snapshot")
    equal(gui:get().worklist.revision, 0)
end)

test("worklist: deferred links and ambiguous event payloads never execute planning", function()
    local gui, _, _, event = runNetwork(5)
    equal(editNetwork(gui, event, "include", "1:5").reason, "edge_not_in_worklist")
    local token = editToken(gui, "exclude", "1:2"); token.sourceId = 1; token.destinationId = 2
    equal(event("plan", token).reason, "invalid_worklist_envelope")
    token = editToken(gui, "exclude", "1:2"); token.network = {edgeId = "1:2"}
    equal(event("plan", token).reason, "invalid_worklist_envelope")
    equal(event("analyzeNetwork", editToken(gui, "reset_all")).reason, "invalid_worklist_envelope")
    equal(gui:get().worklist.revision, 0); equal(heightReads, 0); equal(gui:get().request, nil)
end)

test("worklist: reload and Refresh remove edits and cannot accept old operations", function()
    local gui, step, untilState, event, _, cb = runNetwork(4)
    assert(editNetwork(gui, event, "exclude", "1:4").accepted)
    local token = editToken(gui, "include", "1:4")
    cb.guiHandleEvent(nil, nil, gui, "native", "gameUI", "reactPostInit", {})
    equal(gui:get().worklist, nil); equal(event("plan", token).reason, "stale_session")
    ready(step, untilState); analyze(gui, event); untilState(networkDone)
    assert(editNetwork(gui, event, "mark_study", "1:2").accepted)
    assert(event("refresh").accepted); equal(gui:get().worklist, nil)
    equal(event("status").worklist, nil)
end)

test("worklist: world invalidation removes the worklist while copied state preserves valid edits", function()
    local gui, step, _, event = runNetwork(4)
    local set = gui.set
    local function copy(v)
        if type(v) ~= "table" then assert(type(v) ~= "function"); return v end
        local out = {}; for k, value in pairs(v) do out[k] = copy(value) end; return out
    end
    gui.set = function(self, value) set(self, copy(value)) end
    assert(editNetwork(gui, event, "exclude", "1:4").accepted)
    assert(editNetwork(gui, event, "mark_study", "1:2").accepted)
    equal(gui:get().worklist.graph.overrides, 2)
    worldId = 123; event("status"); equal(gui:get().worklist, nil); equal(heightReads, 0)
end)

test("worklist: exclusion blocks Study Corridor, restore preserves it and original provenance", function()
    local gui, _, untilState, event = runNetwork(4)
    assert(editNetwork(gui, event, "exclude", "1:4").accepted)
    equal(study(gui, event, "1:4").reason, "connection_excluded_from_network_plan")
    equal(heightReads, 0)
    assert(editNetwork(gui, event, "restore", "1:4").accepted)
    assert(editNetwork(gui, event, "exclude", "1:2").accepted)
    assert(study(gui, event, "1:4").accepted); untilState(completed)
    equal(gui:get().request.networkOrigin.classification, "branch")
    equal(gui:get().request.networkOrigin.worklistDecision.revision, 3)
    equal(gui:get().request.networkOrigin.worklistDecision.classificationInterpretation, "historical_only_reassessment_required")
    assert(event("status").corridorOrigin.lines[4]:find("requires reassessment", 1, true))
    local before = heightReads; assert(editNetwork(gui, event, "reset_all").accepted)
    equal(gui:get().request.networkOrigin.worklistDecision.revision, 3); equal(heightReads, before)
    assert(submit(gui, event, 4, 1).accepted); untilState(completed); equal(gui:get().request.networkOrigin, nil)
end)

test("worklist: review edits do not refresh an expired world snapshot or automatically search", function()
    local gui, _, _, event = runNetwork(4); clock = clock + 61
    equal(event("status").canStudy, false)
    assert(editNetwork(gui, event, "mark_study", "1:4").accepted)
    equal(event("status").canStudy, false); equal(gui:get().networkRequestId, 1)
    equal(heightReads, 0); equal(gui:get().requestId, 0)
end)

test("worklist: UI edits keep selection, original reasons and styles while updating plan summary", function()
    local gui, _, _, event = runNetwork(5)
    local render, poll, tree, controls = mountUI(); controls.launcher.params.onClick(); tree = render()
    assert(panelText(tree):find("Network Plan", 1, true))
    local combo = planningCombos(tree)
    combo[1].params.onValueChange("3"); combo[2].params.onValueChange("2"); combo[3].params.onValueChange("1:4")
    tree = render(); local button = find(tree, "Button", "Exclude from plan")[1]
    assert(button.params.meta.enabled); button.params.onClick(); button.params.onClick(); tree = render()
    equal(gui:get().worklist.revision, 1); equal(gui:get().worklist.graph.excluded, 1)
    equal(find(tree, "Button", "Study Corridor")[1].params.meta.enabled, false)
    assert(panelText(tree):find("historical only", 1, true)); assert(panelText(tree):find("Residential capacity:", 1, true))
    equal(planningCombos(tree)[1].params.value, "3"); equal(planningCombos(tree)[2].params.value, "2")
    equal(planningCombos(tree)[3].params.value, "1:4")
    find(tree, "Button", "Mark for further study")[1].params.onClick(); tree = render()
    equal(gui:get().worklist.graph.furtherStudy, 1)
    find(tree, "Button", "Restore original recommendation")[1].params.onClick(); tree = render()
    equal(find(tree, "Button", "Study Corridor")[1].params.meta.enabled, true)
    equal(gui:get().worklist.graph.overrides, 0); equal(heightReads, 0)
    equal(controls.events[#controls.events].name, "oz_railway_network_architect.plan.plan")
    equal(controls.panel.params.initialX, 0.5); equal(controls.panel.params.initialY, 0.5)
    planningCombos(tree)[3].params.onValueChange("1:5"); tree = render()
    equal(find(tree, "Button", "Include in plan")[1].params.meta.enabled, false)
end)

test("worklist: stale UI actions, close and reopen cannot replay edits", function()
    local gui, _, untilState, event = runNetwork(4)
    local render, poll, tree, controls = mountUI(); controls.launcher.params.onClick(); tree = render()
    local oldClick = find(tree, "Button", "Exclude from plan")[1].params.onClick
    oldClick(); tree = render(); oldClick(); render(); equal(gui:get().worklist.revision, 1)
    controls.panel.params.onClose(); render(); controls.launcher.params.onClick(); tree = render()
    equal(gui:get().worklist.revision, 1); assert(panelText(tree):find("Excluded: 1", 1, true))
    local pending = find(tree, "Button", "Reset all edits")[1].params.onClick
    controls.autoJoin = false; pending(); controls.panel.params.onClose(); controls.flush()
    equal(gui:get().worklist.revision, 1)
    controls.autoJoin = true; render(); controls.launcher.params.onClick(); tree = render()
    local obsolete = find(tree, "Button", "Reset all edits")[1].params.onClick
    analyze(gui, event); untilState(networkDone); poll(); render(); obsolete(); render()
    equal(gui:get().worklist.revision, 0)
end)

test("worklist: malformed response pauses polling and explicit Refresh removes stale edits", function()
    local gui = runNetwork(4)
    local render, poll, tree, controls = mountUI(); controls.launcher.params.onClick(); tree = render()
    controls.resultFilter = function(v) v.worklist.epoch = -1; return v end
    poll(); tree = render(); local count = #controls.events; poll(); poll(); equal(#controls.events, count)
    equal(find(tree, "Button", "Exclude from plan")[1].params.meta.enabled, false)
    controls.resultFilter = nil
    find(tree, "Button", "Refresh towns")[1].params.onClick(); render()
    equal(gui:get().worklist, nil); equal(heightReads, 0)
end)

local function batchToken(gui, action)
    local s = gui:get()
    local w = action == "cancel" and s.batch or s.worklist
    return {world = s.world, epoch = s.epoch, batch = {action = action or "start",
        requestId = action == "cancel" and s.batch.id or s.batchRequestId + 1,
        networkRequestId = s.networkRequestId, snapshotId = w.snapshotId, revision = w.revision}}
end
local function startBatch(gui, event) return event("plan", batchToken(gui)) end
local function batchDone(s) return s and s.batch and s.batch.status ~= "running" end
local function mark(gui, event, ...)
    for _, id in ipairs({...}) do assert(editNetwork(gui, event, "mark_study", id).accepted) end
end

test("batch: marks, selections and analysis never start a search; only included marked recommendations qualify", function()
    local gui, step, _, event = runNetwork(5)
    equal(startBatch(gui, event).reason, "no_included_marked_recommendations")
    mark(gui, event, "1:2", "1:4")
    assert(editNetwork(gui, event, "exclude", "1:2").accepted)
    step(100); equal(heightReads, 0); equal(gui:get().batch, nil)
    equal(editNetwork(gui, event, "mark_study", "1:5").reason, "edge_not_in_worklist")
    assert(startBatch(gui, event).accepted)
    local b = gui:get().batch
    equal(b.total, 1); equal(b.queue[1].edgeId, "1:4"); equal(b.active, nil)
    equal(gui:get().requestId, 0); equal(heightReads, 0)
end)

test("batch: a complete branch produces compact validated summary and preserves original provenance", function()
    local gui, _, untilState, event = runNetwork(4)
    local before = serialize(gui:get().network.result)
    mark(gui, event, "1:4"); assert(startBatch(gui, event).accepted); untilState(batchDone)
    local b, dto = gui:get().batch, event("status").batch
    equal(b.status, "completed"); equal(b.succeeded, 1); equal(b.active, nil); equal(#b.queue, 0)
    local r = b.results[1]
    equal(r.sourceId, 1); equal(r.destinationId, 4); equal(r.classification, "branch")
    equal(r.status, "ok"); assert(r.candidateCount > 0); assert(r.preferred.length > 0)
    equal(r.origin.worklistDecision.revision, 1); equal(r.constructionStatus, "unverified")
    equal(serialize(gui:get().network.result), before); equal(gui:get().request, nil)
    equal(dto.completed, 1); equal(dto.remaining, 0)
    local function compact(v)
        if type(v) ~= "table" then assert(type(v) ~= "function" and type(v) ~= "userdata"); return end
        for k, item in pairs(v) do
            assert(k ~= "waypoints" and k ~= "grid" and k ~= "samples" and k ~= "planningJob" and k ~= "hierarchy")
            compact(item)
        end
    end
    compact(b); compact(dto)
    dto.results[1].origin.classification = "tampered"
    equal(gui:get().batch.results[1].origin.classification, "branch")
end)

test("batch: priority then canonical ID ordering is independent of recommendation enumeration", function()
    local gui, _, _, event = runNetwork(4)
    mark(gui, event, "1:4", "1:3", "1:2")
    local rec = gui:get().network.result.recommendations
    for _, edge in ipairs(rec) do edge.priority = edge.id == "1:4" and 1 or 2 end
    rec[1], rec[3] = rec[3], rec[1] -- Deliberate synthetic priority tie/permutation.
    assert(startBatch(gui, event).accepted)
    local q = gui:get().batch.queue
    equal(q[1].edgeId, "1:4"); equal(q[2].edgeId, "1:2"); equal(q[3].edgeId, "1:3")
end)

test("batch: more than four links fails explicitly without truncation or execution", function()
    local gui, _, _, event = runNetwork(10)
    assert(#gui:get().network.result.recommendations >= 5)
    for i = 1, 5 do mark(gui, event, gui:get().network.result.recommendations[i].id) end
    local response = startBatch(gui, event)
    equal(response.accepted, false); assert(response.reason:find("5 eligible links; maximum 4", 1, true))
    equal(gui:get().batch, nil); equal(heightReads, 0)
end)

test("batch: sequential mixed outcomes use one continuation with a separate next-start callback", function()
    local gui, step, untilState, event = runNetwork(4)
    api.engine.terrain.isOnWater = function(p) return p.x > -2500 and p.x < -1000 end
    mark(gui, event, "1:4", "1:2", "1:3"); assert(startBatch(gui, event).accepted)
    local starts = 0
    untilState(function(s)
        local b = s.batch
        if b.active then
            equal(s.request, nil); assert(s.network.finished)
            equal(#b.results, b.cursor - 1)
        end
        local now = logCount("[RNA:BATCH:5C2] STUDY_START")
        assert(now - starts <= 1); starts = now
        return batchDone(s)
    end)
    local b = gui:get().batch
    equal(starts, 3); equal(#b.results, 3); equal(b.status, "completed_with_failures")
    equal(b.unreachable, 1); equal(b.succeeded, 2)
    local byId = {}; for _, r in ipairs(b.results) do byId[r.edgeId] = r end
    equal(byId["1:2"].status, "unreachable"); equal(byId["1:2"].candidateCount, 0)
    equal(byId["1:3"].status, "ok"); equal(byId["1:4"].status, "ok")
    local count = heightReads; step(100); equal(heightReads, count)
    equal(gui:get().requestId, 0)
end)

test("batch: unsupported, unreachable and search-limit are never completed studies", function()
    for _, mode in ipairs({"unsupported", "unreachable", "search_limit"}) do
        local gui, step, untilState, event = newSession(mode == "search_limit" and {maxExpansions = 1} or nil)
        networkFixture(2); entities[2].x, entities[2].y = 0, 1500
        if mode == "unsupported" then
            mapBounds = {minX = 10, maxX = 20, minY = -100, maxY = 1600}
            entities[1].x, entities[2].x = 15, 15
        elseif mode == "unreachable" then api.engine.terrain.isOnWater = function(p) return p.y > 400 and p.y < 800 end end
        ready(step, untilState); analyze(gui, event); untilState(networkDone)
        mark(gui, event, "1:2"); assert(startBatch(gui, event).accepted); untilState(batchDone)
        local b = gui:get().batch
        equal(b.status, "completed_with_failures"); equal(b.results[1].status, mode)
        equal(b.succeeded, 0); equal(b.results[1].candidateCount, 0); equal(b.results[1].preferred, nil)
    end
end)

test("batch: snapshot expires between studies without reanalysis or loss of completed summaries", function()
    local gui, step, untilState, event = runNetwork(4)
    mark(gui, event, "1:2", "1:4"); assert(startBatch(gui, event).accepted)
    untilState(function(s) return #s.batch.results == 1 end)
    equal(gui:get().batch.active, nil); equal(logCount("[RNA:BATCH:5C2] STUDY_START"), 1)
    clock = gui:get().network.began + 61; step()
    local b = gui:get().batch
    equal(b.status, "stopped"); assert(b.reason:find("Analyze Network again", 1, true))
    equal(b.notStarted, 1); equal(#b.results, 1); equal(b.succeeded, 1); equal(#b.queue, 0)
    equal(gui:get().networkRequestId, 1); equal(gui:get().worklist.graph.furtherStudy, 2)
end)

test("batch: expired acceptance and stale worklist tokens cannot create a continuation", function()
    local gui, _, _, event = runNetwork(4); mark(gui, event, "1:4")
    local token = batchToken(gui); editNetwork(gui, event, "include", "1:2")
    equal(event("plan", token).reason, "stale_worklist_snapshot")
    equal(event("plan", token).reason, "duplicate_or_stale_batch_request")
    clock = gui:get().network.began + 61
    assert(startBatch(gui, event).reason:find("network_snapshot_expired", 1, true))
    equal(gui:get().batch, nil); equal(heightReads, 0)
end)

test("batch: changed revision or eligibility stops pending work", function()
    for _, change in ipairs({"revision", "excluded", "unmarked", "snapshot"}) do
        local gui, step, _, event = runNetwork(4); mark(gui, event, "1:4")
        assert(startBatch(gui, event).accepted)
        local s = gui:get()
        if change == "revision" then s.worklist.revision = s.worklist.revision + 1
        elseif change == "snapshot" then s.worklist.snapshotId = "stale"
        elseif change == "excluded" then s.worklist.overrides["1:4"].included = false
        else s.worklist.overrides["1:4"].furtherStudy = false end
        step(); equal(s.batch.status, "invalidated"); equal(s.batch.active, nil); equal(heightReads, 0)
    end
end)

test("batch: endpoints, town index and capacities are revalidated at each handoff", function()
    for _, change in ipairs({"deleted", "moved", "capacity", "index"}) do
        local gui, step, _, event = runNetwork(4); mark(gui, event, "1:4")
        assert(startBatch(gui, event).accepted)
        if change == "deleted" then entities[4] = nil
        elseif change == "moved" then entities[4].x = 20
        elseif change == "capacity" then entities[4].capacity = 600
        else ids[#ids + 1] = 100 end
        step(); assert(batchDone(gui:get())); equal(gui:get().batch.active, nil)
        equal(logCount("[RNA:BATCH:5C2] STUDY_START"), 0); equal(heightReads, 0)
    end
end)

test("batch: busy guard covers all conflicting actions and replay cannot restart a completed batch", function()
    local gui, _, untilState, event = runNetwork(4); mark(gui, event, "1:4")
    local token, edit = batchToken(gui), editToken(gui, "reset_all")
    assert(event("plan", token).accepted); equal(event("plan", token).reason, "busy")
    equal(submit(gui, event, 1, 2).reason, "busy"); equal(analyze(gui, event).reason, "busy")
    equal(study(gui, event, "1:2").reason, "busy"); equal(event("plan", edit).reason, "busy")
    equal(event("refresh").reason, "busy"); equal(gui:get().worklist.revision, 1)
    untilState(batchDone); equal(event("plan", token).reason, "duplicate_or_stale_batch_request")
    equal(logCount("[RNA:BATCH:5C2] START"), 1)
    assert(study(gui, event, "1:4").accepted); equal(startBatch(gui, event).reason, "busy")
    untilState(completed); assert(submit(gui, event, 4, 1).accepted); untilState(completed)
    equal(gui:get().request.networkOrigin, nil); equal(gui:get().batch.succeeded, 1)
end)

test("batch: cancellation invalidates active search and retains only completed summaries", function()
    local gui, step, untilState, event = runNetwork(4)
    mark(gui, event, "1:2", "1:3", "1:4"); assert(startBatch(gui, event).accepted)
    untilState(function(s) return #s.batch.results == 1 end); step()
    local active = gui:get().batch.active; assert(active)
    local token = batchToken(gui, "cancel")
    assert(event("plan", token).accepted); local b = gui:get().batch
    equal(active.status, "invalidated"); equal(b.status, "cancelled"); equal(b.active, nil)
    equal(b.succeeded, 1); equal(b.results[1].status, "ok"); equal(b.results[2].status, "cancelled")
    equal(b.results[2].preferred, nil); equal(b.notStarted, 1); equal(#b.queue, 0)
    local count = heightReads; step(100); equal(heightReads, count)
    equal(event("plan", token).reason, "no_running_batch")
    assert(startBatch(gui, event).accepted)
    equal(event("plan", token).reason, "stale_batch_cancel")
    assert(event("plan", batchToken(gui, "cancel")).accepted)
end)

test("batch: map changes and reactPostInit discard active and pending work without stale results", function()
    for _, mode in ipairs({"world", "reload"}) do
        local gui, step, _, event, _, cb = runNetwork(4)
        mark(gui, event, "1:4"); assert(startBatch(gui, event).accepted); step()
        local active, token = gui:get().batch.active, batchToken(gui, "cancel")
        if mode == "world" then worldId = 999; step()
        else cb.guiHandleEvent(nil, nil, gui, "native", "gameUI", "reactPostInit", {}) end
        equal(active.status, "invalidated"); equal(gui:get().batch, nil)
        equal(event("status").batch, nil); equal(event("plan", token).reason, "stale_session")
    end
end)

test("batch: resource or timing safety failures stop pending studies", function()
    for _, status in ipairs({"resource_limit", "performance_limit", "timing_unavailable", "invalidated", "error"}) do
        local gui, step, _, event = runNetwork(4)
        mark(gui, event, "1:2", "1:4"); startBatch(gui, event); step()
        -- Fault injection at the established continuation boundary, not a fake successful route.
        local r = gui:get().batch.active; r.finished, r.status, r.reason = true, status, "injected_safety_failure"
        step(); local b = gui:get().batch
        equal(b.status, "stopped"); equal(b.results[1].status, status)
        equal(b.succeeded, 0); equal(b.notStarted, 1); equal(b.active, nil)
    end
end)

test("batch: malformed or partial success never becomes a completed study", function()
    local gui, step, _, event = runNetwork(4)
    mark(gui, event, "1:4"); startBatch(gui, event); step()
    local r = gui:get().batch.active
    r.finished, r.status, r.result = true, "ok", {status = "ok", complete = false}
    step(); local b = gui:get().batch
    equal(b.status, "stopped"); equal(b.results[1].status, "error"); equal(b.succeeded, 0)
    equal(b.results[1].candidateCount, 0); equal(b.results[1].preferred, nil)
end)

test("batch: long-distance continuation works with serialized GUI state and deterministic repeated results", function()
    local function run()
        local gui, _, untilState, event = runNetwork(2, function() entities[2].x = -8000 end)
        local set = gui.set
        local function copy(v)
            if type(v) ~= "table" then assert(type(v) ~= "function"); return v end
            local out = {}; for k, x in pairs(v) do out[k] = copy(x) end; return out
        end
        gui.set = function(self, v) set(self, copy(v)) end
        mark(gui, event, "1:2"); assert(startBatch(gui, event).accepted); untilState(batchDone)
        local b = gui:get().batch; equal(b.status, "completed")
        assert(b.results[1].preferred.sections > 1)
        return serialize(b.results)
    end
    equal(run(), run())
end)

test("batch: fresh bounds check and handoff work budget failures stop without a search", function()
    for _, mode in ipairs({"bounds", "budget", "world_during_validation"}) do
        local gui, step, _, event = runNetwork(4)
        mark(gui, event, "1:4"); assert(startBatch(gui, event).accepted)
        if mode == "bounds" then mapBounds.maxX = mapBounds.maxX - 100
        elseif mode == "budget" then clockStep = 0.1
        else
            local capacity = api.engine.util.town.getTownCapacityUsage
            api.engine.util.town.getTownCapacityUsage = function(id) worldId = 100; return capacity(id) end
        end
        step(); assert(batchDone(gui:get())); equal(gui:get().batch.active, nil); equal(heightReads, 0)
    end
end)

test("batch: UI explicit start, duplicate clicks, progress, cancel and existing selections", function()
    local gui, step, _, event = runNetwork(4)
    local render, poll, tree, controls = mountUI(); controls.launcher.params.onClick(); tree = render()
    equal(find(tree, "Button", "Study Marked Corridors")[1].params.meta.enabled, false)
    local combos = planningCombos(tree); combos[1].params.onValueChange("3"); combos[2].params.onValueChange("2")
    find(tree, "Button", "Mark for further study")[1].params.onClick(); tree = render()
    equal(gui:get().batch, nil); equal(heightReads, 0)
    local start = find(tree, "Button", "Study Marked Corridors")[1]
    assert(start.params.meta.enabled); start.params.onClick(); start.params.onClick(); tree = render()
    equal(logCount("[RNA:BATCH:5C2] START"), 1); equal(gui:get().batchRequestId, 1)
    for _, label in ipairs({"Plan", "Analyze Network", "Study Corridor", "Reset all edits", "Study Marked Corridors"}) do
        equal(find(tree, "Button", label)[1].params.meta.enabled, false)
    end
    assert(find(tree, "Button", "Cancel Batch")[1].params.meta.enabled)
    step(); poll(); tree = render(); assert(panelText(tree):find("Current: 1:2", 1, true))
    find(tree, "Button", "Cancel Batch")[1].params.onClick(); tree = render()
    assert(panelText(tree):find("cancelled", 1, true)); assert(panelText(tree):find("Construction feasibility: unverified", 1, true))
    equal(planningCombos(tree)[1].params.value, "3"); equal(planningCombos(tree)[2].params.value, "2")
    equal(controls.events[#controls.events].name, "oz_railway_network_architect.plan.plan")
    equal(controls.panel.params.initialX, 0.5); equal(controls.panel.params.initialY, 0.5)
end)

test("batch: stale UI callbacks, unmount and reopen do not replay or silently cancel", function()
    local gui, _, _, event = runNetwork(4); mark(gui, event, "1:4")
    local render, poll, tree, controls = mountUI(); controls.launcher.params.onClick(); tree = render()
    local start = find(tree, "Button", "Study Marked Corridors")[1].params.onClick
    start(); tree = render(); local cancel = find(tree, "Button", "Cancel Batch")[1].params.onClick
    controls.panel.params.onClose(); render(); equal(gui:get().batch.status, "running")
    controls.launcher.params.onClick(); tree = render(); start(); render(); equal(gui:get().batchRequestId, 1)
    find(tree, "Button", "Cancel Batch")[1].params.onClick(); tree = render()
    find(tree, "Button", "Study Marked Corridors")[1].params.onClick(); render()
    cancel(); render(); equal(gui:get().batch.status, "running"); equal(gui:get().batchRequestId, 2)
    assert(event("plan", batchToken(gui, "cancel")).accepted); poll(); tree = render()
    controls.autoJoin = false
    find(tree, "Button", "Study Marked Corridors")[1].params.onClick()
    controls.panel.params.onClose(); controls.flush(); equal(gui:get().batchRequestId, 2)
end)

test("batch: malformed summary pauses polling and cannot revive old results after reanalysis", function()
    local gui, _, untilState, event = runNetwork(4); mark(gui, event, "1:4")
    startBatch(gui, event); untilState(batchDone)
    local render, poll, tree, controls = mountUI(); controls.launcher.params.onClick(); tree = render()
    assert(panelText(tree):find("Preferred:", 1, true))
    controls.resultFilter = function(v) v.batch.epoch = -1; return v end
    poll(); tree = render(); assert(not panelText(tree):find("Preferred:", 1, true))
    local count = #controls.events; poll(); poll(); equal(#controls.events, count)
    controls.resultFilter = nil; find(tree, "Button", "Refresh towns")[1].params.onClick(); render()
    equal(gui:get().batch, nil); equal(gui:get().worklist, nil)
end)

test("batch: malformed envelopes cannot bypass routing or mutate worklist", function()
    local gui, _, _, event = runNetwork(4); mark(gui, event, "1:4")
    local token = batchToken(gui); token.worklist = editToken(gui, "reset_all").worklist
    equal(event("plan", token).reason, "invalid_batch_envelope")
    equal(event("analyzeNetwork", batchToken(gui)).reason, "invalid_batch_envelope")
    token = batchToken(gui); token.batch.action = "other"
    equal(event("plan", token).reason, "invalid_batch_action")
    token = batchToken(gui); token.epoch = -1
    equal(event("plan", token).reason, "stale_session")
    equal(gui:get().batch, nil); equal(heightReads, 0); equal(gui:get().worklist.revision, 1)
end)

test("batch: exactly four studies complete, release route arrays and allow a subsequent explicit batch", function()
    local gui, _, untilState, event = runNetwork(6, function()
        entities[5].capacity, entities[5].x, entities[5].y = 2000, 2000, 2000
        entities[6].x, entities[6].y = -2000, 2000
    end)
    assert(#gui:get().network.result.recommendations >= 4)
    for i = 1, 4 do mark(gui, event, gui:get().network.result.recommendations[i].id) end
    assert(startBatch(gui, event).accepted); untilState(batchDone)
    local b = gui:get().batch
    equal(b.total, 4); equal(#b.results, 4); equal(b.succeeded, 4); equal(b.active, nil)
    equal(#b.queue, 0); assert(#event("status").batch.lines <= 12)
    local render, poll, tree, controls = mountUI(); controls.launcher.params.onClick(); tree = render()
    assert(panelText(tree):find("Completed: 4", 1, true)); assert(not panelText(tree):find("invalid batch", 1, true))
    assert(startBatch(gui, event).accepted); equal(gui:get().batch.id, 2); equal(#gui:get().batch.results, 0)
    assert(event("plan", batchToken(gui, "cancel")).accepted)
end)

test("batch: next connection rechecks evidence after a successful study", function()
    local gui, step, untilState, event = runNetwork(4)
    mark(gui, event, "1:2", "1:4"); startBatch(gui, event)
    untilState(function(s) return #s.batch.results == 1 end)
    entities[4].capacity = 401
    step(); local b = gui:get().batch
    equal(b.status, "stopped"); assert(b.reason:find("network_capacity_changed", 1, true))
    equal(b.succeeded, 1); equal(b.notStarted, 1); equal(logCount("[RNA:BATCH:5C2] STUDY_START"), 1)
end)

test("batch: incomplete studies may continue but are not successful; pending cancellation executes nothing", function()
    local gui, step, untilState, event = runNetwork(4)
    mark(gui, event, "1:2", "1:4"); startBatch(gui, event); step()
    local r = gui:get().batch.active
    r.finished, r.status, r.reason = true, "incomplete", "injected_missing_samples"
    step(); equal(gui:get().batch.active, nil); equal(gui:get().batch.succeeded, 0)
    untilState(batchDone); equal(gui:get().batch.status, "completed_with_failures")
    equal(gui:get().batch.succeeded, 1); equal(gui:get().batch.results[1].preferred, nil)
    assert(startBatch(gui, event).accepted); local before = heightReads
    assert(event("plan", batchToken(gui, "cancel")).accepted); step(100)
    equal(heightReads, before); equal(gui:get().batch.notStarted, 2); equal(#gui:get().batch.results, 0)
end)

local geometryInspection = ug_require "oz_railway_network_architect::/live_plan_geometry.lua"
local function inspectionToken(gui, candidateId)
    local s=gui:get()
    return {world=s.world,epoch=s.epoch,inspection={requestId=(s.inspectionRequestId or 0)+1,
        corridorRequestId=s.requestId,candidateId=candidateId or s.request.preview.candidates[1].id}}
end
local function inspected(s) return s.inspection and s.inspection.finished end
local function completedSession()
    local gui,step,untilState,event,callbacks=newSession();ready(step,untilState)
    assert(submit(gui,event).accepted);untilState(completed)
    return gui,step,untilState,event,callbacks
end
local function geometryFixture(gui,n)
    local s=gui:get();local c=s.request.result.candidates[1];local first=c.waypoints[1]
    c.waypoints={}
    for i=1,n do c.waypoints[i]={x=first.x+(i-1)*c.sampling.fineSpacing,y=first.y,z=-2,water=false} end
    c.endpoints.destination.x=c.waypoints[n].x;c.endpoints.destination.y=first.y
    s.request.preview=assert(preview.build(s))
    return c
end

test("geometry: no automatic inspection and only complete candidates enable the explicit action",function()
    local gui,step,untilState,event=newSession();ready(step,untilState)
    local render,poll,tree,controls=mountUI();controls.launcher.params.onClick();tree=render()
    equal(find(tree,"Button","Inspect Geometry")[1].params.meta.enabled,false)
    find(tree,"Button","Inspect Geometry")[1].params.onClick();render();equal(gui:get().inspection,nil)
    submit(gui,event);untilState(completed);poll();tree=render()
    assert(find(tree,"Button","Inspect Geometry")[1].params.meta.enabled)
    step(60);poll();render();equal(gui:get().inspection,nil);equal(logCount("[RNA:GEOM:6D] START"),0)
end)
test("geometry: two bounded stages preserve corridor and perform no search or terrain reads",function()
    local gui,step,untilState,event=completedSession()
    local before=serialize(gui:get().request);local sampled=heightReads
    planner.plan=function() error("inspection reran A*") end;planner.step=planner.plan
    assert(event("plan",inspectionToken(gui)).accepted)
    equal(gui:get().inspection.phase,"fit");equal(event("status").busy,true)
    step();equal(gui:get().inspection.phase,"validate");equal(gui:get().inspection.points,nil)
    step();local job=gui:get().inspection
    equal(job.status,"complete");equal(job.curves,nil);equal(job.points,nil)
    equal(job.metrics.continuity,"exact_C0_C1");equal(job.metrics.maxGradient,0)
    equal(serialize(gui:get().request),before);equal(heightReads,sampled);equal(gui:get().requestId,1)
    local value=event("status");assert(geometryInspection.valid(value.inspection,value))
    local serialized=serialize(value.inspection)
    assert(not serialized:find("waypoints=",1,true));assert(not serialized:find("segments=",1,true))
    assert(#serialized<6000);equal(logCount("[RNA:GEOM:6D] COMPLETE"),1)
end)
test("geometry: selected candidate ID is honored and missing resources are not fabricated",function()
    local gui,step,untilState,event=completedSession()
    local function copy(v) if type(v)~="table" then return v end;local t={};for k,x in pairs(v) do t[k]=copy(x) end;return t end
    local s=gui:get();local c=copy(s.request.result.candidates[1]);c.id="fixture_second";c.rank=2
    c.waypoints[2].z=c.waypoints[2].z+1;s.request.result.candidates[2]=c
    s.request.preview=assert(preview.build(s))
    local render,poll,tree,controls=mountUI();controls.launcher.params.onClick();tree=render()
    planningCombos(tree)[3].params.onValueChange(c.id);tree=render()
    find(tree,"Button","Inspect Geometry")[1].params.onClick();render();untilState(inspected);poll();tree=render()
    equal(gui:get().inspection.candidateId,c.id);assert(gui:get().inspection.metrics.maxGradient>0)
    equal(planningCombos(tree)[3].params.value,c.id)
    assert(panelText(tree):find("Missing: track template/lanes/style",1,true))
    assert(panelText(tree):find("Native preview: BLOCKED",1,true));assert(panelText(tree):find("Construction status: unverified",1,true))
    equal(api.cmd,nil);equal(gui:get().inspection.proposal,nil)
end)
test("geometry: oversized corridor returns explicit unsupported without truncating",function()
    local gui,step,untilState,event=completedSession();local c=geometryFixture(gui,257)
    local before=serialize(c);assert(event("plan",inspectionToken(gui)).accepted)
    local job=gui:get().inspection;equal(job.status,"unsupported");assert(job.reason:find("at_most_256",1,true))
    equal(job.points,nil);equal(job.curves,nil);equal(job.metrics,nil);equal(serialize(c),before)
    step(40);equal(logCount("[RNA:GEOM:6D] COMPLETE"),1)
end)
test("geometry: maximum supported size remains bounded and clears temporary curves",function()
    local gui,step,untilState,event=completedSession();geometryFixture(gui,256)
    assert(event("plan",inspectionToken(gui)).accepted);untilState(inspected)
    local job=gui:get().inspection;equal(job.status,"complete");equal(job.metrics.segments,255)
    equal(job.curves,nil);equal(job.points,nil);assert(#serialize(event("status").inspection)<6000)
end)
test("geometry: missing XYZ and discontinuous corridor positions are unsupported",function()
    for _,mode in ipairs({"height","gap"}) do
        local gui,step,untilState,event=completedSession();local c=gui:get().request.result.candidates[1]
        if mode=="height" then c.waypoints[2].z=nil else c.waypoints[2].x=c.waypoints[2].x+1 end
        assert(event("plan",inspectionToken(gui)).accepted);equal(gui:get().inspection.status,"unsupported")
        equal(gui:get().inspection.metrics,nil);equal(gui:get().inspection.points,nil)
    end
end)
test("geometry: reversed neighboring grid steps report incompatible fit rather than completion",function()
    local gui,step,untilState,event=completedSession();local c=geometryFixture(gui,4);local first=c.waypoints[1]
    c.waypoints[3]={x=first.x,y=first.y,z=-2,water=false}
    c.waypoints[4]={x=first.x,y=first.y+32,z=-2,water=false}
    c.endpoints.destination.x=c.waypoints[4].x;c.endpoints.destination.y=c.waypoints[4].y
    gui:get().request.preview=assert(preview.build(gui:get()))
    assert(event("plan",inspectionToken(gui)).accepted);untilState(inspected)
    equal(gui:get().inspection.status,"unsupported");assert(gui:get().inspection.reason:find("fit:",1,true))
end)
test("geometry: busy replay stale and mixed envelopes cannot repeat or reroute inspection",function()
    local gui,step,untilState,event=completedSession();local token=inspectionToken(gui)
    assert(event("plan",token).accepted);equal(event("plan",token).reason,"busy")
    equal(submit(gui,event).reason,"busy");equal(analyze(gui,event).reason,"busy");equal(event("refresh").reason,"busy")
    untilState(inspected);equal(event("plan",token).reason,"duplicate_or_stale_inspection")
    token=inspectionToken(gui);token.inspection.corridorRequestId=99;equal(event("plan",token).reason,"stale_corridor_request")
    token=inspectionToken(gui);token.batch={action="start"};equal(event("plan",token).reason,"invalid_inspection_envelope")
    token=inspectionToken(gui);token.world=-1;equal(event("plan",token).reason,"stale_session")
    local r=gui:get().request
    for _,field in ipairs({"world","requestId"}) do
        local original=r[field];r[field]=-1
        equal(event("plan",inspectionToken(gui)).reason,"completed_corridor_required")
        r[field]=original
    end
    assert(event("plan",inspectionToken(gui)).accepted);untilState(inspected)
    equal(gui:get().inspectionRequestId,2);equal(logCount("[RNA:GEOM:6D] START"),2)
end)
test("geometry: world change and reload discard active and completed inspection",function()
    for _,mode in ipairs({"world","reload"}) do for _,finish in ipairs({false,true}) do
        local gui,step,untilState,event,callbacks=completedSession()
        event("plan",inspectionToken(gui));step();local job=gui:get().inspection
        if finish then untilState(inspected) end
        if mode=="world" then worldId=100;event("status")
        else callbacks.guiHandleEvent(nil,nil,gui,"test","gameUI","reactPostInit",{}) end
        equal(job.status,"invalidated");equal(job.curves,nil);equal(gui:get().inspection,nil)
        equal(event("status").inspection,nil);equal(gui:get().inspectionRequestId,0)
    end end
end)
test("geometry: new manual and refresh requests clear completed results",function()
    for _,mode in ipairs({"plan","refresh"}) do
        local gui,step,untilState,event=completedSession();event("plan",inspectionToken(gui));untilState(inspected)
        if mode=="plan" then assert(submit(gui,event,20,10).accepted) else assert(event("refresh").accepted) end
        equal(gui:get().inspection,nil);equal(event("status").inspection,nil)
        if mode=="plan" then untilState(completed);equal(gui:get().request.status,"ok") end
    end
end)
test("geometry: close reopen and old callbacks cannot replay inspection",function()
    local gui,step,untilState,event=completedSession()
    local render,poll,tree,controls=mountUI();controls.launcher.params.onClick();tree=render()
    local click=find(tree,"Button","Inspect Geometry")[1].params.onClick
    click();render();click();render();equal(gui:get().inspectionRequestId,1)
    controls.panel.params.onClose();render();untilState(inspected)
    controls.autoJoin=false;controls.launcher.params.onClick();tree=render()
    assert(not panelText(tree):find("Geometry inspection #",1,true));click();controls.flush();tree=render()
    assert(panelText(tree):find("Geometry inspection #1",1,true));equal(gui:get().inspectionRequestId,1)
    controls.autoJoin=true;find(tree,"Button","Inspect Geometry")[1].params.onClick();render();untilState(inspected)
    poll();tree=render();equal(gui:get().inspectionRequestId,2)
    controls.autoJoin=false;find(tree,"Button","Inspect Geometry")[1].params.onClick()
    controls.panel.params.onClose();controls.flush();equal(gui:get().inspectionRequestId,2)
end)
test("geometry: malformed response hides results pauses polling and Refresh recovers",function()
    local gui,step,untilState,event=completedSession();event("plan",inspectionToken(gui));untilState(inspected)
    local render,poll,tree,controls=mountUI();controls.launcher.params.onClick();tree=render()
    controls.resultFilter=function(v) v.inspection.epoch=-1;return v end
    poll();tree=render();assert(panelText(tree):find("invalid geometry inspection",1,true))
    assert(not panelText(tree):find("Geometry inspection #",1,true))
    local n=#controls.events;poll();poll();equal(#controls.events,n)
    controls.resultFilter=nil;find(tree,"Button","Refresh towns")[1].params.onClick();render();equal(gui:get().inspection,nil)
end)
test("geometry: performance or unavailable timing discards diagnostics safely",function()
    for _,mode in ipairs({"slow","missing"}) do
        local gui,step,untilState,event=completedSession();event("plan",inspectionToken(gui))
        if mode=="slow" then clockStep=0.06 else api.util.getApplicationTime=function() return nil end end
        step();local job=gui:get().inspection
        equal(job.status,mode=="slow" and "performance_limit" or "timing_unavailable")
        equal(job.curves,nil);equal(job.points,nil);equal(job.metrics,nil)
    end
end)
test("geometry: unexpected math failure releases work without changing corridor",function()
    local gui,step,untilState,event=completedSession();event("plan",inspectionToken(gui))
    local fitter=ug_require "oz_railway_network_architect::/geometry/rail_curve.lua";local fit=fitter.fit
    fitter.fit=function() error("synthetic fitting exception") end;step();fitter.fit=fit
    equal(gui:get().inspection.status,"error");equal(gui:get().inspection.curves,nil)
    equal(gui:get().request.status,"ok");assert(event("status").preview)
end)
test("geometry: network worklist and sequential batch workflows retain ownership and cancellation",function()
    local gui,step,untilState,event=runNetwork(4)
    study(gui,event,"1:4");untilState(completed)
    local original=serialize(gui:get().worklist);event("plan",inspectionToken(gui));untilState(inspected)
    equal(serialize(gui:get().worklist),original)
    editNetwork(gui,event,"mark_study","1:4");equal(gui:get().inspection,nil)
    event("plan",inspectionToken(gui));untilState(inspected)
    assert(startBatch(gui,event).accepted);equal(gui:get().inspection,nil)
    equal(event("plan",inspectionToken(gui)).reason,"busy")
    assert(event("plan",batchToken(gui,"cancel")).accepted);equal(gui:get().batch.status,"cancelled")
    assert(startBatch(gui,event).accepted);untilState(batchDone);equal(gui:get().batch.succeeded,1)
    assert(event("plan",inspectionToken(gui)).accepted);untilState(inspected)
    assert(analyze(gui,event).accepted);equal(gui:get().inspection,nil);untilState(networkDone)
    equal(gui:get().network.status,"ok")
end)
test("geometry: unreachable incomplete or missing candidates cannot be inspected",function()
    for _,status in ipairs({"unreachable","unsupported","incomplete","search_limit"}) do
        local gui,step,untilState,event=completedSession();local token=inspectionToken(gui)
        gui:get().request.status=status
        equal(event("plan",token).reason,"completed_corridor_required");equal(gui:get().inspection,nil)
    end
    local gui,step,untilState,event=completedSession()
    equal(event("plan",inspectionToken(gui,"absent")).reason,"candidate_not_available")
end)

-- Targeted native-acceptance policy fix: modes affect only the live capacity preference.
local networkData = ug_require "oz_railway_network_architect::/network_live_data.lua"
local networkCore = ug_require "oz_railway_network_architect::/planning/network_planner.lua"
local networkSchema = ug_require "oz_railway_network_architect::/planning/network_input.lua"
local networkRequest = ug_require "oz_railway_network_architect::/network_live_request.lua"
local function acceptanceInput(mode)
    local accepted, capacity = networkData.analysisMode(mode); assert(accepted)
    return {unit="world_units", snapshotId="synthetic-acceptance", source="synthetic XY anchors, not native geography",
        preferences={maxTowns=32,maxPairs=496,minCapacity=capacity}, towns={
            {id=30562,name="Winterton",x=0,y=0,z=-2,
                residentialCapacity={value=125,source="synthetic fixture reproducing owner-reported capacity",basis="synthetic"}},
            {id=30563,name="Southwold",x=5877,y=0,z=-2,
                residentialCapacity={value=110,source="synthetic fixture reproducing owner-reported capacity",basis="synthetic"}},
        }}
end
local function acceptanceSession(mode)
    local gui,step,untilState,event,callbacks=newSession();networkFixture(0)
    entities={
        [30562]={id=30562,name="Winterton",x=0,y=0,z=-2,capacity=125},
        [30563]={id=30563,name="Southwold",x=5877,y=0,z=-2,capacity=110},
    }
    ids={30562,30563};ready(step,untilState)
    assert(analyze(gui,event,mode).accepted);untilState(networkDone)
    return gui,step,untilState,event,callbacks
end

test("network modes: strict allowlist and omitted-mode compatibility at collector boundary",function()
    local gui,step,untilState,event=newSession();ready(step,untilState)
    for _,example in ipairs({{"standard",200},{"exploratory",100}}) do
        local mode,capacity=networkData.analysisMode(example[1]);equal(mode,example[1]);equal(capacity,example[2])
    end
    local mode,capacity=networkData.analysisMode(nil);equal(mode,"standard");equal(capacity,200)
    for _,invalid in ipairs({"", "Standard", "EXPLORATORY", " standard", "exploratory ", "unknown", 0, 100, true, false, {}, function() end}) do
        local r,why=networkRequest.start({id=99,tick=10},1,1,invalid)
        equal(r,nil);equal(why,"invalid_analysis_mode")
    end
    equal(logCount("[RNA:NETWORK:5B1] request="),0);equal(heightReads,0)
end)

test("network modes: synthetic 125/110 capacity pair changes gate only and keeps independent score formula",function()
    local standard=acceptanceInput("standard");local before=serialize(standard)
    local s=networkCore.plan(standard);equal(serialize(standard),before)
    equal(#s.recommendations,0);equal(s.decisions[1].status,"deferred")
    equal(s.decisions[1].reasons[1],"capacity_proxy_too_small_without_demand_evidence");equal(s.decisions[1].score,nil)
    local raw=acceptanceInput("exploratory");before=serialize(raw)
    local e=networkCore.plan(raw);equal(serialize(raw),before)
    local edge=e.decisions[1];equal(edge.reasons[1],"capacity_proxy_justifies_conditional_study")
    equal(edge.distance,5877);equal(edge.evidence.demandSupport,nil)
    local expectedSupport=0.5+0.5*110/1000
    local expectedDistance=5877/20000*0.25
    local expectedGeography=0.2*0.5
    assert(math.abs(edge.score.support-expectedSupport)<1e-12)
    assert(math.abs(edge.score.distancePenalty-expectedDistance)<1e-12)
    assert(math.abs(edge.score.geographyPenalty-expectedGeography)<1e-12)
    assert(math.abs(edge.score.total-0.3815375)<1e-12)
    equal(#e.recommendations,1);equal(edge.constructionStatus,"unverified")
    -- An eligible score does not override graph constraints, even in this fixture.
    raw.preferences.maxEdges=0
    local limited=networkCore.plan(raw);equal(#limited.recommendations,0)
    equal(limited.decisions[1].reasons[#limited.decisions[1].reasons],"selected_edge_budget")
    equal(limited.decisions[1].score.total,edge.score.total)
end)

test("network modes: all other normalized preferences and global topology defaults are unchanged",function()
    local s=networkSchema.validate(acceptanceInput("standard")).preferences
    local e=networkSchema.validate(acceptanceInput("exploratory")).preferences
    equal(s.minCapacity,200);equal(e.minCapacity,100)
    for k,v in pairs(s) do if k~="minCapacity" then equal(e[k],v) end end
    equal(e.majorCapacity,1000);equal(e.minDistance,1000);equal(e.maxDistance,20000);equal(e.minScore,0.25)
    equal(e.distanceWeight,0.25);equal(e.geographyWeight,0.5);equal(e.maxDegree,3)
    e.minCapacity=1 -- caller-owned copies must not mutate the contract or pure defaults.
    local input=acceptanceInput("exploratory");input.preferences=nil
    equal(networkSchema.validate(input).preferences.minCapacity,200)
    local _,capacity=networkData.analysisMode("exploratory");equal(capacity,100)
end)

test("network modes: live default and explicit modes populate accepted snapshot result and summary",function()
    for _,mode in ipairs({"omitted","standard","exploratory"}) do
        local gui,step,untilState,event=acceptanceSession(mode~="omitted" and mode or nil)
        local r=gui:get().network;local expected=mode=="exploratory" and 100 or 200
        equal(r.analysisMode,mode=="omitted" and "standard" or mode);equal(r.minCapacity,expected)
        equal(r.snapshot.analysisMode,r.analysisMode);equal(r.snapshot.minCapacity,expected)
        equal(r.result.analysisMode,r.analysisMode);equal(r.result.preferences.minCapacity,expected)
        equal(r.summary.analysisMode,r.analysisMode);equal(r.summary.minCapacity,expected)
        local lines=table.concat(r.summary.lines,"\n")
        assert(lines:find("Minimum residential capacity: "..expected,1,true))
        assert(lines:find("Passenger demand: unknown",1,true));assert(lines:find("Economic feasibility: unverified",1,true))
        assert(networkData.valid(r.summary,event("status")))
        equal(#r.result.recommendations,mode=="exploratory" and 1 or 0)
        equal(r.result.stats.astarSearches,0);equal(heightReads,0);equal(api.cmd,nil)
        assert(hasLog("mode="..r.analysisMode.." min_capacity="..expected))
    end
end)

test("network modes: invalid requests preserve result worklist batch identity and request token",function()
    local gui,step,untilState,event=runNetwork(4)
    mark(gui,event,"1:4");assert(startBatch(gui,event).accepted);untilState(batchDone)
    assert(editNetwork(gui,event,"exclude","1:2").accepted)
    local s=gui:get();local original=serialize({s.network,s.worklist,s.batch})
    for _,mode in ipairs({false,true,{},100,"", "Standard","unknown"," exploratory"}) do
        equal(analyze(gui,event,mode).reason,"invalid_analysis_mode")
        equal(gui:get().networkRequestId,1);equal(serialize({s.network,s.worklist,s.batch}),original)
    end
    local token={world=s.world,epoch=s.epoch,requestId=2,mode="exploratory",preferences={minCapacity=0,majorCapacity=1}}
    assert(event("analyzeNetwork",token).accepted);equal(event("analyzeNetwork",token).reason,"busy")
    untilState(networkDone);equal(gui:get().network.result.preferences.minCapacity,100)
    equal(gui:get().network.result.preferences.majorCapacity,1000)
    equal(event("analyzeNetwork",token).reason,"duplicate_or_stale_network_request")
end)

test("network modes: selector is explicit local state and cannot mutate completed analysis or edits",function()
    local gui,step,untilState,event=runNetwork(4);assert(editNetwork(gui,event,"exclude","1:2").accepted)
    local original=serialize({gui:get().network,gui:get().worklist})
    local render,poll,tree,controls=mountUI();controls.launcher.params.onClick();tree=render()
    local combo=assert(modeCombo(tree));equal(combo.params.value,"standard");equal(#combo.params.items,2)
    equal(combo.params.items[1].params.value,"standard");equal(combo.params.items[2].params.value,"exploratory")
    assert(combo.params.items[1].params.content.params.text:find("capacity threshold 200",1,true))
    assert(combo.params.items[2].params.content.params.text:find("capacity threshold 100",1,true))
    local events=#controls.events;local starts=logCount("START world=")
    planner.plan=function() error("mode selection invoked A*") end;planner.step=planner.plan
    combo.params.onValueChange("exploratory");tree=render()
    equal(#controls.events,events);equal(logCount("START world="),starts);equal(heightReads,0)
    equal(gui:get().networkRequestId,1);equal(serialize({gui:get().network,gui:get().worklist}),original)
    equal(modeCombo(tree).params.value,"exploratory")
    assert(panelText(tree):find("Network analysis mode: Standard",1,true))
    assert(panelText(tree):find("Minimum residential capacity: 200",1,true))
    local click=find(tree,"Button","Analyze Network")[1].params.onClick
    click();click();tree=render();equal(gui:get().networkRequestId,2)
    equal(gui:get().network.analysisMode,"exploratory");equal(gui:get().worklist,nil)
    equal(controls.events[#controls.events].request.mode,"exploratory")
    equal(modeCombo(tree).params.meta.enabled,false)
    combo.params.onValueChange("standard");tree=render();equal(modeCombo(tree).params.value,"exploratory")
    untilState(networkDone);poll();tree=render()
    assert(panelText(tree):find("Network analysis mode: Exploratory",1,true))
    modeCombo(tree).params.onValueChange("standard");tree=render()
    assert(panelText(tree):find("Network analysis mode: Exploratory",1,true))
    assert(panelText(tree):find("Minimum residential capacity: 100",1,true));equal(heightReads,0)
end)

test("network modes: default UI and close reopen reset lifecycle never analyze automatically",function()
    local gui,step,untilState,event=newSession();networkFixture(4);ready(step,untilState)
    local render,poll,tree,controls=mountUI();controls.launcher.params.onClick();tree=render()
    equal(modeCombo(tree).params.value,"standard")
    local old=modeCombo(tree).params.onValueChange
    old("exploratory");tree=render();equal(gui:get().network,nil)
    modeCombo(tree).params.onValueChange("invalid");tree=render();equal(modeCombo(tree).params.value,"exploratory")
    controls.panel.params.onClose();render();old("standard")
    controls.launcher.params.onClick();tree=render();equal(modeCombo(tree).params.value,"exploratory")
    local stale=modeCombo(tree).params.onValueChange
    worldId=100;step();poll();tree=render();stale("exploratory");tree=render()
    equal(modeCombo(tree).params.value,"standard");equal(gui:get().network,nil);equal(heightReads,0)
    equal(logCount("[RNA:NETWORK:5B1] request="),0)
end)

test("network modes: reanalysis replaces snapshot and rejects old worklist handoff and batch tokens",function()
    local gui,step,untilState,event=runNetwork(4)
    mark(gui,event,"1:4");assert(startBatch(gui,event).accepted);untilState(batchDone)
    assert(editNetwork(gui,event,"exclude","1:2").accepted)
    local old=gui:get().network;local edit=editToken(gui,"restore","1:2")
    local handoffToken=studyToken(gui,"1:4");local batchClick=batchToken(gui)
    assert(analyze(gui,event,"exploratory").accepted)
    equal(gui:get().worklist,nil);equal(gui:get().batch,nil);equal(gui:get().network.result,nil)
    untilState(networkDone)
    local s=gui:get();assert(s.network.result.snapshotId~=old.result.snapshotId)
    equal(s.networkRequestId,2);equal(s.worklist.snapshotId,s.network.result.snapshotId)
    equal(s.worklist.revision,0);equal(next(s.worklist.overrides),nil);equal(old.result.analysisMode,"standard")
    equal(event("plan",edit).reason,"stale_worklist_snapshot")
    equal(event("plan",handoffToken).accepted,false);equal(event("plan",batchClick).reason,"stale_worklist_snapshot")
end)

test("network modes: exploratory exclusion individual study and sequential batch preserve safeguards",function()
    local gui,step,untilState,event=runNetwork(4)
    assert(analyze(gui,event,"exploratory").accepted);untilState(networkDone)
    local original=serialize(gui:get().network.result)
    assert(editNetwork(gui,event,"exclude","1:4").accepted)
    equal(study(gui,event,"1:4").reason,"connection_excluded_from_network_plan");equal(heightReads,0)
    assert(editNetwork(gui,event,"restore","1:4").accepted)
    assert(study(gui,event,"1:4").accepted);untilState(completed)
    equal(gui:get().request.sourceId,1);equal(gui:get().request.destinationId,4)
    equal(gui:get().request.networkOrigin.snapshotId,gui:get().network.result.snapshotId)
    mark(gui,event,"1:2","1:4");assert(startBatch(gui,event).accepted);untilState(batchDone)
    equal(gui:get().batch.succeeded,2);equal(#gui:get().batch.results,2)
    equal(serialize(gui:get().network.result),original)
    assert(submit(gui,event,4,1).accepted);untilState(completed);equal(gui:get().request.networkOrigin,nil)
end)

test("network modes: exploratory handoff and next batch study retain original 60 second deadline",function()
    local gui,step,untilState,event=runNetwork(4)
    assert(analyze(gui,event,"exploratory").accepted);untilState(networkDone)
    mark(gui,event,"1:2","1:4");assert(startBatch(gui,event).accepted)
    untilState(function(s) return s.batch and #s.batch.results==1 end)
    clock=gui:get().network.began+61;step()
    equal(gui:get().batch.status,"stopped");equal(#gui:get().batch.results,1)
    assert(gui:get().batch.reason:find("network_snapshot_expired",1,true))
    local reads=heightReads;local why=study(gui,event,"1:4")
    equal(why.accepted,false);assert(why.reason:find("network_snapshot_expired",1,true))
    equal(heightReads,reads);equal(gui:get().networkRequestId,2);equal(gui:get().worklist.graph.furtherStudy,2)
end)

test("network modes: small-capacity acceptance pair can explicitly enter long individual and batch studies",function()
    local gui,step,untilState,event=acceptanceSession("exploratory")
    assert(study(gui,event,"30562:30563").accepted);untilState(completed)
    local r=gui:get().request;equal(r.status,"ok");assert(hasLog("LONG_DISTANCE mode=hierarchical"))
    equal(r.sourceId,30562);equal(r.destinationId,30563)
    equal(r.networkOrigin.evidence.residentialCapacitySource.value,125)
    equal(r.networkOrigin.evidence.residentialCapacityDestination.value,110)
    equal(r.networkOrigin.evidence.demandSupport,nil)
    mark(gui,event,"30562:30563");assert(startBatch(gui,event).accepted);untilState(batchDone)
    equal(gui:get().batch.succeeded,1);equal(gui:get().batch.results[1].constructionStatus,"unverified")
end)

test("network modes: unknown demand capacities and physical rail screening stay unchanged",function()
    local gui,step,untilState,event=acceptanceSession("exploratory")
    entities[30563].capacity=nil;assert(analyze(gui,event,"exploratory").accepted);untilState(networkDone)
    equal(#gui:get().network.result.recommendations,0)
    equal(gui:get().network.result.decisions[1].reasons[1],"insufficient_evidence_not_zero_demand")
    local raw=acceptanceInput("exploratory")
    raw.rail={source="synthetic physical component",basis="synthetic",
        nodes={{id=1,x=0,y=0},{id=2,x=5877,y=0}},segments={{id=3,node0=1,node1=2}}}
    local r=networkCore.plan(raw);equal(#r.recommendations,0)
    equal(r.decisions[1].reasons[1],"inspect_existing_physical_rail_before_new_corridor")
end)

test("network modes: repeated results deterministic and malformed mode summary is rejected",function()
    local gui,step,untilState,event=acceptanceSession("exploratory")
    local previous=serialize(gui:get().network.result.decisions)
    assert(analyze(gui,event,"exploratory").accepted);untilState(networkDone)
    equal(serialize(gui:get().network.result.decisions),previous)
    local render,poll,tree,controls=mountUI();controls.launcher.params.onClick();tree=render()
    controls.resultFilter=function(v) v.networkSummary.minCapacity=200;return v end
    poll();tree=render();assert(panelText(tree):find("invalid network summary",1,true))
    local events=#controls.events;poll();equal(#controls.events,events)
    controls.resultFilter=nil;find(tree,"Button","Refresh towns")[1].params.onClick();render()
    equal(gui:get().network,nil)
end)


-- Public zone contract mock: world-space polygons persist until their matching key is removed.
-- This checks arguments and lifecycle, NOT native freeplay visibility.
local routeOverlay=ug_require "oz_railway_network_architect::/route_overlay.lua"
-- Synthetic occupied town blocks and physical street endpoints. These are not native
-- visibility or catchment evidence; the real adapter is exercised against the declarations.
local function stationFixture()
    local f={objects={},townBuildings={},revisions={}}
    local types=api.type.ComponentType
    types.TOWN_BUILDING="townBuilding";types.BASE_EDGE="edge";types.STATION="station"
    types.CONSTRUCTION="construction";types.MODEL_INSTANCE_LIST="models"
    api.type["enum"]={RoadType={STREET="street",TRACK="track"},TransportMode={TRAIN="train",ELECTRIC_TRAIN="electricTrain"}}
    api.type.Vec3f={new=function(x,y,z) return {x=x,y=y,z=z} end}
    api.type.Box3={new=function(a,b) return {min=a,max=b} end}
    api.engine.getRevision=function(id) return {num=f.revisions[id] or {1,0,0}} end
    local function add(id,box,component)
        if component.models then
            local m=component.models
            local function vector(key) return {size=function() return #m[key] end,
                at=function(_,i) assert(i>=1 and i<=#m[key]);return m[key][i] end} end
            m.fatInstances_native=vector("fatInstances");m.thinInstances_native=vector("thinInstances")
        end
        f.objects[id]={bbox={min={x=box[1],y=box[2],z=-10},max={x=box[3],y=box[4],z=30}},component=component}
    end
    for id,t in pairs(entities) do
        local building=id*100+1;local road=id*100+2
        f.townBuildings[id]={building}
        add(building,{t.x-40,t.y-40,t.x+40,t.y+40},{townBuilding={town=id,construction=building}})
        add(road,{t.x-100,t.y-4,t.x+100,t.y+4},{edge={roadType="street",
            position0={x=t.x-100,y=t.y,z=-2},position1={x=t.x+100,y=t.y,z=-2}}})
    end
    local get=api.engine.getComponent
    api.engine.getComponent=function(id,kind)
        local o=f.objects[id]
        if o then if kind=="volume" then return {bbox=o.bbox} end;return o.component[kind] end
        return get(id,kind)
    end
    api.engine.system.townBuildingSystem={getTown2BuildingMap=function() return f.townBuildings end}
    api.engine.system.stationSystem={getStations=function() return {} end}
    api.engine.system.octreeSystem={findIntersectingEntities=function(b,fn)
        for id,o in pairs(f.objects) do local v=o.bbox
            if b.min.x<=v.max.x and b.max.x>=v.min.x and b.min.y<=v.max.y and b.max.y>=v.min.y then fn(id,{bbox=v}) end
        end
    end}
    f.add=add
    return f
end
local function zoneFixture()
    local f={zones={other_mod_zone={}},adds={},removes={},focus={},commands=0}
    f.station=stationFixture()
    api.type.Vec4f={new=function(x,y,z,w) return {x=x,y=y,z=z,w=w} end}
    api.type.Vec3f={new=function(x,y,z) return {x=x,y=y,z=z} end}
    api.gui.mission={setZone=function(key,polygon,draw,color,prohibit,animation,zOffset)
        assert(key:match('^oz_railway_network_architect%.route%.'))
        equal(draw,true);equal(prohibit,false);equal(animation,false);equal(zOffset,1)
        assert((color.x==0 and color.y==1 and color.z==1) or (color.x==1 and color.y==0.65 and color.z==0)
            or (color.x==0.9 and color.y==0.2 and color.z==1));equal(#polygon,4)
        f.adds[#f.adds+1]={key=key,polygon=polygon,color=color}
        f.zones[key]=polygon
        if f.failAdd then error('zone renderer unavailable fixture') end
    end,removeZone=function(key)
        assert(key~='other_mod_zone');f.removes[#f.removes+1]=key
        if f.failRemove then error('zone removal unavailable fixture') end
        f.zones[key]=nil
    end}
    api.gui.camera={focusPosition=function(position,distance) f.focus[#f.focus+1]={position=position,distance=distance} end}
    api.cmd={sendCommand=function() f.commands=f.commands+1;error('construction forbidden') end,
        makeWorldBuildProposalCmd=function() f.commands=f.commands+1;error('construction forbidden') end}
    return f
end
local function routeAction(gui,event,action,id)
    local s=gui:get();local o=s.routeOverlay
    return event('plan',{world=s.world,epoch=s.epoch,overlay={action=action,lease=o.lease,
        sequence=o.sequence+1,requestId=s.requestId,candidateId=id or o.candidateId}})
end
local function routeShown(s) return s.routeOverlay and s.routeOverlay.status=='shown' end
local function noZones(f) return next(f.zones)=="other_mod_zone" and next(f.zones,"other_mod_zone")==nil end
local function plannedOverlay()
    local gui,step,untilState,event,cb=newSession();ready(step,untilState);local f=zoneFixture()
    event('status',{openRouteView=true});assert(submit(gui,event).accepted)
    untilState(completed);untilState(routeShown)
    return gui,step,untilState,event,f,cb
end
local function showExisting(gui,event)
    event('status',{openRouteView=true})
    return routeAction(gui,event,'show',gui:get().request.preview.candidates[1].id)
end

test('overlay: construction disconnected and legacy events rejected without native calls',function()
    local gui,step,untilState,event=completedSession();local f=zoneFixture()
    for _,action in ipairs({'prepare','confirm','cancel'}) do
        local s=gui:get()
        equal(event('plan',{world=s.world,epoch=s.epoch,track={action=action,requestId=1,disposableCopy=true}}).reason,'construction_disabled')
    end
    step(30);equal(f.commands,0);equal(#f.adds,0)
end)

test('overlay: completed path renders every segment in exact order with no shortcuts or input changes',function()
    local gui,step,untilState,event=completedSession();local f=zoneFixture()
    local before=serialize(gui:get().request);local readsBefore=heightReads
    assert(showExisting(gui,event).accepted);untilState(routeShown)
    local c=gui:get().request.result.candidates[1]
    equal(#f.adds,#c.waypoints-1)
    local bend=false
    for i,item in ipairs(f.adds) do
        local poly=item.polygon;local a,b=c.waypoints[i],c.waypoints[i+1]
        equal((poly[1].x+poly[4].x)/2,a.x);equal((poly[1].y+poly[4].y)/2,a.y)
        equal((poly[2].x+poly[3].x)/2,b.x);equal((poly[2].y+poly[3].y)/2,b.y)
        if i>1 then local p=c.waypoints[i-1];if (a.x-p.x)*(b.y-a.y)~=(a.y-p.y)*(b.x-a.x) then bend=true end end
    end
    assert(bend,'fixture must exercise real corridor bends')
    equal(serialize(gui:get().request),before);equal(heightReads,readsBefore);equal(f.commands,0)
end)

test('overlay: convex connected ribbons preserve offset negative coordinates and shared waypoints',function()
    local pts={{x=-100.5,y=200.25,z=-4},{x=-36.5,y=200.25,z=-1},{x=-36.5,y=264.25,z=2},{x=27.5,y=328.25,z=3}}
    local before=serialize(pts)
    for i=1,#pts-1 do
        local q=assert(routeOverlay.ribbon(pts[i],pts[i+1]))
        local area=0
        for j=1,4 do local b=q[j%4+1];area=area+q[j].x*b.y-b.x*q[j].y end
        assert(area>0)
        assert(math.abs((q[1].x+q[4].x)/2-pts[i].x)<1e-10)
        assert(math.abs((q[2].y+q[3].y)/2-pts[i+1].y)<1e-10)
    end
    equal(serialize(pts),before)
    equal(routeOverlay.ribbon(pts[1],pts[1]),nil)
    equal(routeOverlay.ribbon({x=0/0,y=0,z=0},pts[1]),nil)
end)

test('overlay: auto display occurs only after terminal complete success and while a view owns it',function()
    local gui,step,untilState,event=newSession();ready(step,untilState);local f=zoneFixture()
    event('status',{openRouteView=true});step(20);equal(#f.adds,0)
    submit(gui,event);step();equal(#f.adds,0)
    untilState(completed);untilState(routeShown);assert(#f.adds>1)
    assert(hasLog('DRAW_SUBMITTED'));equal(f.commands,0)
end)

test('overlay: hide show and camera movement preserve geometry without new searches',function()
    local gui,step,untilState,event,f=plannedOverlay()
    local before=serialize(gui:get().request);local first=serialize(f.zones);local readsBefore=heightReads
    local n=#f.adds;step(60);equal(#f.adds,n);equal(serialize(f.zones),first)
    assert(routeAction(gui,event,'focus').accepted);equal(#f.focus,1);equal(#f.adds,n)
    assert(routeAction(gui,event,'hide').accepted);untilState(function() return noZones(f) end)
    equal(gui:get().routeOverlay.status,'hidden')
    assert(routeAction(gui,event,'show').accepted);untilState(routeShown)
    equal(#f.adds,2*n);equal(serialize(gui:get().request),before);equal(heightReads,readsBefore)
    for i=1,n do equal(serialize(f.adds[i].polygon),serialize(f.adds[i+n].polygon)) end
    equal(f.commands,0)
end)

test('overlay: alternatives use their own actual candidate waypoints',function()
    local gui,step,untilState,event,f=plannedOverlay();local r=gui:get().request
    -- The planner may deduplicate flat-map alternatives; create a second validated-shaped
    -- completed route fixture solely to test candidate dispatch, not planner feasibility.
    local original=r.result.candidates[1]
    local second={};for k,v in pairs(original) do second[k]=v end
    second.id='fixture-second';second.rank=2;second.waypoints={}
    local a,b=original.waypoints[1],original.waypoints[#original.waypoints]
    local spacing=original.sampling.fineSpacing
    local x,y=a.x,a.y
    second.waypoints[1]={x=x,y=y,z=a.z,water=false}
    while x~=b.x do x=x+(x<b.x and spacing or -spacing);second.waypoints[#second.waypoints+1]={x=x,y=y,z=a.z,water=false} end
    while y~=b.y do y=y+(y<b.y and spacing or -spacing);second.waypoints[#second.waypoints+1]={x=x,y=y,z=b.z,water=false} end
    r.result.candidates[2]=second
    local compact={};for k,v in pairs(r.preview.candidates[1]) do compact[k]=v end
    compact.id=second.id;compact.rank=2;compact.waypointCount=#second.waypoints;r.preview.candidates[2]=compact
    local n=#f.adds
    assert(routeAction(gui,event,'show',second.id).accepted);untilState(routeShown)
    equal(gui:get().routeOverlay.candidateId,second.id)
    equal(#f.adds-n,#second.waypoints-1)
    local q=f.adds[n+1].polygon
    equal((q[2].y+q[3].y)/2,second.waypoints[2].y)
    assert(serialize(second.waypoints)~=serialize(original.waypoints))
    local state=gui:get();local seq=state.routeOverlay.sequence
    equal(routeAction(gui,event,'show','absent').accepted,false);equal(state.routeOverlay.sequence,seq+1)
    untilState(function() return noZones(f) end)
end)

test('overlay: long route uses bounded batches and full waypoint count',function()
    local gui,step,untilState,event=newSession({config=flow.config()})
    -- Existing long-distance integration fixture coordinates, actual hierarchical core.
    entities[10].x,entities[10].y=-2300,0;entities[20].x,entities[20].y=2300,0
    mapBounds={minX=-6000,maxX=6000,minY=-4000,maxY=4000}
    ready(step,untilState);local f=zoneFixture();event('status',{openRouteView=true})
    assert(submit(gui,event).accepted);untilState(completed)
    equal(gui:get().request.status,'ok');assert(gui:get().request.hierarchy)
    local frames=0
    while not routeShown(gui:get()) do
        local a,b=#f.adds,#f.removes;step();frames=frames+1
        assert(#f.adds-a+#f.removes-b<=routeOverlay.batchSize);assert(frames<200)
    end
    equal(#f.adds,#gui:get().request.result.candidates[1].waypoints-1)
    assert(frames>1);equal(f.commands,0)
end)

test('overlay: unsupported invalid and oversized routes never silently truncate',function()
    for _,mode in ipairs({'incomplete','invalid','oversize','duplicate'}) do
        local gui,step,untilState,event=completedSession();local f=zoneFixture();local r=gui:get().request
        if mode=='incomplete' then r.result.complete=false
        elseif mode=='invalid' then r.result.candidates[1].waypoints[2].z=0/0
        elseif mode=='duplicate' then r.result.candidates[1].waypoints[2]=r.result.candidates[1].waypoints[1]
        else
            local c=r.result.candidates[1];local last=c.waypoints[#c.waypoints]
            for i=#c.waypoints+1,1026 do c.waypoints[i]={x=last.x+i*32,y=last.y,z=0,water=false} end
            r.preview.candidates[1].waypointCount=#c.waypoints
        end
        equal(showExisting(gui,event).accepted,false);step(5);equal(#f.adds,0);equal(f.commands,0)
    end
end)

test('overlay: unreachable search-limit and unsupported results draw nothing',function()
    for _,status in ipairs({'unreachable','search_limit','unsupported','incomplete'}) do
        local gui,step,untilState,event=completedSession();local f=zoneFixture()
        gui:get().request.status=status;gui:get().status=status
        equal(showExisting(gui,event).accepted,false);step(5);equal(#f.adds,0)
    end
end)

test('overlay: replacement and stale actions cannot restore the previous request',function()
    local gui,step,untilState,event,f=plannedOverlay();local s=gui:get();local oldKeys={}
    for k in pairs(f.zones) do if k~='other_mod_zone' then oldKeys[#oldKeys+1]=k end end
    local stale={world=s.world,epoch=s.epoch,overlay={action='show',lease=s.routeOverlay.lease,
        sequence=s.routeOverlay.sequence+1,requestId=s.requestId,candidateId=s.routeOverlay.candidateId}}
    assert(submit(gui,event).accepted);equal(event('plan',stale).accepted,false)
    untilState(completed);untilState(routeShown)
    for _,k in ipairs(oldKeys) do equal(f.zones[k],nil) end
    assert(f.zones.other_mod_zone);equal(f.commands,0)
end)

test('overlay: reset reload and closed views release only owned zones',function()
    for _,mode in ipairs({'reload','world','close'}) do
        local gui,step,untilState,event,f,cb=plannedOverlay();local s=gui:get()
        local stale={world=s.world,epoch=s.epoch,overlay={action='show',lease=s.routeOverlay.lease,
            sequence=s.routeOverlay.sequence+1,requestId=s.requestId,candidateId=s.routeOverlay.candidateId}}
        if mode=='reload' then cb.guiHandleEvent(nil,nil,gui,'test','gameUI','reactPostInit',{})
        elseif mode=='world' then worldId=100;step(30)
        else assert(routeAction(gui,event,'close').accepted) end
        untilState(function() return noZones(f) end)
        equal(event('plan',stale).accepted,false);equal(gui:get().routeOverlay.lease,nil)
        equal(f.commands,0)
    end
end)

test('overlay: stale window close cannot remove a newly opened view',function()
    local gui,step,untilState,event,f=plannedOverlay();local s=gui:get()
    local close={world=s.world,epoch=s.epoch,overlay={action='close',lease=s.routeOverlay.lease}}
    assert(showExisting(gui,event).accepted);untilState(routeShown)
    equal(event('plan',close).reason,'stale_route_view');assert(not noZones(f))
end)

test('overlay: failed drawing cleans partial zones without retries or claimed visibility',function()
    local gui,step,untilState,event=completedSession();local f=zoneFixture();f.failAdd=true
    assert(showExisting(gui,event).accepted);step(5)
    equal(gui:get().routeOverlay.status,'error');equal(#f.adds,1);assert(noZones(f))
    assert(hasLog('api.gui.mission.setZone'));step(30);equal(#f.adds,1)
end)

test('overlay: removal failures are bounded visible and explicitly recoverable',function()
    local gui,step,untilState,event,f=plannedOverlay();f.failRemove=true
    routeAction(gui,event,'hide');step(40);equal(#f.removes,1)
    equal(gui:get().routeOverlay.status,'error');assert(hasLog('api.gui.mission.removeZone'))
    f.failRemove=false;routeAction(gui,event,'hide');untilState(function() return noZones(f) end)
end)

test('overlay: lost teardown dispatch expires the view and cleans without per-frame polling storms',function()
    local gui,step,untilState,event,f=plannedOverlay();clock=clock+6
    step(30);untilState(function() return noZones(f) end)
    equal(gui:get().routeOverlay.lease,nil);assert(hasLog('VIEW_EXPIRED'))
end)

test('overlay: rendering budget failure clears a partial route',function()
    local gui,step,untilState,event=completedSession();local f=zoneFixture()
    assert(showExisting(gui,event).accepted);clockStep=0.1;step();clockStep=0
    equal(gui:get().routeOverlay.status,'error');untilState(function() return noZones(f) end)
    assert(hasLog('rendering_work_budget_exceeded'));equal(f.commands,0)
end)

test('player overlay UI: small controls no construction and no automatic A-star before Plan',function()
    local gui,step,untilState,event=newSession();ready(step,untilState);local f=zoneFixture()
    local render,poll,tree,controls=mountUI(true);controls.launcher.params.onClick();tree=render()
    equal(#find(tree,'ComboBox'),2);equal(#find(tree,'Button','Build Test Track'),0)
    equal(#find(tree,'Button','Plan Railway'),1);equal(gui:get().request,nil);equal(#f.adds,0)
    local txt=panelText(tree)
    for _,name in ipairs({'snapshot','score','revision','Analyze Network','Inspect Geometry','#10','#20'}) do assert(not txt:find(name,1,true)) end
    find(tree,'ComboBox')[1].params.onValueChange('10');find(tree,'ComboBox')[2].params.onValueChange('20');tree=render()
    equal(gui:get().request,nil)
    find(tree,'Button','Plan Railway')[1].params.onClick();render();untilState(completed);untilState(routeShown);poll();tree=render()
    assert(panelText(tree):find('Proposed alignment shown on map',1,true));equal(f.commands,0)
    find(tree,'Button','Hide Route')[1].params.onClick();render();untilState(function() return noZones(f) end);poll();tree=render()
    find(tree,'Button','Show Route')[1].params.onClick();render();untilState(routeShown);poll();tree=render()
    find(tree,'Button','Focus Route')[1].params.onClick();render();equal(#f.focus,1);equal(f.commands,0)
end)

test('player overlay UI: teardown joins cleanup and reopening requires an explicit Show',function()
    local gui,step,untilState,event=newSession();ready(step,untilState);local f=zoneFixture()
    local render,poll,tree,controls=mountUI(true);controls.launcher.params.onClick();tree=render()
    find(tree,'ComboBox')[1].params.onValueChange('10');find(tree,'ComboBox')[2].params.onValueChange('20');tree=render()
    find(tree,'Button','Plan Railway')[1].params.onClick();render();untilState(completed);untilState(routeShown);poll();tree=render()
    controls.autoJoin=false;controls.panel.params.onClose();controls.flush();step(20);assert(noZones(f))
    controls.autoJoin=true;controls.launcher.params.onClick();tree=render()
    assert(noZones(f));assert(not panelText(tree):find('shown on map',1,true))
    find(tree,'Button','Show Route')[1].params.onClick();render();untilState(routeShown)
    equal(f.commands,0)
end)


test('player overlay UI: alternatives select once without rerunning the planner',function()
    local gui,step,untilState,event,f=plannedOverlay();local r=gui:get().request
    -- Renderer-control fixture; original route arrays stay in the owner, not React.
    local c={};for k,v in pairs(r.result.candidates[1]) do c[k]=v end;c.id='alternate';c.rank=2
    local p={};for k,v in pairs(r.preview.candidates[1]) do p[k]=v end;p.id='alternate';p.rank=2
    r.result.candidates[2]=c;r.preview.candidates[2]=p
    local before=serialize(r);local readsBefore=heightReads
    local render,poll,tree,controls=mountUI(true);controls.launcher.params.onClick();tree=render()
    local combos=find(tree,'ComboBox');equal(#combos,3)
    local select=combos[3].params.onValueChange
    select('alternate');select('alternate');tree=render();untilState(routeShown);poll();tree=render()
    equal(gui:get().routeOverlay.candidateId,'alternate');equal(gui:get().routeOverlay.sequence,1)
    equal(serialize(gui:get().request),before);equal(heightReads,readsBefore);equal(f.commands,0)
end)

test('player overlay UI: world changes reclaim a view lease without restoring stale geometry',function()
    local gui,step,untilState,event=newSession();ready(step,untilState);local f=zoneFixture()
    local render,poll,tree,controls=mountUI(true);controls.launcher.params.onClick();tree=render()
    local oldLease=gui:get().routeOverlay.lease
    worldId=100;poll();tree=render();tick=tick+1;step(30)
    poll();tree=render();poll();tree=render()
    assert(gui:get().routeOverlay.lease>oldLease);equal(#f.adds,0)
    find(tree,'ComboBox')[1].params.onValueChange('10');find(tree,'ComboBox')[2].params.onValueChange('20');tree=render()
    find(tree,'Button','Plan Railway')[1].params.onClick();render();untilState(completed);untilState(routeShown)
    equal(f.commands,0)
end)

test('player overlay UI: malformed renderer responses stop polling instead of fabricating visibility',function()
    local gui,step,untilState,event=newSession();ready(step,untilState);local f=zoneFixture()
    local render,poll,tree,controls=mountUI(true);controls.launcher.params.onClick();tree=render()
    controls.resultFilter=function(v) v.routeOverlay.status='fake_visibility';return v end
    poll();tree=render();assert(panelText(tree):find('Connection lost',1,true))
    local count=#controls.events;poll();equal(#controls.events,count);equal(#f.adds,0);equal(f.commands,0)
end)

local function stationSubmit(gui,event)
    local s=gui:get()
    return event('plan',{world=s.world,epoch=s.epoch,requestId=s.requestId+1,sourceId=10,destinationId=20,stationAware=true})
end
local function stationSession(setup)
    local gui,step,untilState,event=newSession();ready(step,untilState)
    if setup then setup() end
    local f=zoneFixture();event('status',{openRouteView=true})
    return gui,step,untilState,event,f
end
test('stations: actual occupied urban bounds produce multiple sites and exactly matched approach endpoints',function()
    local gui,step,untilState,event,f=stationSession();assert(stationSubmit(gui,event).accepted);untilState(completed)
    local r=gui:get().request;equal(r.status,'ok');assert(r.stationAware and r.preview)
    assert(#r.result.candidates>=1 and #r.result.candidates<=2);assert(hasLog('SHORTLIST town=10 sites=3'))
    for _,c in ipairs(r.result.candidates) do
        local s,d=c.stationSites.source,c.stationSites.destination
        assert(s.x~=entities[10].x or s.y~=entities[10].y);assert(d.x~=entities[20].x or d.y~=entities[20].y)
        equal(s.townId,10);equal(d.townId,20);equal(c.waypoints[1].x,s.approach.x);equal(c.waypoints[#c.waypoints].y,d.approach.y)
        assert(require('planning.station_sites').approaches(c,{source=s,destination=d}))
        equal(s.evidence.walkingAccess,'unknown');equal(c.constructionStatus,'unverified')
    end
    local response=event('status');equal(response.preview.candidates[1].waypoints,nil)
    equal(response.preview.candidates[1].stationSites.source.evidence,nil)
    equal(r.child,nil);equal(r.objects,nil);equal(r.towns,nil);equal(r.routes,nil)
    equal(f.commands,0)
end)
test('stations: two colored reservations accompany the exact cyan corridor; switching and hiding never search',function()
    local gui,step,untilState,event,f=stationSession();assert(stationSubmit(gui,event).accepted);untilState(completed);untilState(routeShown)
    local r=gui:get().request;local c=r.result.candidates[1];local n=#c.waypoints-1
    equal(#f.adds,n+6)
    for i=1,n do local p=f.adds[i].polygon
        equal((p[1].x+p[4].x)/2,c.waypoints[i].x);equal((p[2].y+p[3].y)/2,c.waypoints[i+1].y)
        equal(f.adds[i].color.x,0)
    end
    equal(f.adds[n+1].color.x,1);equal(f.adds[n+4].color.x,.9)
    local calls=heightReads;local searches=logCount('PAIR index=')
    if #r.result.candidates>1 then
        assert(routeAction(gui,event,'show',r.result.candidates[2].id).accepted);untilState(routeShown)
        equal(gui:get().routeOverlay.candidateId,r.result.candidates[2].id)
    end
    assert(routeAction(gui,event,'hide').accepted);untilState(function() return noZones(f) end)
    assert(routeAction(gui,event,'show').accepted);untilState(routeShown)
    equal(heightReads,calls);equal(logCount('PAIR index='),searches);equal(f.commands,0)
end)
test('stations: missing occupied urban evidence fails without town-center fallback or A-star',function()
    local gui,step,untilState,event,f=stationSession();f.station.townBuildings[10]={}
    assert(stationSubmit(gui,event).accepted);untilState(completed)
    equal(gui:get().request.result,nil);equal(gui:get().request.status,'unsupported');equal(logCount('PAIR index='),0)
    assert(hasLog('occupied_urban_area_unknown'));equal(#f.adds,0)
end)
test('stations: wet and failed terrain never creates reservations or a substitute route',function()
    for _,mode in ipairs({'wet','missing'}) do
        local gui,step,untilState,event,f=stationSession()
        if mode=='wet' then api.engine.terrain.isOnWater=function() return true end
        else api.engine.terrain.getHeightAt=function() error('site height unavailable') end end
        assert(stationSubmit(gui,event).accepted);untilState(completed)
        equal(gui:get().request.status,'unsupported');equal(gui:get().request.result,nil);equal(#f.adds,0)
    end
end)
test('stations: physical occupancy and absent road evidence leave sites unresolved',function()
    for _,mode in ipairs({'blocked','no road'}) do
        local gui,step,untilState,event,f=stationSession()
        if mode=='blocked' then f.station.add(5000,{-1000,-900,1000,900},{})
        else f.station.objects[1002]=nil;f.station.objects[2002]=nil end
        assert(stationSubmit(gui,event).accepted);untilState(completed)
        equal(gui:get().request.status,'unsupported');equal(#f.adds,0);equal(f.commands,0)
    end
end)
test('stations: native passenger rail classification is terminal-specific, including electric trains',function()
    local gui,step,untilState,event,f=stationSession();local native=require('station_site_api')
    local function station(modes,passengers)
        f.station.add(999,{-20,-20,20,20},{station={terminals={{transportModes=modes,passengersLoad=passengers,passengersUnload=false}}}})
        return native.station(999)
    end
    equal(station({bus=true},true),nil);equal(station({train=true},false),nil)
    equal(station({electricTrain=true},true).id,999);equal(station({train=true},true).id,999)
end)
test('stations: enumeration caps are explicit and do not truncate larger urban evidence',function()
    local gui,step,untilState,event,f=stationSession()
    f.station.townBuildings[10]={};for i=1,513 do f.station.townBuildings[10][i]=i end
    assert(stationSubmit(gui,event).accepted);untilState(completed);equal(gui:get().request.status,'unsupported')
    equal(logCount('PAIR index='),0);equal(#f.adds,0)
end)
test('stations: octree errors retain exact API paths and cannot become vacant land',function()
    local gui,step,untilState,event,f=stationSession()
    api.engine.system.octreeSystem.findIntersectingEntities=function() error('synthetic spatial failure') end
    assert(stationSubmit(gui,event).accepted);untilState(completed)
    assert(hasLog('octreeSystem.findIntersectingEntities'));assert(hasLog('synthetic spatial failure'))
    equal(gui:get().request.result,nil);equal(#f.adds,0)
end)
test('stations: octree overflow is rejected and callable native bindings are used without function type guards',function()
    local gui,step,untilState,event,f=stationSession();local native=require('station_site_api')
    local query=api.engine.system.octreeSystem.findIntersectingEntities
    api.engine.system.octreeSystem.findIntersectingEntities=setmetatable({}, {__call=function(_,...) return query(...) end})
    assert(#native.query(bounds,2048)>0)
    local ok,reason=pcall(native.query,bounds,1);equal(ok,false);assert(tostring(reason):find('station_spatial_query_limit',1,true))
    equal(f.commands,0)
end)
test('stations: session invalidation cancels the active search and removes both marker sets',function()
    local gui,step,untilState,event,f=stationSession();assert(stationSubmit(gui,event).accepted)
    untilState(function(s) return s.request and s.request.child~=nil end)
    local old=gui:get().request;worldId=100;step(30)
    equal(old.status,'invalidated');equal(old.child,nil);equal(gui:get().request,nil);equal(#f.adds,0)
    tick=tick+1;untilState(function(s) return s.status=='idle' end)
    event('status',{openRouteView=true});assert(stationSubmit(gui,event).accepted);untilState(completed);untilState(routeShown)
    worldId=101;step(100);assert(noZones(f));equal(gui:get().request,nil)
end)
test('stations: sixty-second shared budget applies across site selection and corridor pairs',function()
    local gui,step,untilState,event,f=stationSession();assert(stationSubmit(gui,event).accepted);step(5)
    clock=62;untilState(completed);equal(gui:get().request.status,'invalidated')
    assert(hasLog('station_snapshot_invalidated_expired'));equal(gui:get().request.result,nil)
end)
test('stations: world evidence changes before final publishing reject stale reservations',function()
    local gui,step,untilState,event,f=stationSession();assert(stationSubmit(gui,event).accepted)
    untilState(function(s) return s.request and s.request.phase=='verify' end)
    f.station.add(9999,{-1800,-900,1800,900},{})
    untilState(completed);equal(gui:get().request.status,'unsupported');assert(hasLog('station_reservation_changed'));equal(#f.adds,0)
end)
test('stations: deleted selected town during site processing invalidates rather than substituting an anchor',function()
    local gui,step,untilState,event,f=stationSession();assert(stationSubmit(gui,event).accepted)
    untilState(function(s) return s.request and s.request.phase=='sites' end);entities[10]=nil
    untilState(completed);equal(gui:get().request.status,'invalidated');equal(gui:get().request.result,nil)
end)
test('stations: busy and replay guards preserve one explicit request and at most two sequential corridor continuations',function()
    local gui,step,untilState,event,f=stationSession();local s=gui:get()
    local payload={world=s.world,epoch=s.epoch,requestId=1,sourceId=10,destinationId=20,stationAware=true}
    assert(event('plan',payload).accepted);equal(event('plan',payload).accepted,false)
    local maxReads=0
    for _=1,3000 do
        if completed(gui:get()) then break end
        local before=heightReads;step();maxReads=math.max(maxReads,heightReads-before)
        local r=gui:get().request;if r.child then equal(r.child.stationAware,nil) end
    end
    assert(completed(gui:get()));assert(maxReads<=16);assert(logCount('PAIR index=')<=2)
    equal(event('plan',payload).accepted,false);equal(logCount('[RNA:STATION] START'),1)
    local before=serialize(gui:get().request.result.candidates)
    assert(stationSubmit(gui,event).accepted);untilState(completed)
    equal(serialize(gui:get().request.result.candidates),before);equal(f.commands,0)
end)
test('stations: original town pair remains independent from explicit station coordinates',function()
    local gui,step,untilState,event,f=stationSession();assert(stationSubmit(gui,event).accepted)
    untilState(function(s) return s.request and s.request.child and s.request.child.pair end)
    local child=gui:get().request.child;equal(child.townPair.start.x,entities[10].x)
    equal(child.pair.start.x,child.anchorOverride.start.x)
    assert(child.pair.start.x~=child.townPair.start.x or child.pair.start.y~=child.townPair.start.y)
    equal(child.layout.start.distance,0);equal(child.layout.destination.distance,0)
end)
test('stations: long-distance station pair uses the authoritative hierarchy and preserves approaches',function()
    local gui,step,untilState,event,f=stationSession(function()
        entities[10].x=-3000;entities[20].x=3000
        mapBounds={minX=-8000,maxX=8000,minY=-4096,maxY=4096}
    end)
    assert(stationSubmit(gui,event).accepted);untilState(completed)
    local r=gui:get().request;equal(r.status,'ok');assert(hasLog('LONG_DISTANCE mode=hierarchical'))
    assert(r.preview);equal(r.preview.candidates[1].spacing,64)
    for _,c in ipairs(r.result.candidates) do equal(c.waypoints[1].x,c.stationSites.source.approach.x) end
end)
test('stations: alternate UI uses actual station pair metadata and has no automatic site or corridor work',function()
    local gui,step,untilState,event,f=stationSession();entities[10].name='Same';entities[20].name='Same'
    local render,poll,tree,controls=mountUI(true);controls.launcher.params.onClick();tree=render()
    find(tree,'ComboBox')[1].params.onValueChange('10');find(tree,'ComboBox')[2].params.onValueChange('20');tree=render()
    equal(heightReads,0);equal(gui:get().request,nil)
    find(tree,'Button','Plan Railway')[1].params.onClick();render();untilState(completed);untilState(routeShown);poll();tree=render()
    local txt=panelText(tree);assert(txt:find('Station near Same (orange)',1,true));assert(txt:find('Station near Same (purple)',1,true))
    local p=gui:get().request.preview;equal(p.source.id,10);equal(p.destination.id,20)
    if #p.candidates>1 then
        local calls=heightReads;find(tree,'ComboBox')[3].params.onValueChange(p.candidates[2].id);render();untilState(routeShown)
        equal(heightReads,calls);equal(gui:get().routeOverlay.candidateId,p.candidates[2].id)
    end
    controls.panel.params.onClose();controls.flush();step(100);assert(noZones(f))
end)
test('stations: failure while drawing a station polygon clears the already submitted cyan path and all owned markers',function()
    local gui,step,untilState,event,f=stationSession();assert(stationSubmit(gui,event).accepted)
    local setZone=api.gui.mission.setZone
    api.gui.mission.setZone=function(key,poly,draw,color,...)
        setZone(key,poly,draw,color,...)
        if color.x==.9 then error('station marker renderer failure') end
    end
    untilState(completed);step(200)
    equal(gui:get().routeOverlay.status,'error');assert(noZones(f));equal(f.commands,0)
    assert(hasLog('station marker renderer failure'))
end)
test('occupancy acceptance: native component classification is evidenced and construction takes precedence over tree models',function()
    local gui,step,untilState,event,f=stationSession();local native=require('station_site_api')
    local box={minX=-4,maxX=4,minY=-4,maxY=4}
    local function classify(parts)
        f.station.add(8000,{-4,-4,4,4},parts);return native.object({id=8000,box=box},worldId)
    end
    api.res={modelRep={get=function(id) return {metadata=id==1 and {tree={}} or {}} end}}
    equal(classify({townBuilding={town=10}}).kind,'building')
    equal(classify({construction={}}).kind,'construction');equal(classify({}).kind,'unknown')
    local model={fatInstances={{modelId=1}},thinInstances={}}
    local v=classify({models=model});equal(v.kind,'vegetation');assert(v.source:find('model.metadata.tree',1,true))
    equal(classify({models=model,construction={}}).kind,'construction')
    equal(classify({models={fatInstances={},thinInstances={{modelId=1}}}}).kind,'vegetation')
    equal(classify({models={fatInstances={{modelId=1},{modelId=2}},thinInstances={}}}).kind,'unknown')
end)
test('occupancy acceptance: missing failed mixed or oversized model evidence remains unknown without filename guessing',function()
    local gui,step,untilState,event,f=stationSession();local native=require('station_site_api')
    local m={fatInstances={{modelId=1}},thinInstances={}};f.station.add(8000,{-4,-4,4,4},{models=m})
    local raw={id=8000,box={minX=-4,maxX=4,minY=-4,maxY=4}}
    api.res={modelRep={get=function() error('missing model fixture') end}}
    local o=native.object(raw,worldId);equal(o.kind,'unknown');assert(o.classificationIssue:find('api.res.modelRep.get',1,true))
    api.res.modelRep.get=function() return {metadata={tree={},rock={}}} end
    equal(native.object(raw,worldId).kind,'unknown')
    api.res.modelRep.get=function() return {metadata={tree={}}} end
    for i=1,4097 do m.fatInstances[i]={modelId=1} end
    o=native.object(raw,worldId);equal(o.kind,'unknown');equal(o.classificationIssue,'model_instance_limit_4096')
end)
test('occupancy acceptance: final revalidation uses the same body and approach policy including provisional trees',function()
    local gui,step,untilState,event,f=stationSession();local native=require('station_site_api');local p=require('planning.station_occupancy')
    local c={x=0,y=0,dx=1,dy=0,length=160,width=48,clearance={minX=-256,maxX=256,minY=-32,maxY=32}}
    api.res={modelRep={get=function() return {metadata={tree={}}} end}}
    local function check(x,parts,expected)
        f.station.add(8000,{x-2,-2,x+2,2},parts)
        local o=native.object({id=8000,box={minX=x-2,maxX=x+2,minY=-2,maxY=2}},worldId)
        local initial,reason=p.inspect(c,{o});local final,finalReason,r=native.clear(c,worldId)
        equal(initial,expected);equal(final,initial);equal(finalReason,reason);return r
    end
    check(-200,{townBuilding={town=10}},true)
    check(0,{townBuilding={town=10}},false)
    check(110,{},false);check(200,{},true)
    local r=check(110,{models={fatInstances={{modelId=1}},thinInstances={}}},true);equal(r.vegetationClearance,1)
end)
test('occupancy acceptance: verified vegetation can produce provisional sites and routes without any world mutation',function()
    local gui,step,untilState,event,f=stationSession()
    api.res={modelRep={get=function() return {metadata={tree={}}} end}}
    f.station.add(8000,{-1800,-900,1800,900},{models={fatInstances={},thinInstances={{modelId=1}}}})
    assert(stationSubmit(gui,event).accepted);untilState(completed);equal(gui:get().request.status,'ok');untilState(routeShown)
    local c=gui:get().request.result.candidates[1]
    equal(c.stationSites.source.evidence.clearanceStatus,'provisional_vegetation_clearance')
    equal(c.stationSites.source.evidence.finalVegetationClearance,1);equal(c.vegetationClearanceUnverified,true)
    equal(c.constructionStatus,'unverified');equal(f.commands,0)
    assert(hasLog('class=vegetation'));assert(hasLog('source=BOUNDING_VOLUME+MODEL_INSTANCE_LIST+model.metadata.tree'))
    assert(hasLog('REVALIDATION town='));assert(hasLog('CORRIDOR_OCCUPANCY'))
    equal(c.waypoints[1].x,c.stationSites.source.approach.x)
end)
test('occupancy acceptance: classified hard occupancy diagnostics are bounded and never silently treat trees plus unknown models as clear',function()
    local gui,step,untilState,event,f=stationSession()
    api.res={modelRep={get=function(id) return {metadata=id==1 and {tree={}} or {}} end}}
    for i=1,12 do
        f.station.add(8000+i,{-1800,-900,1800,900},{models={fatInstances={{modelId=1},{modelId=2}},thinInstances={}}})
    end
    assert(stationSubmit(gui,event).accepted);untilState(completed);equal(gui:get().request.status,'unsupported')
    equal(heightReads,0);equal(#f.adds,0);assert(logCount('OBSTRUCTION_SAMPLE')<=8)
    assert(hasLog('OCCUPANCY town=10 generated='));assert(hasLog('OCCUPANCY_CLASS town=10 class=unknown'))
    assert(hasLog('source=BOUNDING_VOLUME+MODEL_INSTANCE_LIST'));equal(f.commands,0)
end)
test('occupancy acceptance: between-sample hard conflicts reject a candidate before any route is published',function()
    local gui,step,untilState,event,f=stationSession();assert(stationSubmit(gui,event).accepted)
    untilState(function(s) return s.request and s.request.phase=='corridor_check' end)
    local r=gui:get().request;local w=r.child.result.candidates[1].waypoints
    local a,b=w[1],w[2];local x,y=(a.x+b.x)/2,(a.y+b.y)/2
    -- Fault fixture adds a known tiny building exactly between already sampled waypoints.
    r.objects[#r.objects+1]={id=9900,kind='building',source='TOWN_BUILDING',box={minX=x-1,maxX=x+1,minY=y-1,maxY=y+1}}
    step(2);assert(hasLog('CORRIDOR_CONFLICT candidate='));assert(hasLog('hard_building entity=9900'))
    equal(#f.adds,0);equal(f.commands,0)
end)
test('occupancy acceptance: final revalidation is incremental and cancelled safely on a world change',function()
    local gui,step,untilState,event,f=stationSession();local native=require('station_site_api')
    api.res={modelRep={get=function() return {metadata={tree={}}} end}}
    for i=1,40 do f.station.add(8000+i,{-1,-1,1,1},{models={fatInstances={{modelId=1}},thinInstances={}}}) end
    local c={x=0,y=0,dx=1,dy=0,length=160,width=48,clearance={minX=-256,maxX=256,minY=-32,maxY=32}}
    local job=native.startClear(c,worldId);native.stepClear(job);equal(job.cursor,17);assert(not job.finished)
    native.stepClear(job);equal(job.cursor,33);assert(not job.finished)
    native.stepClear(job);equal(job.clear,true);equal(job.report.vegetationClearance,40);equal(job.raw,nil)
    assert(stationSubmit(gui,event).accepted)
    untilState(function(s) return s.request and s.request.revalidation~=nil end)
    local old=gui:get().request;worldId=100;step(40)
    equal(old.revalidation,nil);equal(old.status,'invalidated');equal(gui:get().request,nil);equal(#f.adds,0)
end)
test('grouped acceptance: one callback shares 64 instance visits across entities and exposes only complete groups',function()
    local gui,step,untilState,event,f=stationSession();local native=require('station_site_api')
    local raw={};local calls=0
    api.res={modelRep={get=function() calls=calls+1;return {metadata={tree={}}} end}}
    for id=8000,8001 do
        local m={fatInstances={},thinInstances={}};for i=1,40 do m.fatInstances[i]={modelId=0} end
        f.station.add(id,{-1,-1,1,1},{models=m})
        raw[#raw+1]={id=id,box={minX=-1,minY=-1,maxX=1,maxY=1}}
    end
    local ctx=native.newModelContext(worldId);local job=native.startObjects(raw,worldId)
    equal(native.stepObjects(job,ctx),64);equal(ctx.visits,64);equal(calls,1)
    equal(#job.objects,1);equal(job.pending.inspected,24);assert(not job.finished)
    equal(native.stepObjects(job,ctx),16);assert(job.finished);equal(#job.objects,2)
    equal(ctx.visits,80);equal(ctx.cacheHits,79);equal(job.raw,nil);equal(f.commands,0)
end)
test('grouped acceptance: large all-tree groups pass initial final and route policies with bounded owner work',function()
    local gui,step,untilState,event,f=stationSession();local calls=0
    api.res={modelRep={get=function() calls=calls+1;return {metadata={tree={}}} end}}
    local m={fatInstances={},thinInstances={}};for i=1,129 do m.thinInstances[i]={modelId=1} end
    f.station.add(8000,{-1800,-900,1800,900},{models=m})
    assert(stationSubmit(gui,event).accepted)
    local finalSeen=false
    for _=1,3000 do
        if completed(gui:get()) then break end
        local before=gui:get().request.modelContext;local visits=before and before.visits or 0
        step();local r=gui:get().request
        if r.modelContext then
            assert(r.modelContext.visits-visits<=64)
            if r.revalidation then finalSeen=true;assert(r.modelContext.visits>=258) end
        end
    end
    local r=gui:get().request;equal(r.status,'ok');assert(finalSeen);equal(calls,2)
    equal(r.modelContext,nil);equal(r.objectJob,nil);untilState(routeShown)
    local c=r.result.candidates[1];equal(c.vegetationClearanceUnverified,true)
    equal(c.stationSites.source.evidence.finalVegetationClearance,1)
    equal(c.waypoints[1].x,c.stationSites.source.approach.x)
    assert(hasLog('MODEL_GROUPS town=10 unique_entities=1 multi_instance_groups=1 instances_inspected=129 all_tree=1'))
    assert(hasLog('MODEL_CANDIDATES town=10'));assert(hasLog('counts=candidates_not_entities'))
    equal(logCount('MODEL_GROUPS town='),2);equal(logCount('MODEL_BUDGET visits='),1);equal(f.commands,0)
end)
test('grouped acceptance: final revalidation refreshes resource metadata and rejects newly incompatible groups',function()
    local gui,step,untilState,event,f=stationSession();local tree=true;local calls=0
    api.res={modelRep={get=function() calls=calls+1;return {metadata=tree and {tree={}} or {rock={}}} end}}
    local m={fatInstances={},thinInstances={}};for i=1,9 do m.fatInstances[i]={modelId=1} end
    f.station.add(8000,{-1800,-900,1800,900},{models=m})
    assert(stationSubmit(gui,event).accepted)
    untilState(function(s) return s.request and s.request.phase=='verify' end)
    equal(calls,1);tree=false;untilState(completed)
    local r=gui:get().request;equal(r.status,'unsupported');equal(calls,2)
    assert(r.reason:find('station_reservation_changed',1,true));equal(r.result,nil)
    assert(hasLog('REVALIDATION_SAMPLE entity=8000 class=unknown'));equal(#f.adds,0);equal(f.commands,0)
end)
test('grouped acceptance: mixed remainder blocks candidates and route masks using retained aggregate bounds',function()
    local gui,step,untilState,event,f=stationSession();local p=require('planning.station_occupancy')
    api.res={modelRep={get=function(id) return {metadata=id==2 and {rock={}} or {tree={}}} end}}
    local m={fatInstances={},thinInstances={}};for i=1,129 do m.fatInstances[i]={modelId=i==129 and 2 or 1} end
    f.station.add(8000,{-1800,-900,1800,900},{models=m})
    assert(stationSubmit(gui,event).accepted)
    untilState(function(s) return s.request and s.request.phase=='sites' end)
    local o=gui:get().request.objects[#gui:get().request.objects]
    equal(o.id,8000);equal(o.kind,'unknown');equal(o.modelGroup.inspected,129)
    equal(o.box.minX,-1800);equal(o.box.maxX,1800)
    equal(p.segment({x=-1700,y=0},{x=1700,y=0},{o}).id,8000)
    untilState(completed);equal(gui:get().request.status,'unsupported');equal(heightReads,0)
    assert(hasLog('all_tree=0 mixed_non_tree=1 unknown=0'))
    assert(hasLog('unknown_group_blocked='));equal(#f.adds,0);equal(f.commands,0)
end)
test('grouped acceptance: world invalidation discards a partial classification and its request cache',function()
    local gui,step,untilState,event,f=stationSession()
    api.res={modelRep={get=function() return {metadata={tree={}}} end}}
    local m={fatInstances={},thinInstances={}};for i=1,4096 do m.fatInstances[i]={modelId=1} end
    f.station.add(8000,{-1800,-900,1800,900},{models=m})
    assert(stationSubmit(gui,event).accepted)
    untilState(function(s) return s.request and s.request.objectJob and s.request.objectJob.pending end)
    local old=gui:get().request;assert(old.objectJob.pending.inspected<4096)
    worldId=100;step(40);equal(old.status,'invalidated');equal(old.modelContext,nil);equal(old.objectJob,nil)
    equal(gui:get().request,nil);equal(heightReads,0);equal(#f.adds,0);equal(f.commands,0)
end)
test('grouped acceptance: oversized aggregate is an explicit unknown blocker without resource reads',function()
    local gui,step,untilState,event,f=stationSession();local calls=0
    api.res={modelRep={get=function() calls=calls+1;return {metadata={tree={}}} end}}
    local m={fatInstances={},thinInstances={}};for i=1,4097 do m.fatInstances[i]={modelId=1} end
    f.station.add(8000,{-1800,-900,1800,900},{models=m})
    assert(stationSubmit(gui,event).accepted);untilState(completed)
    equal(gui:get().request.status,'unsupported');equal(calls,0);equal(heightReads,0)
    assert(hasLog('instances_inspected=0 all_tree=0 mixed_non_tree=0 unknown=1 instance_limit_failures=1'))
    assert(hasLog('issue=model_instance_limit_4096'));equal(f.commands,0)
end)
test('smooth preview: owner retains original candidates and records bounded smoothing outcomes',function()
    local gui,step,untilState,event,f=stationSession();assert(stationSubmit(gui,event).accepted)
    untilState(function(s) return s.request and s.request.phase=='smooth' end)
    local markers=require('planning.station_sites').markers
    local original={};for i,c in ipairs(gui:get().request.routes) do original[i]={id=c.id,points=serialize(c.waypoints),
        source=serialize(markers(c.stationSites.source)),destination=serialize(markers(c.stationSites.destination))} end
    untilState(completed);untilState(routeShown)
    for _,c in ipairs(gui:get().request.result.candidates) do
        assert(c.smoothPreview)
        for _,o in ipairs(original) do if o.id==c.id then
            equal(serialize(c.waypoints),o.points);equal(serialize(markers(c.stationSites.source)),o.source)
            equal(serialize(markers(c.stationSites.destination)),o.destination)
        end end
    end
    assert(hasLog('SMOOTH_COMPLETE'));equal(f.commands,0)
end)
test('smooth preview: live owner and renderer use complete smooth points while station markers stay unchanged',function()
    local gui,step,untilState,event,f=stationSession(function() entities[10].x=-600;entities[10].y=0;entities[20].x=600;entities[20].y=0 end)
    assert(stationSubmit(gui,event).accepted);untilState(completed);untilState(routeShown)
    local c=gui:get().request.result.candidates[1];local smooth=c.smoothPreview
    assert(smooth.status=='validated',smooth.reason);equal(#f.adds,#smooth.points-1+6)
    for i=1,#smooth.points-1 do
        local poly=f.adds[i].polygon
        assert(math.abs((poly[1].x+poly[4].x)/2-smooth.points[i].x)<1e-8)
        assert(math.abs((poly[2].y+poly[3].y)/2-smooth.points[i+1].y)<1e-8)
    end
    local n=#smooth.points-1;equal(f.adds[n+1].color.x,1);equal(f.adds[n+4].color.x,.9)
    equal(smooth.points[1].x,c.stationSites.source.approach.x)
    equal(smooth.points[#smooth.points].z,c.stationSites.destination.approach.z)
    local calls=heightReads;local searches=logCount('PAIR index=');local startCount=logCount('SMOOTH_START')
    assert(routeAction(gui,event,'hide').accepted);step(200);assert(noZones(f))
    assert(routeAction(gui,event,'show',c.id).accepted);untilState(routeShown)
    assert(routeAction(gui,event,'focus',c.id).accepted);equal(heightReads,calls)
    equal(logCount('PAIR index='),searches);equal(logCount('SMOOTH_START'),startCount)
    local response=event('status');equal(response.preview.candidates[1].smoothPreview,nil)
    equal(f.commands,0)
end)
test('smooth preview: curve probes accept bounded native float rounding while planner coordinates stay exact',function()
    reset();local a=require('live_plan_api');local original=api.type.Vec2f.new
    api.type.Vec2f.new=function(x,y) return original(math.floor(x*1024)/1024,math.floor(y*1024)/1024) end
    local r=a.sampleCurve(bounds,10.123456,-2.123456);equal(r.valid,true);equal(r.height,-2)
    assert(r.x~=r.requestedX and math.abs(r.x-r.requestedX)<1/64)
    assert(#a.sample(bounds,10.123456,-2.123456).errors>0)
    local before=heightReads;api.type.Vec2f.new=function(x,y) return original(x+1,y) end
    assert(#a.sampleCurve(bounds,10,0).errors>0);equal(heightReads,before)
    api.type.Vec2f.new=original;equal(a.sampleCurve(bounds,bounds.maxX,0).valid,false);equal(heightReads,before)
end)
test('smooth preview: fresh terrain failure retains complete grid and colored markers without rerunning A star',function()
    local gui,step,untilState,event,f=stationSession(function() entities[10].x=-600;entities[10].y=0;entities[20].x=600;entities[20].y=0 end)
    assert(stationSubmit(gui,event).accepted)
    untilState(function(s) return s.request and s.request.phase=='smooth' end)
    local searches=logCount('PAIR index=');local original=api.engine.terrain.getHeightAt
    api.engine.terrain.getHeightAt=function() error('new curve terrain read fixture') end
    untilState(completed);api.engine.terrain.getHeightAt=original;untilState(routeShown)
    local r=gui:get().request;equal(r.status,'ok');local c=r.result.candidates[1]
    equal(c.smoothPreview.status,'fallback');equal(c.smoothPreview.points,nil)
    assert(c.smoothPreview.reason:find('api.engine.terrain.getHeightAt',1,true))
    equal(#f.adds,#c.waypoints-1+6);equal(logCount('PAIR index='),searches);equal(f.commands,0)
end)
test('smooth preview: work guard and optional time budget preserve grid without extending snapshot age',function()
    for _,mode in ipairs({'work','optional_age','snapshot'}) do
        local gui,step,untilState,event,f=stationSession()
        assert(stationSubmit(gui,event).accepted)
        untilState(function(s) return s.request and s.request.smoothing~=nil end)
        if mode=='work' then clockStep=.04;step();clockStep=0
        elseif mode=='optional_age' then clock=gui:get().request.smoothStarted+11
        else clock=gui:get().request.started+61 end
        untilState(completed)
        if mode=='snapshot' then equal(gui:get().request.status,'invalidated');equal(gui:get().request.result,nil)
        else
            equal(gui:get().request.status,'ok')
            for _,c in ipairs(gui:get().request.result.candidates) do
                equal(c.smoothPreview.status,'fallback');assert(c.smoothPreview.reason:find('budget',1,true))
            end
        end
        equal(f.commands,0)
    end
end)
test('smooth preview: reload during refinement discards partial points and cannot restore old zones',function()
    local gui,step,untilState,event,f=stationSession()
    assert(stationSubmit(gui,event).accepted)
    untilState(function(s) return s.request and s.request.smoothing~=nil end)
    local old=gui:get().request;worldId=100;step(80)
    equal(old.smoothing,nil);equal(old.status,'invalidated');equal(gui:get().request,nil);equal(#f.adds,0);equal(f.commands,0)
end)
test('smooth preview: close during work prevents stale drawing; reopen and alternatives reuse completed data',function()
    local gui,step,untilState,event,f=stationSession(function() entities[10].x=-600;entities[10].y=0;entities[20].x=600;entities[20].y=0 end)
    assert(stationSubmit(gui,event).accepted)
    untilState(function(s) return s.request and s.request.smoothing~=nil end)
    assert(routeAction(gui,event,'close').accepted);untilState(completed);step(20);equal(#f.adds,0)
    local calls=heightReads;event('status',{openRouteView=true})
    local r=gui:get().request
    for _,c in ipairs(r.result.candidates) do
        assert(routeAction(gui,event,'show',c.id).accepted);untilState(routeShown)
        equal(gui:get().routeOverlay.candidateId,c.id)
    end
    equal(heightReads,calls);assert(routeAction(gui,event,'close').accepted);step(300);assert(noZones(f));equal(f.commands,0)
end)
test('smooth preview: per callback native terrain reads stay bounded across a long route',function()
    local gui,step,untilState,event,f=stationSession(function()
        entities[10].x=-4000;entities[10].y=0;entities[20].x=4000;entities[20].y=0
        mapBounds={minX=-9000,maxX=9000,minY=-4096,maxY=4096}
    end)
    assert(stationSubmit(gui,event).accepted)
    untilState(function(s) return s.request and s.request.phase=='smooth' end)
    while not completed(gui:get()) do local before=heightReads;step();assert(heightReads-before<=16) end
    equal(gui:get().request.status,'ok')
    for _,c in ipairs(gui:get().request.result.candidates) do
        local s=c.smoothPreview;assert(s.status=='validated' or s.status=='fallback')
        if s.points then assert(#s.points<=1025);equal(s.points[#s.points].x,c.stationSites.destination.approach.x) end
    end
    equal(f.commands,0)
end)
print('PASS '..passed..' live planning/UI tests (mocked engine and React, not TF3 runtime verification)')
