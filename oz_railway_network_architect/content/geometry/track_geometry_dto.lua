-- Offline intermediate DTO, NOT SimpleProposal, Proposal or an engine object.
-- Vector correspondence is source-backed; native interpolation equivalence is not.
local curve = ug_require "oz_railway_network_architect::/geometry/rail_curve.lua"
local adapter = {}
local axes = {"x", "y", "z"}
local vectors = {"position0", "position1", "tangent0", "tangent1"}
local function plain(v) return type(v) == "table" and getmetatable(v) == nil end
local function finite(v) return type(v) == "number" and v == v and math.abs(v) < math.huge end
local function integer(v, lo, hi) return finite(v) and v % 1 == 0 and v >= lo and v <= hi end
local function keys(t, allowed)
    if not plain(t) then return false end
    for k in pairs(t) do if not allowed[k] then return false end end
    return true
end
local function copy(v) return {x = v.x, y = v.y, z = v.z} end
local function same(a, b) return a.x == b.x and a.y == b.y and a.z == b.z end
local function horizontal(v) return math.sqrt(v.x * v.x + v.y * v.y) end
local function vector(v)
    if not keys(v, {x=true,y=true,z=true}) then return false end
    for _, a in ipairs(axes) do if not finite(v[a]) or math.abs(v[a]) > 1e8 then return false end end
    return true
end
-- Bounded provenance copy: no userdata, closures, metatables, cycles or truncation.
local function metadata(value)
    local entries, chars, active = 0, 0, {}
    local function visit(v, depth)
        if type(v) == "string" then
            chars = chars + #v
            if #v > 1024 or chars > 16384 then error("metadata_limit", 0) end
            return v
        elseif type(v) == "boolean" or finite(v) then return v
        elseif not plain(v) then error("metadata_not_plain", 0) end
        if depth > 6 or active[v] then error("metadata_depth_or_cycle", 0) end
        active[v] = true
        local out = {}
        for k, item in pairs(v) do
            entries = entries + 1
            if entries > 256 then error("metadata_limit", 0) end
            if type(k) ~= "string" and not integer(k, 1, 256) then error("metadata_key", 0) end
            out[visit(k, depth + 1)] = visit(item, depth + 1)
        end
        active[v] = nil
        return out
    end
    return pcall(visit, value, 1)
end
local function report()
    return {inputGeometry = "not_checked", endpointContinuity = "not_checked",
        tangentCompatibility = "not_checked", structuralCompatibility = "not_checked",
        trackTemplateReadiness = "missing", bridgeTunnelDecisions = "not_assessed",
        existingInfrastructureConnections = "not_assessed", terrainAndCollisions = "not_verified",
        nativeProposalVerification = "not_run", constructionStatus = "unverified", joins = {},
        missingPrerequisites = {"native_interpolation_and_float_conversion_validation",
            "resolved_track_template_lanes_style_and_constraints", "bridge_tunnel_and_support_decisions",
            "terrain_clearance_collision_and_earthwork_assessment", "endpoint_attachment_and_ownership",
            "native_proposal_processing_context_and_engine_validation"},
        warnings = {"intermediate_DTO_not_a_native_proposal", "sampled_diagnostics_not_extrema_bounds",
            "C1_does_not_imply_C2", "self_intersections_unchecked", "anchors_not_verified_track_connections"}}
end
local function diagnostic(s, u)
    local p, d, dd = curve.evaluate(s, u)
    local h = horizontal(d)
    if h <= 1e-9 then return nil end -- Guard floating-point evaluation as well as the analytic projection test.
    local grade = d.z / h
    local curvature = (d.x * dd.y - d.y * dd.x) / (h * h * h)
    local gradeRate = (dd.z - d.z * (d.x * dd.x + d.y * dd.y) / (h * h)) / (h * h)
    return p, {signedGradient = grade, signedHorizontalCurvature = curvature,
        gradientRatePerHorizontalMetre = gradeRate}, dd
end

