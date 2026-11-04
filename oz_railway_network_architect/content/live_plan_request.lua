local adapter = ug_require "oz_railway_network_architect::/live_plan_api.lua"
local flow = ug_require "oz_railway_network_architect::/live_plan_data.lua"
local occupancy = ug_require "oz_railway_network_architect::/planning/station_occupancy.lua"
local planner = ug_require "oz_railway_network_architect::/planning/corridor_planner.lua"
local hierarchy = ug_require "oz_railway_network_architect::/planning/corridor_hierarchy.lua"
local config = flow.config()
local prefix = "[RNA:PLAN:4B2] "

local function report(message) debugPrint(prefix .. message) end
local function quoted(value) return string.format("%q", flow.text(value == nil and "unavailable" or value)) end
local function fail(status, reason) error({status = status, reason = reason}, 0) end
local function now()
    local value, reason = adapter.seconds()
    if not flow.finite(value) then fail("timing_unavailable", reason or "api.util.getApplicationTime unavailable") end
    return value
end

local function finish(session, status, reason)
    session.finished, session.status, session.reason = true, status, reason
    if session.samples then
        report(string.format("TERRAIN processed=%d requested=%d valid=%d invalid=%d failed_samples=%d failed_reads=%d",
            #session.samples, session.layout.requested, session.validSamples, session.invalidSamples,
            session.failedSamples, session.failedReads))
        for _, detail in ipairs(session.examples) do report("READ_ERROR detail=" .. quoted(detail)) end
    end
    if session.samples or session.hierarchy then
        report("SNAPSHOT world=" .. tostring(session.world) .. " towns_start_tick=" .. tostring(session.townsStartTick)
            .. " towns_end_tick=" .. tostring(session.townsEndTick) .. " terrain_start_tick=" .. tostring(session.terrainStartTick)
            .. " terrain_end_tick=" .. tostring(session.terrainEndTick) .. " plan_start_tick=" .. tostring(session.planStartTick)
            .. " plan_end_tick=" .. tostring(session.planEndTick) .. " atomic=false")
    end
    local result = session.result
    if result then
        report("SEARCH status=" .. result.status .. " complete=" .. tostring(result.complete)
            .. " candidates=" .. #result.candidates .. " expansions=" .. tostring(result.stats and result.stats.expansions or "unavailable")
            .. " duration_seconds=" .. flow.number(session.searchSeconds))
        if result.error then report("SEARCH_ERROR path=" .. quoted(result.error.path) .. " detail=" .. quoted(result.error.message)) end
        for _, profile in ipairs(result.profiles) do
            report("PROFILE name=" .. profile.name .. " status=" .. profile.status .. " reason=" .. quoted(profile.reason)
                .. " disposition=" .. tostring(profile.disposition or "none"))
        end
        for _, c in ipairs(result.candidates) do
            report(string.format("CANDIDATE rank=%d id=%s profiles=%s length=%s max_gradient=%s elevation_gain=%s elevation_loss=%s touches_water=%s water_segments=%d water_runs=%d distance_score=%s gradient_score=%s water_obstacle_score=%s relative_score=%s construction=unverified",
                c.rank, c.id, table.concat(c.generatedBy, ","), flow.number(c.length), flow.number(c.maxGradient),
                flow.number(c.elevationGain), flow.number(c.elevationLoss), tostring(c.touchesWater), c.waterSegments, c.waterRuns,
                flow.number(c.score.distance), flow.number(c.score.gradient), flow.number(c.score.waterObstacle), flow.number(c.score.total)))
        end
    else
        report("SEARCH status=not_run_or_discarded candidates=0 duration_seconds=" .. flow.number(session.searchSeconds))
    end
    report("PERFORMANCE max_work_callback_seconds=" .. flow.number(session.maxWorkSeconds)
        .. " budget_seconds=" .. flow.number(config.workBudgetSeconds)
        .. " elapsed_seconds=" .. flow.number(session.started and session.lastSeconds and (session.lastSeconds - session.started))
        .. " gui_state_copy_and_summary_logging_excluded=true")
    report("TIMING resolution=unknown work_measurement=" .. (session.zeroWorkRead and "insufficient_resolution" or "unverified_resolution")
        .. " zero_is_not_zero_cost=true elapsed_includes_scheduling=true preemptive=false"
        .. " min_observed_between_work_callbacks_seconds=" .. flow.number(session.minCallbackGap)
        .. " callback_gap_is_not_clock_resolution=true")
    report("WARNINGS " .. (session.anchorOverride
        and "approximate_station_approaches;local_AABB_occupancy_only;other_obstacles_unknown;"
        or "town_centers_are_approximate_anchors;buildings_and_infrastructure_obstacles_unaccounted_for;")
        .. "sampled_terrain_only;no_hard_gradient_limit;relative_scores_not_game_costs;no_construction_validation;water_policy=" .. config.waterPolicy)
    report("COMPLETE status=" .. status .. " candidates=" .. tostring(result and #result.candidates or 0)
        .. " data_complete=" .. tostring((session.hierarchy ~= nil and status == "ok") or (session.samples ~= nil and #session.samples == session.layout.requested
            and session.invalidSamples == 0 and session.failedSamples == 0
            and session.townErrors == 0 and session.rejectedIds == 0 and session.rejectedTowns == 0))
        .. " reason=" .. quoted(reason))
    session.ids, session.towns = nil, nil
end

local function prepare(session)
    local pair, reason = flow.selected(session.towns, session.bounds, session.sourceId, session.destinationId)
    local valid = 0
    for _, town in ipairs(session.towns) do
        if flow.validTown(town, session.bounds) then valid = valid + 1 end
    end
    session.rejectedTowns = #session.towns - valid
    report("TOWNS valid=" .. tostring(valid)
        .. " rejected=" .. tostring(session.rejectedTowns)
        .. " read_errors=" .. session.townErrors)
    if not pair then fail("unsupported", reason) end
    session.townPair=pair
    if session.anchorOverride then
        local selected={method="explicit_station_approaches"}
        for _,role in ipairs({"start","destination"}) do
            local a=session.anchorOverride[role];local t=pair[role]
            if type(a)~="table" or a.townId~=t.id or not flow.finite(a.x) or not flow.finite(a.y) or not flow.finite(a.z)
                or a.x%128~=0 or a.y%128~=0 then fail("unsupported","invalid_station_approach") end
            selected[role]={id=t.id,name=t.name,x=a.x,y=a.y,z=a.z}
        end
        selected.distance=math.sqrt((selected.start.x-selected.destination.x)^2+(selected.start.y-selected.destination.y)^2)
        pair=selected
    end
    session.pair = pair
    report("ENDPOINT_VALIDATION status=ok source_id=" .. session.sourceId .. " destination_id=" .. session.destinationId)
    report("SELECT method=" .. pair.method .. " source_distance=" .. flow.number(pair.distance))
    for _, role in ipairs({"start", "destination"}) do
        local t = pair[role]
        report("TOWN role=" .. role .. " id=" .. t.id .. " name=" .. quoted(t.name)
            .. " source_x=" .. flow.number(t.x) .. " source_y=" .. flow.number(t.y) .. " source_z=" .. flow.number(t.z)
            .. " position_source="..(session.anchorOverride and "station_approach" or "bounding_volume_center"))
    end
    local layout, layoutReason = flow.layout(pair, session.bounds, config)
    if not layout then
        if layoutReason ~= "pair_exceeds_grid_resolution_or_boundary_margin" then fail("unsupported", layoutReason) end
        session.hierarchy = hierarchy.start(pair, session.bounds, {maxSnap = config.maxSnap,
            maxRelativeSnap = config.maxRelativeSnap, constraints = {waterPolicy = config.waterPolicy}})
        if session.anchorOverride then
            for _,role in ipairs({"start","destination"}) do
                local a=session.hierarchy.anchors and session.hierarchy.anchors[role]
                if not a or a.x~=pair[role].x or a.y~=pair[role].y then fail("unsupported","station_approach_snap_rejected") end
            end
        end
        session.phase, session.progress = "hierarchy", "Planning a coarse guide before local terrain refinement."
        report("LONG_DISTANCE mode=hierarchical coarse_spacing=512 fine_spacing=64 window_limit=32")
        for _, role in ipairs({"start", "destination"}) do
            local p = session.hierarchy.anchors and session.hierarchy.anchors[role]
            if p then report("ENDPOINT role=" .. role .. " x=" .. flow.number(p.x) .. " y=" .. flow.number(p.y)
                .. " dx=" .. flow.number(p.dx) .. " dy=" .. flow.number(p.dy) .. " snap_distance=" .. flow.number(p.distance)
                .. " policy=nearest_in_bounds_fine_lattice_half_up") end
        end
        return
    end
    if session.anchorOverride then
        for _,role in ipairs({"start","destination"}) do
            if layout[role].x~=pair[role].x or layout[role].y~=pair[role].y then fail("unsupported","station_approach_snap_rejected") end
        end
    end
    session.layout, session.samples, session.examples = layout, {}, {}
    session.validSamples, session.invalidSamples, session.failedSamples, session.failedReads = 0, 0, 0, 0
    report(string.format("GRID columns=%d rows=%d spacing_x=%d spacing_y=%d origin_x=%d origin_y=%d requested=%d unit=world_units",
        layout.columns, layout.rows, layout.spacing, layout.spacing, layout.originX, layout.originY, layout.requested))
    for _, role in ipairs({"start", "destination"}) do
        local p = layout[role]
        report("ENDPOINT role=" .. role .. " sample_id=" .. p.sampleId .. " x=" .. flow.number(p.x) .. " y=" .. flow.number(p.y)
            .. " dx=" .. flow.number(p.dx) .. " dy=" .. flow.number(p.dy) .. " snap_distance=" .. flow.number(p.distance)
            .. " policy=nearest_sample_half_up")
    end
    session.phase = "sampling"
end

local function verifySources(session)
    local bounds = adapter.bounds()
    for _, key in ipairs({"minX", "minY", "maxX", "maxY"}) do
        if bounds[key] ~= session.bounds[key] then fail("invalidated", "map_bounds_changed") end
    end
    for _, role in ipairs({"start", "destination"}) do
        local previous = (session.townPair or session.pair)[role]
        local current = adapter.town(previous.id)
        if not flow.sameTown(previous, current) then
            fail("invalidated", "selected_town_changed id=" .. previous.id .. " detail=" .. (current.error or "position_or_component_unavailable"))
        end
    end
end

local function sample(session,x,y)
    local raw=adapter.sample(session.bounds,x,y)
    if session.anchorOverride and session.anchorOverride.objects then
        for _,o in ipairs(session.anchorOverride.objects) do
            if occupancy.blocksSample(o,x,y) then raw.blocked=true;break end
        end
        for _,b in ipairs(session.anchorOverride.reservations or {}) do
            if occupancy.blocksSample({kind="unknown",box=b},x,y) then raw.blocked=true;break end
        end
        if session.anchorOverride.directions then
            for _,role in ipairs({"start","destination"}) do
                if occupancy.blocksApproach(session.anchorOverride[role],session.anchorOverride.directions[role],x,y,
                    session.layout and session.layout.spacing or 64) then raw.blocked=true end
            end
        end
    end
    return raw
end

local function work(session, world)
    if session.phase == "begin" then
        report("START world=" .. world.id .. " tick=" .. world.tick .. " app_seconds=" .. flow.number(session.started))
        session.bounds = adapter.bounds()
        session.ids, session.rejectedIds = {session.sourceId, session.destinationId}, 0
        session.towns, session.townErrors, session.cursor, session.townsStartTick = {}, 0, 1, world.tick
        session.phase = "towns"
    elseif session.phase == "towns" then
        local last = math.min(session.cursor + 7, #session.ids)
        for index = session.cursor, last do
            local record = adapter.town(session.ids[index])
            session.towns[#session.towns + 1] = record
            if record.error then
                session.townErrors = session.townErrors + 1
                if session.townErrors <= 4 then report("TOWN_ERROR id=" .. record.id .. " detail=" .. quoted(record.error)) end
            end
        end
        session.cursor = last + 1
        if session.cursor > #session.ids then session.phase = "prepare" end
    elseif session.phase == "prepare" then prepare(session)
    elseif session.phase == "sampling" then
        session.terrainStartTick = session.terrainStartTick or world.tick
        local last = math.min(#session.samples + 16, session.layout.requested)
        for index = #session.samples + 1, last do
            local x, y = flow.position(session.layout, index)
            flow.add(session, sample(session, x, y))
        end
        if #session.samples == session.layout.requested then session.phase = "planning" end
    elseif session.phase == "planning" then
        verifySources(session)
        session.planStartTick = session.planStartTick or world.tick
        if not session.planningJob then
            local input = flow.input(session, config)
            report("ANCHOR_HEIGHT start=" .. flow.number(input.grid.cells[session.layout.start.sampleId].height)
                .. " destination=" .. flow.number(input.grid.cells[session.layout.destination.sampleId].height)
                .. " source=sampled_terrain")
            session.planningJob = planner.start(input)
        else
            local started = now()
            planner.step(session.planningJob, 64)
            local elapsed = now() - started
            if elapsed < 0 then fail("invalidated", "application_clock_went_backwards") end
            session.searchSeconds = (session.searchSeconds or 0) + elapsed
        end
        session.progress = "Searching sampled local terrain (incremental A*)."
        if session.planningJob.finished then
            session.result, session.planningJob, session.phase = session.planningJob.result, nil, "done"
            for _, c in ipairs(session.result.candidates) do
                c.sourceId, c.destinationId, c.refinedSections = session.sourceId, session.destinationId, 1
                c.searchStatus, c.sampling = "complete", {fineSpacing = session.layout.spacing}
                c.endpoints = {start = session.layout.start, destination = session.layout.destination}
                c.originalAnchors = {start = {x = session.pair.start.x, y = session.pair.start.y},
                    destination = {x = session.pair.destination.x, y = session.pair.destination.y}}
            end
        end
    elseif session.phase == "hierarchy" then
        verifySources(session)
        session.terrainStartTick = session.terrainStartTick or world.tick
        session.planStartTick = session.planStartTick or world.tick
        local h = session.hierarchy
        local searching = h.phase == "coarse_search" or h.phase == "fine_search"
        local began = now()
        hierarchy.step(h, function(x, y) return sample(session, x, y) end)
        local elapsed = now() - began
        if elapsed < 0 then fail("invalidated", "application_clock_went_backwards") end
        if searching then session.searchSeconds = (session.searchSeconds or 0) + elapsed end
        session.progress = "Long-distance planning: " .. (h.progress or h.phase)
        local milestone = tostring(h.guideIndex or 0) .. ":" .. tostring(math.floor((h.section or 0) / 8))
        if milestone ~= session.progressMilestone and (session.progressLogCount or 0) < 8 then
            session.progressMilestone = milestone
            session.progressLogCount = (session.progressLogCount or 0) + 1
            debugPrint("[RNA:PLAN:4B3] PROGRESS " .. session.progress)
        end
        if h.finished then
            session.result, session.phase = h.result, "done"
            for _, example in ipairs(h.examples) do report("READ_ERROR detail=" .. quoted(example)) end
            debugPrint("[RNA:PLAN:4B3] SUMMARY status=" .. h.result.status .. " reason=" .. h.result.reason
                .. " samples=" .. h.result.stats.samples .. " unknown=" .. h.result.unknownCells
                .. " expansions=" .. h.result.stats.expansions .. " max_step_expansions=" .. h.result.stats.maxStepExpansions)
            for _, c in ipairs(h.result.candidates) do
                debugPrint("[RNA:PLAN:4B3] CORRIDOR id=" .. c.id .. " sections=" .. c.refinedSections
                    .. " waypoints=" .. #c.waypoints .. " fine_spacing=" .. c.sampling.fineSpacing
                    .. " construction=unverified")
            end
        end
    end
end

local function runWork(session)
    local began = now()
    if session.started == nil then session.started = began end
    if began < (session.lastSeconds or session.started) then fail("invalidated", "application_clock_went_backwards") end
    if session.lastSeconds and began > session.lastSeconds then
        local gap = began - session.lastSeconds
        session.minCallbackGap = math.min(session.minCallbackGap or gap, gap)
    end
    if began - session.started > config.maxAgeSeconds then fail("invalidated", "snapshot_age_limit_exceeded") end
    local before = adapter.world()
    if flow.worldChanged(session, before) then fail("invalidated", "world_identity_or_tick_changed") end
    session.tick = before.tick
    local phase = session.phase
    work(session, before)
    local after = adapter.world()
    if flow.worldChanged(session, after) then fail("invalidated", "world_identity_or_tick_changed_during_callback") end
    session.tick = after.tick
    if phase == "towns" then session.townsEndTick = after.tick end
    if phase == "sampling" or phase == "hierarchy" then session.terrainEndTick = after.tick end
    if phase == "planning" or phase == "hierarchy" then session.planEndTick = after.tick end
    local ended = now()
    session.lastSeconds = ended
    local duration = ended - began
    if duration == 0 then session.zeroWorkRead = true end
    if duration < 0 then fail("invalidated", "application_clock_went_backwards") end
    session.maxWorkSeconds = math.max(session.maxWorkSeconds or 0, duration)
    if duration > config.workBudgetSeconds then fail("performance_limit", "work_slice_budget_exceeded;smaller_slice_or_bookkeeping_required") end
    if ended - session.started > config.maxAgeSeconds then fail("invalidated", "snapshot_age_limit_exceeded") end
    if session.phase == "done" then
        session.result.snapshot = {world = session.world, townsStartTick = session.townsStartTick,
            townsEndTick = session.townsEndTick, terrainStartTick = session.terrainStartTick,
            terrainEndTick = session.terrainEndTick, planStartTick = session.planStartTick,
            planEndTick = session.planEndTick, startedSeconds = session.started, endedSeconds = ended, atomic = false}
        local status = session.result.status
        if status == "ok" and (session.invalidSamples or 0) + (session.failedSamples or 0) + session.townErrors + session.rejectedIds + session.rejectedTowns > 0 then
            status = "incomplete"
        end
        finish(session, status, session.result.reason or "see_search_profiles_and_sample_counts")
    end
end

local request = {}
function request.start(world, sourceId, destinationId, requestId, anchorOverride)
    return {world = world.id, tick = world.tick, sourceId = sourceId, destinationId = destinationId,
        requestId = requestId, phase = "begin", batchWait = 0, anchorOverride=anchorOverride}
end
function request.step(session)
    if session.finished then return end
    session.batchWait = session.batchWait + 1
    if session.batchWait < (session.hierarchy and 1 or 4) then return end
    session.batchWait = 0
    local ok, reason = pcall(runWork, session)
    if not ok then
        if session.hierarchy then hierarchy.cancel(session.hierarchy, "request_failed") end
        session.result, session.planningJob = nil, nil
        local status, detail = "error", reason
        if type(reason) == "table" then status, detail = reason.status, reason.reason end
        finish(session, status, flow.text(detail))
    end
end
function request.invalidate(session, reason)
    if not session.finished then
        if session.hierarchy then hierarchy.cancel(session.hierarchy, reason) end
        session.result, session.planningJob = nil, nil
        finish(session, "invalidated", reason)
    end
end
return request
