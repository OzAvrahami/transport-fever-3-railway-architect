# Station-aware smooth railway preview

Baseline: `main`, `d8f25c6`, initially clean. The owner has accepted native
Midhurst-Morley orange/purple station reservations and the cyan route joining their
approach points. This is a read-only preview extension. **Native acceptance of the
new smoothing is pending**, not implied by the automated tests below.

No construction, native proposal processing, terrain/tree/station changes, save edits,
staging deployment, commits, tags, pushes, identity or revision changes were performed.

## Architecture and preserved ownership

The existing `station_plan_request.lua` GUI-state owner still selects station sites,
runs at most two sequential authoritative A*/hierarchical corridor studies, and checks
their approaches and known obstacles. A new optional `smooth` continuation runs on
those complete candidates before the existing final reservation revalidation.

`geometry/station_smooth_preview.lua` is pure Lua. It calls the existing Hermite fitter
in `geometry/rail_curve.lua`; it does not implement a second spline engine. The GUI
owner supplies fresh protected terrain reads via `live_plan_api.sampleCurve`.
One candidate is processed at a time, using the same verified guiUpdate lifecycle and
world/tick checks. No events, subscriptions, React scheduling or global state were added.

Each candidate retains its original `waypoints`, scores, station choices and exact
approach XYZ. Its separate `smoothPreview` contains either complete checked rendering
points and bounded diagnostics, or a fallback status/reason with **no partial points**.
Station classification, candidate ranking and the original A* outputs are unchanged.
Original scores/statistics describe the original corridor, not a newly costed alignment.

The sole zone owner, `route_overlay.lua`, chooses validated smooth points when present,
otherwise the original grid points. It still requires a current complete corridor,
matching request/world/epoch and valid view lease. It checks exact endpoint agreement,
finite points and the full render-count limit before starting. Orange/purple marker
generation is unchanged. Focus uses the displayed points; Hide/Show and alternatives
reuse stored results without terrain reads or A* reruns. Normal React status responses
still contain compact candidate metadata, never complete curve/waypoint arrays.

New requests and world invalidation discard the owner result/continuation. Close
removes mod-owned zones and revokes the view lease; an owner calculation may finish
while closed, but cannot restore zones. Reopen/show requires a fresh valid lease.
Existing exact-key replacement, bounded removal, heartbeat and reload cleanup remain.

## Verified source contracts

Installed root: `D:\SteamLibrary\steamapps\common\Transport Fever 3`. Files and ZIP
members were read only. References below use one-based lines; `!` separates archive
and member. Octocode exact reads confirmed renderer ownership; localSearch rejected
its query schema, so focused direct searches/reads supplied the remaining evidence.

| Evidence | Verified scope |
|---|---|
| `base/content/scripts.zip!scripts/mathutil.lua:39-55`; `scripts/vec2.tl:74-105`; `base/tealdef/scripts/vec2.d.tl:66-81` | Cubic Hermite interpolation and forward derivatives on normalized parameter [0,1]. The existing fitter uses this mathematical convention; it is not an assertion about native construction acceptance. |
| `api/tealdef/api/type.d.tl:499-511` | Vec2f.new(x,y). Non-integer curve coordinates require accounting for native float conversion; the original integer planner contract remains exact. |
| `api/tealdef/api/engine.d.tl:1725-1745` | terrain.isValidCoordinate(Vec2f), getHeightAt(Vec2f), isOnWater(Vec2f). Height queries can clamp outside the map, so both requested and native coordinates must be strictly inside current bounds and native validation must succeed. |
| `api/tealdef/api/gui.d.tl:694-717` | mission.setZone(key, polygon of Vec2f, draw, Vec4f color, prohibitBuilding, optional animation/offset), removeZone(key). Existing draw=true, prohibitBuilding=false, animation=false, zOffset=1 remain unchanged. |
| `api/tealdef/api/engine.d.tl:225-230` and prior station classification evidence | Known objects are conservative world AABBs with preserved hard/vegetation/unknown classification. No new collider API, road access inference or native occupancy mechanism. |
| Accepted project implementation and owner evidence | guiUpdate continuation, request/view ownership and setZone rendering already work in Freeplay. This change reuses those mechanisms, including camera focus; it does not infer new renderer ownership from internal APIs. |

