-- Validate one explicit topology-to-corridor request. Never runs a search.
local core = ug_require "oz_railway_network_architect::/planning/network_planner.lua"
local flow = ug_require "oz_railway_network_architect::/live_plan_data.lua"
local read = ug_require "oz_railway_network_architect::/network_live_api.lua"
local worklist = ug_require "oz_railway_network_architect::/network_worklist.lua"
local handoff = {}
local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}; for key, item in pairs(value) do result[key] = copy(item) end; return result
end

-- Freshness is a conservative age/identity policy, not proof of an atomic world.
function handoff.available(state, now)
    local n = state.network
    if not n or not n.finished or n.status ~= "ok" or not n.result or not n.snapshot
        or not n.snapshot.entityIds then return false, "network_snapshot_unavailable; Analyze Network again" end
    if n.epoch ~= state.epoch or n.world ~= state.world or n.id ~= state.networkRequestId
        or state.tick < n.tick then return false, "stale_network_session; Analyze Network again" end
    if not flow.finite(now) or not flow.finite(n.began) or now < n.began or now - n.began > 60 then
        return false, "network_snapshot_expired_or_clock_unavailable; Analyze Network again"
    end
    return true
end

function handoff.prepare(state, selected)
    local now, clockError = read.seconds()
    local valid, reason = handoff.available(state, now)
    if not valid then return nil, clockError or reason end
    local n = state.network
    if type(selected) ~= "table" or selected.requestId ~= n.id
        or selected.snapshotId ~= n.result.snapshotId or type(selected.edgeId) ~= "string" then
        return nil, "stale_network_recommendation; Analyze Network again"
    end
    local decision
    if state.worklist then
        if not worklist.matches(state.worklist, state) then return nil, "stale_worklist_snapshot" end
        decision = worklist.decision(state.worklist, selected.edgeId)
        if decision and not decision.included then return nil, "connection_excluded_from_network_plan" end
    end
    local descriptor, why = core.corridorRequest(n.result, selected.edgeId)
    if not descriptor then return nil, why end
    local edge
    for _, candidate in ipairs(n.result.recommendations) do
        if candidate.id == selected.edgeId then edge = candidate; break end
    end
    if not edge or edge.status ~= "recommended" then return nil, "edge_not_recommended" end
    return {networkRequestId = n.id, snapshotId = n.result.snapshotId, edgeId = edge.id,
        world = n.world, epoch = n.epoch, sourceId = descriptor.sourceId, destinationId = descriptor.destinationId,
        anchors = copy(descriptor.pair), classification = edge.classification, priority = edge.priority,
        directDistance = edge.distance, evidence = copy(edge.evidence), reasons = copy(edge.reasons),
        limitations = copy(edge.limitations), infrastructure = copy(edge.infrastructure),
        snapshotStartTick = n.snapshot.startTick, snapshotEndTick = n.snapshot.endTick,
        worklistDecision = decision and {revision = state.worklist.revision, decision = decision,
            classificationInterpretation = state.worklist.graph.classificationInterpretation} or nil,
        checkedSeconds = now, constructionStatus = "unverified"}
end

function handoff.validate(state, origin, source, destination, bounds)
    local n = state.network
    if not flow.sameTown(origin.anchors.start, source) or not flow.sameTown(origin.anchors.destination, destination) then
        return "network_anchor_changed; Analyze Network again"
    end
    for key, value in pairs(n.bounds) do
        if bounds[key] ~= value then return "network_bounds_changed; Analyze Network again" end
    end
    local ids = read.ids(32)
    if #ids ~= #n.snapshot.entityIds then return "network_town_index_changed; Analyze Network again" end
    for i, id in ipairs(ids) do
        if id ~= n.snapshot.entityIds[i] then return "network_town_index_changed; Analyze Network again" end
    end
    for _, item in ipairs({{source.id, origin.evidence.residentialCapacitySource},
        {destination.id, origin.evidence.residentialCapacityDestination}}) do
        local value, reason = read.capacity(item[1])
        if reason then return "network_capacity_revalidation_failed: " .. reason end
        if not item[2] or value.value ~= item[2].value then return "network_capacity_changed; Analyze Network again" end
    end
    local ended, reason = read.seconds()
    local valid, unavailable = handoff.available(state, ended)
    if not valid then return reason or unavailable end
    if ended < origin.checkedSeconds then return "network_handoff_clock_reversed" end
    if ended - origin.checkedSeconds > 0.05 then return "network_handoff_work_limit" end
end

-- Small, independent origin descriptor; never change corridor scores/classification.
function handoff.presentation(r, state)
    local o = r and r.networkOrigin
    if not o or r.requestId ~= state.requestId then return nil end
    return {world = o.world, epoch = o.epoch, requestId = r.requestId,
        lines = {"Corridor study from network #" .. o.networkRequestId .. ": " .. o.classification
            .. " #" .. o.sourceId .. " -> #" .. o.destinationId .. ". Status: " .. (r.status or "planning")
            .. (o.worklistDecision and (" | Worklist revision " .. o.worklistDecision.revision .. " (historical)") or ""),
            "Original recommendation: " .. table.concat(o.reasons, ", "):gsub("_", " "),
            "Network provenance: " .. o.snapshotId .. ", ticks " .. o.snapshotStartTick .. "-" .. o.snapshotEndTick .. ".",
            "Fresh terrain study; network evidence remains a historical snapshot. Construction and economic feasibility unverified."
                .. (o.worklistDecision and o.worklistDecision.classificationInterpretation == "historical_only_reassessment_required"
                    and " Original Mainline/Branch interpretation requires reassessment after edits." or "")}}
end
return handoff
