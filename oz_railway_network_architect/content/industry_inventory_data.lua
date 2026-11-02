-- Plain Lua data only; no engine access or native objects in normalized records.
local inventory = {}

local function finite(value)
    if type(value) == "number" and value == value
        and value ~= math.huge and value ~= -math.huge then return value end
    return nil
end

local function integer(value)
    local number = finite(value)
    return number ~= nil and number % 1 == 0 and number or nil
end

function inventory.entityId(value)
    local number = integer(value)
    return number ~= nil and number >= 0 and number or nil
end

function inventory.text(value)
    return tostring(value):gsub("[%c]", " ")
end

local function nonempty(value)
    return type(value) == "string" and value ~= "" and value or nil
end

function inventory.normalize(raw)
    local records, seen = {}, {}
    local incomplete, rejected = 0, 0
    for _, item in ipairs(raw) do
        local id = inventory.entityId(item.id)
        if id == nil or seen[id] then
            rejected = rejected + 1
        else
            seen[id] = true
            local record = {
                id = id,
                name = nonempty(item.name),
                resource = nonempty(item.resource),
                level = integer(item.level),
                construction = inventory.entityId(item.construction),
                x = finite(item.x), y = finite(item.y), z = finite(item.z),
                error = nonempty(item.error),
            }
            record.status = record.error and "read_error" or "ok"
            if not record.error and (record.name == nil or record.resource == nil
                or record.level == nil or record.construction == nil
                or record.x == nil or record.y == nil or record.z == nil) then
                record.status = "missing_data"
            end
            if record.status ~= "ok" then incomplete = incomplete + 1 end
            records[#records + 1] = record
        end
    end
    table.sort(records, function(a, b) return a.id < b.id end)
    return records, incomplete, rejected
end

local function quoted(value)
    return value == nil and "unavailable" or string.format("%q", inventory.text(value))
end

local function number(value)
    return value == nil and "unavailable" or tostring(value)
end

local function coordinate(value)
    return value == nil and "unavailable" or string.format("%.6f", value)
end

function inventory.format(record)
    local line = string.format("INDUSTRY id=%s name=%s resource=%s level=%s construction=%s x=%s y=%s z=%s status=%s",
        tostring(record.id), quoted(record.name), quoted(record.resource), number(record.level),
        number(record.construction), coordinate(record.x), coordinate(record.y), coordinate(record.z), record.status)
    if record.error then line = line .. " error=" .. quoted(record.error) end
    return line
end

return inventory
