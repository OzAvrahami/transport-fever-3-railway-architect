local adapter = ug_require "oz_railway_network_architect::/live_plan_api.lua"
local flow = ug_require "oz_railway_network_architect::/live_plan_data.lua"
local request = ug_require "oz_railway_network_architect::/live_plan_request.lua"
local preview = ug_require "oz_railway_network_architect::/live_plan_preview.lua"
local network = ug_require "oz_railway_network_architect::/network_live_request.lua"
local handoff = ug_require "oz_railway_network_architect::/network_corridor_handoff.lua"
local config = flow.config()
local eventId = "oz_railway_network_architect.plan"
local prefix = "[RNA:PLAN:4B2] "
local function report(message) debugPrint(prefix .. message) end

local function newState(previous)
    return {epoch = (previous and previous.epoch or 0) + 1, requestId = 0,
        networkRequestId = 0, polls = 0, tick = nil, towns = {}, listVersion = 0, status = "waiting",
        message = "Waiting for a loaded world and tick advance; briefly unpause."}
end

local function reset(state, reason)
    if state.network then network.invalidate(state.network, reason) end
    if state.request then request.invalidate(state.request, reason) end
    report("SESSION_RESET reason=" .. flow.text(reason))
    return newState(state)
end

local function synchronize(state)
    local world = adapter.world()
    if state.world ~= nil and flow.worldChanged(state, world) then
        state = reset(state, "world_identity_or_tick_changed")
    end
    if world then
        if state.world == nil then state.world, state.tick = world.id, world.tick
        elseif world.tick > state.tick then state.ready = true end
        state.tick = world.tick
    end
    return state, world
end

local function startCatalog(state)
    state.catalog = {cursor = 1, towns = {}, rejected = 0, errors = 0}
    state.towns, state.request, state.network = {}, nil, nil
    state.listVersion = state.listVersion + 1
    state.status, state.message = "loading", "Loading town list..."
end

