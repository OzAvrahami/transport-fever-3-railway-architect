local adapter = ug_require "oz_railway_network_architect::/city_inventory_api.lua"
local inventory = ug_require "oz_railway_network_architect::/city_inventory_data.lua"
local prefix = "[RNA:CITY:2B] "

local function report(message)
    debugPrint(prefix .. message)
end

local function scan()
    report("SCAN_START")
    local started, startError = adapter.seconds()
    local ok, records, incomplete, rejected = pcall(function()
        return inventory.normalize(adapter.collect())
    end)
    if ok then
        for _, record in ipairs(records) do report(inventory.format(record)) end
        report(string.format("TOTAL count=%d incomplete=%d rejected=%d", #records, incomplete, rejected))
    else
        report("SCAN_ERROR " .. inventory.text(records))
        report("TOTAL count=unavailable")
    end
    local finished, finishError = adapter.seconds()
    local duration = "unavailable"
    if started ~= nil and finished ~= nil and finished >= started then
        duration = string.format("%.6f", finished - started)
    end
    local timerError = startError or finishError
    report("DURATION seconds=" .. duration .. " clock=application_time includes_record_logging=true"
        .. (timerError and (" error=" .. string.format("%q", inventory.text(timerError))) or ""))
    local status = "error"
    if ok then status = (incomplete > 0 or rejected > 0) and "partial" or "ok" end
    report("SCAN_COMPLETE status=" .. status)
end

function data()
    return {
        guiUpdate = function(_captureParams, _engineState, guiState)
            -- Only GUI callback state is changed. Never write engine state or GUI SaveData.
            local session = guiState:get() or {}
            if session.finished then return end
            local ok, reason = pcall(function()
                if not session.initialized then
                    session.initialized = true
                    session.polls = 0
                    session.missingWorld = 0
                    report("WAIT_WORLD waiting_for_valid_world_and_tick_advance; unpause_to_scan")
                    local missing = adapter.check()
                    if missing then error(missing) end
                end

                -- Bounded readiness checks; never enumerate towns while waiting.
                session.polls = session.polls + 1
                if session.polls > 1 and session.polls % 30 ~= 0 then return end
                local world = adapter.world()
                if world == nil then
                    session.missingWorld = session.missingWorld + 1
                    if session.missingWorld >= 60 then error("world unavailable after 60 readiness checks") end
                    return
                end
                session.missingWorld = 0
                if session.world ~= world.id or session.tick == nil or world.tick < session.tick then
                    session.world = world.id
                    session.tick = world.tick
                    return
                end
                if world.tick <= session.tick then return end

                -- Mark attempted before scanning, even on error; no automatic log/retry storm.
                session.finished = true
                guiState:set(session)
                scan()
            end)
            if not ok then
                session.finished = true
                report("SCAN_ABORTED " .. inventory.text(reason))
            end
            guiState:set(session)
        end,
    }
end