function adapter.convert(input)
    local r = report()
    local function fail(status, reason, field)
        r[field or "inputGeometry"] = "failed"
        return {kind = "intermediate_track_geometry", status = status, reason = reason, report = r}
    end
    if not keys(input, {candidate=true,provenance=true,template=true}) then return fail("invalid_input", "input_contract") end
    local c = input.candidate
    if not keys(c, {kind=true,status=true,unit=true,parameter=true,constructionStatus=true,engineValidation=true,
        removedDuplicates=true,segments=true,assumptions=true,warnings=true,diagnostics=true})
        or c.kind ~= "offline_hermite_candidate" or c.unit ~= "m"
        or c.parameter ~= "u_in_0_1_tangents_dP_du"
        or (c.status ~= "candidate" and c.status ~= "diagnostic_violation")
        or c.constructionStatus ~= "unverified" or c.engineValidation ~= "not_run"
        or not plain(c.segments) or not plain(c.diagnostics) or not plain(c.warnings)
        or not integer(c.removedDuplicates, 0, 254) then return fail("invalid_input", "candidate_contract") end
    local a = c.assumptions
    if not keys(a, {diagnosticSteps=true,minChord=true,maxGradient=true,minRadius=true})
        or not integer(a.diagnosticSteps, 8, 64) or not finite(a.minChord) or a.minChord < 1e-6 or a.minChord > 1e6
        or (a.maxGradient ~= nil and (not finite(a.maxGradient) or a.maxGradient < 0 or a.maxGradient > 1e6))
        or (a.minRadius ~= nil and (not finite(a.minRadius) or a.minRadius <= 0 or a.minRadius > 1e7)) then
        return fail("invalid_input", "candidate_assumptions")
    end
    if not plain(input.provenance) or type(input.provenance.source) ~= "string" or input.provenance.source == ""
        or input.provenance.coordinateFrame ~= "world" then return fail("invalid_input", "explicit_world_provenance_required") end
    local ok, meta = metadata({provenance=input.provenance, assumptions=a, sourceWarnings=c.warnings})
    if not ok then return fail("invalid_input", meta) end
    local template
    if input.template ~= nil then
        if not keys(input.template, {roadTemplate=true,roadStyle=true}) then return fail("invalid_input", "template_fields") end
        template = {}
        for _, k in ipairs({"roadTemplate", "roadStyle"}) do
            local name = input.template[k]
            if type(name) ~= "string" or #name == 0 or #name > 512 or name:find("%c") then
                return fail("invalid_input", "template_resource_reference")
            end
            template[k] = name
        end
        r.trackTemplateReadiness = "references_supplied_not_resolved"
    end
    local count = 0
    for k in pairs(c.segments) do
        count = count + 1
        if count > 255 or (integer(k, 256, 1e9)) then return fail("resource_limit", "max_segments_255") end
        if not integer(k, 1, 255) then return fail("invalid_input", "segments_dense_array") end
    end
    if count == 0 then return fail("invalid_input", "empty_geometry") end
    local nodes, segments = {}, {}
    local total = {evaluatedPoints=0, joinEvaluations=2*(count-1), approximateLength=0, maxAbsGradient=0, maxHorizontalCurvature=0,
        gradientViolations=0, radiusViolations=0}
    -- Validate every record and join before producing a usable DTO.
    for i = 1, count do
        local source = c.segments[i]
        if not keys(source, {position0=true,position1=true,tangent0=true,tangent1=true,
            sourceStartIndex=true,sourceEndIndex=true,diagnostics=true}) then return fail("invalid_input", "segment_fields_at_" .. i) end
        local s = {index=i, node0Index=i, node1Index=i+1}
        for _, key in ipairs(vectors) do
            if not vector(source[key]) then return fail("invalid_input", key .. "_invalid_at_" .. i) end
            s[key] = copy(source[key]) -- Identity: no unit normalization, sign reversal or magnitude rescaling.
        end
        if not integer(source.sourceStartIndex, 1, 255) or not integer(source.sourceEndIndex, source.sourceStartIndex+1, 256) then
            return fail("invalid_input", "source_indices_at_" .. i)
        end
        s.sourceStartIndex, s.sourceEndIndex = source.sourceStartIndex, source.sourceEndIndex
        local dx, dy = s.position1.x-s.position0.x, s.position1.y-s.position0.y
        local chord = math.sqrt(dx*dx + dy*dy)
        if chord <= a.minChord then return fail("unsupported", "degenerate_horizontal_chord_at_" .. i) end
        local t0 = (s.tangent0.x*dx + s.tangent0.y*dy)/chord
        local t1 = (s.tangent1.x*dx + s.tangent1.y*dy)/chord
        -- Conservative DTO policy, not a native track restriction. Analytic minimum
        -- of derivative projected on the chord proves no horizontal stationary point.
        local qa, qb = -6*chord+3*t0+3*t1, 6*chord-4*t0-2*t1
        local minimum = math.min(t0, t1)
        if qa > 0 then
            local u = -qb/(2*qa)
            if u > 0 and u < 1 then minimum = math.min(minimum, (qa*u+qb)*u+t0) end
        end
        if minimum <= 1e-9 then return fail("unsupported", "non_forward_or_stationary_tangent_at_" .. i, "tangentCompatibility") end
        if i > 1 then
            local prev = segments[i-1]
            if not same(prev.position1, s.position0) or prev.sourceEndIndex ~= s.sourceStartIndex then
                return fail("invalid_input", "endpoint_or_source_discontinuity_at_" .. i, "endpointContinuity")
            end
            if not same(prev.tangent1, s.tangent0) then
                return fail("unsupported", "join_not_exact_C1_at_" .. i, "tangentCompatibility")
            end
            local pLeft, left, ddLeft = diagnostic(prev, 1)
            local pRight, right, ddRight = diagnostic(s, 0)
            if not pLeft or not pRight then return fail("unsupported", "sampled_stationary_join_at_" .. i, "tangentCompatibility") end
            r.joins[#r.joins+1] = {nodeIndex=i, C0=true, C1=true, C2=same(ddLeft, ddRight),
                left=left, right=right, curvatureJump=right.signedHorizontalCurvature-left.signedHorizontalCurvature,
                gradientJump=right.signedGradient-left.signedGradient,
                gradientRateJump=right.gradientRatePerHorizontalMetre-left.gradientRatePerHorizontalMetre}
        else nodes[1] = {index=1, position=copy(s.position0), sourcePointIndex=s.sourceStartIndex} end
        nodes[i+1] = {index=i+1, position=copy(s.position1), sourcePointIndex=s.sourceEndIndex}
        segments[i] = s
    end
    for _, s in ipairs(segments) do
        local d, previous = {approximateLength=0,maxAbsGradient=0,maxHorizontalCurvature=0}, nil
        for j = 0, a.diagnosticSteps do
            local p, sample = diagnostic(s, j/a.diagnosticSteps)
            if not p then return fail("unsupported", "sampled_stationary_derivative_at_" .. s.index, "tangentCompatibility") end
            d.maxAbsGradient = math.max(d.maxAbsGradient, math.abs(sample.signedGradient))
            d.maxHorizontalCurvature = math.max(d.maxHorizontalCurvature, math.abs(sample.signedHorizontalCurvature))
            if previous then
                local dx,dy,dz = p.x-previous.x,p.y-previous.y,p.z-previous.z
                d.approximateLength = d.approximateLength + math.sqrt(dx*dx+dy*dy+dz*dz)
            end
            previous = p
        end
        d.gradientViolation = a.maxGradient ~= nil and d.maxAbsGradient > a.maxGradient
        d.radiusViolation = a.minRadius ~= nil and d.maxHorizontalCurvature > 1/a.minRadius
        s.diagnostics = d
        total.evaluatedPoints = total.evaluatedPoints+a.diagnosticSteps+1
        total.approximateLength = total.approximateLength+d.approximateLength
        total.maxAbsGradient = math.max(total.maxAbsGradient,d.maxAbsGradient)
        total.maxHorizontalCurvature = math.max(total.maxHorizontalCurvature,d.maxHorizontalCurvature)
        if d.gradientViolation then total.gradientViolations = total.gradientViolations+1 end
        if d.radiusViolation then total.radiusViolations = total.radiusViolations+1 end
    end
    r.inputGeometry = "mathematically_validated_for_DTO_contract"
    r.endpointContinuity, r.tangentCompatibility = "exact_C0", "exact_C1_forward_dP_du"
    r.structuralCompatibility = "BaseEdge_vector_fields_only_not_native_objects"
    r.sampledDiagnostics = total
    local status = (c.status == "diagnostic_violation" or total.gradientViolations+total.radiusViolations > 0)
        and "diagnostic_violation" or "candidate"
    return {kind="intermediate_track_geometry", status=status, unit="m", parameter=c.parameter,
        sourceCandidateStatus=c.status, sourceRemovedDuplicates=c.removedDuplicates,
        provenance=meta.provenance, assumptions=meta.assumptions, sourceWarnings=meta.sourceWarnings,
        templateReferences=template, nodes=nodes, segments=segments, report=r}
end
return adapter
