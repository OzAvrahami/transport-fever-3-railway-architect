-- One explicit request, advanced only by the existing GUI Game Script owner.
local apiRead = ug_require "oz_railway_network_architect::/network_live_api.lua"
local rail = ug_require "oz_railway_network_architect::/rail_inventory_api.lua"
local railData = ug_require "oz_railway_network_architect::/rail_inventory_data.lua"
local data = ug_require "oz_railway_network_architect::/network_live_data.lua"
local flow = ug_require "oz_railway_network_architect::/live_plan_data.lua"
local planner = ug_require "oz_railway_network_architect::/planning/network_planner.lua"
local request = {}
local function log(r, text) debugPrint("[RNA:NETWORK:5B1] request=" .. r.id .. " " .. text) end
local function warning(r, reason)
    r.warningCount = r.warningCount + 1
    local detail = data.text(reason)
    for _, previous in ipairs(r.warnings) do if previous == detail then return end end
    if #r.warnings < 4 then r.warnings[#r.warnings + 1] = detail; log(r, "READ_WARNING " .. detail) end
end
local function finish(r, status, reason)
    r.finished, r.status, r.message = true, status, reason
    r.ids, r.industryIds, r.rawIndustries, r.discovery, r.edges, r.nodes, r.nodeIds, r.input = nil, nil, nil, nil, nil, nil, nil, nil
    if status ~= "ok" then r.result, r.summary, r.snapshot = nil, nil, nil end
    log(r, "COMPLETE status=" .. status .. " reason=" .. data.text(reason)
        .. " max_work_seconds=" .. string.format("%.6f", r.maxWork or 0) .. " timing_resolution=unverified")
end
function request.invalidate(r, reason) finish(r, "invalidated", reason) end
function request.start(world, epoch, id)
    local r = {id = id, epoch = epoch, world = world.id, startTick = world.tick, tick = world.tick,
        status = "analyzing", phase = "town_index", cursor = 1, missingCapacity = 0, rejected = 0,
        warnings = {}, warningCount = 0, maxWork = 0, message = "Collecting independent network snapshot..."}
    log(r, "START world=" .. world.id .. " tick=" .. world.tick .. " max_towns=32 max_pairs=496")
    return r
end
local function nextPhase(r, phase)
    r.phase, r.cursor = phase, 1; r.message = "Network analysis: " .. phase:gsub("_", " ")
    log(r, "PROGRESS phase=" .. phase)
