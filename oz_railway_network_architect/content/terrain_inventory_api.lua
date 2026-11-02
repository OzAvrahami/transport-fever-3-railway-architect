local readiness = ug_require "oz_railway_network_architect::/city_inventory_api.lua"
local inventory = ug_require "oz_railway_network_architect::/terrain_inventory_data.lua"
local adapter = {world = readiness.world, seconds = readiness.seconds}

function adapter.check()
    if not api or not api.engine or not api.engine.terrain or not api.engine.util
        or not api.type or not api.type.ComponentType or not api.type.Vec2f then
        return "required terrain/readiness namespace unavailable"
    end
    for _, name in ipairs({"getBoundingBox", "isValidCoordinate", "getHeightAt", "getBaseHeightAt", "isOnWater"}) do
        if api.engine.terrain[name] == nil then return "required capability unavailable: api.engine.terrain." .. name end
    end
    local required = {
        {"api.type.Vec2f.new", api.type.Vec2f.new},
        {"api.engine.util.getWorld", api.engine.util.getWorld},
        {"api.engine.entityExists", api.engine.entityExists},
        {"api.engine.getComponent", api.engine.getComponent},
        {"api.type.ComponentType.GAME_TIME", api.type.ComponentType.GAME_TIME},
    }
    for _, entry in ipairs(required) do
        if entry[2] == nil then return "required capability unavailable: " .. entry[1] end
    end
    return nil
end

function adapter.bounds()
    local ok, result = pcall(function()
        local box = api.engine.terrain.getBoundingBox()
        return {minX = box.min.x, minY = box.min.y, maxX = box.max.x, maxY = box.max.y}
    end)
    if not ok then error("api.engine.terrain.getBoundingBox / Box2f.min/max: " .. tostring(result), 0) end
    return inventory.bounds(result)
end

function adapter.sample(bounds, x, y)
    local raw = {x = x, y = y, errors = {}}
    local path = "api.type.Vec2f.new"
    local built, position = pcall(function()
        local value = api.type.Vec2f.new(x, y)
        path = "api.type.Vec2f.x/y"
        -- Keep the actual vector coordinates used by the engine (float rounding included).
        raw.x, raw.y = value.x, value.y
        if inventory.finite(raw.x) == nil or inventory.finite(raw.y) == nil then
            error("expected finite coordinates", 0)
        end
        return value
    end)
    if not built then
        raw.errors[1] = path .. ": " .. tostring(position)
        return raw
    end
    local checked, valid = pcall(function() return api.engine.terrain.isValidCoordinate(position) end)
    if not checked or type(valid) ~= "boolean" then
        raw.errors[1] = "api.engine.terrain.isValidCoordinate: "
            .. (checked and ("expected boolean, got " .. type(valid)) or tostring(valid))
        return raw
    end
    raw.valid = valid and inventory.inside(bounds, raw.x, raw.y)
    if not raw.valid then return raw end -- Never query clamped heights for an invalid point.

    local ok, height = pcall(function() return api.engine.terrain.getHeightAt(position) end)
    if ok and inventory.finite(height) ~= nil then raw.height = height else
        raw.errors[#raw.errors + 1] = "api.engine.terrain.getHeightAt: "
            .. (ok and "expected finite number" or tostring(height))
    end
    local baseOk, baseHeight = pcall(function() return api.engine.terrain.getBaseHeightAt(position) end)
    if baseOk and inventory.finite(baseHeight) ~= nil then raw.baseHeight = baseHeight else
        raw.errors[#raw.errors + 1] = "api.engine.terrain.getBaseHeightAt: "
            .. (baseOk and "expected finite number" or tostring(baseHeight))
    end
    local waterOk, onWater = pcall(function() return api.engine.terrain.isOnWater(position) end)
    if waterOk and type(onWater) == "boolean" then raw.onWater = onWater else
        raw.errors[#raw.errors + 1] = "api.engine.terrain.isOnWater: "
            .. (waterOk and ("expected boolean, got " .. type(onWater)) or tostring(onWater))
    end
    return raw
end

return adapter
