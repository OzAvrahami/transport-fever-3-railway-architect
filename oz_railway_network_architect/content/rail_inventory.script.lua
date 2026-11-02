local adapter = ug_require "oz_railway_network_architect::/rail_inventory_api.lua"
local inventory = ug_require "oz_railway_network_architect::/rail_inventory_data.lua"
local prefix = "[RNA:RAIL:3C] "
local BATCH_SIZE, BATCH_INTERVAL = 32, 4

local function report(message)
    debugPrint(prefix .. message)
end

local function number(value)
    return inventory.finite(value) ~= nil and string.format("%.6f", value) or "unavailable"
end

local function finish(session, aborted)
    session.finished = true
    if aborted then
        session.status = "aborted"
        session.rail = session.rail or {}
        session.rail.status, session.rail.complete = "aborted", false
        report(string.format("PROGRESS edges_read=%d nodes_read=%d complete=false",
            session.rawEdges and #session.rawEdges or 0, session.rawNodes and #session.rawNodes or 0))
    else
        local scan = session.rail
        session.status = scan.status
        report(string.format("SUMMARY segments=%d nodes=%d endpoints=%d junction_candidates=%d multi_segment_nodes=%d graph_segments=%d components=%d isolated_nodes=%d self_loops=%d",
            #scan.segments, #scan.nodes, scan.endpoints, scan.junctionCandidates, scan.multiSegmentNodes,
            scan.graphSegments, scan.components, scan.isolatedNodes, scan.selfLoops))
        report(string.format("VALIDATION duplicates=%d incomplete=%d rejected=%d missing_nodes=%d",
            scan.duplicates, scan.incomplete, scan.rejected, #scan.missingNodeIds))
        report("GEOMETRY chord_total=" .. number(scan.chordTotal) .. " chord_segments=" .. scan.chordSegments
            .. " measure=endpoint_distance_not_track_length")
        for _, detail in ipairs(scan.diagnostics) do
            report("DIAGNOSTIC detail=" .. string.format("%q", inventory.text(detail)))
        end
        if scan.diagnosticCount > #scan.diagnostics then
            report("DIAGNOSTICS_SUPPRESSED count=" .. (scan.diagnosticCount - #scan.diagnostics))
        end
    end
    report("STATIONS status=deferred reason=station_terminal_to_base_edge_mapping_unverified")
    local ended, timerError = adapter.seconds()
    local duration
    if session.started ~= nil and ended ~= nil and ended >= session.started then duration = ended - session.started end
    timerError = session.timerError or timerError
    report("DURATION seconds=" .. number(duration) .. " clock=application_time includes_callback_waits=true"
        .. (timerError and (" error=" .. string.format("%q", inventory.text(timerError))) or ""))
    report((aborted and "SCAN_END" or "SCAN_COMPLETE") .. " status=" .. session.status
        .. " complete=" .. tostring(not aborted))
    -- Keep only the normalized result, or the explicitly incomplete abort marker.
    session.discovery, session.rawEdges, session.rawNodes, session.nodeIds = nil, nil, nil, nil
end

local function begin(session)
    session.started, session.timerError = adapter.seconds()
    report("SCAN_START")
    session.rail = {status = "scanning", complete = false}
    session.discovery = adapter.discover()
    session.rawEdges, session.rawNodes = {}, {}
    session.status, session.phase, session.cursor, session.batchWait = "scanning", "edges", 1, 0
    report(string.format("DISCOVERY unique_segments=%d references=%d batch_size=%d callback_interval=%d",
        #session.discovery.edgeIds, session.discovery.references, BATCH_SIZE, BATCH_INTERVAL))
end

local function batch(session)
    session.batchWait = session.batchWait + 1
    if session.batchWait < BATCH_INTERVAL then return end
    session.batchWait = 0
    local world = adapter.world()
    if world == nil or world.id ~= session.world or world.tick < session.tick then
        error("world unavailable or changed during railway scan", 0)
    end
    session.tick = world.tick
    if session.phase == "edges" then
        local ids = session.discovery.edgeIds
        local last = math.min(session.cursor + BATCH_SIZE - 1, #ids)
        for index = session.cursor, last do session.rawEdges[#session.rawEdges + 1] = adapter.edge(ids[index]) end
        session.cursor = last + 1
        if session.cursor > #ids then
            session.nodeIds = inventory.nodeIds(session.discovery, session.rawEdges)
            session.phase, session.cursor = "nodes", 1
        end
    else
        local last = math.min(session.cursor + BATCH_SIZE - 1, #session.nodeIds)
        for index = session.cursor, last do session.rawNodes[#session.rawNodes + 1] = adapter.node(session.nodeIds[index]) end
        session.cursor = last + 1
        if session.cursor > #session.nodeIds then
            session.rail = inventory.normalize(session.discovery, session.rawEdges, session.rawNodes)
            finish(session, false)
        end
    end
end

function data()
    return {
        guiUpdate = function(_captureParams, _engineState, guiState)
            local session = guiState:get() or {}
            if session.finished then return end
            local ok, reason = pcall(function()
                if not session.initialized then
                    session.initialized, session.polls, session.missingWorld = true, 0, 0
                    session.status = "waiting"
                    report("WAIT_WORLD waiting_for_valid_world_and_tick_advance; unpause_to_scan")
                    local missing = adapter.check()
                    if missing then error(missing, 0) end
                end
                if session.status == "scanning" then batch(session); return end
                -- Same accepted world/tick gate; no railway reads during readiness polling.
                session.polls = session.polls + 1
                if session.polls > 1 and session.polls % 30 ~= 0 then return end
                local world = adapter.world()
                if world == nil then
                    session.missingWorld = session.missingWorld + 1
                    if session.missingWorld >= 60 then error("world unavailable after 60 readiness checks", 0) end
                    return
                end
                session.missingWorld = 0
                if session.world ~= world.id or session.tick == nil or world.tick < session.tick then
                    session.world, session.tick = world.id, world.tick
                    return
                end
                if world.tick <= session.tick then return end
                session.tick = world.tick
                begin(session)
            end)
            if not ok then
                report("SCAN_ABORTED " .. inventory.text(reason))
                finish(session, true)
            end
            -- This Game Script's GUI state only; never engine state or GUI SaveData.
            guiState:set(session)
        end,
    }
end
