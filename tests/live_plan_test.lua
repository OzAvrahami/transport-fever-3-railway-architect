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
        error("session did not reach expected state")
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
local function mountUI()
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
            assert(scope:find("RNA:PLAN:4B2:", 1, true)); controls.joins[#controls.joins + 1] = fn
        end,
        iaHandler = function(fn) return fn end,
        useInputAction = function(name, fn) equal(name, "IA_MENU_BACK"); active.back = fn end,
        fireEvent = function(target, name)
            equal(target, nil); equal(name, "focusMainModButtonArea"); controls.focusReturns = controls.focusReturns + 1
        end,
    }
    local windowApi = {
        addSingletonWindow = function(recipe, params)
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
    local combos = find(tree, "ComboBox")
    equal(#combos, 2)
    equal(combos[1].params.items[2].params.content.params.text, "Twin [#10]")
    equal(combos[1].params.items[3].params.content.params.text, "Twin [#20]")
    combos[1].params.onValueChange("10")
    tree = render(); combos = find(tree, "ComboBox")
    equal(combos[2].params.items[2].params.available, false)
    combos[2].params.onValueChange("10")
    tree = render(); equal(find(tree, "Button", "Plan")[1].params.meta.enabled, false)
    find(tree, "ComboBox")[2].params.onValueChange("20")
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
    tree = render(); find(tree, "ComboBox")[1].params.onValueChange("10")
    tree = render(); find(tree, "ComboBox")[2].params.onValueChange("20")
    callbacks.guiHandleEvent(nil, nil, gui, "test", "gameUI", "reactPostInit", {})
    poll(); tree = render()
    for _, combo in ipairs(find(tree, "ComboBox")) do equal(combo.params.value, "") end
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
    equal(#find(controls.launcher, "ComboBox"), 0); equal(#find(controls.panel, "ComboBox"), 2)
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
    find(tree, "ComboBox")[1].params.onValueChange("10"); tree = render()
    find(tree, "ComboBox")[2].params.onValueChange("20"); tree = render()
    controls.panel.params.onClose(); tree = render()
    controls.launcher.params.onClick(); tree = render()
    equal(find(tree, "ComboBox")[1].params.value, "10"); equal(find(tree, "ComboBox")[2].params.value, "20")
    find(tree, "Button", "Plan")[1].params.onClick()
    render() -- only an already dispatched request continues after closing
    controls.panel.params.onClose(); tree = render(); untilState(completed)
    equal(gui:get().request.status, "ok")
    controls.launcher.params.onClick(); tree = render()
    equal(find(tree, "Button", "Plan")[1].params.meta.enabled, true)
    equal(logCount("REQUEST_START"), 1)
    find(tree, "Button", "Refresh towns")[1].params.onClick(); tree = render()
    for _, combo in ipairs(find(tree, "ComboBox")) do equal(combo.params.value, "") end
end)

test("closed-window session reset clears restored selection before new request", function()
    local gui, step, untilState, event, callbacks = newSession(); ready(step, untilState)
    local render, poll, tree, controls = mountUI()
    controls.launcher.params.onClick(); tree = render()
    find(tree, "ComboBox")[1].params.onValueChange("10"); tree = render()
    find(tree, "ComboBox")[2].params.onValueChange("20"); tree = render()
    controls.panel.params.onClose(); tree = render()
    callbacks.guiHandleEvent(nil, nil, gui, "test", "gameUI", "reactPostInit", {})
    ready(step, untilState)
    controls.launcher.params.onClick(); tree = render()
    for _, combo in ipairs(find(tree, "ComboBox")) do equal(combo.params.value, "") end
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
    assert(controls.launcher.params.meta.tooltip:find("native window container unavailable", 1, true))
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
    equal(#find(tree, "ComboBox")[1].params.items, 3)
    poll(); equal(#controls.events, 1); controls.flush()
    poll(); controls.flush(); equal(#controls.events, 3)
    equal(logCount("UI_ERROR"), 0); equal(logCount("REQUEST_START"), 0); equal(heightReads, 0)
end)

test("Plan and Refresh each dispatch once in joins with queued-click protection", function()
    local gui, step, untilState = newSession(); ready(step, untilState)
    local render, poll, tree, controls = mountUI()
    controls.launcher.params.onClick(); tree = render()
    find(tree, "ComboBox")[1].params.onValueChange("10"); tree = render()
    find(tree, "ComboBox")[2].params.onValueChange("20"); tree = render()
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
    for _, combo in ipairs(find(tree, "ComboBox")) do equal(combo.params.value, "") end
    equal(logCount("REQUEST_START"), 1)
end)

test("unmount cancels pending dispatch and stale handlers cannot update a reopened form", function()
    local gui, step, untilState = newSession(); ready(step, untilState)
    local render, poll, tree, controls = mountUI(); controls.autoJoin = false
    controls.launcher.params.onClick(); tree = render()
    local oldSelection = find(tree, "ComboBox")[1].params.onValueChange
    local oldRefresh = find(tree, "Button", "Refresh towns")[1].params.onClick
    controls.detachWindow(); tree = render()
    controls.launcher.params.onClick(); tree = render()
    equal(#controls.joins, 2)
    oldSelection("10"); oldRefresh()
    controls.flush(); tree = render()
    equal(#controls.events, 1); equal(find(tree, "ComboBox")[1].params.value, "")
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
    find(tree, "ComboBox")[1].params.onValueChange("10"); tree = render()
    find(tree, "ComboBox")[2].params.onValueChange("20"); tree = render()
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
    equal(windowStyle.size[1], 520); equal(windowStyle.size[2], 520)
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
        equal(#find(tree, "ComboBox")[1].params.items, 1)
        for _ = 1, 20 do poll() end
        equal(logCount("UI_ERROR"), 1); equal(#controls.events, 1)
        callbacks.guiHandleEvent = original; controls.resultFilter = nil
        find(tree, "Button", "Refresh towns")[1].params.onClick(); tree = render() -- diagnostic only
        find(tree, "Button", "Refresh towns")[1].params.onClick(); render()
        untilState(function(s) return s.status == "idle" end); poll(); tree = render()
        equal(#find(tree, "ComboBox")[1].params.items, 3)
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
        equal(#find(tree, "ComboBox")[1].params.items, 1)
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
    equal(#find(tree, "ComboBox")[1].params.items, 1)
    for _ = 1, 20 do poll() end
    equal(#controls.events, 1); equal(logCount("UI_ERROR"), 1)
    find(tree, "Button", "Refresh towns")[1].params.onClick(); render()
    equal(#controls.events, 2); equal(logCount("COMM HANDLER_ENTRY"), 0)
    tree = render(); equal(#find(tree, "ComboBox")[1].params.items, 1) -- not applied as fallback data
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
    equal(#find(tree, "ComboBox")[1].params.items, 11)
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
    equal(#find(tree, "ComboBox")[1].params.items, 11)
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
    find(tree, "ComboBox")[1].params.onValueChange("10"); tree = render()
    find(tree, "ComboBox")[2].params.onValueChange("20"); tree = render()
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
    equal(find(tree, "ComboBox")[1].params.value, "10"); equal(find(tree, "ComboBox")[2].params.value, "20")
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
    equal(#find(tree, "ComboBox"), 2); equal(heightReads, 0)
    find(tree, "ComboBox")[1].params.onValueChange("10"); tree = render()
    find(tree, "ComboBox")[2].params.onValueChange("20"); tree = render()
    find(tree, "Button", "Plan")[1].params.onClick(); tree = render()
    equal(#find(tree, "ComboBox"), 2)
    untilState(completed); poll(); tree = render()
    equal(#find(tree, "ComboBox"), 3)
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
        find(tree, "ComboBox")[3].params.onValueChange(c.id); tree = render()
        equal(find(tree, "ComboBox")[3].params.value, c.id)
        assert(panelText(tree):find(string.format("Approximate length: %.1f", c.length), 1, true))
        equal(#controls.events, count); equal(heightReads, 0)
    end
    find(tree, "ComboBox")[3].params.onValueChange("nonexistent"); tree = render()
    equal(find(tree, "ComboBox")[3].params.value, result.candidates[3].id)
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
        equal(#find(tree, "ComboBox"), 2)
        assert(panelText(tree):find("No eligible corridor summary", 1, true))
    end
end)

test("new request replaces summary and stale candidate callbacks cannot restore prior data", function()
    local gui, step, untilState, event = newSession(); ready(step, untilState)
    submit(gui, event); untilState(completed)
    local render, poll, tree, controls = mountUI(); controls.launcher.params.onClick(); tree = render()
    local oldChoice = find(tree, "ComboBox")[3].params.onValueChange
    submit(gui, event, 20, 10); poll(); tree = render(); equal(#find(tree, "ComboBox"), 2)
    oldChoice("corridor_distance"); tree = render(); equal(#find(tree, "ComboBox"), 2)
    untilState(completed); poll(); tree = render()
    local summary = gui:get().request.preview
    equal(summary.requestId, 2); equal(summary.source.id, 20); equal(summary.destination.id, 10)
    local selected = find(tree, "ComboBox")[3].params.value
    oldChoice("nonexistent"); tree = render(); equal(find(tree, "ComboBox")[3].params.value, selected)
    equal(logCount("PANEL_SUMMARY"), 2); equal(logCount("REQUEST_START"), 2)
end)

test("world changes, reload and Refresh clear summaries through existing lifecycle", function()
    for _, mode in ipairs({"world", "reload", "refresh"}) do
        local gui, step, untilState, event, callbacks = newSession(); ready(step, untilState)
        submit(gui, event); untilState(completed)
        local render, poll, tree, controls = mountUI(); controls.launcher.params.onClick(); tree = render()
        equal(#find(tree, "ComboBox"), 3)
        if mode == "world" then worldId = 100
        elseif mode == "reload" then callbacks.guiHandleEvent(nil, nil, gui, "test", "gameUI", "reactPostInit", {})
        else find(tree, "Button", "Refresh towns")[1].params.onClick(); render() end
        poll(); tree = render(); equal(#find(tree, "ComboBox"), 2)
        equal(gui:get().request, nil); equal(logCount("REQUEST_START"), 1)
    end
end)

test("reopen waits for fresh response and unmounted callbacks cannot restore a summary", function()
    local gui, step, untilState, event = newSession(); ready(step, untilState)
    submit(gui, event); untilState(completed)
    local render, poll, tree, controls = mountUI(); controls.launcher.params.onClick(); tree = render()
    local oldChoice = find(tree, "ComboBox")[3].params.onValueChange
    controls.panel.params.onClose(); render(); equal(controls.panel, nil)
    controls.autoJoin = false; controls.launcher.params.onClick(); tree = render()
    equal(#find(tree, "ComboBox"), 2)
    oldChoice("corridor_distance"); equal(#find(render(), "ComboBox"), 2)
    controls.flush(); tree = render(); equal(#find(tree, "ComboBox"), 3)
    controls.unmountLauncher(); render(); equal(controls.panel, nil)
    equal(logCount("REQUEST_START"), 1)
end)

test("malformed preview pauses polling and explicit refresh recovers without stale data", function()
    local gui, step, untilState, event = newSession(); ready(step, untilState)
    submit(gui, event); untilState(completed)
    local render, poll, tree, controls = mountUI(); controls.launcher.params.onClick(); tree = render()
    controls.resultFilter = function(value) value.preview = {kind = "panel_summary"}; return value end
    poll(); tree = render(); equal(#find(tree, "ComboBox"), 2)
    assert(panelText(tree):find("invalid corridor summary", 1, true))
    local count = #controls.events; for _ = 1, 10 do poll(); render() end; equal(#controls.events, count)
    controls.resultFilter = nil
    find(tree, "Button", "Refresh towns")[1].params.onClick(); render()
    untilState(function(s) return s.status == "idle" end); poll(); tree = render()
    equal(#find(tree, "ComboBox"), 2); equal(logCount("REQUEST_START"), 1)
end)

test("consumed rejected click token cannot expose summary under a different request ID", function()
    local gui, step, untilState, event = newSession(); ready(step, untilState)
    submit(gui, event); untilState(completed); assert(event("status").preview)
    local rejected = submit(gui, event, 10, 10)
    equal(rejected.reason, "same_town"); equal(rejected.preview, nil)
    equal(gui:get().request.preview.requestId, 1); equal(rejected.requestId, 2)
    local render, poll, tree, controls = mountUI(); controls.launcher.params.onClick(); tree = render()
    equal(#find(tree, "ComboBox"), 2); equal(logCount("UI_ERROR"), 0)
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
local function analyze(gui, event)
    local s = gui:get()
    return event("analyzeNetwork", {world = s.world, epoch = s.epoch, requestId = s.networkRequestId + 1})
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
    local combos = find(tree, "ComboBox")
    combos[1].params.onValueChange("1"); combos[2].params.onValueChange("2"); tree = render()
    local button = find(tree, "Button", "Analyze Network")[1]
    assert(button.params.meta.enabled); button.params.onClick(); button.params.onClick(); tree = render()
    equal(gui:get().networkRequestId, 1); equal(find(tree, "Button", "Plan")[1].params.meta.enabled, false)
    untilState(networkDone); poll(); tree = render()
    combos = find(tree, "ComboBox"); equal(#combos, 3)
    equal(combos[1].params.value, "1"); equal(combos[2].params.value, "2")
    equal(combos[3].params.value, gui:get().network.summary.links[1].id)
    local last = gui:get().network.summary.links[#gui:get().network.summary.links]
    combos[3].params.onValueChange(last.id); tree = render()
    equal(find(tree, "ComboBox")[3].params.value, last.id)
    equal(heightReads, 0); equal(logCount("START world="), 1)
    assert(controls.events[#controls.events].name:find("status", 1, true))
end)

test("network: refresh, transport failure and close/reopen do not restore stale summaries", function()
    local gui, _, _, event = runNetwork(3)
    local render, poll, tree, controls = mountUI()
    find(tree, "Button", "Railway Network Architect")[1].params.onClick(); tree = render()
    equal(#find(tree, "ComboBox"), 3)
    controls.resultFilter = function() return nil end; poll(); tree = render()
    equal(#find(tree, "ComboBox"), 2)
    controls.resultFilter = nil
    find(tree, "Button", "Refresh towns")[1].params.onClick(); tree = render()
    equal(gui:get().network, nil); equal(#find(tree, "ComboBox"), 2)
    controls.panel.params.onClose(); tree = render()
    find(tree, "Button", "Railway Network Architect")[1].params.onClick(); tree = render()
    equal(#find(tree, "ComboBox"), 2); equal(event("status").networkSummary, nil)
end)

test("network: malformed response stops polling and stale link callbacks are ignored", function()
    local gui, _, _, event = runNetwork(3)
    local render, poll, tree, controls = mountUI()
    find(tree, "Button", "Railway Network Architect")[1].params.onClick(); tree = render()
    local oldChoice = find(tree, "ComboBox")[3].params.onValueChange
    controls.resultFilter = function(value) value.networkSummary = {epoch = -1}; return value end
    poll(); tree = render(); local count = #controls.events; poll(); poll()
    equal(#controls.events, count); equal(#find(tree, "ComboBox"), 2)
    oldChoice("1:2"); tree = render(); equal(#find(tree, "ComboBox"), 2)
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
    local combos = find(tree, "ComboBox")
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
    equal(find(tree, "ComboBox")[1].params.value, "3"); equal(find(tree, "ComboBox")[2].params.value, "2")
    assert(panelText(tree):find("branch #1 -> #4", 1, true)); assert(panelText(tree):find("economic feasibility unverified", 1, true))
    local before = heightReads
    find(tree, "ComboBox")[3].params.onValueChange(gui:get().request.preview.candidates[1].id)
    render(); poll(); equal(heightReads, before)
end)

test("handoff: deferred selection, empty results and expired snapshots disable Study Corridor", function()
    local gui, _, _, event = runNetwork(5)
    local render, poll, tree, controls = mountUI(); controls.launcher.params.onClick(); tree = render()
    find(tree, "ComboBox")[3].params.onValueChange("1:5"); tree = render()
    local button = find(tree, "Button", "Study Corridor")[1]
    equal(button.params.meta.enabled, false); button.params.onClick(); render(); equal(gui:get().request, nil)
    find(tree, "ComboBox")[3].params.onValueChange("1:2"); tree = render()
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

print("PASS " .. passed .. " live planning/UI tests (mocked engine and React, not TF3 runtime verification)")
