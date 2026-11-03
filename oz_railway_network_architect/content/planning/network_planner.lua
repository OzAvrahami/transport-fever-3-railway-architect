-- Conditional corridor-study topology, not alignment, demand forecasting or construction.
local schema = ug_require "oz_railway_network_architect::/planning/network_input.lua"
local planner = {}
local function distance(a, b) return math.sqrt((a.x - b.x)^2 + (a.y - b.y)^2) end
local function forest(ids)
    local parent = {}; for _, id in ipairs(ids) do parent[id] = id end
    local function root(id)
        local r = id; while parent[r] ~= r do r = parent[r] end
        while parent[id] ~= id do local nextId = parent[id]; parent[id] = r; id = nextId end
        return r
    end
    local function join(a, b)
        a, b = root(a), root(b)
        if a == b then return false end
        parent[math.max(a, b)] = math.min(a, b); return true
    end
    return root, join
end
local function idsOf(records)
    local ids = {}; for _, r in ipairs(records) do ids[#ids + 1] = r.id end; return ids
end
local function railHints(m, stats)
    local hints, rail = {}, m.rail
    if not rail then return hints end
    local root, join = forest(idsOf(rail.nodes))
    local incident = {}
    for _, e in ipairs(rail.segments) do join(e.node0, e.node1); incident[e.node0], incident[e.node1] = true, true end
    for _, t in ipairs(m.towns) do
        local best
        for _, n in ipairs(rail.nodes) do
            stats.railNodeComparisons = stats.railNodeComparisons + 1
            if incident[n.id] then
                local d = distance(t, n)
                if d <= m.preferences.railRadius and (not best or d < best.distance) then
                    best = {nodeId = n.id, componentId = root(n.id), distance = d}
                end
            end
        end
        hints[t.id] = best
    end
    return hints
end
local function assess(m, a, b, near)
    local p, key = m.preferences, schema.key(a.id, b.id)
    local hint = m.pairs[key] or {}
    local g, demand, transport = hint.geography, hint.demandSupport, hint.transport
    local ca, cb = a.residentialCapacity, b.residentialCapacity
    local edge = {id = key, sourceId = a.id, destinationId = b.id, distance = distance(a, b),
        status = "deferred", reasons = {}, limitations = {"economic_feasibility_unverified", "alignment_unassessed",
            "town_centers_not_stations", "score_is_not_construction_cost"},
        evidence = {anchors = m.source, residentialCapacitySource = ca, residentialCapacityDestination = cb,
            sourceRegion = a.region, destinationRegion = b.region, demandSupport = demand, geography = g, transport = transport},
        infrastructure = {source = near[a.id], destination = near[b.id],
            provenance = m.rail and {source = m.rail.source, basis = m.rail.basis} or nil},
        constructionStatus = "unverified", scope = "corridor_study_only"}
    if not demand then edge.limitations[#edge.limitations + 1] = "pair_demand_unknown" end
    if not ca or not cb then edge.limitations[#edge.limitations + 1] = "town_capacity_missing" end
    if not g then edge.limitations[#edge.limitations + 1] = "terrain_unassessed_unknown_penalty_is_assumption" end
    if not transport then edge.limitations[#edge.limitations + 1] = "existing_transport_adequacy_unknown" end
    if not m.rail then edge.limitations[#edge.limitations + 1] = "rail_inventory_unavailable" end
    if near[a.id] or near[b.id] then edge.limitations[#edge.limitations + 1] = "rail_proximity_not_station_access_or_operational_route" end
    local function stop(reason, rejected)
        edge.reasons[#edge.reasons + 1] = reason
        if rejected then edge.status = "rejected" end
        return edge
    end
    if edge.distance == 0 then return stop("coincident_anchors", true) end
    if edge.distance < p.minDistance then return stop("short_distance_compare_road_first", true) end
    if edge.distance > p.maxDistance then return stop("distance_exceeds_study_limit") end
    if a.region and b.region and a.region.value ~= b.region.value and not p.allowCrossRegion then
        return stop("separate_regions_require_further_study")
    end
    if a.region and b.region and a.region.value ~= b.region.value then
        edge.limitations[#edge.limitations + 1] = "cross_region_alignment_requires_validation"
    end
    if g and g.blocked then return stop("excluded_by_geographic_assessment") end
    if g and g.difficulty > p.maxDifficulty then return stop("geographic_difficulty_exceeds_preference") end
    if transport and transport.adequacy >= p.adequateTransport then return stop("existing_transport_assessed_adequate") end
    local na, nb = near[a.id], near[b.id]
    edge.infrastructure.samePhysicalComponent = na ~= nil and nb ~= nil and na.componentId == nb.componentId
    if edge.infrastructure.samePhysicalComponent then return stop("inspect_existing_physical_rail_before_new_corridor") end
    local support
    if demand then
        if demand.value < p.minDemandSupport or demand.value == 0 then return stop("supplied_demand_support_too_low") end
        support = demand.value
        edge.reasons[#edge.reasons + 1] = "supplied_demand_support_qualifies"
    elseif ca and cb then
        if ca.value < p.minCapacity or cb.value < p.minCapacity or ca.value == 0 or cb.value == 0 then
            return stop("capacity_proxy_too_small_without_demand_evidence")
        end
        support = 0.5 + 0.5 * math.min(1, math.min(ca.value, cb.value) / p.majorCapacity)
        edge.reasons[#edge.reasons + 1] = "capacity_proxy_justifies_conditional_study"
        edge.limitations[#edge.limitations + 1] = "residential_capacity_is_not_pair_passenger_demand"
    else return stop("insufficient_evidence_not_zero_demand") end
    local difficulty = g and g.difficulty or p.unknownDifficulty
    local distancePenalty, geographyPenalty = edge.distance / p.maxDistance * p.distanceWeight, difficulty * p.geographyWeight
    edge.score = {support = support, distancePenalty = distancePenalty, geographyPenalty = geographyPenalty,
        difficultyUsed = difficulty, difficultyAssumed = g == nil, total = support - distancePenalty - geographyPenalty}
    if edge.score.total < p.minScore then return stop("relative_priority_below_threshold") end
    edge.status = "eligible"
    edge.reasons[#edge.reasons + 1] = "within_distance_limits"
    if g then edge.reasons[#edge.reasons + 1] = "supplied_geographic_screen_passed" end
    if na or nb then edge.reasons[#edge.reasons + 1] = "nearby_rail_reuse_requires_inspection" end
    return edge
end
local function order(a, b)
    if a.score.total ~= b.score.total then return a.score.total > b.score.total end
    if a.distance ~= b.distance then return a.distance < b.distance end
    if a.sourceId ~= b.sourceId then return a.sourceId < b.sourceId end
    return a.destinationId < b.destinationId
end
local function classify(m, result, adjacency, root)
    local groups = {}
    for _, town in ipairs(m.towns) do
        local r = root(town.id)
        if not groups[r] then
            groups[r] = {id = r, townIds = {}, mainlineEdgeIds = {}, status = "isolated"}
            result.components[#result.components + 1] = groups[r]
        end
        local group = groups[r]; group.townIds[#group.townIds + 1] = town.id
    end
    for _, group in ipairs(result.components) do
        if #group.townIds > 1 then
            group.status = "proposed_forest_component"
            local anchors = {}
            for _, id in ipairs(group.townIds) do
                local size = m.townById[id].residentialCapacity
                if size and size.value >= m.preferences.majorCapacity then anchors[#anchors + 1] = id end
            end
            group.mainlineBasis = #anchors >= 2 and "longest_tree_path_between_major_capacity_anchors" or "longest_tree_path_no_two_major_anchors"
            if #anchors < 2 then anchors = group.townIds end
            local target, best = {}, nil
            for _, id in ipairs(anchors) do target[id] = true end
            for _, start in ipairs(anchors) do
                local stack, parent, lengths, via = {start}, {[start] = false}, {[start] = 0}, {}
                while #stack > 0 do
                    local id = table.remove(stack); result.stats.backboneVisits = result.stats.backboneVisits + 1
                    if id > start and target[id] and (not best or lengths[id] > best.length
                        or (lengths[id] == best.length and (start < best.a or (start == best.a and id < best.b)))) then
                        local path, cursor = {}, id
                        while cursor ~= start do path[#path + 1] = via[cursor]; cursor = parent[cursor] end
                        best = {a = start, b = id, length = lengths[id], path = path}
                    end
                    -- Sorted adjacency and a tree make traversal/unique paths deterministic.
                    for _, link in ipairs(adjacency[id]) do
                        if parent[link.neighbor] == nil then
                            parent[link.neighbor], via[link.neighbor] = id, link.edge
                            lengths[link.neighbor] = lengths[id] + link.edge.distance
                            stack[#stack + 1] = link.neighbor
                        end
                    end
                end
            end
            group.mainlineEndpoints = {best.a, best.b}
            -- Reverse reconstruction to source -> destination order.
            for i = #best.path, 1, -1 do
                local edge = best.path[i]; edge.classification = "mainline"
                edge.reasons[#edge.reasons + 1] = group.mainlineBasis
                group.mainlineEdgeIds[#group.mainlineEdgeIds + 1] = edge.id
            end
        end
    end
    for _, edge in ipairs(result.recommendations) do
        if not edge.classification then
            edge.classification = "branch"
            edge.reasons[#edge.reasons + 1] = "off_mainline_tree_connection"
        end
        edge.limitations[#edge.limitations + 1] = "forest_excludes_potentially_useful_loops"
    end
end
local function run(m)
    local result = {status = "ok", snapshotId = m.snapshotId, unit = "world_units", preferences = m.preferences,
        recommendations = {}, decisions = {}, towns = {}, hubs = {}, components = {}, industries = {},
        warnings = {"conditional_topology_studies_not_buildable_network", "no_economic_or_demand_forecast",
            "forest_heuristic_not_global_optimum", "mainline_labels_are_relative_to_each_component",
            "no_terrain_astar_executed", "provenance_is_caller_supplied_not_independently_verified"},
        stats = {pairs = 0, forestChecks = 0, railNodeComparisons = 0, backboneVisits = 0, industryTownComparisons = 0, astarSearches = 0}}
    local near = railHints(m, result.stats)
    local eligible = {}
    for i, a in ipairs(m.towns) do for j = i + 1, #m.towns do
        local edge = assess(m, a, m.towns[j], near)
        result.decisions[#result.decisions + 1] = edge; result.stats.pairs = result.stats.pairs + 1
        if edge.status == "eligible" then eligible[#eligible + 1] = edge end
    end end
    table.sort(eligible, order)
    local root, join = forest(idsOf(m.towns))
    local degree, adjacency = {}, {}
    for _, town in ipairs(m.towns) do degree[town.id], adjacency[town.id] = 0, {} end
    for _, edge in ipairs(eligible) do
        result.stats.forestChecks = result.stats.forestChecks + 1
        local a, b, reason = edge.sourceId, edge.destinationId, nil
        if root(a) == root(b) then reason = "redundant_cycle_in_proposed_topology"
        elseif #result.recommendations >= m.preferences.maxEdges then reason = "selected_edge_budget"
        elseif degree[a] >= m.preferences.maxDegree or degree[b] >= m.preferences.maxDegree then reason = "town_degree_preference" end
        if reason then edge.status = "deferred"; edge.reasons[#edge.reasons + 1] = reason
        else
            join(a, b); degree[a], degree[b] = degree[a] + 1, degree[b] + 1
            edge.status, edge.priority = "recommended", #result.recommendations + 1
            edge.relativePriority = edge.score.total
            result.recommendations[#result.recommendations + 1] = edge
            adjacency[a][#adjacency[a] + 1] = {neighbor = b, edge = edge}
            adjacency[b][#adjacency[b] + 1] = {neighbor = a, edge = edge}
        end
    end
    for _, links in pairs(adjacency) do table.sort(links, function(a, b) return a.neighbor < b.neighbor end) end
    classify(m, result, adjacency, root)
    for _, town in ipairs(m.towns) do
        local report = {id = town.id, name = town.name, x = town.x, y = town.y, z = town.z,
            degree = degree[town.id], componentId = root(town.id), reasons = {}, infrastructure = near[town.id]}
        report.status = report.degree > 0 and "corridor_study_recommended" or "no_new_rail_recommended_now"
        if report.degree == 0 then
            local counts = {}
            for _, edge in ipairs(result.decisions) do
                if edge.sourceId == town.id or edge.destinationId == town.id then
                    local why = edge.reasons[#edge.reasons]; counts[why] = (counts[why] or 0) + 1
                end
            end
            for reason, count in pairs(counts) do report.reasons[#report.reasons + 1] = {reason = reason, count = count} end
            table.sort(report.reasons, function(a, b) return a.reason < b.reason end)
            if #report.reasons == 0 then report.reasons[1] = {reason = "no_other_towns", count = 0} end
        else report.reasons[1] = {reason = "eligible_selected_connections", count = report.degree} end
        if report.degree >= 3 then
            result.hubs[#result.hubs + 1] = {townId = town.id, degree = report.degree,
                reason = "three_or_more_proposed_incident_corridors", status = "potential_interchange",
                limitations = {"station_location_unverified", "not_operational_switch_or_service_connectivity"}}
        end
        result.towns[#result.towns + 1] = report
    end
    for _, industry in ipairs(m.industries) do
        local closest, d
        for _, town in ipairs(m.towns) do
            result.stats.industryTownComparisons = result.stats.industryTownComparisons + 1
            local nextDistance = distance(industry, town)
            if not d or nextDistance < d then closest, d = town, nextDistance end
        end
        result.industries[#result.industries + 1] = {id = industry.id, resource = industry.resource,
            nearbyTownId = d and d <= m.preferences.industryRadius and closest.id or nil,
            distanceToNearestTown = d, status = "deferred", evidence = m.industryEvidence,
            reasons = {"industry_presence_not_freight_demand",
                d and d < m.preferences.minDistance and "short_distance_compare_road_first" or "cargo_flow_and_transport_alternatives_required"}}
    end
    return result
end
function planner.plan(raw)
    local valid, model = pcall(schema.validate, raw)
    if not valid then
        if type(model) ~= "table" or not model.code then error(model, 0) end
        return {status = model.code, error = model, recommendations = {}, decisions = {}}
    end
    return run(model)
end
-- Explicit handoff only. It neither samples terrain nor invokes the corridor core.
function planner.corridorRequest(result, edgeId)
    if type(result) ~= "table" or result.status ~= "ok" then return nil, "invalid_topology_result" end
    for _, edge in ipairs(result.recommendations) do
        if edge.id == edgeId then
            local byId = {}; for _, town in ipairs(result.towns) do byId[town.id] = town end
            local function anchor(id)
                local t = byId[id]; return {id = id, name = t.name, x = t.x, y = t.y, z = t.z}
            end
            return {snapshotId = result.snapshotId, topologyEdgeId = edge.id, sourceId = edge.sourceId,
                destinationId = edge.destinationId, pair = {start = anchor(edge.sourceId), destination = anchor(edge.destinationId)},
                requirements = {"explicit_user_selection", "revalidate_world_entities_and_positions",
                    "fresh_bounded_terrain_sampling", "report_endpoint_snaps", "alignment_may_fail"}, constructionStatus = "unverified"}
        end
    end
    return nil, "edge_not_recommended"
end
return planner
