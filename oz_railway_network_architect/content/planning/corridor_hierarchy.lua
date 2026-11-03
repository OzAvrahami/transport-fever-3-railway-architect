-- Coarse guides followed by overlapping fine windows. No TF3 APIs or retained callbacks.
local planner = ug_require "oz_railway_network_architect::/planning/corridor_planner.lua"
local grid = ug_require "oz_railway_network_architect::/planning/corridor_grid.lua"
local hierarchy = {}
local defaults = {coarseSpacing = 512, fineSpacing = 64, maxSamples = 32768,
    maxVisits = 65536, maxExpansions = 49152, maxSections = 128, maxWaypoints = 4096,
    maxCoarseCells = 4096, maxSnap = 96, maxRelativeSnap = 0.1}
local function finite(v) return type(v) == "number" and v == v and math.abs(v) < math.huge end
local function key(x, y) return string.format("%.0f,%.0f", x, y) end
local function same(a, b) return a.x == b.x and a.y == b.y end
local function copyPoint(p) return {x = p.x, y = p.y, z = p.z, water = p.water} end
local function warnings()
    return {"coarse_guides_not_exhaustive", "fixed_checkpoints_can_miss_feasible_routes",
        "sampled_grid_only_not_construction_geometry", "construction_feasibility_unverified",
        "scores_are_not_game_costs", "obstacles_unaccounted_for", "non_atomic_terrain_snapshot",
        "locally_ranked_sections_not_globally_optimal", "between_sample_features_unverified",
        "bounded_coarse_region_not_global_reachability"}
