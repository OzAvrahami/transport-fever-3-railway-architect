-- TF3 integration only. Imported utility modules are resolved during the scan.
local adapter = {}

function adapter.check()
    if not api then return "required namespace unavailable: api actual=" .. type(api) end
    if not api.engine then return "required namespace unavailable: api.engine actual=" .. type(api.engine) end
    if not api.engine.util then return "required namespace unavailable: api.engine.util actual=" .. type(api.engine.util) end
    if not api.type then return "required namespace unavailable: api.type actual=" .. type(api.type) end
    if not api.type.ComponentType then
        return "required namespace unavailable: api.type.ComponentType actual=" .. type(api.type.ComponentType)
    end
    local engine = api.engine
    -- Check presence only. Documented bindings need not have Lua type "function".
    local failures = {}
    local functions = {
        {"api.engine.util.getWorld", engine.util.getWorld},
        {"api.engine.entityExists", engine.entityExists},
        {"api.engine.getComponent", engine.getComponent},
        {"api.engine.getEntitiesWithComponent", engine.getEntitiesWithComponent},
        {"api.engine.util.getEntityName", engine.util.getEntityName},
        {"ug_require", ug_require},
    }
    for _, capability in ipairs(functions) do
        if capability[2] == nil then
            failures[#failures + 1] = capability[1] .. " expected=present actual=nil"
        end
    end
    local component = api.type.ComponentType
    for _, name in ipairs({"GAME_TIME", "TOWN", "BOUNDING_VOLUME"}) do
        if component[name] == nil then
            failures[#failures + 1] = "api.type.ComponentType." .. name .. " expected=present actual=nil"
        end
    end
    if #failures > 0 then
        return "required capabilities unavailable: " .. table.concat(failures, "; ")
    end
    return nil
end

function adapter.world()
    local path = "api.engine.util.getWorld"
    local ok, result = pcall(function()
        local world = api.engine.util.getWorld()
        if world == nil then return nil end
        path = "api.engine.entityExists"
        if not api.engine.entityExists(world) then return nil end
        path = "api.engine.getComponent(GAME_TIME)"
        local time = api.engine.getComponent(world, api.type.ComponentType.GAME_TIME)
        if time == nil or type(time.tickCount) ~= "number" or time.tickCount < 0
            or time.tickCount ~= time.tickCount or time.tickCount == math.huge then return nil end
        return {id = world, tick = time.tickCount}
    end)
    if not ok then error(path .. ": " .. tostring(result), 0) end
    return result
end

function adapter.seconds()
    if api and api.util and api.util.getApplicationTime ~= nil then
        local ok, value = pcall(function() return api.util.getApplicationTime() end)
        if not ok then return nil, "api.util.getApplicationTime: " .. tostring(value) end
        if ok and type(value) == "number" and value == value
            and value ~= math.huge and value ~= -math.huge then
            return value
        end
    end
    return nil
end

function adapter.collect()
    -- Explicit :: selects base-game content; Lua can import shipped Teal modules.
    local town = ug_require "::/game_mechanics/towns/town_util.tl"
    local entity = ug_require "::/scripts/entity_util.tl"
    if type(town) ~= "table" or town.getTownName == nil
        or type(entity) ~= "table" or entity.getPosition == nil then
        error("required town/entity utility export unavailable")
    end
    local enumerated, ids = pcall(function()
        return api.engine.getEntitiesWithComponent(api.type.ComponentType.TOWN)
    end)
    if not enumerated then error("api.engine.getEntitiesWithComponent: " .. tostring(ids), 0) end
    if type(ids) ~= "table" then error("api.engine.getEntitiesWithComponent: town enumeration returned no table") end
    local records = {}
    for _, id in ipairs(ids) do
        local record = {id = id}
        local path = "api.engine.entityExists"
        local ok, reason = pcall(function()
            if not api.engine.entityExists(id) then error("town entity no longer valid") end
            path = "api.engine.getComponent(TOWN)"
            if api.engine.getComponent(id, api.type.ComponentType.TOWN) == nil then error("town entity no longer valid") end
            -- Keep each field read independent so a missing name cannot hide coordinates.
            local nameOk, name = pcall(function() return town.getTownName(id) end)
            if nameOk then record.name = name else
                record.error = "town_util.getTownName / api.engine.util.getEntityName: " .. tostring(name)
            end
            path = "entity_util.getPosition / api.engine.getComponent(BOUNDING_VOLUME)"
            local posOk, position = pcall(function() return entity.getPosition(id) end)
            if posOk and position ~= nil then
                record.x = position.x
                record.y = position.y
                record.z = position.z
            elseif not posOk then
                local detail = path .. ": " .. tostring(position)
                record.error = record.error and (record.error .. "; " .. detail) or detail
            end
        end)
        if not ok then record.error = path .. ": " .. tostring(reason) end
        records[#records + 1] = record
    end
    return records
end

return adapter
