-- Pure, bounded presentation data. This is an in-panel summary, NOT a map overlay.
local flow = ug_require "oz_railway_network_architect::/live_plan_data.lua"
local sites = ug_require "oz_railway_network_architect::/planning/station_sites.lua"
local preview = {}
local function array(value, limit)
    if type(value) ~= "table" then return nil end
    local n = 0
    for k in pairs(value) do
        n = n + 1
        if n > limit or not flow.id(k) or k < 1 or k > limit then return nil end
    end
    for i = 1, n do if value[i] == nil then return nil end end
    return n
end
local function number(v) return flow.finite(v) and math.abs(v) <= 1e12 end
local function positive(v) return number(v) and v >= 0 end
local function point(p, height)
    return type(p) == "table" and number(p.x) and number(p.y) and (not height or number(p.z))
end
local function text(v, limit) return type(v) == "string" and #v <= limit end
local function copyPoint(p) return {x = p.x, y = p.y, z = p.z} end

-- A compact response contract; no terrain grids, search state or route arrays cross
-- the polling channel. Session/request identity is mandatory even on window reopen.
function preview.valid(value, state)
    if type(value) ~= "table" or value.kind ~= "panel_summary" or state.status ~= "ok" or state.busy == true
        or value.epoch ~= state.epoch or value.world ~= state.world or value.requestId ~= state.requestId
        or not flow.id(value.epoch) or not flow.id(value.world) or not flow.id(value.requestId) then return false end
    for _, role in ipairs({"source", "destination"}) do
        local p = value[role]
        if not point(p) or not flow.id(p.id) or not text(p.name, 100) then return false end
    end
    if value.source.id == value.destination.id then return false end
    local count = array(value.candidates, 3)
    if not count or count < 1 then return false end
    local ids = {}
    for i, c in ipairs(value.candidates) do
        if type(c) ~= "table" or not text(c.id, 100) or c.id == "" or ids[c.id] or c.rank ~= i
            or not text(c.profile, 100) or not point(c.start, true) or not point(c.destination, true)
            or not flow.id(c.waypointCount) or c.waypointCount < 2 or c.waypointCount > 4096
            or not flow.id(c.sections) or c.sections < 1 or c.sections > 128
            or (c.spacing ~= 32 and c.spacing ~= 64 and c.spacing ~= 128)
            or type(c.water) ~= "boolean" or not flow.id(c.waterRuns) or c.waterRuns > c.waypointCount
            or type(c.score) ~= "table" then return false end
        for _, key in ipairs({"length", "gain", "loss", "gradient", "waterExposure", "sourceSnap", "destinationSnap"}) do
            if not positive(c[key]) then return false end
        end
        for _, key in ipairs({"distance", "gradient", "waterObstacle", "total"}) do
            if not positive(c.score[key]) then return false end
        end
        if c.stationSites then
            for _,role in ipairs({"source","destination"}) do
                local s=c.stationSites[role];local endpoint=role=="source" and c.start or c.destination
                if not sites.valid(s) or s.townId~=value[role].id then return false end
                for _,axis in ipairs({"x","y","z"}) do if endpoint[axis]~=s.approach[axis] then return false end end
            end
        end
        ids[c.id] = true
    end
    return true
end

