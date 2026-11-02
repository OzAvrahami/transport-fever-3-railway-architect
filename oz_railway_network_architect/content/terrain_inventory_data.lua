-- Pure Lua grid, normalized samples and aggregates. No game API access.
local inventory = {}

function inventory.finite(value)
    if type(value) == "number" and value == value
        and value ~= math.huge and value ~= -math.huge then return value end
    return nil
end

function inventory.text(value)
    return tostring(value):gsub("[%c]", " ")
end

function inventory.number(value)
    return value == nil and "unavailable" or string.format("%.6f", value)
end

function inventory.bounds(raw)
    local bounds = {
        minX = inventory.finite(raw.minX), minY = inventory.finite(raw.minY),
        maxX = inventory.finite(raw.maxX), maxY = inventory.finite(raw.maxY),
    }
    if bounds.minX == nil or bounds.minY == nil or bounds.maxX == nil or bounds.maxY == nil then
        error("terrain bounds: expected four finite coordinates", 0)
    end
    if bounds.maxX <= bounds.minX or bounds.maxY <= bounds.minY
        or inventory.finite(bounds.maxX - bounds.minX) == nil
        or inventory.finite(bounds.maxY - bounds.minY) == nil then
        error("terrain bounds: expected finite positive width and height", 0)
    end
    return bounds
end

function inventory.inside(bounds, x, y)
    return inventory.finite(x) ~= nil and inventory.finite(y) ~= nil
        and x > bounds.minX and x < bounds.maxX and y > bounds.minY and y < bounds.maxY
end

function inventory.new(bounds, nx, ny)
    if inventory.finite(nx) == nil or inventory.finite(ny) == nil then
        error("terrain grid: expected finite dimensions", 0)
    end
    for _, size in ipairs({nx, ny}) do
        if inventory.finite(size) == nil or size % 1 ~= 0 or size < 1 or size > 24 then
            error("terrain grid: dimensions must be integers from 1 to 24", 0)
        end
    end
    return {
        bounds = inventory.bounds(bounds), nx = nx, ny = ny, requested = nx * ny,
        status = "scanning", complete = false, processed = 0,
        valid = 0, invalid = 0, failedSamples = 0, failedReads = 0,
        heightCount = 0, waterCount = 0, waterReads = 0, samples = {}, errors = {},
    }
end

function inventory.position(scan, index)
    local column = (index - 1) % scan.nx
    local row = math.floor((index - 1) / scan.nx)
    local b = scan.bounds
    -- Cell centers, X varying fastest. Never query the bounding-box edges.
    return b.minX + (column + 0.5) / scan.nx * (b.maxX - b.minX),
        b.minY + (row + 0.5) / scan.ny * (b.maxY - b.minY)
end

function inventory.add(scan, raw)
    local sample = {x = inventory.finite(raw.x), y = inventory.finite(raw.y), failedReads = #raw.errors}
    if type(raw.valid) == "boolean" then sample.valid = raw.valid end
    if sample.valid == true then
        sample.height = inventory.finite(raw.height)
        sample.baseHeight = inventory.finite(raw.baseHeight)
        if type(raw.onWater) == "boolean" then sample.onWater = raw.onWater end
    end
    if sample.valid == false then
        sample.status = "invalid"
        scan.invalid = scan.invalid + 1
    elseif sample.valid == true and sample.height ~= nil and sample.baseHeight ~= nil
        and sample.onWater ~= nil and sample.failedReads == 0 then
        sample.status = "ok"
        scan.valid = scan.valid + 1
    else
        sample.status = "read_error"
        scan.failedSamples = scan.failedSamples + 1
    end
    scan.processed = scan.processed + 1
    scan.samples[scan.processed] = sample
    scan.failedReads = scan.failedReads + sample.failedReads
    for _, detail in ipairs(raw.errors) do
        if #scan.errors < 4 then
            scan.errors[#scan.errors + 1] = {index = scan.processed, detail = detail}
        end
    end
    -- Statistics use each available, validated field, including partially read points.
    if sample.height ~= nil then
        scan.heightCount = scan.heightCount + 1
        scan.minimum = scan.minimum == nil and sample.height or math.min(scan.minimum, sample.height)
        scan.maximum = scan.maximum == nil and sample.height or math.max(scan.maximum, sample.height)
        scan.mean = (scan.mean or 0) * (1 - 1 / scan.heightCount) + sample.height / scan.heightCount
    end
    if sample.onWater ~= nil then
        scan.waterReads = scan.waterReads + 1
        if sample.onWater then scan.waterCount = scan.waterCount + 1 end
    end
end

function inventory.finish(scan)
    scan.complete = scan.processed == scan.requested
    if not scan.complete then scan.status = "aborted"
    elseif scan.valid == scan.requested then scan.status = "ok"
    elseif scan.valid == 0 then scan.status = "error"
    else scan.status = "partial" end
end

return inventory
