local grid = require "planning.corridor_grid"
local search = require "planning.corridor_search"
local planner = {}

local function warnings(model)
    local result = {"sampled_grid_only_not_construction_geometry", "construction_feasibility_unverified",
        "scores_are_not_game_costs", "profile_alternatives_not_exhaustive"}
    if model.maxGradient == nil then result[#result + 1] = "no_hard_gradient_limit" end
    if model.unknownCells > 0 then result[#result + 1] = "unknown_samples_excluded" end
    if model.hintCount > 0 then result[#result + 1] = "infrastructure_hints_not_used_for_routing" end
    return result
end

local function edgeKey(a, b)
    return math.min(a, b) .. ":" .. math.max(a, b)
end

local function summarize(model, profile, found)
    local candidate = {id = "corridor_" .. profile.name, generatedBy = {profile.name}, sampleIds = found.path,
        waypoints = {}, length = 0, horizontalLength = 0, elevationGain = 0, elevationLoss = 0,
        maxGradient = 0, gradientExposure = 0, waterExposure = 0, obstacleExposure = 0,
        waterSegments = 0, waterRuns = 0, touchesWater = false, waterTransitions = {},
        feasibility = "sampled_constraints_satisfied", constructionStatus = "unverified",
        warnings = warnings(model), searchScore = found.score, edges = {}}
    local previousWater = false
    for index, id in ipairs(found.path) do
        local waypoint = grid.waypoint(model, id)
        candidate.waypoints[index] = waypoint
        if waypoint.water then
            candidate.touchesWater = true
            if not previousWater then candidate.waterRuns = candidate.waterRuns + 1 end
        end
        if index > 1 and waypoint.water ~= previousWater then
            candidate.waterTransitions[#candidate.waterTransitions + 1] = {
                fromIndex = index - 1, toIndex = index, entering = waypoint.water}
        end
        previousWater = waypoint.water
        if index > 1 then
            local step = grid.step(model, found.path[index - 1], id)
            candidate.length = candidate.length + step.length
            candidate.horizontalLength = candidate.horizontalLength + step.horizontal
            candidate.elevationGain = candidate.elevationGain + math.max(0, step.dz)
            candidate.elevationLoss = candidate.elevationLoss + math.max(0, -step.dz)
            candidate.maxGradient = math.max(candidate.maxGradient, step.gradient)
            candidate.gradientExposure = candidate.gradientExposure + step.gradientExposure
            candidate.waterExposure = candidate.waterExposure + step.waterExposure
            candidate.obstacleExposure = candidate.obstacleExposure + step.obstacleExposure
            if step.waterExposure > 0 then candidate.waterSegments = candidate.waterSegments + 1 end
            candidate.edges[edgeKey(found.path[index - 1], id)] = step.horizontal
        end
    end
    candidate.cumulativeElevationChange = candidate.elevationGain + candidate.elevationLoss
    candidate.score = grid.score(candidate, model.rankingWeights)
    if candidate.touchesWater then candidate.warnings[#candidate.warnings + 1] = "water_crossing_structure_unverified" end
    if #found.path == 1 then candidate.warnings[#candidate.warnings + 1] = "identical_endpoints_zero_length" end
    return candidate
end

local function identical(a, b)
    if #a.sampleIds ~= #b.sampleIds then return false end
    for index, id in ipairs(a.sampleIds) do if b.sampleIds[index] ~= id then return false end end
    return true
end

local function difference(a, b)
    local shortest = math.min(a.horizontalLength, b.horizontalLength)
    if shortest == 0 then return 0 end
    local shared = 0
    -- Ordered traversal avoids hash-order floating-point summation differences.
    for index = 2, #a.sampleIds do
        local key = edgeKey(a.sampleIds[index - 1], a.sampleIds[index])
        if b.edges[key] then shared = shared + a.edges[key] end
    end
    return math.max(0, math.min(1, 1 - shared / shortest))
end

function planner.plan(input)
    local valid, model = pcall(grid.validate, input)
    if not valid then
        -- Only documented validation failures become input errors; programming errors propagate.
        if type(model) ~= "table" or not model.code then error(model, 0) end
        return {status = model.code, complete = false, candidates = {}, profiles = {}, error = model}
    end
    local result = {status = "ok", complete = true, candidates = {}, profiles = {}, warnings = warnings(model),
        unit = model.unit, unknownCells = model.unknownCells, infrastructureHintCount = model.hintCount,
        rankingWeights = model.rankingWeights, minDifference = model.minDifference,
        grid = {columns = model.columns, rows = model.rows, originX = model.originX, originY = model.originY,
            spacingX = model.spacingX, spacingY = model.spacingY},
        constraints = {allowDiagonal = model.allowDiagonal, waterPolicy = model.waterPolicy, maxGradient = model.maxGradient},
        stats = {cells = #model.cells, expansions = 0, peakOpen = 0,
            maxCells = model.maxCells, maxExpansions = model.maxExpansions}}
    local routes = {}
    for order, profile in ipairs(model.profiles) do
        local found = search.run(model, profile.weights, model.maxExpansions - result.stats.expansions)
        local attempt = {name = profile.name, status = found.status, reason = found.reason,
            weights = profile.weights, expansions = found.stats.expansions, searchScore = found.score}
        result.profiles[order] = attempt
        result.stats.expansions = result.stats.expansions + found.stats.expansions
        result.stats.peakOpen = math.max(result.stats.peakOpen, found.stats.peakOpen)
        if found.status == "search_limit" then result.status, result.complete = "search_limit", false end
        if found.status == "found" then
            local candidate = summarize(model, profile, found)
            candidate.order, candidate.attempt = order, attempt
            routes[#routes + 1] = candidate
        end
    end
    -- Compare all alternatives using one policy, not their incomparable search weights.
    table.sort(routes, function(a, b)
        if a.score.total ~= b.score.total then return a.score.total < b.score.total end
        if a.length ~= b.length then return a.length < b.length end
        return a.order < b.order
    end)
    for _, candidate in ipairs(routes) do
        local representative, exact, separation
        for _, kept in ipairs(result.candidates) do
            exact, separation = identical(candidate, kept), difference(candidate, kept)
            if exact or separation < model.minDifference then representative = kept; break end
        end
        if representative then
            candidate.attempt.disposition = exact and "duplicate" or "similar"
            candidate.attempt.representedBy, candidate.attempt.difference = representative.id, separation
            if exact then representative.generatedBy[#representative.generatedBy + 1] = candidate.generatedBy[1] end
        else
            candidate.rank = #result.candidates + 1
            candidate.attempt.disposition, candidate.attempt.candidateId = "retained", candidate.id
            result.candidates[#result.candidates + 1] = candidate
        end
    end
    for _, candidate in ipairs(result.candidates) do candidate.edges, candidate.order, candidate.attempt = nil, nil, nil end
    if #result.candidates == 0 and result.complete then result.status = "unreachable" end
    if not result.complete then result.warnings[#result.warnings + 1] = "search_budget_exhausted_alternatives_incomplete" end
    return result
end

return planner
