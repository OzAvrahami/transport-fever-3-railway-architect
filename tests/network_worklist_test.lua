local worklist = ug_require "oz_railway_network_architect::/network_worklist.lua"
local passed = 0
local function equal(a, b) assert(a == b, "expected " .. tostring(b) .. ", got " .. tostring(a)) end
local function test(name, run)
    local ok, reason = pcall(run); assert(ok, name .. ": " .. tostring(reason))
    passed = passed + 1; print("PASS worklist: " .. name)
end
local function serialize(v)
    if type(v) ~= "table" then return tostring(v) end
    local keys, parts = {}, {}; for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for _, k in ipairs(keys) do parts[#parts + 1] = tostring(k) .. "=" .. serialize(v[k]) end
    return "{" .. table.concat(parts, ",") .. "}"
end
local function edge(a, b, class)
    return {id = math.min(a, b) .. ":" .. math.max(a, b), sourceId = a, destinationId = b,
        classification = class or "mainline", status = "recommended", score = {total = 0.8}, evidence = {source = "synthetic"}}
end
local function fixture()
    return {status = "ok", snapshotId = "synthetic", towns = {{id = 1}, {id = 2}, {id = 3}, {id = 4}, {id = 5}},
        recommendations = {edge(1, 2), edge(1, 3), edge(1, 4, "branch")}}
end
local function create(r) return assert(worklist.create(r or fixture(), {world = 9, epoch = 1, networkRequestId = 2})) end
local function operation(w, action, id)
    return {snapshotId = w.snapshotId, networkRequestId = w.networkRequestId, revision = w.revision, action = action, edgeId = id}
end
local function edit(w, action, id) return assert(worklist.edit(w, operation(w, action, id), 100)) end

test("defaults preserve proposal, isolated towns and candidate hubs", function()
    local w = create()
    equal(w.revision, 0); equal(w.graph.included, 3); equal(w.graph.overrides, 0)
    equal(#w.graph.components, 2); equal(w.graph.unconnected[1], 5); equal(w.graph.hubs[1], 1)
    equal(w.graph.branchGroups[1].mainlineAnchorIds[1], 1)
    equal(w.graph.classificationInterpretation, "original_proposal_unverified")
end)
test("include exclude restore and reset keep the source and prior worklist immutable", function()
    local r = fixture(); local initial = serialize(r); local w = create(r); local first = serialize(w)
    local excluded = edit(w, "exclude", "1:4")
    equal(serialize(w), first); equal(excluded.graph.included, 2); equal(#excluded.graph.hubs, 0)
    equal(excluded.graph.classificationInterpretation, "historical_only_reassessment_required")
    equal(excluded.edges[3].classification, "branch")
    local included = edit(excluded, "include", "1:4")
    equal(included.graph.included, 3); equal(included.graph.overrides, 1)
    equal(worklist.decision(included, "1:4").provenance.actor, "user")
    local restored = edit(included, "restore", "1:4")
    equal(restored.graph.overrides, 0); equal(serialize(restored.graph), serialize(w.graph))
    restored = edit(edit(restored, "exclude", "1:2"), "mark_study", "1:3")
    local reset = edit(restored, "reset_all")
    equal(reset.revision, 6); equal(serialize(reset.graph), serialize(w.graph)); equal(serialize(r), initial)
end)
test("study flag is independent of membership with explicit user provenance", function()
    local w = edit(edit(create(), "exclude", "1:4"), "mark_study", "1:4")
    local d = worklist.decision(w, "1:4")
    equal(d.included, false); equal(d.furtherStudy, true); equal(d.provenance.action, "mark_study")
    equal(d.provenance.revision, 2); equal(d.provenance.tick, 100)
    w = edit(w, "include", "1:4"); equal(worklist.decision(w, "1:4").furtherStudy, true)
    w = edit(w, "restore", "1:4"); equal(worklist.decision(w, "1:4").furtherStudy, false)
end)
test("removing all mainline edges leaves detached original branches without relabeling", function()
    local w = edit(edit(create(), "exclude", "1:2"), "exclude", "1:3")
    equal(w.graph.branchGroups[1].status, "detached_from_original_mainline")
    equal(#w.graph.branchGroups[1].mainlineAnchorIds, 0)
    equal(#w.graph.components, 4); equal(#w.graph.hubs, 0)
    equal(worklist.entry(w, "1:4").classification, "branch")
    equal(worklist.summary(w).entries[3].branchRelationship, "detached_from_original_mainline anchors=")
end)
test("duplicates and reversed endpoint references count once, conflicting duplicates fail", function()
    local r = fixture(); r.recommendations[4] = edge(2, 1)
    local w = create(r); equal(w.duplicates, 1); equal(w.graph.included, 3); equal(w.graph.cycles, 0)
    equal(#w.graph.adjacency[1], 3)
    r.recommendations[4].classification = "branch"
    local bad, reason = worklist.create(r, w); equal(bad, nil); equal(reason, "conflicting_duplicate_recommendation")
end)
test("cycles are reported deterministically and removal updates consistency", function()
    local r = fixture(); r.recommendations[4] = edge(2, 3)
    local w = create(r); equal(w.graph.cycles, 1)
    w = edit(w, "exclude", "2:3"); equal(w.graph.cycles, 0)
    equal(w.graph.classificationInterpretation, "historical_only_reassessment_required")
end)
test("stale and replayed operations cannot mutate prior state", function()
    local w = create(); local token = operation(w, "exclude", "1:2")
    w = assert(worklist.edit(w, token, 10)); local snapshot = serialize(w)
    local bad, reason = worklist.edit(w, token, 10); equal(bad, nil); equal(reason, "duplicate_or_stale_worklist_revision")
    token = operation(w, "include", "1:2"); token.snapshotId = "other"
    equal(worklist.edit(w, token, 10), nil)
    equal(worklist.edit(w, operation(w, "include", "2:4"), 10), nil)
    equal(worklist.edit(w, operation(w, "reset_all", "1:2"), 10), nil)
    equal(serialize(w), snapshot)
end)
test("empty graphs and disconnected subsets are valid without forced connectivity", function()
    local w = create({status = "ok", snapshotId = "empty", towns = {}, recommendations = {}})
    equal(#w.graph.components, 0); equal(edit(w, "reset_all").graph.included, 0)
    w = create(); for _, e in ipairs(w.edges) do w = edit(w, "exclude", e.id) end
    equal(#w.graph.components, 5); equal(#w.graph.unconnected, 5)
end)
test("input permutations and repeated operations produce deterministic graphs", function()
    local r = fixture(); local a = create(r)
    r.towns[1], r.towns[5] = r.towns[5], r.towns[1]
    r.recommendations[1], r.recommendations[3] = r.recommendations[3], r.recommendations[1]
    local b = create(r)
    equal(serialize(a), serialize(b))
    equal(serialize(edit(a, "exclude", "1:2")), serialize(edit(b, "exclude", "1:2")))
end)
test("limits and unknown endpoints fail rather than truncate; max graph stays bounded", function()
    local r = {status = "ok", snapshotId = "max", towns = {}, recommendations = {}}
    for i = 1, 32 do r.towns[i] = {id = i}; if i > 1 then r.recommendations[i - 1] = edge(i - 1, i) end end
    local w = create(r); equal(w.graph.included, 31); equal(#w.graph.components, 1)
    equal(#worklist.summary(w).entries, 31)
    r.towns[33] = {id = 33}; equal(worklist.create(r, w), nil)
    r = fixture(); r.recommendations[1].destinationId = 999; equal(worklist.create(r, w), nil)
    w.revision = 1000000; equal(worklist.edit(w, operation(w, "reset_all"), 0), nil)
end)
print("PASS " .. passed .. " pure worklist tests")
