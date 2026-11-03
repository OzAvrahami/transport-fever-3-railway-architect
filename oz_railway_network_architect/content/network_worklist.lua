-- Pure session worklist. Original recommendations are read, never modified.
local worklist = {}
local function id(v) return type(v) == "number" and v >= 0 and v <= 2147483647 and v % 1 == 0 end
local function array(value, limit)
    if type(value) ~= "table" then return false end
    local count = 0
    for k in pairs(value) do
        count = count + 1
        if not id(k) or k < 1 or k > limit or count > limit then return false end
    end
    for i = 1, count do if value[i] == nil then return false end end
    return true
end
local function clone(v)
    if type(v) ~= "table" then return v end
    local copy = {}; for k, item in pairs(v) do copy[k] = clone(item) end; return copy
end
function worklist.entry(w, edgeId)
    for _, e in ipairs(w and w.edges or {}) do if e.id == edgeId then return e end end
end
function worklist.decision(w, edgeId)
    if not worklist.entry(w, edgeId) then return nil end
    local override = w.overrides[edgeId]
    return {included = not override or override.included, furtherStudy = override and override.furtherStudy or false,
        provenance = override and clone(override.provenance) or {actor = "algorithm", action = "original_recommendation"}}
end

local function analyze(w)
    local g = {included = 0, excluded = 0, overrides = 0, furtherStudy = 0, duplicates = w.duplicates,
        cycles = 0, components = {}, hubs = {}, unconnected = {}, adjacency = {}, branchGroups = {}}
    local parent, mainNodes, branchAdj = {}, {}, {}
    for _, town in ipairs(w.towns) do parent[town], g.adjacency[town], branchAdj[town] = town, {}, {} end
    local function root(a)
        while parent[a] ~= a do a = parent[a] end
        return a
    end
    for _, e in ipairs(w.edges) do
        local d = worklist.decision(w, e.id)
        if w.overrides[e.id] then g.overrides = g.overrides + 1 end
        if d.furtherStudy then g.furtherStudy = g.furtherStudy + 1 end
        if d.included then
            g.included = g.included + 1
            local a, b = root(e.sourceId), root(e.destinationId)
            if a == b then g.cycles = g.cycles + 1 else parent[math.max(a, b)] = math.min(a, b) end
            table.insert(g.adjacency[e.sourceId], {townId = e.destinationId, edgeId = e.id})
            table.insert(g.adjacency[e.destinationId], {townId = e.sourceId, edgeId = e.id})
            if e.classification == "mainline" then mainNodes[e.sourceId], mainNodes[e.destinationId] = true, true
            else
                table.insert(branchAdj[e.sourceId], {townId = e.destinationId, edgeId = e.id})
                table.insert(branchAdj[e.destinationId], {townId = e.sourceId, edgeId = e.id})
            end
        else g.excluded = g.excluded + 1 end
    end
    local components, visited = {}, {}
    for _, town in ipairs(w.towns) do
        table.sort(g.adjacency[town], function(a, b) return a.townId < b.townId end)
        local r = root(town)
        if not components[r] then components[r] = {id = r, townIds = {}}; g.components[#g.components + 1] = components[r] end
        table.insert(components[r].townIds, town)
        local degree = #g.adjacency[town]
        if degree == 0 then g.unconnected[#g.unconnected + 1] = town end
        if degree >= 3 then g.hubs[#g.hubs + 1] = town end
        -- Components of retained ORIGINAL branch edges, and their shared nodes
        -- with retained ORIGINAL mainline edges. No new service classification.
        if not visited[town] and #branchAdj[town] > 0 then
            local group = {townIds = {}, edgeIds = {}, mainlineAnchorIds = {}}
            local queue, cursor, edgeSet = {town}, 1, {}; visited[town] = true
            while cursor <= #queue do
                local t = queue[cursor]; cursor = cursor + 1
                group.townIds[#group.townIds + 1] = t
                if mainNodes[t] then group.mainlineAnchorIds[#group.mainlineAnchorIds + 1] = t end
                for _, link in ipairs(branchAdj[t]) do
                    if not edgeSet[link.edgeId] then edgeSet[link.edgeId] = true; group.edgeIds[#group.edgeIds + 1] = link.edgeId end
                    if not visited[link.townId] then visited[link.townId] = true; queue[#queue + 1] = link.townId end
                end
            end
            table.sort(group.townIds); table.sort(group.edgeIds); table.sort(group.mainlineAnchorIds)
            group.status = #group.mainlineAnchorIds > 0 and "attached_to_original_mainline" or "detached_from_original_mainline"
            g.branchGroups[#g.branchGroups + 1] = group
        end
    end
    table.sort(g.components, function(a, b) return a.id < b.id end)
    g.classificationInterpretation = g.excluded == 0 and g.cycles == 0 and g.duplicates == 0
        and "original_proposal_unverified" or "historical_only_reassessment_required"
    return g
end

function worklist.create(result, identity)
    if type(result) ~= "table" or result.status ~= "ok" or type(result.snapshotId) ~= "string"
        or #result.snapshotId == 0 or #result.snapshotId > 160 or not array(result.towns, 32) or not array(result.recommendations, 31)
        or type(identity) ~= "table" or not id(identity.world) or not id(identity.epoch) or not id(identity.networkRequestId) then
        return nil, "invalid_or_oversized_worklist_source"
    end
    local w = {world = identity.world, epoch = identity.epoch, networkRequestId = identity.networkRequestId,
        snapshotId = result.snapshotId, revision = 0, towns = {}, edges = {}, overrides = {}, duplicates = 0}
    local towns, edges = {}, {}
    for _, t in ipairs(result.towns) do
        if type(t) ~= "table" or not id(t.id) or towns[t.id] then return nil, "invalid_worklist_town" end
        towns[t.id] = true; w.towns[#w.towns + 1] = t.id
    end
    for _, e in ipairs(result.recommendations) do
        if type(e) ~= "table" or not id(e.sourceId) or not id(e.destinationId)
            or not towns[e.sourceId] or not towns[e.destinationId] or e.sourceId == e.destinationId
            or e.status ~= "recommended" or (e.classification ~= "mainline" and e.classification ~= "branch") then
            return nil, "invalid_worklist_recommendation"
        end
        local a, b = math.min(e.sourceId, e.destinationId), math.max(e.sourceId, e.destinationId)
        local key = a .. ":" .. b
        if e.id ~= key then return nil, "noncanonical_worklist_edge_id" end
        if edges[key] then
            if edges[key].classification ~= e.classification then return nil, "conflicting_duplicate_recommendation" end
            w.duplicates = w.duplicates + 1
        else
            local entry = {id = key, sourceId = a, destinationId = b, classification = e.classification}
            edges[key] = entry; w.edges[#w.edges + 1] = entry
        end
    end
    table.sort(w.towns)
    table.sort(w.edges, function(a, b) return a.sourceId < b.sourceId or (a.sourceId == b.sourceId and a.destinationId < b.destinationId) end)
    w.graph = analyze(w)
    return w
end

function worklist.matches(w, state)
    local n = state.network
    return w ~= nil and n ~= nil and n.finished == true and n.status == "ok" and n.result ~= nil
        and w.world == state.world and w.world == n.world and w.epoch == state.epoch and w.epoch == n.epoch
        and w.networkRequestId == state.networkRequestId and w.networkRequestId == n.id
        and w.snapshotId == n.result.snapshotId
end

-- Copy-on-accept: a rejected operation never partially changes the old worklist.
function worklist.edit(w, operation, tick)
    if type(operation) ~= "table" or operation.snapshotId ~= w.snapshotId
        or operation.networkRequestId ~= w.networkRequestId then return nil, "stale_worklist_snapshot" end
    if operation.revision ~= w.revision then return nil, "duplicate_or_stale_worklist_revision" end
    if w.revision >= 1000000 then return nil, "worklist_edit_limit; Analyze Network again" end
    local action = operation.action
    if action ~= "include" and action ~= "exclude" and action ~= "restore" and action ~= "mark_study"
        and action ~= "reset_all" then return nil, "invalid_worklist_action" end
    if action ~= "reset_all" and not worklist.entry(w, operation.edgeId) then return nil, "edge_not_in_worklist" end
    if action == "reset_all" and operation.edgeId ~= nil then return nil, "reset_all_must_not_target_edge" end
    local nextValue = clone(w); nextValue.revision = w.revision + 1
    if action == "reset_all" then nextValue.overrides = {}
    elseif action == "restore" then nextValue.overrides[operation.edgeId] = nil
    else
        local prior = worklist.decision(w, operation.edgeId)
        nextValue.overrides[operation.edgeId] = {
            included = action == "include" or (action ~= "exclude" and prior.included),
            furtherStudy = action == "mark_study" or prior.furtherStudy,
            provenance = {actor = "user", action = action, revision = nextValue.revision, tick = tick}}
    end
    nextValue.graph = analyze(nextValue)
    return nextValue
end

function worklist.summary(w)
    if not w then return nil end
    local g, rows, groups = w.graph, {}, {}
    for _, e in ipairs(w.edges) do
        local d = worklist.decision(w, e.id)
        local relation = "not_an_included_original_branch"
        for _, group in ipairs(g.branchGroups) do for _, edgeId in ipairs(group.edgeIds) do
            if edgeId == e.id then relation = group.status .. " anchors=" .. table.concat(group.mainlineAnchorIds, ",") end
        end end
        rows[#rows + 1] = {id = e.id, included = d.included, furtherStudy = d.furtherStudy,
            actor = d.provenance.actor, action = d.provenance.action,
            classification = e.classification, branchRelationship = relation}
    end
    for _, group in ipairs(g.components) do groups[#groups + 1] = "[" .. table.concat(group.townIds, ",") .. "]" end
    return {world = w.world, epoch = w.epoch, networkRequestId = w.networkRequestId,
        snapshotId = w.snapshotId, revision = w.revision, entries = rows,
        classificationInterpretation = g.classificationInterpretation,
        lines = {
            "Included: " .. g.included .. " | Excluded: " .. g.excluded .. " | User overrides: " .. g.overrides .. " | Further study: " .. g.furtherStudy,
            "Edited components (including isolated towns): " .. #g.components .. " " .. table.concat(groups, " "),
            "Unconnected town IDs: " .. (#g.unconnected > 0 and table.concat(g.unconnected, ", ") or "none")
                .. " | Potential hub IDs: " .. (#g.hubs > 0 and table.concat(g.hubs, ", ") or "none"),
            "Duplicate source references: " .. g.duplicates .. " | Independent cycles: " .. g.cycles .. ". No operational routing implied.",
            g.classificationInterpretation == "original_proposal_unverified"
                and "Original Mainline/Branch proposal retained; still unverified."
                or "Membership or source consistency changed. Original Mainline/Branch labels are historical only; reassessment required.",
            "User edits apply to this snapshot only; they do not refresh evidence or run A*. Construction and economics unverified.",
        }}
end
function worklist.find(summary, edgeId)
    for _, row in ipairs(summary and summary.entries or {}) do if row.id == edgeId then return row end end
end
function worklist.valid(summary, state)
    if type(summary) ~= "table" or summary.world ~= state.world or summary.epoch ~= state.epoch
        or summary.networkRequestId ~= state.networkRequestId or not state.networkSummary
        or summary.snapshotId ~= state.networkSummary.snapshotId or not id(summary.revision)
        or not array(summary.entries, 31) or not array(summary.lines, 6) or #summary.lines ~= 6 then return false end
    for _, line in ipairs(summary.lines) do if type(line) ~= "string" or #line > 1600 then return false end end
    local seen = {}
    for _, row in ipairs(summary.entries) do
        if type(row) ~= "table" or type(row.id) ~= "string" or seen[row.id]
            or type(row.included) ~= "boolean" or type(row.furtherStudy) ~= "boolean"
            or (row.actor ~= "user" and row.actor ~= "algorithm") or type(row.action) ~= "string"
            or (row.classification ~= "mainline" and row.classification ~= "branch")
            or type(row.branchRelationship) ~= "string" or #row.branchRelationship > 512 then return false end
        seen[row.id] = true
    end
    return summary.classificationInterpretation == "original_proposal_unverified"
        or summary.classificationInterpretation == "historical_only_reassessment_required"
end
return worklist
