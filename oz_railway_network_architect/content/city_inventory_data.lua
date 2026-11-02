-- Pure Lua normalization and log formatting. No game API access.
local inventory = {}

function inventory.finite(value)
    if type(value) == "number" and value == value
        and value ~= math.huge and value ~= -math.huge then
        return value
    end
    return nil
end

function inventory.text(value)
    return tostring(value):gsub("[%c]", " ")
end

function inventory.normalize(raw)
    local records = {}
    local seen = {}
    local rejected = 0
    local incomplete = 0
    for _, item in ipairs(raw) do
        local id = inventory.finite(item.id)
        if id == nil or id < 0 or id % 1 ~= 0 or seen[id] then
            rejected = rejected + 1
        else
            seen[id] = true
            local record = {
                id = id,
                name = type(item.name) == "string" and item.name ~= "" and item.name or nil,
                x = inventory.finite(item.x),
                y = inventory.finite(item.y),
                z = inventory.finite(item.z),
                error = item.error,
            }
            record.status = record.error and "read_error" or "ok"
            if record.name == nil or record.x == nil or record.y == nil or record.z == nil then
                if not record.error then record.status = "missing_data" end
            end
            if record.status ~= "ok" then incomplete = incomplete + 1 end
            records[#records + 1] = record
        end
    end
    table.sort(records, function(a, b) return a.id < b.id end)
    return records, incomplete, rejected
end

local function coordinate(value)
    return value == nil and "unavailable" or string.format("%.6f", value)
end

function inventory.format(record)
    local name = record.name == nil and "unavailable" or string.format("%q", inventory.text(record.name))
    local result = string.format("TOWN id=%s name=%s x=%s y=%s z=%s status=%s",
        tostring(record.id), name, coordinate(record.x), coordinate(record.y),
        coordinate(record.z), record.status)
    if record.error then
        result = result .. " error=" .. string.format("%q", inventory.text(record.error))
    end
    return result
end

return inventory