end
local function batch(r, ids, size, fn)
    local last = math.min(#ids, r.cursor + size - 1)
    for i = r.cursor, last do fn(ids[i]) end
    r.cursor = last + 1
    return r.cursor > #ids
end
local function work(r)
    if r.phase == "town_index" then
        r.bounds = apiRead.bounds()
        r.ids, r.rejected = apiRead.ids(32)
        r.input = {unit = "world_units", snapshotId = "world:" .. r.world .. ":epoch:" .. r.epoch .. ":network:" .. r.id,
            source = "TOWN / entity_util.getPosition bounding-volume center; not a station", towns = {},
            preferences = {maxTowns = 32, maxPairs = 496}}
        nextPhase(r, "towns")
    elseif r.phase == "towns" then
        if batch(r, r.ids, 4, function(id)
            local raw = apiRead.town(id)
            local t = data.town(raw, r.bounds)
            if raw.error then warning(r, raw.error) end
            if t then
                local reason; t.residentialCapacity, reason = apiRead.capacity(id)
                if reason then r.missingCapacity = r.missingCapacity + 1; warning(r, reason) end
                r.input.towns[#r.input.towns + 1] = t
            else r.rejected = r.rejected + 1 end
        end) then nextPhase(r, "industry_index") end
    elseif r.phase == "industry_index" then
        local ok, ids, rejected = pcall(apiRead.industryIds, 128)
        if ok then
            r.industryIds, r.rawIndustries = ids, {}
            if rejected > 0 then warning(r, "invalid industry IDs rejected: " .. rejected) end
            nextPhase(r, "industries")
        else warning(r, "industries omitted: " .. tostring(ids)); nextPhase(r, "rail_index") end
    elseif r.phase == "industries" then
        if batch(r, r.industryIds, 4, function(id)
            local raw = apiRead.industry(id)
            if raw.error then warning(r, raw.error) end
            r.rawIndustries[#r.rawIndustries + 1] = raw
        end) then
            local missing; r.input.industries, missing = data.industries(r.rawIndustries)
            if missing > 0 then warning(r, "industry position/resource unavailable: " .. missing) end
            r.rawIndustries, r.industryIds = nil, nil
            nextPhase(r, "rail_index")
        end
    elseif r.phase == "rail_index" then
        local ok, d = pcall(rail.discover)
        if ok and #d.edgeIds <= 8192 and #d.nodeIds <= 4096 then
            r.discovery, r.edges, r.nodes = d, {}, {}; nextPhase(r, "rail_edges")
        else warning(r, "rail omitted: " .. (ok and "network rail size limit" or tostring(d))); nextPhase(r, "verify_towns") end
    elseif r.phase == "rail_edges" then
        if batch(r, r.discovery.edgeIds, 16, function(id) r.edges[#r.edges + 1] = rail.edge(id) end) then
            r.nodeIds = railData.nodeIds(r.discovery, r.edges)
            if #r.nodeIds > 4096 then
                warning(r, "rail omitted: network node size limit"); r.discovery, r.edges, r.nodes, r.nodeIds = nil, nil, nil, nil
                nextPhase(r, "verify_towns")
            else nextPhase(r, "rail_nodes") end
        end
    elseif r.phase == "rail_nodes" then
        if batch(r, r.nodeIds, 16, function(id) r.nodes[#r.nodes + 1] = rail.node(id) end) then nextPhase(r, "rail_normalize") end
    elseif r.phase == "rail_normalize" then
        local reason; r.input.rail, reason = data.rail(r.discovery, r.edges, r.nodes)
        if reason then warning(r, reason) end
        r.discovery, r.edges, r.nodes, r.nodeIds = nil, nil, nil, nil
        nextPhase(r, "verify_towns")
    elseif r.phase == "verify_towns" then
        if batch(r, r.input.towns, 4, function(t)
            local raw = apiRead.town(t.id)
            if not flow.sameTown(t, raw) then error("town_anchor_changed_during_snapshot", 0) end
        end) then nextPhase(r, "verify_index") end
    elseif r.phase == "verify_index" then
        local ids = apiRead.ids(32)
        if #ids ~= #r.ids then error("town_index_changed_during_snapshot", 0) end
        for i, id in ipairs(ids) do if id ~= r.ids[i] then error("town_index_changed_during_snapshot", 0) end end
        local bounds = apiRead.bounds()
        for k, v in pairs(r.bounds) do if bounds[k] ~= v then error("map_bounds_changed_during_snapshot", 0) end end
        nextPhase(r, "topology")
    elseif r.phase == "topology" then
        -- Canonical synchronous pure algorithm, deliberately capped at 32/496.
        -- This call is not preemptible; the measured-work guard runs afterward.
        r.result = planner.plan(r.input)
        if r.result.status ~= "ok" then error("network input rejected: " .. r.result.status, 0) end
        r.snapshot = {world = r.world, startTick = r.startTick, endTick = r.tick,
            source = r.input.source, towns = r.input.towns, entityIds = r.ids,
            industrySource = r.input.industries and r.input.industries.source,
            railSource = r.input.rail and r.input.rail.source,
            railNodes = r.input.rail and #r.input.rail.nodes,
            railSegments = r.input.rail and #r.input.rail.segments}
        nextPhase(r, "summary")
    elseif r.phase == "summary" then
        r.summary = data.summary(r)
        log(r, "RESULT towns=" .. #r.result.towns .. " connections=" .. #r.result.recommendations
            .. " pairs=" .. r.result.stats.pairs .. " astar_searches=0")
        r.pendingComplete = true
    end
end
function request.step(r)
    if r.finished then return end
    local began, clockError = apiRead.seconds()
    if not flow.finite(began) then finish(r, "timing_unavailable", clockError or "application clock unavailable"); return end
    r.began = r.began or began
    local world = apiRead.world()
    if flow.worldChanged(r, world) then request.invalidate(r, "world_identity_or_tick_changed"); return end
    r.tick = world.tick
    if began < r.began or began - r.began > 60 then request.invalidate(r, "snapshot_age_or_clock_limit"); return end
    local ok, reason = pcall(work, r)
    local ended, endError = apiRead.seconds()
    if not flow.finite(ended) or ended < began then finish(r, "timing_unavailable", endError or "clock unavailable or reversed"); return end
    r.maxWork = math.max(r.maxWork, ended - began)
    if ended - began > 0.05 then finish(r, "performance_limit", "network_callback_work_budget_exceeded"); return end
    if not ok then
        local detail = tostring(reason)
        finish(r, detail:find("limit", 1, true) and "unsupported" or "error", data.text(reason)); return
    end
    world = apiRead.world()
    if flow.worldChanged(r, world) then request.invalidate(r, "world_changed_during_work"); return end
    r.tick = world.tick
    if ended - r.began > 60 then request.invalidate(r, "snapshot_age_limit"); return end
    if r.pendingComplete then
        r.pendingComplete = nil
        finish(r, "ok", "Completed conditional network study. Inspect proposed and deferred links below.")
    end
end
return request
