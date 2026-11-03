-- Offline mathematical candidate only. No engine imports, proposals or live caller.
-- Convention: cubic Hermite on u in [0,1], both tangents dP/du in metres.
local curve = {}
local axes = {"x", "y", "z"}
local function finite(v) return type(v) == "number" and v == v and math.abs(v) < math.huge end
local function plain(v) return type(v) == "table" and getmetatable(v) == nil end
local function point(p, limit)
    if not plain(p) then return false end
    for _, a in ipairs(axes) do if not finite(p[a]) or math.abs(p[a]) > limit then return false end end
    return true
end
local function copy(p) return {x = p.x, y = p.y, z = p.z} end
local function delta(a, b) return {x = b.x - a.x, y = b.y - a.y, z = b.z - a.z} end
local function horizontal(p) return math.sqrt(p.x * p.x + p.y * p.y) end
local function length(p) return math.sqrt(p.x * p.x + p.y * p.y + p.z * p.z) end
local function radius(d)
    d.radiusStatus = "sampled_straight"
    if d.maxHorizontalCurvature > 0 then
        local r = 1 / d.maxHorizontalCurvature
        d.radiusStatus = finite(r) and "sampled" or "numeric_overflow"
        if finite(r) then d.minSampledRadius = r end
    end
end
local function failure(status, reason)
    return {kind = "offline_hermite_candidate", status = status, reason = reason, segments = {},
        constructionStatus = "unverified", engineValidation = "not_run"}
end

local function evaluate(s, u)
    local u2, u3 = u * u, u * u * u
    local p, d, dd = {}, {}, {}
    for _, a in ipairs(axes) do
        local distance = s.position1[a] - s.position0[a]
        local t0, t1 = s.tangent0[a], s.tangent1[a]
        -- Translation-stable form; no large absolute-position polynomial coefficients.
        p[a] = s.position0[a] + distance * (3 * u2 - 2 * u3)
            + t0 * (u3 - 2 * u2 + u) + t1 * (u3 - u2)
        d[a] = distance * (6 * u - 6 * u2) + t0 * (3 * u2 - 4 * u + 1) + t1 * (3 * u2 - 2 * u)
        dd[a] = distance * (6 - 12 * u) + t0 * (6 * u - 4) + t1 * (6 * u - 2)
    end
    return p, d, dd
end

function curve.evaluate(segment, u)
    if not plain(segment) or not finite(u) or u < 0 or u > 1 then return nil, "invalid_segment_or_parameter" end
    for _, key in ipairs({"position0", "position1", "tangent0", "tangent1"}) do
        if not point(segment[key], 1e8) then return nil, "invalid_segment_vector" end
    end
    return evaluate(segment, u)
end