function preview.build(state)
    local r = state.request
    if not r or not r.finished or state.status ~= "ok" or r.status ~= "ok"
        or r.world ~= state.world or r.requestId ~= state.requestId then return nil, "request_not_complete_ok" end
    local result = r.result
    if type(result) ~= "table" or result.status ~= "ok" or result.complete ~= true
        or not result.snapshot or result.snapshot.world ~= state.world then return nil, "result_not_complete_ok" end
    local count = array(result.candidates, 3)
    if not count or count == 0 then return nil, "no_complete_candidates" end
    local pair = r.pair
    if type(pair) ~= "table" or not point(pair.start) or not point(pair.destination)
        or pair.start.id ~= r.sourceId or pair.destination.id ~= r.destinationId then return nil, "invalid_anchors" end
    local value = {kind = "panel_summary", epoch = state.epoch, world = state.world,
        requestId = state.requestId, candidates = {}}
    for role, original in pairs({source = pair.start, destination = pair.destination}) do
        value[role] = {id = original.id, name = flow.text(original.name):sub(1, 100), x = original.x, y = original.y}
    end
    for i, c in ipairs(result.candidates) do
        local n = type(c) == "table" and array(c.waypoints, 4096)
        if not n or n < 2 or c.searchStatus ~= "complete" or c.constructionStatus ~= "unverified"
            or c.feasibility ~= "sampled_constraints_satisfied" or c.sourceId ~= r.sourceId
            or c.destinationId ~= r.destinationId or c.rank ~= i then return nil, "invalid_candidate" end
        local spacing = c.sampling and c.sampling.fineSpacing
        if spacing ~= 32 and spacing ~= 64 and spacing ~= 128 then return nil, "invalid_resolution" end
        for j, p in ipairs(c.waypoints) do
            if not point(p, true) or type(p.water) ~= "boolean" then return nil, "invalid_waypoint" end
            if j > 1 then
                local previous = c.waypoints[j - 1]
                local dx, dy = math.abs(p.x - previous.x), math.abs(p.y - previous.y)
                local tolerance = spacing * 1e-9
                if (dx > tolerance and math.abs(dx - spacing) > tolerance)
                    or (dy > tolerance and math.abs(dy - spacing) > tolerance) or dx + dy <= tolerance then
                    return nil, "discontinuous_candidate"
                end
            end
        end
        local first, last = c.waypoints[1], c.waypoints[n]
        local endpoints = c.endpoints
        if not endpoints or not point(endpoints.start) or not point(endpoints.destination)
            or first.x ~= endpoints.start.x or first.y ~= endpoints.start.y
            or last.x ~= endpoints.destination.x or last.y ~= endpoints.destination.y then return nil, "endpoint_mismatch" end
        local profileCount = array(c.generatedBy, 3)
        if not profileCount or profileCount < 1 then return nil, "invalid_profiles" end
        for _, name in ipairs(c.generatedBy) do if not text(name, 30) then return nil, "invalid_profiles" end end
        if type(c.score) ~= "table" then return nil, "invalid_score" end
        value.candidates[i] = {id = c.id, rank = i, profile = table.concat(c.generatedBy, ", "),
            start = copyPoint(first), destination = copyPoint(last), waypointCount = n,
            sections = c.refinedSections, spacing = spacing, length = c.length,
            gain = c.elevationGain, loss = c.elevationLoss, gradient = c.maxGradient,
            water = c.touchesWater, waterRuns = c.waterRuns, waterExposure = c.waterExposure,
            sourceSnap = endpoints.start.distance, destinationSnap = endpoints.destination.distance,
            score = {distance = c.score.distance, gradient = c.score.gradient,
                waterObstacle = c.score.waterObstacle, total = c.score.total}}
        if r.stationAware and not c.stationSites then return nil,"missing_station_sites" end
        if c.stationSites then
            local compact={}
            for _,role in ipairs({"source","destination"}) do
                local s=c.stationSites[role]
                if not sites.valid(s) then return nil,"invalid_station_reservation" end
                compact[role]={townId=s.townId,x=s.x,y=s.y,z=s.z,dx=s.dx,dy=s.dy,
                    length=s.length,width=s.width,approximate=true,approach=copyPoint(s.approach)}
            end
            value.candidates[i].stationSites=compact
        end
    end
    if not preview.valid(value, state) then return nil, "invalid_summary" end
    return value
end

function preview.find(value, id)
    for _, c in ipairs(value and value.candidates or {}) do if c.id == id then return c end end
end

function preview.lines(value, id)
    local c = preview.find(value, id)
    if not c then return {"No eligible corridor summary. A completed 'ok' result is required; see status and log."} end
    local function xyz(p) return string.format("(%.1f, %.1f, %.1f)", p.x, p.y, p.z) end
    return {
        "Completed request #" .. value.requestId .. ". Construction feasibility: unverified.",
        string.format("Source: %s [#%d] | town anchor (%.1f, %.1f)", value.source.name, value.source.id, value.source.x, value.source.y),
        string.format("Destination: %s [#%d] | town anchor (%.1f, %.1f)", value.destination.name, value.destination.id, value.destination.x, value.destination.y),
        "Route start XYZ: " .. xyz(c.start) .. " | end XYZ: " .. xyz(c.destination),
        string.format("Endpoint snaps: %.1f / %.1f world units. Town anchors are not stations.", c.sourceSnap, c.destinationSnap),
        string.format("Approximate length: %.1f world units | elevation gain/loss: %.1f / %.1f", c.length, c.gain, c.loss),
        string.format("Maximum sampled gradient: %.2f%% | water: %s | water runs: %d | exposure: %.1f", c.gradient * 100, c.water and "yes" or "no", c.waterRuns, c.waterExposure),
        string.format("Relative score: %.2f (distance %.2f + gradient %.2f + water/obstacle %.2f). Not construction cost.", c.score.total, c.score.distance, c.score.gradient, c.score.waterObstacle),
        string.format("%d ordered waypoints retained by planner | %d refined section(s) | %d-unit samples. No path is drawn.", c.waypointCount, c.sections, c.spacing),
        "Snapshot only; not a live terrain monitor. Between-sample terrain, buildings, curves, bridges, tunnels and track connections are unverified.",
    }
end
return preview
