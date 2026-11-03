-- Pure input validation and sampled-grid transitions. No game or file access.
local grid = {}
local MAX_CELLS, MAX_DIMENSION, MAX_EXPANSIONS = 16384, 256, 49152
local names = {"distance", "terrain", "balanced"}
local defaults = {
    distance = {distance = 1, gradient = 0, water = 0, obstacle = 0},
    terrain = {distance = 1, gradient = 40, water = 8, obstacle = 8},
    balanced = {distance = 1, gradient = 8, water = 2, obstacle = 2},
}

local function fail(path, message, code)
    error({code = code or "invalid_input", path = path, message = message}, 0)
end

local function default(value, fallback)
    if value == nil then return fallback end
    return value
end

local function record(value, path, allowed)
    if type(value) ~= "table" or getmetatable(value) ~= nil then fail(path, "expected a plain table without a metatable") end
    -- Fixed-size records: stop on the first unsupported key, without copying input.
    for key in pairs(value) do
        if not allowed[key] then fail(path, "unsupported field") end
    end
    return value
end

local function number(value, path, minimum, maximum, integer)
    if type(value) ~= "number" or value ~= value or value < minimum or value > maximum
        or (integer and value % 1 ~= 0) then
        fail(path, "expected finite " .. (integer and "integer" or "number")
            .. " in [" .. minimum .. ", " .. maximum .. "]")
    end
    return value
end

local function boolean(value, path, default)
    if value == nil then return default end
    if type(value) ~= "boolean" then fail(path, "expected boolean") end
    return value
end

local function stringValue(value, path, maximum)
    if type(value) ~= "string" or #value == 0 or #value > maximum then
        fail(path, "expected nonempty bounded string")
    end
    return value
end

local function array(value, path, maximum, expected)
    if type(value) ~= "table" or getmetatable(value) ~= nil then fail(path, "expected plain dense array") end
    local count = 0
    for key in pairs(value) do
        count = count + 1
        if count > maximum then fail(path, "array limit exceeded", "input_limit") end
        number(key, path .. " index", 1, maximum, true)
    end
    if expected and count ~= expected then fail(path, "incorrect array size") end
    for index = 1, count do
        if value[index] == nil then fail(path, "sparse arrays are unsupported") end
    end
    return count
end

local function weights(raw, fallback, path)
    raw = record(default(raw, {}), path, {distance = true, gradient = true, water = true, obstacle = true})
    local result = {}
    for _, key in ipairs({"distance", "gradient", "water", "obstacle"}) do
        local value = raw[key]
        if value == nil then value = fallback[key] end
        result[key] = number(value, path .. "." .. key, key == "distance" and 0.000001 or 0, 1000000)
    end
    return result
end