end
local function finish(s, status, reason)
    local routes = s.routes or {}
    table.sort(routes, function(a, b)
        if a.score.total ~= b.score.total then return a.score.total < b.score.total end
        if a.length ~= b.length then return a.length < b.length end
        return a.id < b.id
    end)
    local kept = {}
    for _, candidate in ipairs(routes) do
        local duplicate = false
        for _, prior in ipairs(kept) do
            local shared = 0
            for i = 2, #candidate.waypoints do
                local a, b = candidate.waypoints[i - 1], candidate.waypoints[i]
                local ka, kb = key(a.x, a.y), key(b.x, b.y)
                local edge = ka < kb and (ka .. ":" .. kb) or (kb .. ":" .. ka)
                if prior.edges[edge] then shared = shared + candidate.edges[edge] end
            end
            local shortest = math.min(prior.horizontalLength, candidate.horizontalLength)
            if shortest == 0 or 1 - shared / shortest < 0.25 then duplicate = true; break end
        end
        if not duplicate then candidate.rank = #kept + 1; kept[#kept + 1] = candidate end
    end
    for _, c in ipairs(kept) do c.edges = nil end
    if status == nil then
        status = #kept == 0 and "unreachable" or ((s.unknown > 0 or s.rejectedGuides > 0) and "incomplete" or "ok")
        reason = #kept == 0 and "all_coarse_guides_failed_refinement" or "refined_routes_validated"
    end
    s.result = {status = status, reason = reason, complete = status == "ok", candidates = kept,
        profiles = s.attempts or {}, warnings = warnings(), unknownCells = s.unknown or 0,
        rankingWeights = s.rankingWeights, stats = {expansions = s.expansions or 0,
            samples = s.sampleCount or 0, visits = s.visits or 0, maxStepExpansions = s.maxStepExpansions or 0},
        sampling = {coarseSpacing = defaults.coarseSpacing, fineSpacing = defaults.fineSpacing,
            maxWindowSamples = 1024, region = s.coarseRegion},
        constraints = s.constraintsValidated and s.options and s.options.constraints or nil}
    if s.options and s.options.constraints and s.options.constraints.maxGradient == nil then
        s.result.warnings[#s.result.warnings + 1] = "no_hard_gradient_limit"
    end
    if status == "search_limit" or status == "resource_limit" then s.result.warnings[#s.result.warnings + 1] = "alternatives_incomplete_budget_exhausted" end
    if (s.rejectedGuides or 0) > 0 then s.result.warnings[#s.result.warnings + 1] = "some_guides_failed_refinement" end
    if (s.unknown or 0) > 0 then s.result.warnings[#s.result.warnings + 1] = "unknown_samples_excluded" end
    s.finished, s.phase, s.progress = true, "done", status .. ": " .. reason
    -- Release working grids/cache on every terminal path; candidates contain plain waypoints.
    s.cache, s.window, s.job, s.guides, s.checkpoints, s.route, s.routes, s.pointIndex = nil, nil, nil, nil, nil, nil, nil, nil
    if status == "invalid_input" or status == "input_limit" then s.options, s.bounds = nil, nil end
    return s.result
end
local function fail(s, status, reason) finish(s, status, reason); return false end
local function axisBounds(low, high, spacing)
    return math.ceil((low + 1) / spacing), math.floor((high - 1) / spacing)
end
local function snap(point, bounds, spacing)
    local x0, x1 = axisBounds(bounds.minX, bounds.maxX, spacing)
    local y0, y1 = axisBounds(bounds.minY, bounds.maxY, spacing)
    if x1 < x0 or y1 < y0 then return nil end
    local x = math.max(x0, math.min(x1, math.floor(point.x / spacing + 0.5))) * spacing
    local y = math.max(y0, math.min(y1, math.floor(point.y / spacing + 0.5))) * spacing
    return {x = x, y = y, dx = x - point.x, dy = y - point.y,
        distance = math.sqrt((x - point.x)^2 + (y - point.y)^2)}
end
local function window(s, a, b, coarse, wide)
    local spacing = coarse and s.options.coarseSpacing or s.options.fineSpacing
    local x0, x1 = axisBounds(s.bounds.minX, s.bounds.maxX, spacing)
    local y0, y1 = axisBounds(s.bounds.minY, s.bounds.maxY, spacing)
    if coarse then
        -- Broad bounded neighborhood; never scan a huge map just because it exists.
        local distance = math.sqrt((b.x - a.x)^2 + (b.y - a.y)^2)
        local margin = math.max(2048, math.ceil(distance * 0.25 / spacing) * spacing)
        x0 = math.max(x0, math.floor((math.min(a.x, b.x) - margin) / spacing))
        x1 = math.min(x1, math.ceil((math.max(a.x, b.x) + margin) / spacing))
        y0 = math.max(y0, math.floor((math.min(a.y, b.y) - margin) / spacing))
        y1 = math.min(y1, math.ceil((math.max(a.y, b.y) + margin) / spacing))
    else
        local margin = wide and 512 or 256
        x0 = math.max(x0, math.floor((math.min(a.x, b.x) - margin) / spacing))
        x1 = math.min(x1, math.ceil((math.max(a.x, b.x) + margin) / spacing))
        y0 = math.max(y0, math.floor((math.min(a.y, b.y) - margin) / spacing))
        y1 = math.min(y1, math.ceil((math.max(a.y, b.y) + margin) / spacing))
    end
    local columns, rows = x1 - x0 + 1, y1 - y0 + 1
    if columns < 1 or rows < 1 or columns > (coarse and 64 or 32) or rows > (coarse and 64 or 32)
        or columns * rows > (coarse and s.options.maxCoarseCells or 1024) then
        return fail(s, "unsupported", coarse and "coarse_map_coverage_limit" or "refinement_window_limit")
    end
    s.window = {columns = columns, rows = rows, spacingX = spacing, spacingY = spacing,
        originX = x0 * spacing, originY = y0 * spacing, cells = {}, unit = "world_units"}
    if coarse then s.coarseRegion = {minX = x0 * spacing, maxX = x1 * spacing, minY = y0 * spacing, maxY = y1 * spacing} end
    s.windowStart, s.windowEnd, s.cursor = {x = a.x, y = a.y}, {x = b.x, y = b.y}, 1
    s.phase = coarse and "coarse_sampling" or "fine_sampling"
    return true
end

function hierarchy.start(pair, bounds, options)
    local s = {options = {}, bounds = bounds, cache = {}, sampleCount = 0, visits = 0,
        unknown = 0, expansions = 0, routes = {}, attempts = {}, rejectedGuides = 0,
        examples = {}, phase = "initializing"}
    for k, v in pairs(defaults) do s.options[k] = v end
    if options ~= nil and (type(options) ~= "table" or getmetatable(options) ~= nil) then finish(s, "invalid_input", "options_table_required"); return s end
    for k, v in pairs(options or {}) do
        if defaults[k] == nil and k ~= "constraints" and k ~= "profiles" and k ~= "rankingWeights" then
            finish(s, "invalid_input", "unknown_option_" .. tostring(k)); return s
        end
        s.options[k] = v
    end
    for k, maximum in pairs(defaults) do
        local v = s.options[k]
        local minimum = (k == "maxSnap" or k == "maxRelativeSnap") and 0 or 1
        if not finite(v) or v < minimum or v > maximum or (k ~= "maxRelativeSnap" and k ~= "maxSnap" and v % 1 ~= 0)
            or ((k == "coarseSpacing" or k == "fineSpacing") and v ~= maximum) then
            finish(s, "invalid_input", "invalid_limit_" .. k); return s
        end
    end
    local constraints = s.options.constraints
    if constraints ~= nil and (type(constraints) ~= "table" or getmetatable(constraints) ~= nil) then
        finish(s, "invalid_input", "constraints_table_required"); return s
    end
    s.options.constraints = {waterPolicy = "exclude"}
    for k, v in pairs(constraints or {}) do
        if k ~= "maxGradient" and k ~= "waterPolicy" and k ~= "allowDiagonal" then
            finish(s, "invalid_input", "unknown_constraint"); return s
        end
        s.options.constraints[k] = v
    end
    -- Validate policy/weights before any terrain query; copy normalized settings.
    local valid, model = pcall(grid.validate, {start = {x = 0, y = 0}, destination = {x = 0, y = 0},
        grid = {columns = 1, rows = 1, originX = 0, originY = 0, spacingX = 1, spacingY = 1,
            unit = "world_units", cells = {{height = 0, water = false}}},
        constraints = s.options.constraints, profiles = s.options.profiles, rankingWeights = s.options.rankingWeights})
    if not valid then
        if type(model) ~= "table" or not model.code then error(model, 0) end
        finish(s, model.code, model.path .. ": " .. model.message); return s
    end
    s.constraintsValidated = true
    s.options.profiles, s.options.rankingWeights, s.rankingWeights = {}, model.rankingWeights, model.rankingWeights
    for _, profile in ipairs(model.profiles) do s.options.profiles[profile.name] = profile.weights end
    if type(bounds) ~= "table" then finish(s, "invalid_input", "bounds_required"); return s end
    for _, k in ipairs({"minX", "minY", "maxX", "maxY"}) do
        if not finite(bounds[k]) or math.abs(bounds[k]) > 1e6 then finish(s, "invalid_input", "invalid_bounds"); return s end
    end
    if bounds.minX >= bounds.maxX or bounds.minY >= bounds.maxY then finish(s, "invalid_input", "invalid_bounds"); return s end
    s.bounds = {minX = bounds.minX, minY = bounds.minY, maxX = bounds.maxX, maxY = bounds.maxY}
    if type(pair) ~= "table" then finish(s, "invalid_input", "pair_required"); return s end
    for _, role in ipairs({"start", "destination"}) do
        local p = pair[role]
        if type(p) ~= "table" or not finite(p.id) or p.id < 0 or p.id % 1 ~= 0 or not finite(p.x) or not finite(p.y) or p.x <= bounds.minX or p.x >= bounds.maxX
            or p.y <= bounds.minY or p.y >= bounds.maxY then finish(s, "invalid_input", "invalid_endpoint"); return s end
    end
    s.sourceId, s.destinationId = pair.start.id, pair.destination.id
    s.originalAnchors = {start = {x = pair.start.x, y = pair.start.y}, destination = {x = pair.destination.x, y = pair.destination.y}}
    s.anchors = {start = snap(pair.start, bounds, s.options.fineSpacing),
        destination = snap(pair.destination, bounds, s.options.fineSpacing)}
    local distance = math.sqrt((pair.start.x - pair.destination.x)^2 + (pair.start.y - pair.destination.y)^2)
    for _, role in ipairs({"start", "destination"}) do
        local p = s.anchors[role]
        if not p or p.distance > math.min(s.options.maxSnap, distance * s.options.maxRelativeSnap) then
            finish(s, "unsupported", "fine_endpoint_approximation_exceeds_limit"); return s
        end
    end
    if same(s.anchors.start, s.anchors.destination) then finish(s, "unsupported", "anchors_snap_to_same_sample"); return s end
    local a, b = snap(pair.start, bounds, s.options.coarseSpacing), snap(pair.destination, bounds, s.options.coarseSpacing)
    if not a or not b then finish(s, "unsupported", "no_coarse_lattice_inside_map"); return s end
    window(s, a, b, true)
    return s
end

local function sampleBatch(s, read)
    local w = s.window
    for _ = 1, 16 do
        if s.cursor > w.columns * w.rows then break end
        if s.visits >= s.options.maxVisits then return fail(s, "resource_limit", "sample_visit_limit") end
        s.visits = s.visits + 1
        local x = w.originX + ((s.cursor - 1) % w.columns) * w.spacingX
        local y = w.originY + math.floor((s.cursor - 1) / w.columns) * w.spacingY
        local k = key(x, y)
        local cell = s.cache[k]
        if cell == nil then
            if s.sampleCount >= s.options.maxSamples then return fail(s, "resource_limit", "terrain_sample_limit") end
            local ok, raw = pcall(read, x, y)
            cell = {}
            if ok and type(raw) == "table" and raw.valid == true then
                if finite(raw.height) and math.abs(raw.height) <= 1e6 then cell.height = raw.height end
                if type(raw.water) == "boolean" then cell.water = raw.water end
                if type(raw.blocked) == "boolean" then cell.blocked = raw.blocked end
                if finite(raw.obstaclePenalty) and raw.obstaclePenalty >= 0 and raw.obstaclePenalty <= 1e6 then cell.obstaclePenalty = raw.obstaclePenalty end
            end
            if cell.height == nil or cell.water == nil then
                s.unknown = s.unknown + 1
                if #s.examples < 4 then
                    local detail = not ok and tostring(raw) or (type(raw) == "table" and raw.errors and raw.errors[1]) or "invalid_or_missing_sample"
                    s.examples[#s.examples + 1] = k .. ": " .. tostring(detail):sub(1, 240)
                end
            end
            s.cache[k], s.sampleCount = cell, s.sampleCount + 1
        end
        w.cells[s.cursor], s.cursor = cell, s.cursor + 1
    end
    if s.cursor > w.columns * w.rows then s.phase = s.phase == "coarse_sampling" and "coarse_prepare" or "fine_prepare" end
    return true
end
local function beginSearch(s, coarse)
    local budget = math.min(coarse and 12288 or 3072, s.options.maxExpansions - s.expansions)
    if budget <= 0 then return fail(s, "search_limit", "total_expansion_limit") end
    s.job = planner.start({start = s.windowStart, destination = s.windowEnd, grid = s.window,
        constraints = s.options.constraints or {waterPolicy = "exclude"}, profiles = s.options.profiles,
        rankingWeights = s.options.rankingWeights, limits = {maxCells = coarse and 4096 or 1024, maxExpansions = budget}})
    s.phase = coarse and "coarse_search" or "fine_search"
end
local function newRoute(s)
    local guide = s.guides[s.guideIndex]
    if not guide then return finish(s) end
    s.checkpoints = {s.anchors.start}
    for _, p in ipairs(guide.waypoints) do
        if not same(s.checkpoints[#s.checkpoints], p) then s.checkpoints[#s.checkpoints + 1] = p end
    end
    if not same(s.checkpoints[#s.checkpoints], s.anchors.destination) then s.checkpoints[#s.checkpoints + 1] = s.anchors.destination end
    if #s.checkpoints - 1 > s.options.maxSections then return finish(s, "resource_limit", "refinement_section_limit") end
    s.route = {id = "hierarchical_" .. s.guideIndex, generatedBy = guide.generatedBy,
        sourceId = s.sourceId, destinationId = s.destinationId, waypoints = {}, refinedSections = 0,
        sampling = {coarseSpacing = s.options.coarseSpacing, fineSpacing = s.options.fineSpacing},
        endpoints = s.anchors, originalAnchors = s.originalAnchors, warnings = warnings(),
        refinementPolicy = "best_common_score_per_window", constructionStatus = "unverified", searchStatus = "refining"}
    s.pointIndex, s.section, s.wide = {}, 1, false
    s.phase = "section"
end
local function rejectGuide(s, reason)
    s.rejectedGuides = s.rejectedGuides + 1
    s.attempts[#s.attempts + 1] = {name = "guide_" .. s.guideIndex, status = "unreachable", reason = reason}
    s.guideIndex, s.phase = s.guideIndex + 1, "guide"
end
local function stitch(s, part)
    local route, points = s.route, s.route.waypoints
    if #points > 0 then
        local last, first = points[#points], part.waypoints[1]
        if not same(last, first) or last.z ~= first.z or last.water ~= first.water then
            return fail(s, "error", "refinement_join_mismatch")
        end
    end
    for _, p in ipairs(part.waypoints) do
        local k = key(p.x, p.y)
        local previous = s.pointIndex[k]
        if previous then
            -- Erase loops at an identical coordinate. Final edges are revalidated below.
            for i = #points, previous + 1, -1 do s.pointIndex[key(points[i].x, points[i].y)] = nil; points[i] = nil end
        else
            if #points >= s.options.maxWaypoints then return fail(s, "resource_limit", "waypoint_limit") end
            points[#points + 1] = copyPoint(p); s.pointIndex[k] = #points
        end
    end
    route.refinedSections = route.refinedSections + 1
    s.section, s.wide, s.phase = s.section + 1, false, "section"
    return true
end
local function edgeModel(s, a, b)
    local spacing = s.options.fineSpacing
    local dc, dr = math.abs(b.x - a.x) / spacing, math.abs(b.y - a.y) / spacing
    if (dc ~= 0 and dc ~= 1) or (dr ~= 0 and dr ~= 1) or dc + dr == 0 then return nil end
    local x0, y0 = math.min(a.x, b.x), math.min(a.y, b.y)
    local cells = {}
    for y = 0, dr do for x = 0, dc do cells[#cells + 1] = s.cache[key(x0 + x * spacing, y0 + y * spacing)] or {} end end
    local model = grid.validate({start = {x = a.x, y = a.y}, destination = {x = b.x, y = b.y},
        grid = {columns = dc + 1, rows = dr + 1, originX = x0, originY = y0,
            spacingX = spacing, spacingY = spacing, unit = "world_units", cells = cells},
        constraints = s.options.constraints or {waterPolicy = "exclude"}, rankingWeights = s.options.rankingWeights})
    return grid.step(model, model.start, model.destination)
end
local function validateBatch(s)
    local c = s.route
    if not s.validateIndex then
        if not same(c.waypoints[1], s.anchors.start) or not same(c.waypoints[#c.waypoints], s.anchors.destination) then
            return fail(s, "error", "refined_endpoint_mismatch")
        end
        for _, k in ipairs({"length", "horizontalLength", "elevationGain", "elevationLoss", "maxGradient",
            "gradientExposure", "waterExposure", "obstacleExposure", "waterSegments", "waterRuns"}) do c[k] = 0 end
        c.edges, c.waterTransitions, c.touchesWater = {}, {}, false
        s.validateIndex = 1
    end
    for _ = 1, 32 do
        local index = s.validateIndex
        if index > #c.waypoints then
            c.cumulativeElevationChange = c.elevationGain + c.elevationLoss
            c.score = grid.score(c, s.rankingWeights)
            c.searchStatus, c.feasibility = "complete", "sampled_constraints_satisfied"
            if s.options.constraints.maxGradient == nil then c.warnings[#c.warnings + 1] = "no_hard_gradient_limit" end
            if s.unknown > 0 then c.warnings[#c.warnings + 1] = "unknown_samples_excluded" end
            if c.touchesWater then c.warnings[#c.warnings + 1] = "water_crossing_structure_unverified" end
            s.routes[#s.routes + 1] = c
            s.attempts[#s.attempts + 1] = {name = "guide_" .. s.guideIndex, status = "found", reason = "all_sections_validated"}
            s.guideIndex, s.validateIndex, s.phase = s.guideIndex + 1, nil, "guide"
            return
        end
        local p, previous = c.waypoints[index], c.waypoints[index - 1]
        if p.water then
            c.touchesWater = true
            if not previous or not previous.water then c.waterRuns = c.waterRuns + 1 end
        end
        if previous then
            local metrics = edgeModel(s, previous, p)
            if not metrics then return fail(s, "error", "refined_continuity_or_constraint_failure") end
            c.length, c.horizontalLength = c.length + metrics.length, c.horizontalLength + metrics.horizontal
            c.elevationGain, c.elevationLoss = c.elevationGain + math.max(0, metrics.dz), c.elevationLoss + math.max(0, -metrics.dz)
            c.maxGradient = math.max(c.maxGradient, metrics.gradient)
            for _, k in ipairs({"gradientExposure", "waterExposure", "obstacleExposure"}) do c[k] = c[k] + metrics[k] end
            if metrics.waterExposure > 0 then c.waterSegments = c.waterSegments + 1 end
            if p.water ~= previous.water then c.waterTransitions[#c.waterTransitions + 1] = {fromIndex = index - 1, toIndex = index, entering = p.water} end
            local ka, kb = key(previous.x, previous.y), key(p.x, p.y)
            c.edges[ka < kb and (ka .. ":" .. kb) or (kb .. ":" .. ka)] = metrics.horizontal
        end
        s.validateIndex = index + 1
    end
end

function hierarchy.step(s, read)
    if s.finished then return s.result end
    local phase = s.phase
    if phase == "coarse_sampling" or phase == "fine_sampling" then sampleBatch(s, read)
    elseif phase == "coarse_prepare" or phase == "fine_prepare" then beginSearch(s, phase == "coarse_prepare")
    elseif phase == "coarse_search" or phase == "fine_search" then
        local function expansions() return (s.job.result.stats and s.job.result.stats.expansions or 0)
            + (s.job.search and s.job.search.stats.expansions or 0) end
        local before = expansions()
        local remaining = s.options.maxExpansions - s.expansions
        if remaining <= 0 then return finish(s, "search_limit", "total_expansion_limit") end
        planner.step(s.job, math.min(64, remaining))
        local used = expansions() - before
        s.expansions, s.maxStepExpansions = s.expansions + used, math.max(s.maxStepExpansions or 0, used)
        if s.job.finished then
            local result = s.job.result
            s.job, s.window = nil, nil
            if result.status == "search_limit" then return finish(s, "search_limit", "window_expansion_limit") end
            if result.error then return finish(s, result.status, result.error.path .. ": " .. result.error.message) end
            if phase == "coarse_search" then
                if #result.candidates == 0 then return finish(s, "unreachable", "no_coarse_guide_at_sampled_resolution") end
                s.guides, s.rankingWeights, s.guideIndex, s.phase = result.candidates, result.rankingWeights, 1, "guide"
            elseif #result.candidates == 0 then
                if not s.wide then s.wide, s.phase = true, "section"
                else rejectGuide(s, "refinement_section_unreachable_" .. s.section) end
            else stitch(s, result.candidates[1]) end
        end
    elseif phase == "guide" then newRoute(s)
    elseif phase == "section" then
        if s.section >= #s.checkpoints then s.phase = "validate"
        else window(s, s.checkpoints[s.section], s.checkpoints[s.section + 1], false, s.wide) end
    elseif phase == "validate" then validateBatch(s)
    else return finish(s, "error", "unknown_hierarchy_phase") end
    if not s.finished then
        s.progress = string.format("%s | guide %d/%d | section %d | samples %d | expansions %d",
            s.phase, s.guideIndex or 0, s.guides and #s.guides or 0, s.section or 0, s.sampleCount, s.expansions)
    end
    return s.finished and s.result or nil
end
function hierarchy.cancel(s, reason)
    s.routes = {}
    finish(s, "invalidated", reason or "cancelled")
end
return hierarchy
