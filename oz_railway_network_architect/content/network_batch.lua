-- Session-owned sequential coordinator. No planner implementation or native scheduler.
local flow = ug_require "oz_railway_network_architect::/live_plan_data.lua"
local adapter = ug_require "oz_railway_network_architect::/live_plan_api.lua"
local handoff = ug_require "oz_railway_network_architect::/network_corridor_handoff.lua"
local worklist = ug_require "oz_railway_network_architect::/network_worklist.lua"
local request = ug_require "oz_railway_network_architect::/live_plan_request.lua"
local preview = ug_require "oz_railway_network_architect::/live_plan_preview.lua"
local batch = {}
local function report(message) debugPrint("[RNA:BATCH:5C2] " .. message) end
local function copy(v)
    if type(v) ~= "table" then return v end
    local out = {}; for k, item in pairs(v) do out[k] = copy(item) end; return out
end
function batch.running(b) return b ~= nil and b.status == "running" end

-- Priority is the original one-based recommendation rank (smaller is earlier).
function batch.selection(state)
    if not worklist.matches(state.worklist, state) then return nil, "stale_worklist_snapshot" end
    local selected, seen = {}, {}
    for _, edge in ipairs(state.network.result.recommendations) do
        local decision = worklist.decision(state.worklist, edge.id)
        if edge.status == "recommended" and decision and decision.included and decision.furtherStudy and not seen[edge.id] then
            if not flow.id(edge.priority) or edge.priority < 1 then return nil, "invalid_recommendation_priority" end
            selected[#selected + 1] = {edgeId = edge.id, priority = edge.priority,
                sourceId = edge.sourceId, destinationId = edge.destinationId, classification = edge.classification}
            seen[edge.id] = true
        end
    end
    table.sort(selected, function(a, b)
        if a.priority ~= b.priority then return a.priority < b.priority end
        return a.edgeId < b.edgeId
    end)
    if #selected == 0 then return nil, "no_included_marked_recommendations" end
    if #selected > 4 then return nil, "batch_limit_exceeded: " .. #selected .. " eligible links; maximum 4; edit study flags first" end
    return selected
end

local function identity(b, state)
    return b.world == state.world and b.epoch == state.epoch and worklist.matches(state.worklist, state)
        and b.networkRequestId == state.networkRequestId and b.snapshotId == state.worklist.snapshotId
        and b.revision == state.worklist.revision
end

function batch.start(state, token)
    if not flow.id(token.requestId) or token.requestId ~= (state.batchRequestId or 0) + 1 then
        return nil, "duplicate_or_stale_batch_request"
    end
    -- Consume even rejected explicit starts; retry requires a new click token.
    state.batchRequestId = token.requestId
    if not worklist.matches(state.worklist, state) or token.networkRequestId ~= state.networkRequestId
        or token.snapshotId ~= state.worklist.snapshotId or token.revision ~= state.worklist.revision then
        return nil, "stale_worklist_snapshot"
    end
    local valid, reason = handoff.available(state, adapter.seconds())
    if not valid then return nil, reason end
    local queue; queue, reason = batch.selection(state)
    if not queue then return nil, reason end
    local b = {id = token.requestId, world = state.world, epoch = state.epoch,
        networkRequestId = state.networkRequestId, snapshotId = state.worklist.snapshotId,
        revision = state.worklist.revision, queue = queue, total = #queue, cursor = 1,
        status = "running", results = {}, succeeded = 0, unsupported = 0, unreachable = 0}
    report("START batch=" .. b.id .. " total=" .. b.total .. " revision=" .. b.revision)
    return b
end

