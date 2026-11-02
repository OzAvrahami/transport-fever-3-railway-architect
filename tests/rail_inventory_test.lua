-- Synthetic Lua data and API mocks only: these tests do not prove TF3 runtime behavior.
local content = ROOT .. "/oz_railway_network_architect/content/"
local inventory = dofile(content .. "rail_inventory_data.lua")
local passed = 0
local function test(name, run)
    local ok, reason = pcall(run)
    assert(ok, name .. ": " .. tostring(reason))
    passed = passed + 1
    print("PASS " .. name)
end
local function equal(actual, expected)
    assert(actual == expected, "expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function node(id)
    return {id = id, available = true, position = {x = id * 10, y = 0, z = -2}}
end
local function edge(id, a, b)
    return {id = id, isTrack = true, node0 = a, node1 = b,
        position0 = node(a).position, position1 = node(b).position, template = "test_track"}
end
local function graph(edges, nodes, map)
    if not map then
        map = {}
        for _, e in ipairs(edges) do
            for _, id in ipairs({e.node0, e.node1}) do
                map[id] = map[id] or {}
                map[id][#map[id] + 1] = e.id
            end
        end
    end
    return inventory.normalize(inventory.discover(map), edges, nodes)
end

test("empty graph and empty non-track node arrays", function()
    local r = graph({}, {}, {[99] = {}})
    equal(#r.segments, 0); equal(#r.nodes, 0); equal(r.components, 0)
    equal(r.status, "ok"); equal(r.complete, true); equal(r.rejected, 0)
end)
test("single segment and zero/negative coordinates", function()
    local r = graph({edge(10, 1, 2)}, {node(2), node(1)})
    equal(#r.segments, 1); equal(#r.nodes, 2); equal(r.endpoints, 2)
    equal(r.components, 1); equal(r.chordTotal, 10); equal(r.nodes[1].position.y, 0)
    equal(r.nodes[1].position.z, -2); equal(r.status, "ok")
end)
test("linear track sorts records and adjacency", function()
    local r = graph({edge(20, 2, 3), edge(10, 1, 2)}, {node(3), node(1), node(2)})
    equal(r.segments[1].id, 10); equal(r.nodes[1].id, 1)
    equal(r.adjacency[2][1].segment, 10); equal(r.adjacency[2][2].segment, 20)
    equal(r.endpoints, 2); equal(r.multiSegmentNodes, 1); equal(r.junctionCandidates, 0)
end)
test("branch is a candidate junction", function()
    local r = graph({edge(10, 1, 2), edge(20, 2, 3), edge(30, 2, 4)},
        {node(1), node(2), node(3), node(4)})
    equal(r.junctionCandidates, 1); equal(r.endpoints, 3); equal(r.components, 1)
    equal(#r.adjacency[2], 3)
end)
test("duplicate references are deduplicated without degrading success", function()
    local d = inventory.discover({[2] = {10, 10}, [1] = {10, 10}})
    equal(d.references, 4); equal(d.duplicates, 3); equal(#d.edgeIds, 1)
    local r = inventory.normalize(d, {edge(10, 1, 2)}, {node(1), node(2)})
    equal(#r.segments, 1); equal(r.duplicates, 3); equal(r.status, "ok")
end)
test("missing node produces partial graph without invented incidence", function()
    local r = graph({edge(10, 1, 2)}, {node(1), {id = 2, available = false, error = "gone"}})
    equal(#r.segments, 1); equal(#r.nodes, 1); equal(r.graphSegments, 0)
    equal(r.missingNodeIds[1], 2); equal(r.isolatedNodes, 1); equal(r.incomplete, 2)
    equal(r.status, "partial"); equal(#r.adjacency[1], 0)
end)
test("disconnected components", function()
    local r = graph({edge(10, 1, 2), edge(20, 3, 4)}, {node(1), node(2), node(3), node(4)})
    equal(r.components, 2); equal(r.endpoints, 4); equal(r.status, "ok")
end)
test("missing/nonfinite geometry is not zero; topology survives", function()
    local e, n = edge(10, 1, 2), node(1)
    e.position0.x, e.template, n.position.z = 0/0, nil, math.huge
    local r = graph({e}, {n, node(2)})
    equal(r.segments[1].position0, nil); equal(r.nodes[1].position, nil)
    equal(r.chordSegments, 0); equal(r.graphSegments, 1); equal(r.status, "partial")
end)
test("invalid references and non-track records rejected", function()
    local e = edge(10, 1, 2); e.isTrack = false
    local r = graph({e}, {node(1), node(2)}, {[1] = {10, -1, "bad"}, [2] = {10}})
    equal(#r.segments, 0); equal(r.rejected, 3); equal(r.status, "partial")
end)
test("self-loop counts one distinct incident segment", function()
    local r = graph({edge(10, 1, 1)}, {node(1)})
    equal(r.selfLoops, 1); equal(r.nodes[1].degree, 1); equal(r.chordTotal, 0)
end)
test("node requests include verified endpoints omitted from index", function()
    local ids = inventory.nodeIds(inventory.discover({[1] = {10}}), {edge(10, 1, 2)})
    equal(#ids, 2); equal(ids[2], 2)
end)
test("malformed enumeration and size limits abort instead of truncating", function()
    equal(pcall(inventory.discover, nil), false)
    equal(pcall(inventory.discover, {[1] = 10}), false)
    local limit = inventory.MAX_SEGMENTS
    inventory.MAX_SEGMENTS = 1
    local ok = pcall(inventory.discover, {[1] = {10, 20}})
    inventory.MAX_SEGMENTS = limit
    equal(ok, false)
end)
test("diagnostics bounded to four examples", function()
    local nodes = {}
    for id = 1, 10 do nodes[id] = {id = id, available = false, error = "missing"} end
    local r = graph({}, nodes)
    equal(#r.diagnostics, 4); equal(r.diagnosticCount, 10)
end)

-- API mocks deliberately implement only the documented read surface.
local tick, reads, mapCalls, logs = 1, 0, 0, {}
local index, components = {}, {}
local readiness = {world = function() return {id = 99, tick = tick} end, seconds = function() return 1 end}
api = {engine = {util = {getWorld = function() return 99 end}, system = {streetSystem = {}},
    entityExists = function(id) reads = reads + 1; return components[id] ~= nil end,
    getComponent = function(id, kind) reads = reads + 1; return components[id] and components[id][kind] end},
    type = {ComponentType = {BASE_EDGE = "edge", BASE_NODE = "node", GAME_TIME = "time"},
        ["enum"] = {RoadType = {TRACK = "track", STREET = "street"}}}}
api.engine.system.streetSystem.getNode2TrackEdgeMap = function() mapCalls = mapCalls + 1; return index end
local adapter
ug_require = function(path)
    if path:find("city_inventory_api", 1, true) then return readiness end
    if path:find("rail_inventory_data", 1, true) then return inventory end
    if path:find("rail_inventory_api", 1, true) then return adapter end
    error("unexpected import: " .. path)
end
adapter = dofile(content .. "rail_inventory_api.lua")
test("adapter uses documented track enum and copies native fields", function()
    equal(adapter.check(), nil)
    components[10] = {edge = {roadType = "track", node0 = 1, node1 = 2,
        position0 = node(1).position, position1 = node(2).position, roadTemplate = "test_track"}}
    components[1] = {node = {position = node(1).position}}
    equal(adapter.edge(10).template, "test_track"); equal(adapter.node(1).position.y, 0)
    components[10].edge.roadType = "street"
    equal(adapter.edge(10).isTrack, false)
end)
test("capability checks accept present bindings without function-type restriction", function()
    local original = api.engine.getComponent
    api.engine.getComponent = {}
    equal(adapter.check(), nil)
    local record = adapter.edge(10)
    assert(record.error:find("api.engine.getComponent(10, BASE_EDGE)", 1, true))
    assert(record.error:find("call", 1, true))
    api.engine.getComponent = nil
    assert(adapter.check():find("api.engine.getComponent", 1, true))
    api.engine.getComponent = original
end)
test("read errors preserve API path and original message", function()
    local original = api.engine.getComponent
    api.engine.getComponent = function() error("synthetic engine failure", 0) end
    equal(adapter.edge(10).error, "api.engine.getComponent(10, BASE_EDGE): synthetic engine failure")
    api.engine.getComponent = original
    local before = reads
    adapter.node(-1); adapter.edge("invalid")
    equal(reads, before)
end)

debugPrint = function(message) logs[#logs + 1] = message end
dofile(content .. "rail_inventory.script.lua")
local callback = data().guiUpdate
local function state()
    local value
    return {get = function() return value end, set = function(_, v) value = v end}
end
local function advance(gui, count)
    for _ = 1, count do callback(nil, nil, gui) end
end
test("empty lifecycle waits for tick advance and finishes once; new GUI session rescans", function()
    index, components, mapCalls, tick, logs = {}, {}, 0, 1, {}
    local gui = state()
    advance(gui, 60); equal(mapCalls, 0)
    tick = 2; advance(gui, 60)
    equal(mapCalls, 1); equal(gui:get().rail.status, "ok"); equal(#gui:get().rail.nodes, 0)
    advance(gui, 120); equal(mapCalls, 1)
    local reloaded = state()
    advance(reloaded, 1); tick = 3; advance(reloaded, 60)
    equal(mapCalls, 2); equal(reloaded:get().rail.status, "ok")
end)
test("component reads are batched and graph stays incomplete until finalization", function()
    index, components, reads, tick = {}, {}, 0, 10
    for id = 1, 66 do components[id] = {node = {position = node(id).position}} end
    for id = 1, 65 do
        local entity = 1000 + id
        index[id] = {entity}
        components[entity] = {edge = {node0 = id, node1 = id + 1, roadType = "track",
            position0 = node(id).position, position1 = node(id + 1).position, roadTemplate = "test_track"}}
    end
    local gui = state(); advance(gui, 1); tick = 11; advance(gui, 29)
    equal(gui:get().rail.complete, false); equal(reads, 0)
    advance(gui, 3); equal(reads, 0)
    advance(gui, 1); equal(reads, 64); equal(gui:get().rail.complete, false)
    advance(gui, 60)
    equal(gui:get().rail.complete, true); equal(#gui:get().rail.segments, 65)
    equal(#gui:get().rail.nodes, 66); equal(gui:get().rail.endpoints, 2)
    equal(gui:get().rawEdges, nil)
end)
test("world time reversal aborts once without successful completion", function()
    tick, logs = 20, {}
    local gui = state(); advance(gui, 1); tick = 21; advance(gui, 29)
    tick = 19; advance(gui, 4)
    equal(gui:get().status, "aborted"); equal(gui:get().rail.complete, false)
    local count = #logs; advance(gui, 120); equal(#logs, count)
    for _, message in ipairs(logs) do assert(not message:find("SCAN_COMPLETE", 1, true)) end
end)
test("enumeration failure never becomes an empty-network success", function()
    local original = api.engine.system.streetSystem.getNode2TrackEdgeMap
    api.engine.system.streetSystem.getNode2TrackEdgeMap = function() error("index unavailable", 0) end
    tick, logs = 30, {}
    local gui = state(); advance(gui, 1); tick = 31; advance(gui, 29)
    equal(gui:get().status, "aborted")
    local found = false
    for _, message in ipairs(logs) do
        if message:find("getNode2TrackEdgeMap(): index unavailable", 1, true) then found = true end
        assert(not message:find("SCAN_COMPLETE", 1, true))
    end
    equal(found, true)
    api.engine.system.streetSystem.getNode2TrackEdgeMap = original
end)
print("PASS " .. passed .. " railway tests (synthetic, not TF3 runtime verification)")
