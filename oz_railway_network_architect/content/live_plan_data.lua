-- Plain data preparation for the bounded live prototype; no engine access.
local flow = {}

function flow.config()
    return {maxTowns = 256, gridLimit = 32, maxSnap = 96, maxRelativeSnap = 0.1,
        maxExpansions = 3072, waterPolicy = "exclude", workBudgetSeconds = 0.05, maxAgeSeconds = 60}
end

function flow.finite(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

function flow.id(value)
    return flow.finite(value) and value >= 0 and value % 1 == 0
end

function flow.checkConfig(config)
    for _, rule in ipairs({{"maxTowns", 2, 256, true}, {"gridLimit", 2, 32, true},
        {"maxSnap", 0, 96}, {"maxRelativeSnap", 0, 0.1}, {"maxExpansions", 1, 3072, true},
        {"workBudgetSeconds", 0.001, 0.05}, {"maxAgeSeconds", 1, 60}}) do
        local value = config[rule[1]]
        if not flow.finite(value) or value < rule[2] or value > rule[3] or (rule[4] and value % 1 ~= 0) then
            return "unsupported prototype configuration: " .. rule[1]
        end
    end
    if config.waterPolicy ~= "exclude" and config.waterPolicy ~= "penalize" then return "unsupported waterPolicy" end
    return nil
end

function flow.text(value)
    return tostring(value):gsub("[%c]", " "):sub(1, 400)
end

function flow.number(value)
    return flow.finite(value) and string.format("%.6f", value) or "unavailable"
end

function flow.ids(raw, limit)
    if type(raw) ~= "table" then error("TOWN enumeration: expected entity array", 0) end
    local ids, seen, count, rejected = {}, {}, 0, 0
    for _, id in pairs(raw) do
        count = count + 1
        if count > limit then error("town enumeration limit exceeded; no truncated selection", 0) end
        if not flow.id(id) or seen[id] then rejected = rejected + 1 else
            seen[id] = true; ids[#ids + 1] = id
        end
    end
    table.sort(ids)
    return ids, rejected
end

function flow.validTown(town, bounds)
    return flow.id(town.id) and flow.finite(town.x) and flow.finite(town.y) and flow.finite(town.z)
        and town.x > bounds.minX and town.x < bounds.maxX
        and town.y > bounds.minY and town.y < bounds.maxY
end

function flow.select(towns, bounds, config)
    if #towns > config.maxTowns then return nil, "town_limit" end
    local valid, seen, rejected = {}, {}, 0
    for _, town in ipairs(towns) do
        if flow.validTown(town, bounds) and not seen[town.id] then
            valid[#valid + 1] = town; seen[town.id] = true
        else rejected = rejected + 1 end
    end
    table.sort(valid, function(a, b) return a.id < b.id end)
    local stats = {valid = #valid, rejected = rejected}
    if #valid < 2 then return nil, "fewer_than_two_valid_towns", stats end
    local best, distanceSquared
    for a = 1, #valid - 1 do
        for b = a + 1, #valid do
            local d = (valid[a].x - valid[b].x)^2 + (valid[a].y - valid[b].y)^2
            if flow.finite(d) and d > 0 and (distanceSquared == nil or d < distanceSquared) then
                best, distanceSquared = {start = valid[a], destination = valid[b]}, d
            end
        end
    end
    if not best then return nil, "no_distinct_anchor_positions", stats end
    best.distance = math.sqrt(distanceSquared)
    best.method = "closest_valid_pair_xy_then_entity_id"
    return best, nil, stats
end

local function axis(a, b, minimum, maximum, spacing, limit)
    local low, high = math.ceil(minimum + 1), math.floor(maximum - 1)
    local first, last = math.min(a, b), math.max(a, b)
    if first < low or last > high then return nil end
    local wantedLow = math.max(low, math.floor(first - spacing))
    local wantedHigh = math.min(high, math.ceil(last + spacing))
    local count = math.min(math.ceil((wantedHigh - wantedLow) / spacing) + 1,
        math.floor((high - low) / spacing) + 1)
    if count < 2 or count > limit then return nil end
    local origin = math.max(low, math.min(wantedLow, high - (count - 1) * spacing))
    if origin > first or origin + (count - 1) * spacing < last then return nil end
    return {origin = origin, count = count}
end

function flow.position(layout, index)
    return layout.originX + ((index - 1) % layout.columns) * layout.spacing,
        layout.originY + math.floor((index - 1) / layout.columns) * layout.spacing
end

local function snap(layout, town)
    local c = math.floor((town.x - layout.originX) / layout.spacing + 0.5)
    local r = math.floor((town.y - layout.originY) / layout.spacing + 0.5)
    local id = r * layout.columns + c + 1
    local x, y = flow.position(layout, id)
    return {sampleId = id, x = x, y = y, dx = x - town.x, dy = y - town.y,
        distance = math.sqrt((x - town.x)^2 + (y - town.y)^2)}
end

function flow.layout(pair, bounds, config)
    for _, key in ipairs({"minX", "minY", "maxX", "maxY"}) do
        if not flow.finite(bounds[key]) or math.abs(bounds[key]) > 1e6 then return nil, "unsupported_map_bounds" end
    end
    if bounds.maxX <= bounds.minX or bounds.maxY <= bounds.minY then return nil, "invalid_map_bounds" end
    local lastReason = "pair_exceeds_grid_resolution_or_boundary_margin"
    for _, spacing in ipairs({32, 64, 128}) do
        local x = axis(pair.start.x, pair.destination.x, bounds.minX, bounds.maxX, spacing, config.gridLimit)
        local y = axis(pair.start.y, pair.destination.y, bounds.minY, bounds.maxY, spacing, config.gridLimit)
        if x and y then
            local layout = {columns = x.count, rows = y.count, originX = x.origin, originY = y.origin, spacing = spacing}
            layout.requested = layout.columns * layout.rows
            layout.start, layout.destination = snap(layout, pair.start), snap(layout, pair.destination)
            local allowance = math.min(config.maxSnap, pair.distance * config.maxRelativeSnap)
            if layout.start.sampleId == layout.destination.sampleId then lastReason = "anchors_snap_to_same_sample"
            elseif layout.start.distance > allowance or layout.destination.distance > allowance then
                lastReason = "endpoint_approximation_exceeds_limit"
            else return layout end
        end
    end
    return nil, lastReason
end

function flow.add(session, raw)
    local index = #session.samples + 1
    session.samples[index] = raw -- Retain actual query coordinates and partial values.
    if raw.valid == false then session.invalidSamples = session.invalidSamples + 1
    elseif raw.valid == true and flow.finite(raw.height) and type(raw.water) == "boolean" and #raw.errors == 0 then
        session.validSamples = session.validSamples + 1
    else session.failedSamples = session.failedSamples + 1 end
    session.failedReads = session.failedReads + #raw.errors
    for _, reason in ipairs(raw.errors) do
        if #session.examples < 4 then session.examples[#session.examples + 1] = "sample " .. index .. ": " .. reason end
    end
end

function flow.input(session, config)
    local layout, cells = session.layout, {}
    for index = 1, layout.requested do
        local raw = session.samples[index]
        local cell = {}
        if raw and raw.valid == true then
            if flow.finite(raw.height) then cell.height = raw.height end
            if type(raw.water) == "boolean" then cell.water = raw.water end
        end
        -- Obstacle fields are deliberately absent: no obstacle source is verified.
        cells[index] = cell
    end
    return {start = {x = layout.start.x, y = layout.start.y},
        destination = {x = layout.destination.x, y = layout.destination.y},
        grid = {columns = layout.columns, rows = layout.rows, originX = layout.originX, originY = layout.originY,
            spacingX = layout.spacing, spacingY = layout.spacing, unit = "world_units", cells = cells},
        constraints = {waterPolicy = config.waterPolicy},
        limits = {maxCells = config.gridLimit^2, maxExpansions = config.maxExpansions}}
end

function flow.worldChanged(session, world)
    return world == nil or world.id ~= session.world or not flow.finite(world.tick) or world.tick < session.tick
end

function flow.sameTown(a, b)
    return b ~= nil and a.id == b.id and a.x == b.x and a.y == b.y and a.z == b.z
end

return flow
