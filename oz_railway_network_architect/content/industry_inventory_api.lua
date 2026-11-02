local readiness = ug_require "oz_railway_network_architect::/city_inventory_api.lua"
local inventory = ug_require "oz_railway_network_architect::/industry_inventory_data.lua"
local adapter = {world = readiness.world, seconds = readiness.seconds}

function adapter.check()
    if not api or not api.engine or not api.engine.util or not api.type
        or not api.type.ComponentType then return "required engine namespace unavailable" end
    local engine = api.engine
    local capabilities = {
        {"api.engine.util.getWorld", engine.util.getWorld},
        {"api.engine.entityExists", engine.entityExists},
        {"api.engine.getComponent", engine.getComponent},
        {"api.engine.getEntitiesWithComponent", engine.getEntitiesWithComponent},
        {"api.engine.util.getEntityName", engine.util.getEntityName},
    }
    for _, capability in ipairs(capabilities) do
        if capability[2] == nil then return "required capability unavailable: " .. capability[1] end
    end
    for _, name in ipairs({"GAME_TIME", "INDUSTRY", "CONSTRUCTION"}) do
        if api.type.ComponentType[name] == nil then
            return "required component unavailable: api.type.ComponentType." .. name
        end
    end
    return nil
end

local function addError(record, detail)
    record.error = record.error and (record.error .. "; " .. detail) or detail
end

function adapter.collect()
    local enumerated, ids = pcall(function()
        return api.engine.getEntitiesWithComponent(api.type.ComponentType.INDUSTRY)
    end)
    if not enumerated then error("api.engine.getEntitiesWithComponent(INDUSTRY): " .. tostring(ids), 0) end
    if type(ids) ~= "table" then error("api.engine.getEntitiesWithComponent(INDUSTRY): expected entity array", 0) end
    local records = {}
    for _, id in ipairs(ids) do
        local record = {id = id}
        -- Reject malformed IDs in normalization without passing them into the engine.
        if inventory.entityId(id) ~= nil then
            local path = "api.engine.entityExists(industry)"
            local ok, reason = pcall(function()
                if not api.engine.entityExists(id) then error("industry entity no longer valid", 0) end
                path = "api.engine.getComponent(INDUSTRY)"
                local industry = api.engine.getComponent(id, api.type.ComponentType.INDUSTRY)
                if industry == nil then error("industry component unavailable", 0) end
                record.level = industry.level
                record.construction = industry.construction

                -- Name failure must not hide construction data or coordinates.
                local named, name = pcall(function() return api.engine.util.getEntityName(id) end)
                if named then record.name = name else
                    addError(record, "api.engine.util.getEntityName(industry): " .. tostring(name))
                end

                if inventory.entityId(record.construction) == nil then return end
                path = "api.engine.entityExists(construction)"
                if not api.engine.entityExists(record.construction) then error("construction entity no longer valid", 0) end
                path = "api.engine.getComponent(CONSTRUCTION)"
                local construction = api.engine.getComponent(record.construction, api.type.ComponentType.CONSTRUCTION)
                if construction == nil then return end
                record.resource = construction.fileName
                if construction.transf == nil then return end
                -- Shipped construction-position pattern; no assumed matrix indices.
                path = "Construction.transf:getTransl()"
                local position = construction.transf:getTransl()
                if position ~= nil then
                    record.x, record.y, record.z = position.x, position.y, position.z
                end
            end)
            if not ok then addError(record, path .. ": " .. tostring(reason)) end
        end
        records[#records + 1] = record
    end
    return records
end

return adapter
