# Phase 4B.3: bounded long-distance corridor planning

Baseline: accepted commit `ea318ea` on main plus the complete existing uncommitted
Phase 4B.2 workspace. No reset, commit, tag, push, dependency installation or staging
deployment was performed. GUI layout, subscriptions, routing, inventories, identity
and revision are preserved. This implementation awaits code review and native TF3
verification; synthetic success is not a native performance or construction claim.

## Architecture decision and research

Three approaches were compared before implementation:

| Approach | Decision |
| --- | --- |
| One large fine grid | Reject: large area sampling and open sets grow with map area, including terrain irrelevant to the requested corridor. Increasing spacing alone would lose local resolution. |
| Full HPA* with cached cluster entrances | Defer: it requires verified fine-scale connectivity for entrances, preprocessing and cache invalidation. It is more infrastructure than this request needs. |
| Bounded coarse guides with overlapping refinement windows | Choose: reuse the existing canonical grid rules and A*, sample fine terrain near guides only, and explicitly reject a guide whose sections cannot connect. |

The primary algorithm reference is Botea, Mueller and Schaeffer,
[Near Optimal Hierarchical Path-Finding](https://webdocs.cs.ualberta.ca/~mmueller/ps/2004/hpastar.pdf).
That work abstracts local clusters and refines paths. This implementation borrows
the coarse-to-local strategy, but is **not HPA***: it does not precompute portals or
claim the paper's optimality/performance results. Our coarse grid contains sampled
terrain, not verified fine-grid connectivity. A coarse route is always only a guide.

### Procedure

1. Preserve the accepted short-route layout policy: at most 32x32 samples at spacing
   32, 64 or 128. The exact former paths, costs and deterministic tie-breaking remain
   valid. Only `pair_exceeds_grid_resolution_or_boundary_margin` enters hierarchy;
   other endpoint/input failures do not silently fall back.
2. Snap final planning anchors to an in-bounds global 64-unit lattice, recording X/Y,
   dx/dy and distance. Retain the existing maximum 96-unit and 10%-of-pair-distance
   snap allowances; callers may lower them. Original town coordinates stay explicit.
3. Select a broad coarse region around the nearest in-bounds 512-unit guide anchors.
   Add a margin of max(2048, 25% of guide distance rounded up to 512), clipped to map
   bounds. Cap the region at 64x64 samples / 4096 cells. Rectangular and offset maps
   work; excessive coverage returns `unsupported/coarse_map_coverage_limit`.
4. Query actual terrain at those coarse sample coordinates through the unchanged
   read adapter. Run the existing distance, terrain and balanced profiles incrementally.
   Retain up to three distinct guides; no artificial alternatives are manufactured.
5. For each guide, form checkpoints from the fine source anchor, coarse waypoints
   and fine destination anchor. Remove consecutive duplicates. Each adjacent pair
   receives a 64-unit refinement window with 256-unit margins, clipped to map bounds.
   If its fine search is unreachable, retry once with 512-unit margins. Windows never
   exceed 32x32. Fixed lattice coordinates make all shared joins exact.
6. Query each coordinate at most once per request, reusing its actual height/water
   reading in overlapping windows and at joins. Never interpolate the 24x24 inventory,
   invent missing heights or borrow another Game Script's snapshot.
7. Run the canonical three-profile planner in each window. Select its lowest common
   score candidate. Stitch only matching X/Y/Z/water endpoints. Remove loops at
   identical coordinates deterministically; no connecting chord or unsampled bridge
   is inserted. A failed section rejects the whole guide, never publishes its prefix.
8. Revalidate **every final edge** with canonical `corridor_grid.validate/step`,
   including orthogonal corner samples for diagonals, water exclusions and configured
   gradient limits. Recompute complete-route metrics after loop removal.
9. Rank complete candidates using the same common ranking weights. Remove routes
   with less than 25% distinct undirected edge length relative to the shorter route.
   Keep fewer candidates when guides converge. Partial alternative coverage or unknown
   samples is reported explicitly; no global optimality or reachability is asserted.

The coarse guide's profile is lineage information. Fine sections select the best
common score from their local profile results; this greedy section selection is not
a globally optimal corridor search. No railway curve-radius or gradient standard
has been invented. `maxGradient` remains an optional caller assumption; the live
configuration still has no hard gradient cutoff and excludes water by default.

## Source-backed TF3 integration

No new native scheduling, communication, construction or threading API is used.

- Installed `base/tealdef/scripts/gamescript.d.tl:40-68` declares transient GUI state
  get/set and the existing guiUpdate/guiHandleEvent signatures. The accepted live
  request owner already advances work through guiUpdate; this patch stores plain
  continuation tables there and calls their next step on subsequent callbacks.
- `base/content/game_mechanics.zip`, `company/company.script.tl:380-389` explicitly
  subscribes engine state to GUI event names. The runtime-verified RNA subscription
  resource, descriptor and seven-argument event handler are unchanged.
- [Official engine reference](https://wiki.transportfever3.com/script-doc/api/engine.html)
  documents read access from GUI State. Existing `live_plan_api.lua` continues to use
  protected entity/town, bounds, coordinate-validity, height and water reads. All new
  sample positions pass through its existing bounds and Vec2f checks. No new field,
  coordinate constructor or binding-type assumption is introduced.
- Existing mod-qualified ug_require loading resolves one authoritative implementation
  under `content/planning/`; there are no independently maintained search copies.
- No coroutine, closure, thread, native userdata or metatable is retained in search
  continuation state. Tests deep-copy continuations without preserving table aliases.
  An alias-dependent profile update found by that test was corrected by reconnecting
  temporary profile references only during final result assembly.

The general wiki Game Scripts article currently warns that its content is not yet
adapted to TF3. It was not used to infer new lifecycle behavior. Installed definitions
and the project's real-game callback evidence are the integration authority.

## Pure Lua contracts

The accepted synchronous API remains `planner.plan(input)`. It now wraps:

```lua
local job = planner.start(input) -- validates/copies the existing input contract
while not job.finished do
    planner.step(job, 64)       -- at most 64 search expansions; no native calls
end
local result = job.result
```

`corridor_search.start/step` implements the same indexed heap, neighbor ordering,
heuristic, cost weights and tie-breaking formerly used in search.run. There is one
A* implementation. The synchronous wrappers remain useful for offline tests.

The hierarchy API is separate from native integration:

```lua
local h = hierarchy.start({
    start = {id = sourceId, x = sourceX, y = sourceY},
    destination = {id = destinationId, x = destinationX, y = destinationY},
}, {minX = minX, minY = minY, maxX = maxX, maxY = maxY}, {
    constraints = {waterPolicy = "exclude"}, -- optional maxGradient, allowDiagonal
    -- Optional profiles and rankingWeights use the canonical planner contract.
    -- Numeric resource limits may be lowered, not raised above built-in caps.
})
-- Called by the existing request owner; read is passed per call, never stored:
hierarchy.step(h, function(x, y)
    return {valid = true, height = actualHeight, water = actualWater}
end)
-- Or discard partial/just-finished data before publication:
hierarchy.cancel(h, "world_changed")
```

Terrain returns may omit height/water or indicate invalid coordinates. Such samples
remain unknown and excluded. Read exceptions are captured with at most four bounded
examples. Zero and negative heights, and false water values, remain valid. Synthetic
callers can provide verified blocked/obstaclePenalty fields; the live adapter does
not provide obstacle information and the result warns about that omission.

Coarse spacing 512 and fine spacing 64 are fixed initial settings, not tunable railway
standards. Public options also accept lower maxSamples, maxVisits, maxExpansions,
maxSections, maxWaypoints, maxCoarseCells and endpoint snap allowances. Invalid policies
and weights are rejected before terrain queries. Water remains excluded when only a
gradient constraint is supplied; it is penalized only when explicitly requested.

### Output

Every complete live candidate contains:

- id/rank/generatedBy, sourceId and destinationId;
- ordered continuous waypoints with X/Y, sampled Z and water flag;
- originalAnchors and endpoints with explicit snapping deltas/distances;
- length/horizontalLength, elevationGain/elevationLoss/cumulativeElevationChange,
  maxGradient, gradientExposure;
- touchesWater, waterExposure, waterSegments, waterRuns and waterTransitions;
- common score components: distance, gradient, water, obstacle, waterObstacle, total;
- refinedSections, sampling.fineSpacing (and coarseSpacing for hierarchy), searchStatus;
- feasibility=`sampled_constraints_satisfied`, constructionStatus=`unverified`, warnings.

Short-route metadata is additive; canonical short-route geometry/scoring is unchanged.
Long routes also identify `refinementPolicy=best_common_score_per_window`.
The top-level result includes status/reason/complete, actual sample/visit/expansion
counts, coarse region, policies, rejected-guide attempts and data-quality warnings.
The live owner attaches world, town/terrain/planning tick ranges, application start/end
times and `atomic=false`. There is no claim that a multi-callback terrain snapshot is
atomic or that terrain edits within the same world can all be detected.

`unreachable` is always qualified by the searched abstraction/sections, e.g.
`no_coarse_guide_at_sampled_resolution` or `all_coarse_guides_failed_refinement`.
It is not a statement that no real railway could connect those towns. `search_limit`,
`resource_limit`, `unsupported`, `invalidated` and `incomplete` stay distinct.

## Work and memory limits

| Limit | Value |
| --- | --- |
| Sample visits per hierarchy callback | 16, including cache hits; at most 16 new reads |
| Search expansions per live callback | 64, at most 8 neighbor transitions each |
| Final route validation per callback | 32 waypoints |
| Coarse grid | 64x64 / 4096 cells, actual 512-unit readings |
| Fine window | At most 32x32 / 1024 cells, actual 64-unit readings |
| Unique request samples | 32,768 |
| Total sample visits including cached overlaps | 65,536 |
| Total hierarchy expansions | 49,152 across all grids/profiles |
| Per-grid profile expansion budget | 12,288 coarse; 3,072 fine, also limited by remaining total |
| Guides / refined sections | At most 3 guides, 128 sections per guide |
| Complete route waypoints | At most 4096 per candidate |
| Wider retry | Once per failed section, 256 to 512 margin |
| Observed-work / snapshot-age guards | Existing 50 ms / 60 seconds |

The hierarchy advances once per GUI callback; short-route collection/search retains
the every-fourth-callback cadence. No per-frame replanning occurs: these callbacks
advance the one explicitly accepted request. Invalidated/finished requests stop work.

Initialization/validation of a bounded grid, reconstructing/summarizing one bounded
path, stitching a section and final deduplication are finite synchronous bookkeeping
operations. They are not covered by the 64-expansion count. Their input sizes are
bounded by the table above and live observed-work guard. Native reads and GUI state
copying cannot be preempted. The existing application clock has no verified resolution;
zero deltas are not proof of zero work. GUI-state serialization and rendering costs
remain outside the current work timer, so there is no proven sub-50ms native guarantee.

Synthetic flat-map counts from the development Lua 5.4 runtime:

| Requested separation | Unique samples | Expansions | Hierarchy step calls |
| --- | ---: | ---: | ---: |
| 8192 units | 1370 | 483 | 279 |
| 16000 units | 2544 | 942 | 541 |

These are operation counts, not TF3 latency measurements. Obstacles, detours and
multiple guides increase work. Slow callback delivery can trigger the retained
60-second age limit; the implementation does not enlarge a budget to hide that risk.
Caches and pending models are released on completion/cancellation. At most three
complete candidate outputs remain in request memory. No external or save cache exists.

## Implementation and relevant diff

Exact files changed in this phase relative to the pre-edit uncommitted snapshot:

```text
AGENTS.md
README.md
docs/phase_4b3_long_distance.md                  new
oz_railway_network_architect/content/
  planning/corridor_search.lua                  resumable canonical A*
  planning/corridor_planner.lua                 resumable profiles and result assembly
  planning/corridor_hierarchy.lua               new orchestration/stitching/validation
  live_plan_request.lua                        short/long continuations and provenance
  live_plan.script.lua                         progress and terminal status wording only
tests/
  hierarchical_planner_test.lua                new
  live_plan_test.lua                           continuation/live regression coverage
  run_lua_tests.py                             includes new suite
```

Relevant control-flow diff (abbreviated; source contains full guards):

```diff
-function search.run(model, weights, budget)
+function search.start(model, weights, budget)
+    return {model = model, weights = weights, budget = budget, ...}
+end
+function search.step(state, limit)
+    -- Same heap, costs and neighbors; stop when this expansion slice is used.
+end
+function search.run(model, weights, budget)
+    -- Synchronous wrapper over start/step.
 end

-function planner.plan(input)
+function planner.start(input)
     -- Existing validation/model and result schema.
+end
+function planner.step(job, limit)
+    -- Advance one profile; final ranking/dedup remains canonical.
+end
+function planner.plan(input)
+    -- Synchronous wrapper over start/step.
 end

-    if not layout then fail("unsupported", layoutReason) end
+    if not layout then
+        if layoutReason ~= "pair_exceeds_grid_resolution_or_boundary_margin" then
+            fail("unsupported", layoutReason)
+        end
+        session.hierarchy = hierarchy.start(pair, session.bounds, ...)
+        session.phase = "hierarchy"
+        return
+    end

-    session.result = planner.plan(input)
+    session.planningJob = planner.start(input)
+    -- Subsequent callbacks:
+    planner.step(session.planningJob, 64)

+    elseif session.phase == "hierarchy" then
+        verifySources(session)
+        hierarchy.step(session.hierarchy, function(x, y)
+            return adapter.sample(session.bounds, x, y)
+        end)
+        -- Publish only terminal results after the existing world/time guards.
```

The owner publishes progress through its existing message field. No new UI resource,
control, subscription, event name or response transport was introduced. All four accepted
scanners and the GUI script/stylesheet remain byte-for-byte unchanged from this
phase's starting snapshot. The grid transition/scoring module is unchanged.

## Automated verification

Command (uses the existing cached dependency; no installation):

```powershell
uv run --no-project --offline --with lupa==2.8 python tests/run_lua_tests.py
```

**123 tests pass:** 20 railway, 22 original planner, 20 hierarchy and 61 live/UI.
**35 Lua files** pass Lua 5.4 syntax checks. JSON, UTF-8 without BOM, local resource
references/imports, descriptor exports and unchanged identity/revision pass.

Coverage includes short-route parity against canonical results; repeated scheduling
and plain-state copying; recorded Morley/Winterton coordinate separation; 8192/16000
routes; offset rectangular maps; mountain/valley detours; water exclusion and explicit
penalty; a fine barrier invisible on the coarse grid; a successful wider-window retry;
missing/nonfinite heights and read errors; overlapping sample reuse; joint continuity;
loop-free final paths; recomputed geometry; common ranking and real alternatives;
empty alternatives on impossible sampled routes; all resource caps; early policy
validation; cancellation, including after the last work slice; GUI progress/selection;
world, bounds, town and reload invalidation; age/performance guards; no automatic Plan.

The previous distant-pair UI test now expects a successfully refined synthetic route,
which is the requested behavior change. The same selection, close/reopen and transport
assertions remain. The world-change-during-search test injects the change at the new
step boundary instead of the former synchronous plan call. No failures were masked
by weakening freshness or busy/replay validation.

## Native review/acceptance and next milestone

No staging files were changed. After code review, close TF3 before manually updating
the two canonical planner files, adding corridor_hierarchy.lua, and replacing
live_plan_request.lua and live_plan.script.lua. The existing GUI resources, stylesheet,
event subscription resource and .gs descriptor require no replacement. Do not copy
tests/docs into staging or overwrite unrelated local work.

1. Recheck a known successful short town pair: same explicit selection, bounded
   sampling, stable ranked geometry and no automatic planning.
2. Request Morley to Winterton. Expect LONG_DISTANCE mode=hierarchical, explicit
   endpoint snaps, bounded `[RNA:PLAN:4B3] PROGRESS` markers, then SUMMARY/CORRIDOR and
   the existing `[RNA:PLAN:4B2]` SEARCH/CANDIDATE/COMPLETE logs. Real terrain may reject
   a guide that succeeds on synthetic terrain; inspect exact status/reason.
3. Try an 8000+ pair and, where map extent permits, a 16000-unit pair. Record elapsed
   time, max observed callback work, sample/expansion counts and visible responsiveness.
   Zero work time must still display the timing-resolution warning.
4. Close/reopen while planning: the existing owner continues and selections/status
   behave as before. A map reload must discard the old request and never publish its
   candidates into the new session. Do not save just for validation.
5. Check an island/water-separated pair: excluded water must not become a fabricated
   successful crossing. Try another explicit request after any failure or completion.

Representative new markers:

```text
[RNA:PLAN:4B2] LONG_DISTANCE mode=hierarchical coarse_spacing=512 fine_spacing=64 window_limit=32
[RNA:PLAN:4B3] PROGRESS Long-distance planning: fine_sampling | guide 1/1 | section 1 | samples ... | expansions ...
[RNA:PLAN:4B3] SUMMARY status=ok reason=refined_routes_validated samples=... unknown=0 expansions=... max_step_expansions=...
[RNA:PLAN:4B3] CORRIDOR id=hierarchical_1 sections=... waypoints=... fine_spacing=64 construction=unverified
[RNA:PLAN:4B2] COMPLETE status=ok candidates=1 data_complete=true reason="refined_routes_validated"
```

Progress formatting uses spaced counters in the actual message (`samples N`,
`expansions N`); values and guide counts depend on the actual map. Progress log entries
are capped at eight per request; the UI message continues updating without per-frame
logging. Existing full candidate logs report scores, gradients, elevation and water.

Known limits: a coarse sample may miss narrow valleys or barriers; coarse anchor
placement can reject a fine-scale-feasible endpoint; fixed checkpoints can constrain
an otherwise viable route; a bounded neighborhood may miss a distant detour; 64-unit
samples cannot prove terrain between samples; section choices are locally greedy;
state-copy overhead and native responsiveness are not yet measured. No curves,
bridges, tunnels, station placement, track connections, economy or construction
feasibility have been validated.

The next milestone is **native acceptance and profiling of Phase 4B.3**. Only after
review should adaptive checkpoint/guide recovery or route visualization be scoped.
No network planning, overlays or construction work is included here.
