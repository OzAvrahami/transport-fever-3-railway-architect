local adapter = ug_require "oz_railway_network_architect::/live_plan_api.lua"
local flow = ug_require "oz_railway_network_architect::/live_plan_data.lua"
local planner = ug_require "oz_railway_network_architect::/planning/corridor_planner.lua"
local config = flow.config()
local prefix = "[RNA:PLAN:4B1] "

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
    report("WARNINGS town_centers_are_approximate_anchors;sampled_terrain_only;buildings_and_infrastructure_obstacles_unaccounted_for;no_hard_gradient_limit;relative_scores_not_game_costs;no_construction_validation;water_policy=" .. config.waterPolicy)
    report("COMPLETE status=" .. status .. " candidates=" .. tostring(result and #result.candidates or 0)
        .. " data_complete=" .. tostring(session.samples ~= nil and #session.samples == session.layout.requested
            and session.invalidSamples == 0 and session.failedSamples == 0
            and session.townErrors == 0 and session.rejectedIds == 0 and session.rejectedTowns == 0)
        .. " reason=" .. quoted(reason))
    session.ids, session.towns = nil, nil
end

local function prepare(session)
    local pair, reason, stats = flow.select(session.towns, session.bounds, config)
    session.rejectedTowns = stats and stats.rejected or 0
    report("TOWNS valid=" .. tostring(stats and stats.valid or 0)
        .. " rejected=" .. tostring((stats and stats.rejected or 0) + session.rejectedIds)
        .. " read_errors=" .. session.townErrors)
    if not pair then fail("unsupported", reason) end
    session.pair = pair
    report("SELECT method=" .. pair.method .. " source_distance=" .. flow.number(pair.distance))
    for _, role in ipairs({"start", "destination"}) do
        local t = pair[role]
        report("TOWN role=" .. role .. " id=" .. t.id .. " name=" .. quoted(t.name)
            .. " source_x=" .. flow.number(t.x) .. " source_y=" .. flow.number(t.y) .. " source_z=" .. flow.number(t.z)
            .. " position_source=bounding_volume_center")
    end
    local layout, layoutReason = flow.layout(pair, session.bounds, config)
    if not layout then fail("unsupported", layoutReason) end
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
        local previous = session.pair[role]
        local current = adapter.town(previous.id)
        if not flow.sameTown(previous, current) then
            fail("invalidated", "selected_town_changed id=" .. previous.id .. " detail=" .. (current.error or "position_or_component_unavailable"))
        end
    end
end

local function work(session, world)
    if session.phase == "begin" then
        report("START world=" .. world.id .. " tick=" .. world.tick .. " app_seconds=" .. flow.number(session.started))
        session.bounds = adapter.bounds()
        session.ids, session.rejectedIds = adapter.ids(config.maxTowns)
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
            flow.add(session, adapter.sample(session.bounds, x, y))
        end
        if #session.samples == session.layout.requested then session.phase = "planning" end
    elseif session.phase == "planning" then
        verifySources(session)
        session.planStartTick = world.tick
        local input = flow.input(session, config) -- Fresh plain tables, never a shared scanner state.
        report("ANCHOR_HEIGHT start=" .. flow.number(input.grid.cells[session.layout.start.sampleId].height)
            .. " destination=" .. flow.number(input.grid.cells[session.layout.destination.sampleId].height)
            .. " source=sampled_terrain")
        local started = now()
        session.result = planner.plan(input)
        session.searchSeconds = now() - started
        if session.searchSeconds < 0 then fail("invalidated", "application_clock_went_backwards") end
        session.phase = "done"
    end
end

local function runWork(session)
    local began = now()
    if session.started == nil then session.started = began end
    if began < (session.lastSeconds or session.started) then fail("invalidated", "application_clock_went_backwards") end
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
    if phase == "sampling" then session.terrainEndTick = after.tick end
    if phase == "planning" then session.planEndTick = after.tick end
    local ended = now()
    session.lastSeconds = ended
    local duration = ended - began
    if duration < 0 then fail("invalidated", "application_clock_went_backwards") end
    session.maxWorkSeconds = math.max(session.maxWorkSeconds or 0, duration)
    if duration > config.workBudgetSeconds then fail("performance_limit", "synchronous_work_budget_exceeded;resumable_search_or_smaller_workload_required") end
    if ended - session.started > config.maxAgeSeconds then fail("invalidated", "snapshot_age_limit_exceeded") end
    if session.phase == "done" then
        local status = session.result.status
        if status == "ok" and session.invalidSamples + session.failedSamples + session.townErrors + session.rejectedIds + session.rejectedTowns > 0 then
            status = "incomplete"
        end
        finish(session, status, "see_search_profiles_and_sample_counts")
    end
end

function data()
    return {
        guiUpdate = function(_captureParams, _engineState, guiState)
            local session = guiState:get() or {}
            if session.finished then return end
            local ok, reason = pcall(function()
                if not session.initialized then
                    session.initialized, session.polls, session.missingWorld, session.batchWait = true, 0, 0, 0
                    report("WAIT_WORLD waiting_for_valid_world_and_tick_advance;unpause_to_plan")
                    local invalidConfig = flow.checkConfig(config)
                    if invalidConfig then fail("unsupported", invalidConfig) end
                    local missing = adapter.check()
                    if missing then fail("error", missing) end
                end
                if session.phase then
                    session.batchWait = session.batchWait + 1
                    if session.batchWait < 4 then return end
                    session.batchWait = 0
                    runWork(session); return
                end
                session.polls = session.polls + 1
                if session.polls > 1 and session.polls % 30 ~= 0 then return end
                local world = adapter.world()
                if world == nil then
                    session.missingWorld = session.missingWorld + 1
                    if session.missingWorld >= 60 then fail("error", "world_unavailable_after_60_readiness_checks") end
                    return
                end
                session.missingWorld = 0
                if session.world ~= world.id or session.tick == nil or world.tick < session.tick then
                    session.world, session.tick = world.id, world.tick; return
                end
                if world.tick <= session.tick then return end
                session.phase = "begin"
                runWork(session)
            end)
            if not ok then
                session.result = nil -- Never publish stale, failed or over-budget candidates.
                local status, detail = "error", reason
                if type(reason) == "table" then status, detail = reason.status, reason.reason end
                finish(session, status, flow.text(detail))
            end
            -- Own GUI callback state only. No engine-state or GUI SaveData writes.
            guiState:set(session)
        end,
    }
end