local function record(b, status, reason, summary)
    local edge, active = b.queue[b.cursor], b.active
    b.results[#b.results + 1] = {edgeId = edge.edgeId, sourceId = edge.sourceId,
        destinationId = edge.destinationId, classification = edge.classification, priority = edge.priority,
        status = status, reason = flow.text(reason):sub(1, 600), candidateCount = summary and #summary.candidates or 0,
        preferred = summary and copy(summary.candidates[1]) or nil,
        origin = active and copy(active.networkOrigin) or nil,
        constructionStatus = "unverified",
        limitations = "Historical sampled corridor only; demand, economics, between-sample terrain, buildings, stations and construction unverified."}
    if status == "ok" then b.succeeded = b.succeeded + 1 end
    if status == "unsupported" then b.unsupported = b.unsupported + 1 end
    if status == "unreachable" then b.unreachable = b.unreachable + 1 end
    report("RESULT batch=" .. b.id .. " edge=" .. edge.edgeId .. " status=" .. status
        .. " candidates=" .. b.results[#b.results].candidateCount .. " reason=" .. flow.text(reason))
    b.active = nil -- Release ALL terrain grids, caches, search state and route arrays.
    b.cursor = b.cursor + 1
end

function batch.stop(b, status, reason)
    if not batch.running(b) then return end
    if b.active then
        request.invalidate(b.active, reason)
        record(b, status, reason)
    end
    b.status, b.reason = status, flow.text(reason):sub(1, 600)
    b.notStarted = b.total - #b.results
    b.queue = {} -- Pending work is discarded, never resumed implicitly.
    report("STOP batch=" .. b.id .. " status=" .. status .. " reason=" .. flow.text(reason))
end

function batch.cancel(state, token)
    local b = state.batch
    if not batch.running(b) then return false, "no_running_batch" end
    if token.requestId ~= b.id or token.networkRequestId ~= b.networkRequestId
        or token.snapshotId ~= b.snapshotId or token.revision ~= b.revision then
        return false, "stale_batch_cancel"
    end
    batch.stop(b, "cancelled", "cancelled_by_user; completed summaries retained")
    return true
end

local function step(b, state)
    if not identity(b, state) then batch.stop(b, "invalidated", "worklist_or_network_identity_changed"); return end
    if b.active then
        request.step(b.active) -- Exactly one existing continuation; never start another in this callback.
        if not b.active.finished then return end
        local r, summary, invalid = b.active, nil, nil
        if r.status == "ok" then
            summary, invalid = preview.build({request = r, requestId = r.requestId,
                world = state.world, epoch = state.epoch, status = r.status})
        end
        local status, reason = invalid and "error" or r.status, invalid or r.reason
        record(b, status, reason, summary)
        local safe = status == "ok" or status == "unsupported" or status == "unreachable"
            or status == "search_limit" or status == "incomplete"
        if not safe then batch.stop(b, "stopped", reason); return end
        if b.cursor > b.total then
            b.status = b.succeeded == b.total and "completed" or "completed_with_failures"
            b.queue, b.notStarted = {}, 0
            report("COMPLETE batch=" .. b.id .. " status=" .. b.status .. " succeeded=" .. b.succeeded)
        end
        return
    end
    local edge = b.queue[b.cursor]
    local decision = worklist.decision(state.worklist, edge.edgeId)
    if not decision or not decision.included or not decision.furtherStudy then
        batch.stop(b, "invalidated", "connection_no_longer_eligible"); return
    end
    -- The original network age starts at collection, not batch acceptance or the prior route.
    local origin, reason = handoff.prepare(state, {requestId = b.networkRequestId,
        snapshotId = b.snapshotId, edgeId = edge.edgeId})
    if not origin then batch.stop(b, "stopped", reason); return end
    local source, destination = adapter.town(origin.sourceId), adapter.town(origin.destinationId)
    local bounds = adapter.bounds()
    local pair; pair, reason = flow.selected({source, destination}, bounds, origin.sourceId, origin.destinationId)
    if not pair then batch.stop(b, "invalidated", "endpoint_validation_failed: " .. flow.text(reason)); return end
    reason = handoff.validate(state, origin, source, destination, bounds)
    if reason then batch.stop(b, "stopped", reason); return end
    local world = adapter.world()
    if flow.worldChanged(state, world) then batch.stop(b, "invalidated", "world_changed_during_handoff"); return end
    b.active = request.start(world, origin.sourceId, origin.destinationId, b.cursor)
    b.active.networkOrigin = origin
    report("STUDY_START batch=" .. b.id .. " index=" .. b.cursor .. " edge=" .. edge.edgeId)
end

function batch.step(b, state)
    if not batch.running(b) then return end
    local ok, reason = pcall(step, b, state)
    if not ok then batch.stop(b, "stopped", "batch_callback_error: " .. flow.text(reason)) end
end

-- At most four compact records; no continuation, grid or waypoint arrays in responses.
function batch.summary(b)
    if not b then return nil end
    local remaining = batch.running(b) and b.total - #b.results - (b.active and 1 or 0) or 0
    local current = b.active and b.queue[b.cursor].edgeId or nil
    local lines = {string.format("Batch #%d: %s | Selected: %d | Current: %s", b.id, b.status, b.total, current or "none"),
        string.format("Completed: %d | Processed: %d | Unsupported: %d | Unreachable: %d | Remaining: %d | Not started: %d",
            b.succeeded, #b.results, b.unsupported, b.unreachable, remaining, b.notStarted or 0),
        "Construction feasibility: unverified. Original Mainline/Branch labels and evidence are historical; edits may require reassessment."}
    if b.reason then lines[#lines + 1] = b.reason end
    for _, r in ipairs(b.results) do
        lines[#lines + 1] = string.format("%s | %s #%d -> #%d | %s | candidates=%d | %s",
            r.edgeId, r.classification, r.sourceId, r.destinationId, r.status, r.candidateCount, r.reason)
        local c = r.preferred
        if c then lines[#lines + 1] = string.format("Preferred: %s | length %.1f | max gradient %.2f%% | water %s / runs %d / exposure %.1f | relative score %.2f (not cost)",
            c.profile, c.length, c.gradient * 100, tostring(c.water), c.waterRuns, c.waterExposure, c.score.total) end
    end
    return {id = b.id, world = b.world, epoch = b.epoch, networkRequestId = b.networkRequestId,
        snapshotId = b.snapshotId, revision = b.revision, status = b.status, running = batch.running(b),
        total = b.total, currentEdgeId = current, processed = #b.results, completed = b.succeeded,
        unsupported = b.unsupported, unreachable = b.unreachable, remaining = remaining,
        notStarted = b.notStarted or 0, results = copy(b.results), lines = lines}
end
return batch