The official [engine reference](https://wiki.transportfever3.com/script-doc/api/engine.html)
documents read-only engine access from GUI state. The [GUI reference](https://wiki.transportfever3.com/script-doc/api/gui.html)
documents the existing zone operations. Installed declarations above provide the exact
contracts used. No ProposalViewer, world objects, commands or construction tools are used.

## Geometry and validation

1. Copy up to 4096 original XYZ points incrementally. Remove only exactly forward-
   collinear XYZ intermediates; no approximate shortcut or endpoint shift. Reject
   invalid/duplicate points or more than 256 remaining knots without truncation.
2. Fit the accepted Hermite representation, retaining each remaining knot. New optional
   fitter directions fix the first tangent's horizontal direction to the source station
   axis and the final forward tangent to the **negative** destination station axis.
   Tangent magnitudes use adjacent horizontal chord lengths; endpoint vertical grade
   comes from the adjacent route chord, not an invented native platform profile.
3. The preview uses shared interior derivatives scaled by 1.75. This explicit fitting
   heuristic spreads a grid turn; it is not a TF3 engineering rule. The fitter's default
   remains 1 for existing offline/DTO callers. Shared derivatives preserve exact C1
   joins in consecutive unit parameter intervals. Existing default geometry tests pass.
4. Convert each Hermite segment to equivalent cubic Bezier controls:
   `B0=P0, B1=P0+T0/3, B2=P1-T1/3, B3=P1`. De Casteljau subdivision changes neither
   curve shape nor endpoints. A whole segment's control hull must stay within the
   configured XY distance of its original chord; exact-collinear cleanup preserves
   that chord's original path. No curve is accepted just for looking smoother.
5. For every subdivision span, the control hull bounds the **entire** curve. Test that
   hull against known hard AABBs expanded by the 12 m ribbon margin plus 1/64 m, both
   station bodies with the existing 12 m approach-validation margin, and map bounds.
   If overlap cannot be excluded, subdivide; unresolved spans reject the smooth result.
   This catches collisions between samples. Unknowns remain hard; verified vegetation
   remains provisional clearance and does not authorize tree removal.
6. Derivative Bezier controls `Q_i=3(B_(i+1)-B_i)` and second-derivative controls
   `R_i=2(Q_(i+1)-Q_i)` give interval bounds. The minimum positive projection of Q
   onto the span's chord direction lower-bounds horizontal speed. Interval products
   bound `abs(dx*ddy-dy*ddx)`, giving a conservative curvature upper bound after
   division by speed cubed. `max(abs(dz))/minimum_horizontal_speed` bounds grade.
   Refine until both limits are established or reject. These checks cover intervals,
   not just the fitter's initial sampled diagnostics. Floating-point arithmetic is
   not formally outward-rounded interval arithmetic; extremely degenerate spans fail.
7. Subdivide until control-hull/chord deviation is at most 0.25 m and the XY control
   polygon length is at most 16 m. The polygon length upper-bounds XY arc length;
   every portion of the complete accepted curve is represented. The output ribbon
   is a bounded polygonal approximation, not native rail geometry.
8. Probe fresh terrain at the first point, then each span's actual curve midpoint,
   end, and two midpoint side positions 12 m from the centreline. Reject water,
   invalid/missing/error samples or excessive absolute curve-height/terrain difference.
   Preserve zero/negative heights. Side probes use the curve midpoint height as an
   approximate level ribbon reservation; this does not solve crossfall or earthworks.
9. Only after all spans and probes pass is a smooth result retained. Existing final
   town/world/bounds/reservation checks still run before publishing the route.

The native Vec2f terrain-probe conversion is recorded separately from requested
curve coordinates and may differ by at most 1/64 m per axis. Larger error rejects
smoothing. Original grid sampling still rejects any coordinate change. Renderer
Vec2f conversion introduces native precision beyond the double-precision tessellation
bound; visual accuracy on the owner's map remains part of native acceptance.

## Explicit preview assumptions and hard limits

These are provisional RNA preview policies, **not verified TF3 construction rules**.
They do not modify accepted search budgets, slopes, station-site choices or metadata.

| Policy | Value |
|---|---|
| Minimum horizontal curve radius | 40 m, conservatively checked over spans |
| Maximum absolute vertical grade | 0.08 (8%), rise per horizontal distance |
| Maximum sampled absolute curve Z minus terrain height | 2 m; cut/fill and vertical clearance remain unverified |
| Maximum XY curve-to-original-chord deviation | 24 m |
| Mathematical ribbon tessellation error | 0.25 m |
| Maximum span XY arc-length bound | 16 m; terrain probes are discrete, not a continuous terrain proof |
| Interior tangent scale | 1.75 relative to the existing shared tangent heuristic |
| Input / cleaned knots | 4096 / 256 |
| Subdivision nodes / depth | 8192 / 12 per candidate |
| Render spans / terrain probes | 1024 / 4097 per candidate; at most two candidates |
| Per callback | 32 copied input points; a separate <=255-segment fit with eight diagnostic intervals; up to eight subdivision units or sixteen terrain probes |
| Preview processing time | At most 10 s elapsed across both candidates, within the unchanged 60 s station snapshot limit |
| Observed work guard | Existing 50 ms; a smoothing overrun stops optional smoothing and retains grid results for normal final checks |
| Renderer | Existing 16 zone operations/callback, 1024 route polygons plus six station polygons |

Policy overrides in pure tests can tighten constraints/reduce budgets, not increase
work or weaken the minimum radius. Production uses the fixed explicit policy above.
Native calls, the bounded fit, per-span checks against the capped object inventory,
and GUI state copying are not preemptible. Zero clock deltas do not prove zero work.
The 10 s deadline includes callback scheduling; it can reject smoothing on slow
machines without invalidating an otherwise current grid route.

Known occupancy is the unchanged collected local town neighborhoods, at most 4096
normalized object records in total. There is no new global obstacle inventory. The
continuation stores only plain data; completed results release knots/curves/subdivision
stacks and retain at most 1025 points per candidate. No terrain grid is duplicated.

## Fallback and remaining limitations

- Smoothing is all-or-nothing **per candidate**. No partial curve, truncated route,
  altered station, new site or automatic A* retry is substituted. Failed smoothing
  keeps that candidate's original grid route and logs its exact reason.
- Snapshot/world invalidation still discards stale results altogether. It cannot keep
  an old route merely to satisfy a visual fallback requirement. The 60 s limit is
  unchanged. An original route beyond the existing renderer limit remains explicitly
  unsupported if no complete bounded smooth representation exists.
- Tight grid turns may not meet the 40 m radius preference with this one fitting
  heuristic. The ordinary short mocked station fixture intentionally retains its grid
  route; a 64 m diagonal-transition fixture and a live-owner straight fixture pass.
  No native success rate is predicted and thresholds are not relaxed on failure.
- C1 ensures continuous heading and grade, but not C2 curvature continuity, clothoids,
  cant, native speed/radius behavior, self-intersection clearance or operational routing.
- Fresh terrain/water probes cannot exclude a narrow feature between probes or certify
  the full ribbon surface. No continuous terrain extrema/collision contract was found
  or invented. Known AABB checks are conservative and incomplete outside their source
  neighborhoods; same-world changes during the interval snapshot are not atomic.
- setZone draws **2D polygons draped onto terrain** with an offset, not an elevated
  XYZ track mesh. Mathematical endpoints retain exact XYZ, but the preview does not
  depict engineered vertical structures. Bridges/tunnels, cut/fill, station access,
  native track attachment and construction acceptance remain unverified.
- The original corridor and station data remain available. Smooth-only values are
  not passed to the offline geometry inspection tool or falsely substituted for the
  original corridor's scores and statistics.

## Exact changed files

| File | Change |
|---|---|
| `oz_railway_network_architect/content/geometry/rail_curve.lua` | Optional fixed endpoint directions/interior scale; equivalent Bezier subdivision and conservative derivative/hull helpers. Default fitter behavior preserved. |
| `oz_railway_network_architect/content/geometry/station_smooth_preview.lua` | New pure bounded fitting, validation, probes and explicit fallback continuation. |
| `oz_railway_network_architect/content/live_plan_api.lua` | Protected curve probes with bounded native rounding; original planner sampling contract preserved. |
| `oz_railway_network_architect/content/station_plan_request.lua` | Optional sequential smoothing before final checks, time guards, diagnostics and cleanup. |
| `oz_railway_network_architect/content/route_overlay.lua` | Select complete smooth points or original grid; preserve stations/keys/lifecycle; focus displayed path. |
| `tests/station_smooth_test.lua` | 24 pure geometry/terrain-fixture regressions. |
| `tests/live_plan_test.lua` | Eight live-owner/renderer/lifecycle regressions using mocks. |
| `tests/run_lua_tests.py` | Register new suite. |
| `AGENTS.md` | Current accepted baseline and smoothing safety rules. |
| `README.md` | Current behavior, validation counts and report link. |
| `docs/station_aware_smooth_preview.md` | This report and native acceptance procedure. |

Unchanged: A*/hierarchy, topology/worklists/batch algorithms, four inventories, station
site generation/scoring/classification, occupancy policy, compact UI/styles, event
subscriptions, manifest/metadata identity/revision. No new dependency or native API.

## Automated validation

Before edits: **432 tests passed**, 63 Lua files compiled. After changes: **464 tests
passed**, 65 Lua files compiled. Full suite, not a selected subset:

```powershell
uv run --no-project --offline --with lupa==2.8 python tests/run_lua_tests.py
git diff --check
```

Static checks cover Lua 5.4 syntax, imports/resource targets, descriptor exports,
UTF-8 without BOM, JSON, read-only metadata/identity/revision and forbidden construction
call patterns. Diff review includes new files and verifies unchanged accepted modules.

New evidence includes independent Hermite/Bezier midpoint and derivative checks, C1
joins with fixed tangents, dense samples enclosed by conservative bounds, grade/radius
limits, missing terrain, water at centre/side probes, a building hit only by the new
curve ribbon, between-probe hard obstacles, platform reservation intersection, exact
endpoints/marker geometry, input immutability, deterministic results, 8000 m input,
render/subdivision/terrain/knot limits, float conversion, no A* rerun, actual renderer
polygon coordinates under mocks, original-grid fallback, optional/snapshot time limits,
reload, close during work, fresh reopen, alternatives and bounded per-callback reads.

These tests validate code behavior and mathematical assumptions. **They do not prove
native smoothing visibility or native railway feasibility.**

## One focused Midhurst-Morley acceptance test

After owner review and manual deployment of the complete package, load the same
accepted map. No deployment commands were run by the assistant.

1. Open the existing RNA window; choose Midhurst and Morley and click **Plan Railway**
   once. The compact planning UI remains unchanged. Capture logs from station START
   through final completion and route DRAW_SUBMITTED.
2. Compare both orange/purple reservations and their orientation with the accepted
   baseline. They must remain at the selected station sites. The new pass never changes
   them or replaces their approach points with town centers.
3. Read `SMOOTH_COMPLETE`: `status=validated` means every implemented preview check
   completed, **not** construction validity. Route START must say `alignment=smooth`.
   Inspect the cyan route at bends and both station approaches; capture a wide view
   and closeups. No gaps, abrupt platform turn, or straight shortcut through known
   hard obstacles should appear. Compare the exact approach XYZ in owner data/logs
   where available; visual inspection alone cannot establish numeric equality.
4. If `status=fallback`, route START should say `alignment=grid`, and the accepted
   grid route must remain visible. Capture the exact reason (including radius/grade
   values, terrain error, obstacle ID, reservation or budget reason). This verifies
   safe fallback but does **not** satisfy native visible-smoothing acceptance.
5. Pan, rotate and zoom. Try any genuinely available alternative, Hide/Show and Focus.
   Confirm no additional PAIR/SMOOTH_START appears just for viewing. Close/reopen and
   explicitly Show again; close or reload and verify all mod markers clean up.
6. Confirm no track, station, tree or terrain change. Capture errors or missing overlay
   behavior honestly; do not infer success from logs alone or increase limits on the fly.

Expected diagnostic shape (numbers depend on the map):

```text
[RNA:STATION] SMOOTH_START candidate=... min_radius=40 max_grade=0.08 terrain_delta=2 assumptions=provisional
[RNA:STATION] SMOOTH_COMPLETE candidate=... status=validated|fallback reason=... segments=... probes=... max_curvature_bound=... max_grade_bound=... terrain_delta=... obstacle_coverage=known_local_AABBs terrain_validation=sampled construction=unverified
[RNA:STATION] SMOOTH_FALLBACK candidate=... reason=observed_50ms_work_guard
[RNA:STATION] COMPLETE status=ok reason=...smooth_preview_optional;construction_unverified
[RNA:ROUTE] START request=... candidate=... segments=... alignment=smooth|grid prohibitBuilding=false
[RNA:ROUTE] DRAW_SUBMITTED request=... candidate=... zones=... native_visibility=unverified
```

SMOOTH_FALLBACK is emitted only for a measured overrun after a terminal smoothing
result; it overrides any earlier validated diagnostic for that candidate. No per-point
logging. Stop for owner review and this native test, not further feature development.
