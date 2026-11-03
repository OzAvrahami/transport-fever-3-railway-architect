# Phase 4B.1: first live-map corridor prototype

Baseline `05f7fd4` on `main`. This implementation has automated mock verification,
not TF3 runtime verification. It performs one read-only test-pair planning attempt
per Game Script GUI session. No UI, construction, save data, exports, automatic
staging, commits or publication are added.

## Verified integration contracts

Definitions and shipped scripts were inspected read-only under
`D:\SteamLibrary\steamapps\common\Transport Fever 3` before implementation.

| Contract | Source evidence |
| --- | --- |
| `.lua` modules, `.gs.lua` registration, `.script.lua` callbacks, mod-qualified paths | [Official resource reference](https://wiki.transportfever3.com/doku.php?id=modding:general:resourcetypes). |
| `ug_require(string) -> any` for game-related modules | `api/tealdef/main.d.tl:5-6`; shipped `gui.zip/gui/construction/construction_colors.gres.lua:1` imports a Lua module this way. That color helper is evidence only, not a dependency. Accepted mod adapters also use these imports. |
| `guiUpdate(userParams, readOnlyEngineState, guiState)`; GUI-state get/set | [Official Game Script reference](https://wiki.transportfever3.com/script-doc/content/scripts/gamescript.html); installed `base/tealdef/scripts/gamescript.d.tl:40-67`; `game_mechanics.zip/game_mechanics/celebrations/celebrations.gs.lua:9-10` and `.script.tl:286-297`. |
| GUI engine reads; TOWN enumeration | [Official engine reference](https://wiki.transportfever3.com/script-doc/api/engine.html); shipped `gui.zip/gui/statistics/statistic_towns.tl:468` calls `getEntitiesWithComponent(TOWN)`. |
| Town bounding-volume center and name | `scripts.zip/scripts/entity_util.tl:48-54` reads BOUNDING_VOLUME and returns its midpoint. `game_mechanics.zip/game_mechanics/towns/town_util.tl:1561-1562` delegates names to `api.engine.util.getEntityName`. |
| `terrain.getBoundingBox()`, `isValidCoordinate(Vec2f)`, `getHeightAt(Vec2f)`, `isOnWater(Vec2f)` | Installed `api/tealdef/api/engine.d.tl:1725-1754`, also the official engine reference. Out-of-bounds height queries can clamp. |
| Box2f min/max x/y; Vec2f.new(x,y) | `api/tealdef/api/type.d.tl:856-865,511`; shipped `gui/map_editor/map_editor.tl:1746-1747` constructs/validates vectors. The accepted terrain adapter uses these fields. |
| `api.util.getApplicationTime()` seconds, GUI only | `api/tealdef/api/util.d.tl:174-176`. Clock granularity is not established. |

`live_plan.gs.lua` registers `live_plan.script@guiUpdate`. Its own GUI state owns
towns, bounds, selected anchors, samples, tick ranges, timings and result. It reuses
only the accepted city adapter's world/timer functions and terrain adapter's bounds
function. It neither invokes another inventory callback nor reads another GUI state.
No world queries occur at module evaluation. No cross-script communication is added.

## One authoritative planner

The three core files moved from root `planning/` into the mod's `content/planning/`.
Only three dependency import lines changed; validation, search and ranking did not.

```diff
-local grid = require "planning.corridor_grid"
+local grid = ug_require "oz_railway_network_architect::/planning/corridor_grid.lua"
-local search = require "planning.corridor_search"
+local search = ug_require "oz_railway_network_architect::/planning/corridor_search.lua"
```

The search module has the same grid-import replacement. Offline tests map resource
imports to these exact files. There are no independently edited copies, generated
algorithms or game-time standard-require fallbacks.

## Selection, sampling and provenance

- Enumerate at most 256 town references, deduplicate/sort IDs, and read eight towns
  every fourth callback. Larger enumeration aborts without truncated selection.
- Exclude/count invalid IDs, unavailable/nonfinite XYZ and out-of-map centers.
  Missing names print `unavailable`; read failures include API paths.
- Examine at most 32,640 pairs. Choose minimum positive XY distance, breaking ties
  lexicographically by entity IDs. Lower ID is start. Coincident centers cannot form
  the pair. Fewer than two valid towns is `unsupported`, without terrain reads.
  This is a diagnostic selection, not an economic recommendation to connect towns.
- Keep source ID/name/XYZ separate from snapped endpoints. Centers are approximate
  anchors, not stations. Snap to nearest samples, half-up on ties; log dx/dy and
  XY distance. Endpoint Z comes from sampled terrain, never the source center's Z.
- Try spacing 32, 64, then 128 world-coordinate units; use the first layout with
  at most 32 columns/rows. Start with one spacing of padding around anchor extents,
  trim padding to map bounds, and shift the integer origin inward if necessary.
  Both anchors must remain covered. A one-unit query margin separates samples
  from map boundaries. Narrow/boundary-adjacent layouts may be unsupported.
- Both snaps must be distinct and each distance <= min(96 units, 10% of pair
  distance). Inadequate layouts stop with a precise reason. These are prototype
  quality limits, not railway standards or a construction accuracy guarantee.
- Map bounds must be finite/increasing and within +/-1,000,000 world units. Integer
  origins/steps give integer sample XY within this range. Native Vec2f x/y must equal
  nominal XY exactly; mismatch makes the sample unavailable before terrain queries.
  API validity and explicit strict map bounds are checked before height/water reads.
- Read 16 points every fourth callback, at most 1,024 samples / 64 batches. Retain
  requested/actual XY, validity, partial values and errors. Nil stays unknown; zero,
  negative heights and false water remain valid. Never interpolate the old 24x24
  inventory or accept clamped outside-map heights.
- Build fresh plain Lua planner input immediately before calling the core, preserving
  its validation independently of GUI-state table representation. `unit=world_units`
  preserves raw coordinates without an unverified conversion.
- Obstacle sources are unverified. Obstacle fields are omitted; the core uses neutral
  defaults, and logs explicitly state buildings/infrastructure obstacles are
  unaccounted for. This does not establish an obstacle-free map. No existing-track
  attachment or operational routing is inferred.

Default water policy is **exclude**, making wet samples impassable. Controlled
settings are in `live_plan_data.config()`: limits may be lowered, or water policy
explicitly changed to `penalize` for testing. No save-specific town IDs are configured.
Configuration validation prevents raising the approved workload/approximation caps.
Phase 4A profiles/ranking are unchanged; no hard railway gradient limit is invented.
Water paths under penalize do not validate bridges. All results remain coarse
corridors with unresolved subcell features, curves, structures, stations and costs.

## Session and timing safety

Use the accepted valid-world/advancing-tick gate: first callback/every 30 callbacks,
abort after 60 consecutive unavailable-world checks. A paused valid world waits
without repeated logging. After initial readiness, work can continue while paused.
The mod never changes game speed.

Every work callback checks world ID and nondecreasing tick before and after work.
Bounds and both selected town positions/components are rechecked before planning.
Changes invalidate the attempt and discard candidates. Town, terrain and planning
tick ranges plus application times document freshness; snapshots older than 60
seconds are discarded. No automatic retries, ongoing replanning, engine-state
writes, GUI SaveData or external persistence.

The new script's GUI state retains samples/results. A fresh GUI state permits a new
attempt. The definitions do not guarantee reset on every load path: **same-process
reload must be tested**. Reused world IDs with nondecreasing ticks cannot independently
prove session continuity. Terrain can change between batches; no atomic snapshot
is claimed. Avoid editing during acceptance.

Planning is synchronous once, in its own callback, capped at **3,072 total expansions**.
The verified GUI timer measures the core call and maximum work-callback duration.
Work over **50 ms**, unavailable timing, clock regression or excess snapshot age
terminates the attempt. Over-budget candidates are discarded; smaller/resumable
work needs review. No unverified asynchronous mechanism or automatic tuning is added.

Timing is checked after work returns: it cannot preempt the first stall. GUI-state
get/set, module loading and final summary logging add costs outside reported work
duration. Native enumeration allocation is not bounded by the returned-array cap.
A zero timer value is not proof of zero cost. Actual TF3 latency must be measured.

Local Lua 5.4/Lupa core-only benchmark, **not TF3**: a 1,024-cell unreachable fixture
used 3,054 expansions, peak open set 88. Five runs: 22.127, 24.615, 20.975, 25.712,
23.276 ms. This excludes native sampling and GUI costs.

## Exact runtime log fields

Placeholders below are illustrative, not runtime evidence. There are two TOWN and
ENDPOINT lines, up to three PROFILE/CANDIDATE lines and up to four READ_ERROR examples.
No grid/waypoint dump is emitted.

```text
[RNA:PLAN:4B1] WAIT_WORLD waiting_for_valid_world_and_tick_advance;unpause_to_plan
[RNA:PLAN:4B1] START world=<id> tick=<tick> app_seconds=<seconds>
[RNA:PLAN:4B1] TOWNS valid=<n> rejected=<n> read_errors=<n>
[RNA:PLAN:4B1] SELECT method=closest_valid_pair_xy_then_entity_id source_distance=<distance>
[RNA:PLAN:4B1] TOWN role=<start|destination> id=<id> name="<name>" source_x=<x> source_y=<y> source_z=<z> position_source=bounding_volume_center
[RNA:PLAN:4B1] GRID columns=<n> rows=<n> spacing_x=<step> spacing_y=<step> origin_x=<x> origin_y=<y> requested=<n> unit=world_units
[RNA:PLAN:4B1] ENDPOINT role=<start|destination> sample_id=<id> x=<x> y=<y> dx=<dx> dy=<dy> snap_distance=<distance> policy=nearest_sample_half_up
[RNA:PLAN:4B1] ANCHOR_HEIGHT start=<z|unavailable> destination=<z|unavailable> source=sampled_terrain
[RNA:PLAN:4B1] TERRAIN processed=<n> requested=<n> valid=<n> invalid=<n> failed_samples=<n> failed_reads=<n>
[RNA:PLAN:4B1] READ_ERROR detail="sample <index>: <API path>: <original error>"
[RNA:PLAN:4B1] SNAPSHOT world=<id> towns_start_tick=<tick> towns_end_tick=<tick> terrain_start_tick=<tick> terrain_end_tick=<tick> plan_start_tick=<tick> plan_end_tick=<tick> atomic=false
[RNA:PLAN:4B1] SEARCH status=<core status> complete=<boolean> candidates=<n> expansions=<n> duration_seconds=<seconds>
[RNA:PLAN:4B1] PROFILE name=<distance|terrain|balanced> status=<found|unreachable|search_limit> reason="<reason|unavailable>" disposition=<retained|duplicate|similar|none>
[RNA:PLAN:4B1] CANDIDATE rank=<rank> id=<id> profiles=<names> length=<length> max_gradient=<rise/run> elevation_gain=<gain> elevation_loss=<loss> touches_water=<boolean> water_segments=<n> water_runs=<n> distance_score=<score> gradient_score=<score> water_obstacle_score=<score> relative_score=<score> construction=unverified
[RNA:PLAN:4B1] PERFORMANCE max_work_callback_seconds=<seconds> budget_seconds=0.050000 elapsed_seconds=<seconds> gui_state_copy_and_summary_logging_excluded=true
[RNA:PLAN:4B1] WARNINGS town_centers_are_approximate_anchors;sampled_terrain_only;buildings_and_infrastructure_obstacles_unaccounted_for;no_hard_gradient_limit;relative_scores_not_game_costs;no_construction_validation;water_policy=exclude
[RNA:PLAN:4B1] COMPLETE status=<status> candidates=<n> data_complete=<boolean> reason="<reason>"
```

Optional TOWN_ERROR lines identify up to four failed town reads. SEARCH_ERROR gives
core validation path/message. If planning never ran or was discarded, SEARCH instead
prints `status=not_run_or_discarded candidates=0 duration_seconds=<value|unavailable>`.
Tick fields may be `nil` following early failure.

| Final status | Interpretation |
| --- | --- |
| ok | Core finished with complete collection; only sampled feasibility is established. |
| incomplete | Candidates exist but collection had rejected/failed data. Review counts. |
| unreachable | No route in this grid. PROFILE distinguishes endpoint_unavailable/open_set_exhausted; excluded water or missing samples can cause either. |
| search_limit | Budget exhausted; any retained candidates cover completed searches only. |
| unsupported | Insufficient towns, coincident anchors, inadequate bounds/resolution/snap quality or invalid configuration. Exact reason is logged. |
| invalidated | Incompatible world/tick, bounds, selected town, clock or snapshot-age change. Candidates discarded. |
| performance_limit | Work exceeded 50 ms; candidates discarded. Stop for smaller/resumable-work review. |
| timing_unavailable | Timing cannot be established; no accepted result. |
| error / invalid_input / input_limit | Read/import/core validation failure; inspect API paths or SEARCH_ERROR. |

## Validation and manual acceptance

The original 22 planning and 20 railway tests remain unchanged and pass. Nineteen
new integration tests cover every requested scenario, actual callback/adapter/core
wiring under mocks, native-coordinate guards, post-search invalidation, time/age
limits and configuration caps. They do not prove native TF3 loading or reload behavior.
Static checks cover 28 Lua files, JSON, imports, callback references and UTF-8.
All 19 accepted package files are unchanged; reversing only import replacements
reproduces the accepted core source at 05f7fd4.

Use the [guarded staging procedure](../README.md#safe-update-of-the-installed-development-copy)
with TF3 closed. It adds seven files after checking the accepted baseline. The agent
has not executed it. Do not deploy repository tests or documentation.

1. Enable revision 1 in a disposable test game with at least two towns. Finish loading
   and briefly unpause. Expect one WAIT_WORLD, START and final COMPLETE.
2. Confirm town IDs/names and source centers, nearest-pair selection and reported snap
   offsets. Both endpoints must satisfy the declared approximation limits.
3. Verify grid <=32x32, spacing 32/64/128, processed=requested and
   valid+invalid+failed_samples=processed. Inspect missing/invalid data, not just count.
4. Inspect SEARCH/PROFILE reasons and 0..3 ranked candidates. Zero candidates must
   have an explicit explanation; no candidate should claim construction readiness.
5. Retain planner seconds, maximum work-callback seconds, grid size, expansions,
   TF3 build and observed GUI responsiveness. Any freeze/performance_limit requires
   review, not a raised budget or unverified async mechanism.
6. Confirm all four accepted inventories still complete. Run/pause/resume normally:
   there must be no second attempt within the same loaded session.
7. Reload in the same process, load a different map, and restart TF3. Each new session
   must collect fresh data once. Compare unchanged-map candidates excluding timings/ticks.
8. Test empty/single-town, oversized/poorly represented pairs and wet/disconnected
   cases when available. Unsupported/unreachable are legitimate explicit outcomes.
9. Retain PLAN logs plus surrounding errors before another launch replaces stdout.
   Stop after Phase 4B.1 for review; do not proceed to Phase 4B.2.