function grid.validate(input)
    record(input, "input", {start = true, destination = true, grid = true, constraints = true,
        profiles = true, rankingWeights = true, minDifference = true, limits = true, infrastructureHints = true})
    local limits = record(default(input.limits, {}), "limits", {maxCells = true, maxExpansions = true})
    local maxCells = number(default(limits.maxCells, MAX_CELLS), "limits.maxCells", 1, MAX_CELLS, true)
    local maxExpansions = number(default(limits.maxExpansions, MAX_EXPANSIONS), "limits.maxExpansions", 1, MAX_EXPANSIONS, true)
    local raw = record(input.grid, "grid", {columns = true, rows = true, originX = true, originY = true,
        spacingX = true, spacingY = true, unit = true, cells = true})
    local model = {
        columns = number(raw.columns, "grid.columns", 1, MAX_DIMENSION, true),
        rows = number(raw.rows, "grid.rows", 1, MAX_DIMENSION, true),
        originX = number(raw.originX, "grid.originX", -1e9, 1e9),
        originY = number(raw.originY, "grid.originY", -1e9, 1e9),
        spacingX = number(raw.spacingX, "grid.spacingX", 0.001, 1e6),
        spacingY = number(raw.spacingY, "grid.spacingY", 0.001, 1e6),
        unit = stringValue(raw.unit, "grid.unit", 32),
        cells = {}, unknownCells = 0, maxExpansions = maxExpansions, maxCells = maxCells,
    }
    local count = model.columns * model.rows
    if count > maxCells then fail("grid", "cell limit exceeded", "input_limit") end
    number(model.originX + (model.columns - 1) * model.spacingX, "grid maximum X", -1e9, 1e9)
    number(model.originY + (model.rows - 1) * model.spacingY, "grid maximum Y", -1e9, 1e9)
    array(raw.cells, "grid.cells", count, count)
    local constraints = record(default(input.constraints, {}), "constraints",
        {allowDiagonal = true, waterPolicy = true, maxGradient = true})
    model.allowDiagonal = boolean(constraints.allowDiagonal, "constraints.allowDiagonal", true)
    model.waterPolicy = default(constraints.waterPolicy, "penalize")
    if model.waterPolicy ~= "penalize" and model.waterPolicy ~= "exclude" then
        fail("constraints.waterPolicy", "expected penalize or exclude")
    end
    if constraints.maxGradient ~= nil then
        model.maxGradient = number(constraints.maxGradient, "constraints.maxGradient", 0, 1e6)
    end
    for id = 1, count do
        local path = "grid.cells[" .. id .. "]"
        local cell = record(raw.cells[id], path, {height = true, water = true, blocked = true, obstaclePenalty = true})
        local height
        if cell.height ~= nil then height = number(cell.height, path .. ".height", -1e6, 1e6) end
        local water = boolean(cell.water, path .. ".water", nil)
        local blocked = boolean(cell.blocked, path .. ".blocked", false)
        local penalty = number(default(cell.obstaclePenalty, 0), path .. ".obstaclePenalty", 0, 1e6)
        local unknown = height == nil or water == nil
        if unknown then model.unknownCells = model.unknownCells + 1 end
        model.cells[id] = {height = height, water = water, obstaclePenalty = penalty,
            traversable = not unknown and not blocked and not (water and model.waterPolicy == "exclude")}
    end
    local function endpoint(location, path)
        record(location, path, {x = true, y = true})
        local x = number(location.x, path .. ".x", -1e9, 1e9)
        local y = number(location.y, path .. ".y", -1e9, 1e9)
        local column = (x - model.originX) / model.spacingX
        local row = (y - model.originY) / model.spacingY
        local c, r = math.floor(column + 0.5), math.floor(row + 0.5)
        -- Compare reconstructed world positions: subtract/divide can lose precision
        -- for a fine grid far from the origin even when x/y are exact sample values.
        if math.abs(x - (model.originX + c * model.spacingX)) > model.spacingX * 1e-6
            or math.abs(y - (model.originY + r * model.spacingY)) > model.spacingY * 1e-6 then
            fail(path, "location must coincide with a grid sample; no arbitrary snapping")
        end
        if c < 0 or c >= model.columns or r < 0 or r >= model.rows then fail(path, "outside grid") end
        return r * model.columns + c + 1
    end
    model.start, model.destination = endpoint(input.start, "start"), endpoint(input.destination, "destination")
    local profiles = record(default(input.profiles, {}), "profiles", {distance = true, terrain = true, balanced = true})
    model.profiles = {}
    for _, name in ipairs(names) do
        model.profiles[#model.profiles + 1] = {name = name, weights = weights(profiles[name], defaults[name], "profiles." .. name)}
    end
    -- Ranking is shared by all routes and is independent of search-profile overrides.
    model.rankingWeights = weights(input.rankingWeights, defaults.balanced, "rankingWeights")
    model.minDifference = number(input.minDifference == nil and 0.25 or input.minDifference, "minDifference", 0, 1)
    model.hintCount = 0
    if input.infrastructureHints ~= nil then
        model.hintCount = array(input.infrastructureHints, "infrastructureHints", 256)
        for index = 1, model.hintCount do
            local path = "infrastructureHints[" .. index .. "]"
            local hint = record(input.infrastructureHints[index], path,
                {id = true, x = true, y = true, verified = true, source = true})
            stringValue(hint.id, path .. ".id", 128)
            stringValue(hint.source, path .. ".source", 256)
            number(hint.x, path .. ".x", -1e9, 1e9)
            number(hint.y, path .. ".y", -1e9, 1e9)
            if hint.verified ~= true then fail(path .. ".verified", "caller must supply verified provenance") end
        end
    end
    return model
end

function grid.indices(model, id)
    return (id - 1) % model.columns, math.floor((id - 1) / model.columns)
end

function grid.waypoint(model, id)
    local column, row = grid.indices(model, id)
    return {sampleId = id, x = model.originX + column * model.spacingX,
        y = model.originY + row * model.spacingY, z = model.cells[id].height, water = model.cells[id].water}
end

local function gradeAllowed(model, a, b, distance)
    return model.maxGradient == nil or math.abs(a.height - b.height) / distance <= model.maxGradient
end

-- Returns additive raw metrics, or nil for a forbidden transition.
function grid.step(model, from, to)
    local a, b = model.cells[from], model.cells[to]
    if not a or not b or not a.traversable or not b.traversable then return nil end
    local ac, ar = grid.indices(model, from)
    local bc, br = grid.indices(model, to)
    local dc, dr = math.abs(ac - bc), math.abs(ar - br)
    if dc > 1 or dr > 1 or dc + dr == 0 then return nil end
    if dc == 1 and dr == 1 then
        if not model.allowDiagonal then return nil end
        local c, d = model.cells[ar * model.columns + bc + 1], model.cells[br * model.columns + ac + 1]
        -- Both orthogonal ways around the corner must be admissible, including grade.
        if not c.traversable or not d.traversable
            or not gradeAllowed(model, a, c, model.spacingX) or not gradeAllowed(model, c, b, model.spacingY)
            or not gradeAllowed(model, a, d, model.spacingY) or not gradeAllowed(model, d, b, model.spacingX) then return nil end
    end
    local horizontal = math.sqrt((dc * model.spacingX)^2 + (dr * model.spacingY)^2)
    if not gradeAllowed(model, a, b, horizontal) then return nil end
    local dz = b.height - a.height
    local gradient = math.abs(dz) / horizontal
    return {horizontal = horizontal, length = math.sqrt(horizontal^2 + dz^2), dz = dz,
        gradient = gradient, gradientExposure = horizontal * gradient^2,
        waterExposure = (a.water or b.water) and horizontal or 0,
        obstacleExposure = horizontal * (a.obstaclePenalty + b.obstaclePenalty) / 2}
end

function grid.score(metrics, weights)
    local result = {distance = metrics.length * weights.distance,
        gradient = metrics.gradientExposure * weights.gradient,
        water = metrics.waterExposure * weights.water, obstacle = metrics.obstacleExposure * weights.obstacle}
    result.waterObstacle = result.water + result.obstacle
    result.total = result.distance + result.gradient + result.waterObstacle
    return result
end

return grid
