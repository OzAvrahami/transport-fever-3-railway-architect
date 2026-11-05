local readiness = ug_require "oz_railway_network_architect::/city_inventory_api.lua"
local terrain = ug_require "oz_railway_network_architect::/terrain_inventory_api.lua"
local flow = ug_require "oz_railway_network_architect::/live_plan_data.lua"
local adapter = {world = readiness.world, seconds = readiness.seconds, bounds = terrain.bounds}
local entityUtil

function adapter.check()
    local missing = readiness.check()
    if missing then return missing end
    if not api.engine.terrain then return "required namespace unavailable: api.engine.terrain" end
    if not api.type.Vec2f then return "required namespace unavailable: api.type.Vec2f" end
    if api.type.Vec2f.new == nil then return "required capability unavailable: api.type.Vec2f.new" end
    for _, name in ipairs({"getBoundingBox", "isValidCoordinate", "getHeightAt", "isOnWater"}) do
        if api.engine.terrain[name] == nil then return "required capability unavailable: api.engine.terrain." .. name end
    end
    if not api.util or api.util.getApplicationTime == nil then return "required capability unavailable: api.util.getApplicationTime" end
    return nil
end

function adapter.ids(limit)
    local ok, result = pcall(function()
        return api.engine.getEntitiesWithComponent(api.type.ComponentType.TOWN)
    end)
    if not ok then error("api.engine.getEntitiesWithComponent(TOWN): " .. tostring(result), 0) end
    local accepted, ids, rejected = pcall(flow.ids, result, limit)
    if not accepted then error("api.engine.getEntitiesWithComponent(TOWN): " .. tostring(ids), 0) end
    return ids, rejected
end

function adapter.town(id)
    local record = {id = id}
    if not flow.id(id) then record.error = "invalid town entity ID"; return record end
    local path = "api.engine.entityExists(" .. id .. ")"
    local ok, reason = pcall(function()
        if api.engine.entityExists(id) ~= true then error("town unavailable", 0) end
        path = "api.engine.getComponent(TOWN)"
        if api.engine.getComponent(id, api.type.ComponentType.TOWN) == nil then error("TOWN unavailable", 0) end
        local named, name = pcall(function() return api.engine.util.getEntityName(id) end)
        if named then record.name = name else record.error = "api.engine.util.getEntityName: " .. tostring(name) end
        path = "ug_require(::/scripts/entity_util.tl)"
        if entityUtil == nil then entityUtil = ug_require "::/scripts/entity_util.tl" end
        path = "entity_util.getPosition / api.engine.getComponent(BOUNDING_VOLUME)"
        local position = entityUtil.getPosition(id)
        if position ~= nil then record.x, record.y, record.z = position.x, position.y, position.z end
    end)
    if not ok then record.error = (record.error and (record.error .. "; ") or "") .. path .. ": " .. tostring(reason) end
    return record
end

local function sample(bounds, x, y, tolerance)
    local raw = {requestedX = x, requestedY = y, errors = {}}
    local path = "api.type.Vec2f.new"
    local ok, position = pcall(function()
        local p = api.type.Vec2f.new(x, y)
        path = "Vec2f.x/y exact grid-coordinate check"
        raw.x, raw.y = p.x, p.y
        if tolerance then
            path="Vec2f.x/y bounded curve-probe rounding"
            if not flow.finite(raw.x) or not flow.finite(raw.y) or math.abs(raw.x-x)>tolerance or math.abs(raw.y-y)>tolerance then
                error("native_curve_coordinate_precision_limit",0)
            end
        elseif raw.x ~= x or raw.y ~= y then error("native coordinates differ from integer planner grid", 0) end
        return p
    end)
    if not ok then raw.errors[1] = path .. ": " .. tostring(position); return raw end
    local checked, valid = pcall(function() return api.engine.terrain.isValidCoordinate(position) end)
    if not checked or type(valid) ~= "boolean" then
        raw.errors[1] = "api.engine.terrain.isValidCoordinate: " .. (checked and "expected boolean" or tostring(valid))
        return raw
    end
    raw.valid = valid and x > bounds.minX and x < bounds.maxX and y > bounds.minY and y < bounds.maxY
        and raw.x > bounds.minX and raw.x < bounds.maxX and raw.y > bounds.minY and raw.y < bounds.maxY
    if not raw.valid then return raw end
    local heightOk, height = pcall(function() return api.engine.terrain.getHeightAt(position) end)
    if heightOk and flow.finite(height) then raw.height = height else
        raw.errors[#raw.errors + 1] = "api.engine.terrain.getHeightAt: " .. (heightOk and "expected finite number" or tostring(height))
    end
    local waterOk, water = pcall(function() return api.engine.terrain.isOnWater(position) end)
    if waterOk and type(water) == "boolean" then raw.water = water else
        raw.errors[#raw.errors + 1] = "api.engine.terrain.isOnWater: " .. (waterOk and "expected boolean" or tostring(water))
    end
    return raw
end

function adapter.sample(bounds,x,y) return sample(bounds,x,y) end
-- Curve probes are not integer planner samples. Preserve requested geometry and
-- report native probe coordinates; accept at most 1/64 m of Vec2f rounding per axis.
function adapter.sampleCurve(bounds,x,y) return sample(bounds,x,y,1/64) end

return adapter
