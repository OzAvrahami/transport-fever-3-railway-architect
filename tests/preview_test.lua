-- Pure presentation gate tests: no engine, renderer or filesystem dependency.
local preview = ug_require "oz_railway_network_architect::/live_plan_preview.lua"
local planner = ug_require "oz_railway_network_architect::/planning/corridor_planner.lua"
local fixtures = require "tests.corridor_fixtures"
local passed = 0
local function equal(a, b) assert(a == b, tostring(a) .. " ~= " .. tostring(b)) end
local function test(name, fn)
    local ok, reason = pcall(fn); assert(ok, name .. ": " .. tostring(reason))
    passed = passed + 1; print("PASS preview: " .. name)
end
local function fixture()
    local input = fixtures.comparison()
    input.grid.unit, input.grid.spacingX, input.grid.spacingY = "world_units", 32, 32
    input.grid.originX, input.grid.originY = -1000.3, 800.7
    for _, role in ipairs({"start", "destination"}) do
        input[role].x = input.grid.originX + input[role].x * 3.2
        input[role].y = input.grid.originY + input[role].y * 3.2
    end
    for _, cell in ipairs(input.grid.cells) do cell.height = cell.height * 3.2 - 2 end
    local result = planner.plan(input)
    equal(result.status, "ok"); equal(#result.candidates, 3)
    result.snapshot = {world = 99}
    local pair = {start = {id = 10, name = "Twin", x = input.start.x, y = input.start.y},
        destination = {id = 20, name = "Twin", x = input.destination.x, y = input.destination.y}}
    for _, c in ipairs(result.candidates) do
        c.sourceId, c.destinationId, c.refinedSections, c.searchStatus = 10, 20, 1, "complete"
        c.sampling = {fineSpacing = 32}
        c.endpoints = {start = {x = input.start.x, y = input.start.y, distance = 0},
            destination = {x = input.destination.x, y = input.destination.y, distance = 0}}
    end
    return {world = 99, epoch = 1, requestId = 3, status = "ok", request = {
        world = 99, requestId = 3, status = "ok", finished = true, sourceId = 10, destinationId = 20,
        pair = pair, result = result}}
end

test("complete canonical alternatives retain rank, world coordinates and unverified semantics", function()
    local state = fixture(); local value = assert(preview.build(state))
    equal(#value.candidates, 3); equal(preview.valid(value, state), true)
    equal(value.source.id, 10); equal(value.destination.id, 20)
    equal(value.source.name, value.destination.name)
    for i, c in ipairs(value.candidates) do
        local original = state.request.result.candidates[i]
        equal(c.start.x, original.waypoints[1].x); equal(c.start.z, -2)
        equal(c.destination.y, original.waypoints[#original.waypoints].y)
        equal(c.length, original.length); equal(c.score.total, original.score.total)
        equal(c.waypoints, nil); equal(c.sections, 1); equal(c.rank, i)
        local lines = table.concat(preview.lines(value, c.id), "\n")
        assert(lines:find("Construction feasibility: unverified", 1, true))
        assert(lines:find("No path is drawn", 1, true)); assert(lines:find("Twin [#10]", 1, true))
        assert(lines:find("Twin [#20]", 1, true))
    end
end)
test("unfinished, unsupported, unreachable, budget-limited and invalidated requests have no summary", function()
    for _, status in ipairs({"planning", "unsupported", "unreachable", "search_limit", "resource_limit", "invalidated", "error", "incomplete"}) do
        local state = fixture(); state.status, state.request.status = status, status
        equal(preview.build(state), nil)
    end
    local state = fixture(); state.request.finished = false; equal(preview.build(state), nil)
    state = fixture(); state.request.result.complete = false; equal(preview.build(state), nil)
    state = fixture(); state.request.result.candidates = {}; equal(preview.build(state), nil)
end)
test("invalid geometry, discontinuity, wrong endpoints and partial sections are rejected", function()
    for _, damage in ipairs({
        function(c) c.waypoints[2].x = c.waypoints[2].x + 500 end,
        function(c) c.waypoints[2].z = 0/0 end,
        function(c) c.waypoints[2].water = nil end,
        function(c) c.endpoints.destination.x = 123 end,
        function(c) c.searchStatus = "refining" end,
        function(c) c.sourceId = 21 end,
        function(c) c.constructionStatus = "buildable" end,
    }) do
        local state = fixture(); damage(state.request.result.candidates[1]); equal(preview.build(state), nil)
    end
end)
test("response identities, duplicate alternatives and malformed metadata cannot restore old summaries", function()
    local state = fixture(); local value = assert(preview.build(state))
    for _, key in ipairs({"epoch", "world", "requestId"}) do
        state[key] = state[key] + 1; equal(preview.valid(value, state), false); state[key] = state[key] - 1
    end
    value.candidates[2].id = value.candidates[1].id; equal(preview.valid(value, state), false)
    value = assert(preview.build(state)); value.candidates[1].score.total = 0/0; equal(preview.valid(value, state), false)
    value = assert(preview.build(state)); value.candidates[1].waypointCount = 4097; equal(preview.valid(value, state), false)
    value = assert(preview.build(state)); value.candidates[1].profile = string.rep("x", 101); equal(preview.valid(value, state), false)
end)
test("oversized or sparse result arrays are rejected without publishing a truncated route", function()
    local state = fixture(); state.request.result.candidates[4] = state.request.result.candidates[1]
    equal(preview.build(state), nil)
    state = fixture(); state.request.result.candidates[2] = nil; equal(preview.build(state), nil)
    state = fixture(); state.request.result.candidates[1].waypoints[4097] = {x = 0, y = 0, z = 0, water = false}
    equal(preview.build(state), nil)
end)
test("compact payload is independent of original geometry; formatting performs no engine operations", function()
    local state = fixture(); local value = assert(preview.build(state))
    state.request.result.candidates[1].waypoints[1].x = 123
    assert(value.candidates[1].start.x ~= 123)
    local old = api
    api = setmetatable({}, {__index = function() error("unexpected engine/GUI operation") end})
    for _ = 1, 20 do for _, c in ipairs(value.candidates) do equal(#preview.lines(value, c.id), 10) end end
    api = old
    equal(#preview.lines(nil, ""), 1)
end)
print("PASS " .. passed .. " preview summary tests (no map rendering claim)")
