local hierarchy = ug_require "oz_railway_network_architect::/planning/corridor_hierarchy.lua"
local planner = ug_require "oz_railway_network_architect::/planning/corridor_planner.lua"
local passed = 0
local function equal(a, b) assert(a == b, "expected " .. tostring(b) .. ", got " .. tostring(a)) end
local function test(name, fn)
    local ok, message = pcall(fn); assert(ok, name .. ": " .. tostring(message))
    passed = passed + 1; print("PASS hierarchy: " .. name)
end
local function serialize(v)
    if type(v) ~= "table" then return tostring(v) end
    local keys, parts = {}, {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for _, k in ipairs(keys) do parts[#parts + 1] = tostring(k) .. "=" .. serialize(v[k]) end
    return "{" .. table.concat(parts, ",") .. "}"
end
local function clone(v)
    if type(v) ~= "table" then assert(type(v) ~= "function" and type(v) ~= "thread" and type(v) ~= "userdata"); return v end
    equal(getmetatable(v), nil)
    local t = {}; for k, value in pairs(v) do t[k] = clone(value) end; return t
end
local bounds = {minX = -1024, maxX = 17408, minY = -2048, maxY = 2048}
local function pair(length, offsetX, offsetY)
    return {start = {id = 10, x = offsetX or 0, y = offsetY or 0},
        destination = {id = 20, x = (offsetX or 0) + length, y = offsetY or 0}}
end
local function flat() return {valid = true, height = -2, water = false} end
local function run(p, b, read, options, copyAt)
    local job = hierarchy.start(p, b, options)
    local calls, ticks = 0, 0
    while not job.finished do
        local before, expansions = calls, job.expansions
        hierarchy.step(job, function(x, y)
            calls = calls + 1
            assert(x > b.minX and x < b.maxX and y > b.minY and y < b.maxY)
            return (read or flat)(x, y)
        end)
        assert(calls - before <= 16); assert(job.expansions - expansions <= 64)
        ticks = ticks + 1; assert(ticks < 12000, "test continuation stalled")
        if copyAt == "each" or ticks == copyAt then job = clone(job) end
    end
    equal(job.cache, nil); equal(job.job, nil)
    return job.result, job, ticks
end
local function continuous(result, p)
    assert(#result.candidates > 0, result.reason)
    for _, c in ipairs(result.candidates) do
        equal(c.sourceId, p.start.id); equal(c.destinationId, p.destination.id)
        equal(c.constructionStatus, "unverified"); equal(c.searchStatus, "complete")
        equal(c.waypoints[1].x, c.endpoints.start.x); equal(c.waypoints[#c.waypoints].x, c.endpoints.destination.x)
        local length, gain, loss, grade = 0, 0, 0, 0
        local seen = {}
        for index, point in ipairs(c.waypoints) do
            local key = point.x .. ":" .. point.y; assert(not seen[key]); seen[key] = true
            if index > 1 then
                local a = c.waypoints[index - 1]
                local dx, dy, dz = math.abs(point.x - a.x), math.abs(point.y - a.y), point.z - a.z
                assert((dx == 0 or dx == 64) and (dy == 0 or dy == 64) and dx + dy > 0)
                local distance = math.sqrt(dx * dx + dy * dy)
                length = length + math.sqrt(distance * distance + dz * dz)
                gain, loss, grade = gain + math.max(0, dz), loss + math.max(0, -dz), math.max(grade, math.abs(dz) / distance)
            end
        end
        assert(math.abs(c.length - length) < 1e-6)
        equal(c.elevationGain, gain); equal(c.elevationLoss, loss); equal(c.maxGradient, grade)
        equal(c.score.total, c.score.distance + c.score.gradient + c.score.waterObstacle)
        assert(c.refinedSections > 1)
    end
end

test("resumable core preserves synchronous result and deterministic ties", function()
    local input = {start = {x = 0, y = 0}, destination = {x = 70, y = 70},
        grid = {columns = 8, rows = 8, originX = 0, originY = 0, spacingX = 10, spacingY = 10, unit = "world_units", cells = {}}}
    for i = 1, 64 do input.grid.cells[i] = {height = i % 5, water = false} end
    local expected = planner.plan(input)
    local job = planner.start(input)
    while not job.finished do planner.step(job, 1); job = clone(job) end
    equal(serialize(job.result), serialize(expected))
end)

test("Morley-Winterton recorded offsets refine at 64 units with explicit snaps", function()
    local p = {start = {id = 10, x = -804, y = -624}, destination = {id = 20, x = 3676, y = -1268}}
    local b = {minX = -4096, maxX = 4096, minY = -2048, maxY = 2048}
    local result = run(p, b); equal(result.status, "ok"); continuous(result, p)
    assert(result.candidates[1].endpoints.start.distance <= 96)
    assert(result.candidates[1].endpoints.destination.distance <= 96)
end)

test("8000 and 16000 unit routes remain continuous within sampling and expansion bounds", function()
    for _, length in ipairs({8192, 16000}) do
        local p = pair(length); local result, job, ticks = run(p, bounds)
        equal(result.status, "ok"); continuous(result, p)
        assert(result.stats.samples <= 32768); assert(result.stats.expansions <= 49152)
        equal(result.candidates[1].sampling.fineSpacing, 64)
        print("HIERARCHY_BENCH length=" .. length .. " samples=" .. result.stats.samples
            .. " expansions=" .. result.stats.expansions .. " steps=" .. ticks)
    end
end)

test("rectangular offset map uses world coordinates without origin assumptions", function()
    local p = pair(8192, 100000, -50000)
    local b = {minX = 99500.25, maxX = 109000.75, minY = -51000.5, maxY = -49000.25}
    local result = run(p, b); equal(result.status, "ok"); continuous(result, p)
end)

test("mountain barrier and valley gap produce a real detour", function()
    local p = pair(8192)
    local function terrain(x, y)
        return {valid = true, water = false, height = (x >= 3584 and x <= 4608 and y < 1024) and 1000 or 0}
    end
    local result = run(p, bounds, terrain, {constraints = {waterPolicy = "exclude", maxGradient = 0.1}})
    continuous(result, p)
    local detour = false
    for _, point in ipairs(result.candidates[1].waypoints) do if point.y >= 1024 then detour = true end end
    equal(detour, true); assert(result.candidates[1].maxGradient <= 0.1)
end)

test("water exclusion detours through gap; complete barrier yields no fabricated route", function()
    local p = pair(8192)
    for _, gap in ipairs({true, false}) do
        local result = run(p, bounds, function(x, y)
            return {valid = true, height = 0, water = x >= 3584 and x <= 4608 and (not gap or y < 1024)}
        end)
        if gap then continuous(result, p); equal(result.candidates[1].touchesWater, false)
        else equal(result.status, "unreachable"); equal(#result.candidates, 0) end
    end
end)

test("configured water penalty retains exposure and does not assert a bridge", function()
    local p = pair(8192)
    local result = run(p, bounds, function(x) return {valid = true, height = 0, water = x >= 3584 and x <= 4608} end,
        {constraints = {waterPolicy = "penalize"}})
    continuous(result, p); equal(result.candidates[1].touchesWater, true)
    assert(result.candidates[1].waterExposure > 0); assert(result.candidates[1].score.waterObstacle > 0)
end)

test("coarse guide crossing an unseen fine water barrier is rejected", function()
    local p = pair(8192)
    local result = run(p, bounds, function(x)
        return {valid = true, height = 0, water = x == 3904} -- not on coarse 512 lattice
    end)
    equal(result.status, "unreachable"); equal(#result.candidates, 0)
    equal(result.reason, "all_coarse_guides_failed_refinement")
end)

test("missing heights and read failures remain unknown, never zero", function()
    local p = pair(8192)
    local result, job = run(p, bounds, function(x, y)
        if x == 3904 then return {valid = true, water = false} end
        if x == -512 and y == -1536 then error("synthetic terrain failure") end
        return flat()
    end)
    assert(result.unknownCells > 0); equal(#result.candidates, 0)
    assert(#job.examples > 0 and #job.examples <= 4)
end)

test("overlapping sections query each coordinate once and validate joins", function()
    local seen, p = {}, pair(8192)
    local result = run(p, bounds, function(x, y)
        local k = x .. ":" .. y; assert(not seen[k]); seen[k] = true
        return {valid = true, height = x / 1000 + y / 2000, water = false}
    end)
    continuous(result, p); assert(result.candidates[1].refinedSections >= 16)
    assert(result.candidates[1].elevationGain > 0)
end)

test("repeated planning and plain-state continuation are deterministic; alternatives deduplicate", function()
    local p = pair(8192)
    local a = run(p, bounds); local b = run(p, bounds, nil, nil, "each")
    equal(serialize(a), serialize(b)); equal(#a.candidates, 1)
end)

test("cancellation clears partial data and cannot produce a completed corridor", function()
    local job = hierarchy.start(pair(8192), bounds)
    for _ = 1, 30 do hierarchy.step(job, flat) end
    hierarchy.cancel(job, "world_changed")
    equal(job.finished, true); equal(job.result.status, "invalidated"); equal(job.cache, nil)
    equal(#job.result.candidates, 0)
    hierarchy.step(job, function() error("read after cancellation") end)
end)

test("sample, visit, search, section, waypoint and coverage limits are explicit", function()
    for _, setting in ipairs({{maxSamples = 4}, {maxVisits = 4}, {maxExpansions = 1}, {maxSections = 1}, {maxWaypoints = 2}}) do
        local result = run(pair(8192), bounds, nil, setting)
        assert(result.status == "resource_limit" or result.status == "search_limit", result.status)
        equal(#result.candidates, 0)
    end
    local result = run(pair(40000), {minX = -100000, maxX = 100000, minY = -2048, maxY = 2048})
    equal(result.status, "unsupported"); equal(result.reason, "coarse_map_coverage_limit")
end)

test("invalid endpoints, data, configuration and identical anchors fail safely", function()
    for _, setting in ipairs({{maxSamples = math.huge}, {fineSpacing = 128}, {unknown = true}}) do
        equal(run(pair(8192), bounds, nil, setting).status, "invalid_input")
    end
    equal(run(pair(0), bounds).status, "unsupported")
    local result = run(pair(8192), bounds, function() return {valid = true, height = 0/0, water = false} end)
    equal(#result.candidates, 0); assert(result.unknownCells > 0)
    equal(run(pair(8192), bounds, nil, {constraints = {maxGradient = -1}}).status, "invalid_input")
end)
test("distinct coarse guides remain distinct complete alternatives under common ranking", function()
    local p = pair(8192)
    local result = run(p, bounds, function(x, y)
        return {valid = true, water = false, height = (x >= 3584 and x <= 4608 and math.abs(y) < 1024) and 600 or 0}
    end)
    continuous(result, p); assert(#result.candidates >= 2)
    for i = 2, #result.candidates do assert(result.candidates[i - 1].score.total <= result.candidates[i].score.total) end
end)

test("large map only samples a bounded coarse neighborhood and fine corridor", function()
    local p = pair(8192)
    local result = run(p, {minX = -100000, maxX = 100000, minY = -100000, maxY = 100000})
    continuous(result, p); equal(result.status, "ok")
    assert(result.sampling.region.minX >= -2048 and result.sampling.region.maxX <= 10240)
    assert(result.stats.samples < 10000)
end)

test("policy validation precedes sampling and gradient-only configuration keeps water excluded", function()
    local queried = 0
    local function read() queried = queried + 1; return flat() end
    equal(run(pair(8192), bounds, read, {constraints = {maxGradient = -1}}).status, "invalid_input")
    equal(queried, 0)
    local result = run(pair(8192), bounds, function(x)
        return {valid = true, height = 0, water = x >= 3584 and x <= 4608}
    end, {constraints = {maxGradient = 0.1}})
    equal(result.status, "unreachable"); equal(#result.candidates, 0)
    equal(run(pair(8192), bounds, nil, {maxSnap = 0, maxRelativeSnap = 0}).status, "ok")
end)

test("late cancellation discards a finished result before request publication", function()
    local result, job = run(pair(8192), bounds); assert(#result.candidates > 0)
    hierarchy.cancel(job, "world_changed_after_last_work_slice")
    equal(job.result.status, "invalidated"); equal(#job.result.candidates, 0)
end)

test("unknown off-route samples yield explicit incomplete data with verified continuous candidates", function()
    local p = pair(8192)
    local result = run(p, bounds, function(x, y)
        if x == 0 and y == 1536 then return {valid = true, water = false} end
        return flat()
    end)
    equal(result.status, "incomplete"); equal(result.complete, false)
    assert(result.unknownCells > 0); continuous(result, p)
    for _, c in ipairs(result.candidates) do for _, point in ipairs(c.waypoints) do equal(point.z, -2) end end
end)

test("one wider refinement window recovers a local detour missed by the coarse guide", function()
    local wideSample = false
    local p = pair(8192)
    local result = run(p, bounds, function(x, y)
        if x == 256 and y == 512 then wideSample = true end
        return {valid = true, height = 0, water = x == 256 and math.abs(y) <= 320}
    end)
    equal(result.status, "ok"); continuous(result, p); equal(wideSample, true)
    equal(result.candidates[1].touchesWater, false); assert(result.candidates[1].length > 8192)
end)

print("PASS " .. passed .. " hierarchical planner tests (synthetic only)")
