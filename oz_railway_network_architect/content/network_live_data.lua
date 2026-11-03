-- Pure projection and bounded panel DTO. No engine or policy implementation.
local flow = ug_require "oz_railway_network_architect::/live_plan_data.lua"
local industry = ug_require "oz_railway_network_architect::/industry_inventory_data.lua"
local rail = ug_require "oz_railway_network_architect::/rail_inventory_data.lua"
local data = {}
function data.text(v) return flow.text(v):sub(1, 160) end
function data.town(raw, bounds, capacity)
    if not flow.validTown(raw, bounds) or math.abs(raw.x) > 1000000 or math.abs(raw.y) > 1000000
        or math.abs(raw.z) > 1000000 then return nil end
    return {id = raw.id, name = type(raw.name) == "string" and raw.name ~= "" and data.text(raw.name) or nil,
        x = raw.x, y = raw.y, z = raw.z, residentialCapacity = capacity}
end
function data.industries(raw)
    local normalized = industry.normalize(raw)
    local result = {source = "INDUSTRY.construction / CONSTRUCTION.fileName and transf:getTransl()", basis = "observed", records = {}}
    local missing = 0
    for _, r in ipairs(normalized) do
        if r.x ~= nil and r.y ~= nil and math.abs(r.x) <= 1000000 and math.abs(r.y) <= 1000000 then
            result.records[#result.records + 1] = {id = r.id, x = r.x, y = r.y, resource = r.resource and data.text(r.resource)}
            if not r.resource then missing = missing + 1 end
        else missing = missing + 1 end
    end
    return result, missing
end
function data.rail(discovery, edges, nodes)
    local normalized = rail.normalize(discovery, edges, nodes)
    -- An incomplete graph must not be mistaken for evidence of separate components.
    if normalized.status ~= "ok" then return nil, "partial_rail_inventory_omitted: " .. table.concat(normalized.diagnostics, "; ") end
    local result = {source = "streetSystem track index / BASE_EDGE / BASE_NODE physical graph", basis = "observed", nodes = {}, segments = {}}
    for _, n in ipairs(normalized.nodes) do
        if not n.position or math.abs(n.position.x) > 1000000 or math.abs(n.position.y) > 1000000 then
            return nil, "rail_coordinates_unavailable"
        end
        result.nodes[#result.nodes + 1] = {id = n.id, x = n.position.x, y = n.position.y}
    end
    for _, e in ipairs(normalized.segments) do
        if not e.topologyValid then return nil, "invalid_rail_topology_omitted" end
        result.segments[#result.segments + 1] = {id = e.id, node0 = e.node0, node1 = e.node1}
    end
    return result
end
local function codes(values) return table.concat(values or {}, ", "):gsub("_", " ") end
function data.summary(r)
    local result = r.result
    local s = {epoch = r.epoch, world = r.world, requestId = r.id, links = {}, lines = {}}
    local main, branch, omitted, deferred, hubs = 0, 0, {}, 0, {}
    local names = {}; for _, t in ipairs(result.towns) do
        names[t.id] = (t.name or "Town") .. " [#" .. t.id .. "]"
        if t.degree == 0 then omitted[#omitted + 1] = "#" .. t.id end
    end
    for _, h in ipairs(result.hubs) do hubs[#hubs + 1] = "#" .. h.townId end
    local function append(e)
        local evidence = e.evidence
        s.links[#s.links + 1] = {id = e.id,
            label = (e.priority and ("Rank " .. e.priority .. " ") or "") .. (e.classification or e.status)
                .. " | #" .. e.sourceId .. " - #" .. e.destinationId,
            lines = {names[e.sourceId] .. " -> " .. names[e.destinationId],
                string.format("Direct distance %.0f world units; relative score %s.", e.distance,
                    e.score and string.format("%.4f", e.score.total) or "not scored"),
                "Reasons: " .. codes(e.reasons),
                "Residential capacity: " .. (evidence.residentialCapacitySource and evidence.residentialCapacitySource.value or "unknown")
                    .. " / " .. (evidence.residentialCapacityDestination and evidence.residentialCapacityDestination.value or "unknown") .. "; passenger demand unknown.",
                "Physical rail nodes near anchors: " .. (e.infrastructure.source and e.infrastructure.source.nodeId or "none verified")
                    .. " / " .. (e.infrastructure.destination and e.infrastructure.destination.nodeId or "none verified") .. ". No service or station access inferred.",
                "Limitations: " .. codes(e.limitations)}}
    end
    for _, e in ipairs(result.recommendations) do
        if e.classification == "mainline" then main = main + 1 else branch = branch + 1 end
        append(e)
    end
    -- At most 31 selected plus 24 deferred/rejected decisions cross the UI boundary.
    local shown = 0
    for _, e in ipairs(result.decisions) do if e.status ~= "recommended" then
        deferred = deferred + 1
        if shown < 24 then append(e); shown = shown + 1 end
    end end
    s.lines = {
        string.format("Towns analyzed: %d | Connections: %d | Mainlines: %d | Branches: %d", #result.towns, #result.recommendations, main, branch),
        "Potential hubs: " .. (#hubs > 0 and table.concat(hubs, ", ") or "none"),
        "No new rail recommended now: " .. (#omitted > 0 and table.concat(omitted, ", ") or "none"),
        "Deferred/rejected pairs: " .. deferred .. "; first " .. shown .. " shown in ID order. All proposed links shown in rank order.",
        "Capacity is a proxy, not demand. Terrain, transport adequacy, economics and construction are unverified. No A* executed.",
        "Industries: " .. #result.industries .. " context records; no freight links inferred. Missing capacity: " .. r.missingCapacity .. "; rejected towns: " .. r.rejected,
        "Snapshot world " .. r.world .. ", ticks " .. r.startTick .. "-" .. r.tick .. "; not atomic or a continuously refreshed assessment.",
        "Read warnings: " .. r.warningCount .. (#r.warnings > 0 and (". " .. table.concat(r.warnings, "; ")) or ""),
        "Policy: minimum distance 1000; capacity 200; major anchor 1000; assumed unknown difficulty 0.2; degree limit 3. These are study preferences.",
    }
    return s
end
function data.valid(s, owner)
    if type(s) ~= "table" or s.epoch ~= owner.epoch or s.world ~= owner.world
        or s.requestId ~= owner.networkRequestId or type(s.lines) ~= "table" or #s.lines > 9
        or type(s.links) ~= "table" or #s.links > 55 then return false end
    for _, line in ipairs(s.lines) do if type(line) ~= "string" or #line > 1600 then return false end end
    for _, link in ipairs(s.links) do
        if type(link) ~= "table" or type(link.id) ~= "string" or type(link.label) ~= "string"
            or type(link.lines) ~= "table" or #link.lines ~= 6 then return false end
        for _, line in ipairs(link.lines) do if type(line) ~= "string" or #line > 1600 then return false end end
    end
    return true
end
function data.find(s, id)
    for _, link in ipairs(s and s.links or {}) do if link.id == id then return link end end
end
return data