-- Input is an explicit XYZ projection of a corridor, never the corridor object itself.
function curve.fit(input)
    if not plain(input) or input.unit ~= "m" or not plain(input.points) then return failure("invalid_input", "expected_plain_points_and_unit_m") end
    for k in pairs(input) do
        if k ~= "points" and k ~= "unit" and k ~= "options" then return failure("invalid_input", "unknown_input_field") end
    end
    local options = input.options == nil and {} or input.options
    if not plain(options) then return failure("invalid_input", "options_not_plain") end
    for k in pairs(options) do
        if k ~= "diagnosticSteps" and k ~= "minChord" and k ~= "maxGradient" and k ~= "minRadius" then
            return failure("invalid_input", "unknown_option")
        end
    end
    local steps = options.diagnosticSteps == nil and 32 or options.diagnosticSteps
    local minimum = options.minChord == nil and 1e-6 or options.minChord -- Numerical policy, NOT an engine minimum.
    if not finite(steps) or steps % 1 ~= 0 or steps < 8 or steps > 64 then return failure("invalid_input", "diagnostic_steps_range_8_64") end
    if not finite(minimum) or minimum < 1e-6 or minimum > 1e6 then return failure("invalid_input", "invalid_min_chord") end
    if options.maxGradient ~= nil and (not finite(options.maxGradient) or options.maxGradient < 0 or options.maxGradient > 1e6) then
        return failure("invalid_input", "invalid_gradient_assumption")
    end
    if options.minRadius ~= nil and (not finite(options.minRadius) or options.minRadius <= 0 or options.minRadius > 1e7) then
        return failure("invalid_input", "invalid_radius_assumption")
    end
    local count = 0
    for k in pairs(input.points) do
        count = count + 1
        if count > 256 then return failure("resource_limit", "max_input_points_256") end
        if not finite(k) or k % 1 ~= 0 or k < 1 or k > 256 then return failure("invalid_input", "points_must_be_dense_array") end
    end
    local points, source, removed = {}, {}, 0
    for i = 1, count do
        local p = input.points[i]
        if not point(p, 1e7) then return failure("invalid_input", "invalid_or_missing_xyz_at_" .. i) end
        for k in pairs(p) do if k ~= "x" and k ~= "y" and k ~= "z" then return failure("invalid_input", "project_xyz_explicitly") end end
        local previous = points[#points]
        if previous and previous.x == p.x and previous.y == p.y and previous.z == p.z then removed = removed + 1
        else points[#points + 1], source[#source + 1] = copy(p), i end
    end
    if #points < 2 then return failure("invalid_input", "need_two_distinct_points") end
    local chords, lengths, tangents = {}, {}, {}
    for i = 1, #points - 1 do
        chords[i] = delta(points[i], points[i + 1]); lengths[i] = horizontal(chords[i])
        if lengths[i] <= minimum then return failure("unsupported", "horizontal_chord_below_prototype_minimum_at_" .. i) end
    end
    tangents[1], tangents[#points] = copy(chords[1]), copy(chords[#chords])
    for i = 2, #points - 1 do
        local a, b, la, lb = chords[i - 1], chords[i], lengths[i - 1], lengths[i]
        local scale = 0.5 * math.min(la, lb)
        local t = {}
        for _, k in ipairs(axes) do t[k] = scale * (a[k] / la + b[k] / lb) end
        if horizontal(t) <= 1e-9 then return failure("unsupported", "reversal_or_near_stationary_tangent_at_" .. i) end
        tangents[i] = t -- Same derivative on both sides: C1 in consecutive unit intervals.
    end
    local result = {kind = "offline_hermite_candidate", status = "candidate", unit = "m",
        parameter = "u_in_0_1_tangents_dP_du", constructionStatus = "unverified", engineValidation = "not_run",
        removedDuplicates = removed, segments = {}, assumptions = {minChord = minimum,
            diagnosticSteps = steps, maxGradient = options.maxGradient, minRadius = options.minRadius},
        warnings = {"not_native_track_geometry_validation", "sampled_diagnostics_not_extrema_bounds",
            "smoothing_leaves_sampled_corridor_terrain_and_obstacles_unchecked", "self_intersections_unchecked",
            "C1_not_C2_or_constant_speed", "anchors_not_stations_or_verified_track_connections"},
        diagnostics = {approximateLength = 0, maxAbsGradient = 0, maxHorizontalCurvature = 0,
            evaluatedPoints = 0, gradientViolations = 0, radiusViolations = 0}}
    for i = 1, #points - 1 do
        local segment = {position0 = copy(points[i]), position1 = copy(points[i + 1]),
            tangent0 = copy(tangents[i]), tangent1 = copy(tangents[i + 1]),
            sourceStartIndex = source[i], sourceEndIndex = source[i + 1],
            diagnostics = {approximateLength = 0, maxAbsGradient = 0, maxHorizontalCurvature = 0}}
        local d, previous = segment.diagnostics, nil
        for j = 0, steps do
            local p, first, second = evaluate(segment, j / steps)
            local speed = horizontal(first)
            if speed <= 1e-9 then return failure("unsupported", "sampled_horizontal_derivative_near_zero_at_" .. i) end
            local grade = first.z / speed
            local curvature = math.abs(first.x * second.y - first.y * second.x) / (speed * speed * speed)
            d.maxAbsGradient = math.max(d.maxAbsGradient, math.abs(grade))
            d.minSignedGradient = math.min(d.minSignedGradient or grade, grade)
            d.maxSignedGradient = math.max(d.maxSignedGradient or grade, grade)
            d.maxHorizontalCurvature = math.max(d.maxHorizontalCurvature, curvature)
            if previous then d.approximateLength = d.approximateLength + length(delta(previous, p)) end
            previous = p
        end
        -- nil radius with zero curvature denotes a straight sample set, not radius zero.
        radius(d)
        d.gradientViolation = options.maxGradient ~= nil and d.maxAbsGradient > options.maxGradient
        d.radiusViolation = options.minRadius ~= nil and d.minSampledRadius ~= nil and d.minSampledRadius < options.minRadius
        local total = result.diagnostics
        total.approximateLength = total.approximateLength + d.approximateLength
        total.maxAbsGradient = math.max(total.maxAbsGradient, d.maxAbsGradient)
        total.maxHorizontalCurvature = math.max(total.maxHorizontalCurvature, d.maxHorizontalCurvature)
        total.evaluatedPoints = total.evaluatedPoints + steps + 1
        if d.gradientViolation then total.gradientViolations = total.gradientViolations + 1 end
        if d.radiusViolation then total.radiusViolations = total.radiusViolations + 1 end
        result.segments[i] = segment
    end
    local d = result.diagnostics
    radius(d)
    if d.gradientViolations + d.radiusViolations > 0 then result.status = "diagnostic_violation" end
    return result
end
return curve
