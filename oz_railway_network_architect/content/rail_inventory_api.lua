local readiness = ug_require "oz_railway_network_architect::/city_inventory_api.lua"
local inventory = ug_require "oz_railway_network_architect::/rail_inventory_data.lua"
local adapter = {world = readiness.world, seconds = readiness.seconds}

function adapter.check()
    if not api or not api.engine or not api.engine.util or not api.engine.system
        or not api.engine.system.streetSystem or not api.type or not api.type.ComponentType
        or not api.type["enum"] or not api.type["enum"].RoadType then
        return "required railway API namespace unavailable"
    end
    local capabilities = {
        {"api.engine.util.getWorld", api.engine.util.getWorld},
        {"api.engine.entityExists", api.engine.entityExists},
        {"api.engine.getComponent", api.engine.getComponent},
        {"api.engine.system.streetSystem.getNode2TrackEdgeMap", api.engine.system.streetSystem.getNode2TrackEdgeMap},
        {"api.type.enum.RoadType.TRACK", api.type["enum"].RoadType.TRACK},
    }
    for _, capability in ipairs(capabilities) do
        if capability[2] == nil then return "required capability unavailable: " .. capability[1] end
    end
    for _, name in ipairs({"GAME_TIME", "BASE_EDGE", "BASE_NODE"}) do
        if api.type.ComponentType[name] == nil then
            return "required component unavailable: api.type.ComponentType." .. name
        end
    end
    return nil
end

function adapter.discover()
    local ok, map = pcall(function() return api.engine.system.streetSystem.getNode2TrackEdgeMap() end)
    if not ok then error("api.engine.system.streetSystem.getNode2TrackEdgeMap(): " .. tostring(map), 0) end
    local normalized, result = pcall(inventory.discover, map)
    if not normalized then error("api.engine.system.streetSystem.getNode2TrackEdgeMap(): " .. tostring(result), 0) end
    return result
end

local function position(value)
    if value == nil then return nil end
    return {x = value.x, y = value.y, z = value.z}
end

function adapter.edge(id)
    local record = {id = id}
    if inventory.id(id) == nil then record.error = "invalid segment entity ID"; return record end
    local path = "api.engine.entityExists(" .. id .. ")"
    local ok, reason = pcall(function()
        if api.engine.entityExists(id) ~= true then error("segment entity unavailable", 0) end
        path = "api.engine.getComponent(" .. id .. ", BASE_EDGE)"
        local edge = api.engine.getComponent(id, api.type.ComponentType.BASE_EDGE)
        if edge == nil then error("BASE_EDGE unavailable", 0) end
        path = "BASE_EDGE(" .. id .. ").roadType"
        record.isTrack = edge.roadType == api.type["enum"].RoadType.TRACK
        if not record.isTrack then error("not RoadType.TRACK", 0) end
        path = "BASE_EDGE(" .. id .. ").node0/node1"
        record.node0, record.node1 = edge.node0, edge.node1
        path = "BASE_EDGE(" .. id .. ").position0"
        record.position0 = position(edge.position0)
        path = "BASE_EDGE(" .. id .. ").position1"
        record.position1 = position(edge.position1)
        path = "BASE_EDGE(" .. id .. ").roadTemplate"
        record.template = edge.roadTemplate
    end)
    if not ok then record.error = path .. ": " .. tostring(reason) end
    return record
end

function adapter.node(id)
    local record = {id = id, available = false}
    if inventory.id(id) == nil then record.error = "invalid node entity ID"; return record end
    local path = "api.engine.entityExists(" .. id .. ")"
    local ok, reason = pcall(function()
        if api.engine.entityExists(id) ~= true then error("node entity unavailable", 0) end
        path = "api.engine.getComponent(" .. id .. ", BASE_NODE)"
        local node = api.engine.getComponent(id, api.type.ComponentType.BASE_NODE)
        if node == nil then error("BASE_NODE unavailable", 0) end
        record.available = true
        path = "BASE_NODE(" .. id .. ").position"
        record.position = position(node.position)
    end)
    if not ok then record.error = path .. ": " .. tostring(reason) end
    return record
end

return adapter
