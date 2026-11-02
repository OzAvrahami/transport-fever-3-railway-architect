local adapter = ug_require "oz_railway_network_architect::/terrain_inventory_api.lua"
local inventory = ug_require "oz_railway_network_architect::/terrain_inventory_data.lua"
local prefix = "[RNA:TERRAIN:3B] "
local GRID_X, GRID_Y = 24, 24
local BATCH_SIZE, BATCH_INTERVAL = 16, 4

local function report(message)
    debugPrint(prefix .. message)
end

local function finish(session, aborted)
    session.finished = true
    local scan = session.terrain
    if scan then
        if aborted then scan.status, scan.complete = "aborted", false else inventory.finish(scan) end
        for _, entry in ipairs(scan.errors) do
            report(string.format("READ_ERROR sample=%d detail=%q", entry.index, inventory.text(entry.detail)))
        end
        report(string.format("SUMMARY processed=%d requested=%d valid=%d invalid=%d failed_samples=%d failed_reads=%d suppressed_errors=%d",
            scan.processed, scan.requested, scan.valid, scan.invalid, scan.failedSamples,
            scan.failedReads, math.max(0, scan.failedReads - #scan.errors)))
        report("HEIGHT min=" .. inventory.number(scan.minimum) .. " max=" .. inventory.number(scan.maximum)
            .. " mean=" .. inventory.number(scan.mean) .. " height_samples=" .. tostring(scan.heightCount))
        report("WATER count=" .. (scan.waterReads == 0 and "unavailable" or tostring(scan.waterCount))
            .. " water_reads=" .. tostring(scan.waterReads))
    else
        report("BOUNDS unavailable")
        report("SUMMARY processed=0 requested=" .. tostring(GRID_X * GRID_Y)
            .. " valid=0 invalid=0 failed_samples=0 failed_reads=0")
        report("HEIGHT min=unavailable max=unavailable mean=unavailable height_samples=0")
        report("WATER count=unavailable water_reads=0")
    end
    local ended, timerError = adapter.seconds()
    local duration
    if session.started ~= nil and ended ~= nil and ended >= session.started then duration = ended - session.started end
    timerError = session.timerError or timerError
    report("DURATION seconds=" .. inventory.number(duration) .. " clock=application_time includes_callback_waits=true"
        .. (timerError and (" error=" .. string.format("%q", inventory.text(timerError))) or ""))
    session.status = aborted and "aborted" or scan.status
    report((aborted and "SCAN_END" or "SCAN_COMPLETE") .. " status=" .. session.status
        .. " complete=" .. tostring(scan ~= nil and scan.complete))
end

local function begin(session)
    session.started, session.timerError = adapter.seconds()
    report("SCAN_START status=scanning")
    session.terrain = inventory.new(adapter.bounds(), GRID_X, GRID_Y)
    session.status, session.batchWait = "scanning", 0
    local b = session.terrain.bounds
    report("BOUNDS min_x=" .. inventory.number(b.minX) .. " min_y=" .. inventory.number(b.minY)
        .. " max_x=" .. inventory.number(b.maxX) .. " max_y=" .. inventory.number(b.maxY))
end

local function batch(session)
    session.batchWait = session.batchWait + 1
    if session.batchWait < BATCH_INTERVAL then return end
    session.batchWait = 0
    local world = adapter.world()
    if world == nil or world.id ~= session.world or world.tick < session.tick then
        error("world unavailable or changed during terrain scan", 0)
    end
    session.tick = world.tick
    local scan = session.terrain
    local last = math.min(scan.processed + BATCH_SIZE, scan.requested)
    for index = scan.processed + 1, last do
        local x, y = inventory.position(scan, index)
        inventory.add(scan, adapter.sample(scan.bounds, x, y))
    end
    if scan.processed == scan.requested then finish(session, false) end
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
                    report(string.format("GRID columns=%d rows=%d requested=%d batch_size=%d callback_interval=%d",
                        GRID_X, GRID_Y, GRID_X * GRID_Y, BATCH_SIZE, BATCH_INTERVAL))
                    local missing = adapter.check()
                    if missing then error(missing, 0) end
                end
                if session.status == "scanning" then batch(session); return end

                -- Preserve the accepted readiness gate; no terrain reads while waiting.
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
            -- Plain normalized samples live only in this Game Script's GUI state.
            -- Never write engine state, GUI SaveData, savegames or external files.
            guiState:set(session)
        end,
    }
end
