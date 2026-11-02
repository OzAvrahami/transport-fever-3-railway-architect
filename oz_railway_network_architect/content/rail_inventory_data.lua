-- Pure Lua: discovery normalization and undirected base-node incidence graph.
local inventory = {}
inventory.MAX_SEGMENTS = 20000
inventory.MAX_NODES = 40000
inventory.MAX_REFERENCES = 100000

function inventory.finite(value)
    if type(value) == "number" and value == value
        and value ~= math.huge and value ~= -math.huge then return value end
    return nil
end

function inventory.id(value)
    local number = inventory.finite(value)
    return number ~= nil and number >= 0 and number % 1 == 0 and number or nil
end

function inventory.text(value)
    return tostring(value):gsub("[%c]", " ")
end

local function sortedKeys(set)
    local keys = {}
    for key in pairs(set) do keys[#keys + 1] = key end
    table.sort(keys)
    return keys
end

function inventory.discover(map)
    if type(map) ~= "table" then error("track index: expected node-to-edge table", 0) end
    local edges, nodes = {}, {}
    local result = {references = 0, duplicates = 0, rejected = 0}
    local entries, edgeCount, nodeCount = 0, 0, 0
    for node, references in pairs(map) do
        entries = entries + 1
        if entries > inventory.MAX_REFERENCES then error("track index entry limit exceeded", 0) end
        if type(references) ~= "table" then error("track index: expected edge array", 0) end
        if inventory.id(node) == nil then
            result.rejected = result.rejected + 1
        else
            for _, id in pairs(references) do
                result.references = result.references + 1
                if result.references > inventory.MAX_REFERENCES then error("track reference limit exceeded", 0) end
                if inventory.id(id) == nil then
                    result.rejected = result.rejected + 1
                else
                    if not nodes[node] then nodes[node], nodeCount = true, nodeCount + 1 end
                    if edges[id] then result.duplicates = result.duplicates + 1 else
                        edges[id], edgeCount = true, edgeCount + 1
                    end
                    if edgeCount > inventory.MAX_SEGMENTS or nodeCount > inventory.MAX_NODES then
                        error("rail inventory size limit exceeded; no truncated graph accepted", 0)
                    end
                end
            end
        end
    end
    -- Empty arrays can belong to non-track nodes; they do not create rail nodes.
    result.edgeIds, result.nodeIds = sortedKeys(edges), sortedKeys(nodes)
    return result
end

function inventory.nodeIds(discovery, rawEdges)
    local ids = {}
    for _, id in ipairs(discovery.nodeIds) do ids[id] = true end
    for _, edge in ipairs(rawEdges) do
        if edge.isTrack == true then
            if inventory.id(edge.node0) ~= nil then ids[edge.node0] = true end
            if inventory.id(edge.node1) ~= nil then ids[edge.node1] = true end
        end
    end
    local result = sortedKeys(ids)
    if #result > inventory.MAX_NODES then error("rail node limit exceeded", 0) end
    return result
end

local function position(raw)
    if type(raw) ~= "table" then return nil end
    local x, y, z = inventory.finite(raw.x), inventory.finite(raw.y), inventory.finite(raw.z)
    if x == nil or y == nil or z == nil then return nil end
    return {x = x, y = y, z = z}
end

local function note(result, detail)
    result.diagnosticCount = result.diagnosticCount + 1
    if #result.diagnostics < 4 then result.diagnostics[#result.diagnostics + 1] = detail end
end

function inventory.normalize(discovery, rawEdges, rawNodes)
    local result = {
        segments = {}, nodes = {}, adjacency = {}, missingNodeIds = {}, rejectedSegmentIds = {},
        duplicates = discovery.duplicates, rejected = discovery.rejected, incomplete = 0,
        endpoints = 0, multiSegmentNodes = 0, junctionCandidates = 0, isolatedNodes = 0,
        graphSegments = 0, components = 0, selfLoops = 0, chordSegments = 0, chordTotal = 0,
        diagnostics = {}, diagnosticCount = 0, complete = true,
    }
    if discovery.rejected > 0 then note(result, "track index: malformed node/edge references") end
    local nodeById, seenNodes, seenEdges = {}, {}, {}
    -- Readers use sorted discovery IDs. Sorting copies also makes synthetic inputs deterministic.
    local nodeInputs, edgeInputs = {}, {}
    for _, raw in ipairs(rawNodes) do nodeInputs[#nodeInputs + 1] = raw end
    for _, raw in ipairs(rawEdges) do edgeInputs[#edgeInputs + 1] = raw end
    table.sort(nodeInputs, function(a, b) return (inventory.id(a.id) or -1) < (inventory.id(b.id) or -1) end)
    table.sort(edgeInputs, function(a, b) return (inventory.id(a.id) or -1) < (inventory.id(b.id) or -1) end)
    for _, raw in ipairs(nodeInputs) do
        local id = inventory.id(raw.id)
        if id == nil or seenNodes[id] then
            result.rejected = result.rejected + 1
        else
            seenNodes[id] = true
            if raw.available ~= true then
                result.missingNodeIds[#result.missingNodeIds + 1] = id
                result.incomplete = result.incomplete + 1
                note(result, "node " .. id .. ": " .. (raw.error or "BASE_NODE unavailable"))
            else
                local node = {id = id, position = position(raw.position), degree = 0}
                node.status = node.position ~= nil and raw.error == nil and "ok" or "incomplete"
                if node.status ~= "ok" then
                    result.incomplete = result.incomplete + 1
                    note(result, "node " .. id .. ": " .. (raw.error or "position unavailable"))
                end
                nodeById[id], result.adjacency[id] = node, {}
                result.nodes[#result.nodes + 1] = node
            end
        end
    end
    for _, raw in ipairs(edgeInputs) do
        local id = inventory.id(raw.id)
        if id == nil or seenEdges[id] then
            result.rejected = result.rejected + 1
        else
            seenEdges[id] = true
            if raw.isTrack ~= true then
                result.rejected = result.rejected + 1
                result.rejectedSegmentIds[#result.rejectedSegmentIds + 1] = id
                note(result, "segment " .. id .. ": " .. (raw.error or "not verified as RoadType.TRACK"))
            else
                local edge = {id = id, node0 = inventory.id(raw.node0), node1 = inventory.id(raw.node1),
                    position0 = position(raw.position0), position1 = position(raw.position1)}
                if type(raw.template) == "string" and raw.template ~= "" then edge.template = raw.template end
                edge.topologyValid = edge.node0 ~= nil and edge.node1 ~= nil
                    and nodeById[edge.node0] ~= nil and nodeById[edge.node1] ~= nil
                edge.status = edge.topologyValid and edge.position0 ~= nil and edge.position1 ~= nil
                    and edge.template ~= nil and raw.error == nil and "ok" or "incomplete"
                if edge.status ~= "ok" then
                    result.incomplete = result.incomplete + 1
                    note(result, "segment " .. id .. ": " .. (raw.error or "missing endpoint, position or template"))
                end
                if edge.position0 and edge.position1 then
                    local a, b = edge.position0, edge.position1
                    edge.chordLength = inventory.finite(math.sqrt((b.x-a.x)^2 + (b.y-a.y)^2 + (b.z-a.z)^2))
                    if edge.chordLength ~= nil then
                        result.chordSegments = result.chordSegments + 1
                        result.chordTotal = result.chordTotal + edge.chordLength
                    end
                end
                if edge.topologyValid then
                    result.graphSegments = result.graphSegments + 1
                    local a, b = result.adjacency[edge.node0], result.adjacency[edge.node1]
                    a[#a + 1] = {segment = id, neighbor = edge.node1}
                    if edge.node0 == edge.node1 then result.selfLoops = result.selfLoops + 1 else
                        b[#b + 1] = {segment = id, neighbor = edge.node0}
                    end
                end
                result.segments[#result.segments + 1] = edge
            end
        end
    end
    local visited = {}
    for _, node in ipairs(result.nodes) do
        local adjacent = result.adjacency[node.id]
        node.degree = #adjacent -- Distinct incident segments, self-loop counted once.
        if node.degree == 0 then result.isolatedNodes = result.isolatedNodes + 1 end
        if node.degree == 1 then result.endpoints = result.endpoints + 1 end
        if node.degree >= 2 then result.multiSegmentNodes = result.multiSegmentNodes + 1 end
        if node.degree >= 3 then result.junctionCandidates = result.junctionCandidates + 1 end
        if not visited[node.id] then
            result.components = result.components + 1
            local queue, cursor = {node.id}, 1
            visited[node.id] = true
            while cursor <= #queue do
                local id = queue[cursor]
                cursor = cursor + 1
                for _, incidence in ipairs(result.adjacency[id]) do
                    if not visited[incidence.neighbor] then
                        visited[incidence.neighbor] = true
                        queue[#queue + 1] = incidence.neighbor
                    end
                end
            end
        end
    end
    result.status = result.incomplete == 0 and result.rejected == 0 and result.isolatedNodes == 0 and "ok" or "partial"
    return result
end

return inventory