local function collect(state)
    local catalog = state.catalog
    local began, clockError = adapter.seconds()
    if not flow.finite(began) then error(clockError or "api.util.getApplicationTime unavailable", 0) end
    if not catalog.ids then
        catalog.bounds = adapter.bounds()
        catalog.ids, catalog.rejected = adapter.ids(config.maxTowns)
    else
        local last = math.min(catalog.cursor + 7, #catalog.ids)
        for i = catalog.cursor, last do
            local town = adapter.town(catalog.ids[i])
            if flow.validTown(town, catalog.bounds) then
                catalog.towns[#catalog.towns + 1] = {id = town.id, name = type(town.name) == "string" and flow.text(town.name) or "unavailable"}
            else catalog.rejected = catalog.rejected + 1 end
            if town.error then
                catalog.errors = catalog.errors + 1
                if catalog.errors <= 4 then report("TOWN_ERROR id=" .. town.id .. " detail=" .. flow.text(town.error)) end
            end
        end
        catalog.cursor = last + 1
        if catalog.cursor > #catalog.ids then
            state.towns, state.catalog = catalog.towns, nil
            state.status = #state.towns >= 2 and "idle" or "unsupported"
            state.message = #state.towns >= 2 and "No request submitted. Select two towns and press Plan."
                or "Fewer than two valid towns. Refresh towns after map changes."
            report("TOWNS available=" .. #state.towns .. " rejected=" .. catalog.rejected .. " read_errors=" .. catalog.errors)
            report("STATE status=" .. state.status .. " request=none")
        end
    end
    local ended, endedError = adapter.seconds()
    if not flow.finite(ended) then error(endedError or "api.util.getApplicationTime unavailable", 0) end
    if ended < began then error("application_clock_went_backwards", 0) end
    if ended - began > config.workBudgetSeconds then error("town_collection_performance_limit", 0) end
end

local function busy(state)
    return (state.request ~= nil and not state.request.finished) or (state.network ~= nil and not state.network.finished)
end

local function response(state, accepted, reason)
    local r = state.request
    local studyReady, studyReason = handoff.available(state, adapter.seconds())
    local towns = {}
    for _, town in ipairs(state.towns) do towns[#towns + 1] = {id = town.id, name = town.name} end
    return {epoch = state.epoch, world = state.world, tick = state.tick, listVersion = state.listVersion,
        requestId = state.requestId, accepted = accepted, reason = reason, towns = towns,
        status = state.status, message = state.message, busy = busy(state),
        networkRequestId = state.networkRequestId,
        canAnalyze = state.ready == true and state.catalog == nil and not busy(state),
        networkStatus = state.network and state.network.status or "idle",
        networkMessage = state.network and state.network.message or "No network analysis requested.",
        networkSummary = state.network and state.network.summary or nil,
        canStudy = studyReady and not busy(state) and state.ready == true and state.catalog == nil,
        studyReason = studyReason,
        corridorOrigin = handoff.presentation(r, state),
        canPlan = state.ready == true and state.catalog == nil and #towns >= 2
            and (state.status ~= "error" or (r ~= nil and r.finished)),
        candidates = r and r.result and #r.result.candidates or 0,
        preview = not busy(state) and r and preview.valid(r.preview, state) and r.preview or nil}
end

local function update(state)
    if not state.checked then
        local reason = flow.checkConfig(config) or adapter.check()
        if reason then error(reason, 0) end
        state.checked = true
        -- Entity lookup confirms registration only, not GUI-handler delivery.
        local scriptName = "oz_railway_network_architect" .. "::/live_plan.gs"
        local found, entity = pcall(function()
            return api.engine.system.gameScriptSystem.getEntityForGameScript(scriptName)
        end)
        report("REGISTRATION_LOOKUP name=" .. scriptName .. " status="
            .. (found and flow.id(entity) and "resolved" or "unavailable")
            .. (found and (" entity=" .. flow.text(entity))
                or (" detail=api.engine.system.gameScriptSystem.getEntityForGameScript: " .. flow.text(entity))))
        report("UI_SESSION_READY status=waiting request=none communication=trace-v1 handler=guiHandleEvent")
    end
    state.polls = state.polls + 1
    local active = state.catalog or busy(state)
    if not active and state.polls ~= 1 and state.polls % 30 ~= 0 then return state end
    local world
    state, world = synchronize(state)
    if not world or not state.ready then return state end
    if state.status == "waiting" then startCatalog(state) end
    if state.catalog and state.polls % 4 == 0 then
        collect(state)
        state = synchronize(state) -- Do not expose a catalog from an invalidated world.
    end
    if state.request and not state.request.finished then
        request.step(state.request)
        if not state.request.finished and state.request.progress then state.message = state.request.progress end
        if state.request.finished then
            local r = state.request
            state.status = r.status
            -- Build once from a finished, validated request, never from a coarse guide
            -- or unfinished section. Existing status transport carries only this DTO.
            local previewReason
            r.preview, previewReason = preview.build(state)
            debugPrint("[RNA:PREVIEW:4B4] PANEL_SUMMARY request=" .. state.requestId
                .. " candidates=" .. (r.preview and #r.preview.candidates or 0)
                .. " reason=" .. (previewReason or "complete_snapshot") .. " map_overlay=false")
            local messages = {ok = "Completed", incomplete = "Completed with missing data",
                unreachable = "No route through the sampled region", unsupported = "These anchors cannot be represented adequately",
                invalidated = "Map data changed; please try again", performance_limit = "Work budget exceeded; review required",
                resource_limit = "Long-distance planning resource limit reached", search_limit = "Search budget reached", timing_unavailable = "Timing unavailable", error = "Planning failed"}
            state.message = (messages[r.status] or "Planning failed: " .. r.status)
                .. ". Candidates: " .. (r.result and #r.result.candidates or 0) .. ". Details in log."
            if r.status == "unsupported" and r.hierarchy then
                state.message = "No corridor was calculated within the current bounded sampling or endpoint limits. "
                    .. "Try another pair; the precise reason is in the log."
            end
            if r.status == "unsupported" and r.reason == "pair_exceeds_grid_resolution_or_boundary_margin" then
                state.message = "The selected towns exceed the current prototype's sampling resolution or map-boundary margin. "
                    .. "No route was calculated. Try towns closer together and away from the map edge."
                if r.pair and (math.abs(r.pair.start.x - r.pair.destination.x) > (config.gridLimit - 1) * 128
                    or math.abs(r.pair.start.y - r.pair.destination.y) > (config.gridLimit - 1) * 128) then
                    state.message = "The selected towns are too far apart for the current prototype's sampling resolution. "
                        .. "No route was calculated. Try towns closer together."
                end
            end
        end
    end
    if state.network and not state.network.finished then network.step(state.network) end
    return state
end

function data()
    return {
        guiUpdate = function(_params, _engineState, guiState)
            local state = guiState:get()
            if not state or not state.epoch then state = newState() end
            local ok, updated = pcall(update, state)
            if ok then state = updated else
                if state.request then request.invalidate(state.request, "session_update_failed") end
                if state.network then network.invalidate(state.network, "session_update_failed") end
                if state.status ~= "error" then report("ERROR detail=" .. flow.text(updated)) end
                state.status, state.message, state.catalog = "error", flow.text(updated), nil
            end
            guiState:set(state)
        end,
        guiHandleEvent = function(_params, _engineState, guiState, _src, id, name, param)
            -- Diagnostic envelope only; never a planning/replay token. The UI
            -- enables tracing for at most eight dispatches per launcher lifetime.
            local trace = type(param) == "table" and param._rnaTrace or nil
            local traceId = type(trace) == "table" and type(trace.id) == "string" and trace.id or nil
            local related = id == eventId or (type(name) == "string" and name:sub(1, #eventId + 1) == eventId .. ".")
            local traceEnabled = (traceId ~= nil and #traceId <= 64 and trace.enabled == true)
                or (related and traceId == nil)
            if traceEnabled then
                local diagnosticState = guiState:get()
                if not diagnosticState or not diagnosticState.epoch then diagnosticState = newState() end
                local count = diagnosticState.communicationTraceCount or 0
                traceEnabled = count < 8
                if traceEnabled then
                    diagnosticState.communicationTraceCount = count + 1
                    guiState:set(diagnosticState)
                end
            end
            local function traceEvent(message)
                if traceEnabled then
                    report("COMM " .. message .. " trace=" .. flow.text(traceId or "unavailable"))
                end
            end
            traceEvent("HANDLER_ENTRY src=" .. flow.text(_src) .. " id=" .. string.format("%q", flow.text(id))
                .. " name=" .. flow.text(name) .. " param_type=" .. type(param))
            -- Shipped mission_sim handles this exact lifecycle notification by resetting GUI data.
            if id == "gameUI" and name == "reactPostInit" then
                guiState:set(reset(guiState:get() or {}, "reactPostInit")); return
            end
            if id ~= eventId then
                traceEvent("HANDLER_ROUTE accepted=false reason=event_id"); return
            end
            if type(name) ~= "string" or name:sub(1, #eventId + 1) ~= eventId .. "." then
                traceEvent("HANDLER_ROUTE accepted=false reason=event_name_prefix"); return
            end
            name = name:sub(#eventId + 2)
            if name ~= "status" and name ~= "plan" and name ~= "refresh" and name ~= "analyzeNetwork" then
                traceEvent("HANDLER_ROUTE accepted=false reason=event_action"); return
            end
            traceEvent("HANDLER_ROUTE accepted=true action=" .. name)
            local state = guiState:get()
            if not state or not state.epoch then state = newState() end
            local accepted, reason = false, nil
            local ok, detail = pcall(function()
                state = synchronize(state)
                if name == "status" then return end
                if busy(state) then reason = "busy"; return end
                if name == "refresh" then
                    if not state.ready then reason = "world_not_ready"; return end
                    startCatalog(state); accepted = true; return
                end
                if type(param) ~= "table" or param.world ~= state.world or param.epoch ~= state.epoch then
                    reason = "stale_session"; return
                end
                if name == "analyzeNetwork" then
                    if not flow.id(param.requestId) or param.requestId ~= state.networkRequestId + 1 then
                        reason = "duplicate_or_stale_network_request"; return
                    end
                    if not state.ready or state.catalog then reason = "not_ready"; return end
                    state.networkRequestId = param.requestId
                    state.network = network.start({id = state.world, tick = state.tick}, state.epoch, param.requestId)
                    accepted = true; return
                end
                if not flow.id(param.requestId) or param.requestId ~= state.requestId + 1 then reason = "duplicate_or_stale_request"; return end
                if not state.ready or state.catalog or (state.status == "error" and not state.request) then reason = "not_ready"; return end
                -- Consume the click token even on validation failure; replay cannot restart work.
                state.requestId = param.requestId
                local sourceId, destinationId, origin = param.sourceId, param.destinationId, nil
                if param.network ~= nil then
                    origin, reason = handoff.prepare(state, param.network)
                    if not origin then return end
                    sourceId, destinationId = origin.sourceId, origin.destinationId
                end
                if not flow.id(sourceId) or not flow.id(destinationId) then reason = "invalid_selected_ids"; return end
                if sourceId == destinationId then reason = "same_town"; return end
                local seen = {}
                for _, town in ipairs(state.towns) do seen[town.id] = true end
                if not seen[sourceId] or not seen[destinationId] then reason = "selection_not_in_town_list"; return end
                local source, destination = adapter.town(sourceId), adapter.town(destinationId)
                for _, town in ipairs({source, destination}) do
                    if town.error then report("ENDPOINT_ERROR id=" .. town.id .. " detail=" .. flow.text(town.error)) end
                end
                local bounds = adapter.bounds()
                local pair, invalid = flow.selected({source, destination},
                    bounds, sourceId, destinationId)
                if not pair then reason = invalid; return end
                if origin then
                    reason = handoff.validate(state, origin, source, destination, bounds)
                    if reason then return end
                end
                local world = adapter.world()
                if flow.worldChanged(state, world) then state = reset(state, "world_changed_during_request"); reason = "stale_session"; return end
                state.request = request.start(world, sourceId, destinationId, param.requestId)
                state.request.networkOrigin = origin
                if origin then
                    debugPrint("[RNA:HANDOFF:5B2] START request=" .. param.requestId
                        .. " network=" .. origin.networkRequestId .. " edge=" .. origin.edgeId
                        .. " classification=" .. origin.classification .. " snapshot=" .. origin.snapshotId)
                end
                state.status, state.message = "planning", "Planning in progress. See log for diagnostics."
                report("REQUEST_START request=" .. param.requestId .. " source_id=" .. sourceId .. " destination_id=" .. destinationId)
                accepted = true
            end)
            if not ok then reason = flow.text(detail) end
            if reason and name ~= "status" then
                -- Busy/replay rejection must not overwrite an active/completed request.
                report("REQUEST_REJECTED reason=" .. flow.text(reason))
            end
            guiState:set(state)
            local value = response(state, accepted, reason)
            value._rnaTraceId = traceId
            traceEvent("HANDLER_RESPONSE type=table epoch=" .. tostring(value.epoch)
                .. " status=" .. flow.text(value.status) .. " towns=" .. #value.towns
                .. " accepted=" .. tostring(accepted) .. " reason=" .. flow.text(reason))
            return value
        end,
    }
end
