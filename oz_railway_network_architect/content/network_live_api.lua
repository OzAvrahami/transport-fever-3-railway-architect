-- Native reads only. Inventory normalization and topology policy remain separate.
local live = ug_require "oz_railway_network_architect::/live_plan_api.lua"
local flow = ug_require "oz_railway_network_architect::/live_plan_data.lua"
local adapter = {world = live.world, seconds = live.seconds, bounds = live.bounds,
    town = live.town, ids = live.ids}

function adapter.capacity(id)
    local path = "api.type.enum.LandUseType.RESIDENTIAL"
    local ok, value = pcall(function()
        local index = api.type["enum"].LandUseType.RESIDENTIAL + 1
        path = "api.engine.util.town.getTownCapacityUsage"
        local usages = api.engine.util.town.getTownCapacityUsage(id)
        return usages and usages[index] and usages[index].capacity
    end)
    if not ok then return nil, path .. ": " .. tostring(value) end
    if not flow.id(value) or value > 10000000 then return nil, path .. ": residential capacity unavailable or invalid" end
    return {value = value, source = "api.engine.util.town.getTownCapacityUsage / LandUseType.RESIDENTIAL + 1", basis = "observed"}
end

function adapter.industryIds(limit)
    local ok, value = pcall(function()
        return api.engine.getEntitiesWithComponent(api.type.ComponentType.INDUSTRY)
    end)
    if not ok then error("api.engine.getEntitiesWithComponent(INDUSTRY): " .. tostring(value), 0) end
    return flow.ids(value, limit)
end

-- The accepted industry's collect() reads the whole list synchronously. Read one
-- entity here using its verified contract; reuse its pure normalizer afterward.
function adapter.industry(id)
    local raw, path = {id = id}, "api.engine.entityExists(industry)"
    local ok, reason = pcall(function()
        if not api.engine.entityExists(id) then error("industry unavailable", 0) end
        path = "api.engine.getComponent(INDUSTRY)"
        local ind = api.engine.getComponent(id, api.type.ComponentType.INDUSTRY)
        if ind == nil then error("INDUSTRY unavailable", 0) end
        raw.construction, raw.level = ind.construction, ind.level
        path = "api.engine.entityExists(construction)"
        if not flow.id(raw.construction) or not api.engine.entityExists(raw.construction) then error("construction unavailable", 0) end
        path = "api.engine.getComponent(CONSTRUCTION)"
        local c = api.engine.getComponent(raw.construction, api.type.ComponentType.CONSTRUCTION)
        if c == nil then error("CONSTRUCTION unavailable", 0) end
        raw.resource = c.fileName
        path = "Construction.transf:getTransl()"
        local p = c.transf:getTransl()
        raw.x, raw.y, raw.z = p.x, p.y, p.z
    end)
    if not ok then raw.error = path .. ": " .. tostring(reason) end
    return raw
end
return adapter
