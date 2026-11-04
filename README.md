# Railway Network Architect

**Phase 6C: offline railway proposal assembly (awaiting review).**

The new pure-Lua `content/geometry/track_proposal_assembly.lua` revalidates Phase 6B
geometry and produces a symbolic assembly descriptor with deterministic negative IDs,
shared nodes, unchanged endpoint/tangent values and explicit resource configuration.
It creates no native objects. Resource resolution, native constructor defaults, ownership,
terrain/collisions and engine acceptance remain unresolved. ProposalViewer accepts
SimpleProposal in its declarations, but safe RNA activation and cleanup are still gated.
No live script loads the assembler; no UI or planning behavior changes.

**312 automated tests pass**, including 22 new assembly regressions; 53 Lua
files pass syntax checks. Existing planners, inventories, events, UI and limits are
unchanged, as are the Phase 6A fitter and Phase 6B adapter. See the [Phase 6C assembly
contract, source evidence and preview safety gate](docs/phase_6c_native_proposal_assembly.md),
[Phase 6B DTO contract](docs/phase_6b_track_proposal_contract.md) and the
[Phase 6A mathematical foundation](docs/phase_6a_rail_geometry.md).
No construction commands, proposal-validation calls, staging deployment, commits, tags or pushes.

**Phase 5C.2 background: reviewed batch corridor studies; native verification pending.**

After **Analyze Network**, mark included recommendations for further study, then click
**Study Marked Corridors**. At most four links run sequentially, in original priority
order; larger selections are rejected without truncation. Marking alone never runs A*.
**Cancel Batch** stops active/pending work and retains labeled completed summaries.
The panel reports progress, individual outcomes and compact preferred-route metrics.
No route is construction-ready. Manual Plan and individual Study Corridor remain available
when no conflicting job is running; batch results are separate from manual results.

Every next study must pass the unchanged handoff checks and **60-second deadline from
network collection start**. Expiry stops pending work and asks for Analyze Network again;
it never reanalyzes automatically or discards your edits to refresh evidence. Reanalysis,
Refresh and map reload clear the batch. Closing the window alone does not cancel it.

**247 automated tests pass**, including 24 new batch regressions; 47 Lua files pass
syntax checks. Native rendering, scheduling and state-copy performance remain unverified.
See the [Phase 5C.2 coordinator, contracts, limits, examples, diff and acceptance report](docs/phase_5c2_batch_corridor_studies.md).
No staging deployment, commits, tags, pushes or identity/revision changes. Stop for review.

**Phase 5C.1 background: editable Network Plan (awaiting native verification).**

After **Analyze Network**, select a proposed connection and use **Include in plan**,
**Exclude from plan**, **Restore original recommendation**, or **Mark for further
study**. **Reset all edits** restores all algorithm recommendations. The original
scores, classifications, reasons and evidence remain intact; user overrides are
session-local and shown separately.

The Network Plan section recalculates included/excluded counts, components,
unconnected towns, potential hubs and original branch attachments. Membership
changes carry a warning that original Mainline/Branch interpretation needs reassessment.
Edits never run A*. Included recommendations retain explicit **Study Corridor**;
manual town-pair planning is unchanged. Deferred/rejected links remain informational.

Edits clear on reanalysis, Refresh or map/session reset. They are not saved. Reviewing
an older snapshot does not extend its 60-second corridor-handoff freshness policy.
See the [Phase 5C.1 ownership, editing contract, tests and native acceptance report](docs/phase_5c1_network_worklist.md).
No staging deployment, commits, tags, pushes or revision changes. Stop for review.

**Phase 5B.2 background: network recommendation to corridor handoff.**

Run **Analyze Network**, select a recommended Mainline or Branch connection, then
click **Study Corridor**. Only that explicit action starts fresh terrain collection
and the existing corridor planner. Deferred/rejected links remain informational.
The original recommendation and evidence remain separate from the physical result;
a completed corridor is not construction-ready or economically validated.

The handoff checks session/snapshot identity, a 60-second snapshot age, town index,
bounds, endpoint locations and capacities. Expired or changed evidence requires
another explicit Analyze Network request. Same-world rail/industry edits are not
fully revalidated. Existing manual Plan, selections, native window styles and five
event subscriptions are preserved. A busy-response preview inconsistency found in
Phase 5B.1 was fixed with a failing-then-passing regression test.

See [Phase 5B.2 contracts, audit, tests, file changes and native acceptance](docs/phase_5b2_network_corridor_handoff.md).
No staging deployment, commits, tags, pushes or revision changes. Stop for review.

**Phase 5B.1 background: explicit live-map network analysis.**

Open the existing RNA panel and press **Analyze Network** to collect a fresh,
independent town/industry/physical-rail snapshot and run the accepted Phase 5A core.
Network analysis never runs automatically. Corridor source/destination selection and Plan remain
available; network and corridor jobs cannot run concurrently.

The panel reports conditional mainlines/branches, potential hubs, towns left without
new rail and inspectable reasons for proposed and deferred links. Residential capacity
is a proxy, not measured passenger demand. Demand, terrain suitability, existing
transport-service quality, economics and construction remain unverified. Industry
presence never creates a freight recommendation; physical track proximity never
establishes operational service. No terrain A* runs during network analysis.

Live studies cap at 32 towns / 496 pairs. Collection uses bounded batches and the
existing GUI owner; inventory scripts do not share their snapshots. Larger town maps
return an explicit unsupported result, not a truncated proposal. Optional inventory
limits/failures produce visible warnings. Zero recommendations can be a valid result.

See the [Phase 5B.1 evidence, policy audit, performance limits, exact update steps and
manual acceptance procedure](docs/phase_5b1_live_network.md), and the unchanged
[Phase 5A contracts and synthetic example](docs/phase_5a_network_topology.md).
All previous local work is preserved. No staging update, commit or push was performed.

**Phase 4B.4 presentation background (awaiting native verification):**

The complete supported world-space route rendering contract could not be established
from installed sources. This phase implements the authorized fallback: **a read-only
summary inside the planning window, not a map overlay**. After a successful Plan,
select a ranked candidate to see endpoints, approximate length, elevation, gradient,
water exposure, resolution and relative score. No route or terrain points are drawn.
Only complete `ok` results appear; limited, incomplete or failed results remain in
the normal status/log diagnostics. Candidate selection does not recompute a route.

Summaries clear on a new request, Refresh towns or session reset, and are hidden
on communication failure. Reopening requires a fresh status response before showing
a summary. Existing town selections, window styling and event subscriptions remain
unchanged. See the [Phase 4B.4 review, evidence, limits and acceptance report](docs/phase_4b4_corridor_preview.md).
No staging deployment, commits or pushes were performed. Stop for code review.

**Phase 4B.3 planning background:**

The existing town-selection UI and communication remain unchanged. Short requests
retain their previous sampling policy. Pairs beyond that coverage now use a coarse
512-unit guide followed by overlapping 64-unit terrain windows and incremental A*.
Only complete, revalidated section chains become candidates. No construction or
route visualization is added. All prior uncommitted Phase 4B.2 work is preserved.

See [Phase 4B.3 architecture, limits, tests and native acceptance](docs/phase_4b3_long_distance.md).
No staging files were updated; stop for code review before installation.

The prior UI milestone follows for context.
Baseline: accepted commit **ea318ea** on `main`. Phase 4B.1 was runtime verified
(Goole to Morley), and all four read-only inventories work. The town-selection communication and planning workflow are runtime verified.
The latest layout adjustments and Phase 4B.3 require native verification. Mod identity and revision remain unchanged.

Open **Railway Network Architect** in the game's mod-button area (the game also
provides a **Mods** entry in its radial menu). Briefly unpause after loading if the
world-readiness gate is waiting. Choose source and destination by name plus entity
ID, then press **Plan**. No plan runs automatically on load or when opening the UI.
The launcher opens a separate native planning window; only its button occupies the
horizontal mod-button area. Title-bar close, Back, or the launcher closes the window.
Selections survive reopening within the session; Refresh towns and session changes
clear them. Closing does not cancel an accepted planning request; a click still queued for dispatch is discarded on close. The window shows idle, planning,
result and error states. Duplicate names remain distinct.
The form uses a bounded, scrollable native window. Planner events are queued through
React main-thread joins. A communication failure pauses status polling and shows an
error; **Refresh towns** explicitly retries. GUI subscriptions, ten-town responses
and user-selected planning are now runtime verified. The communication architecture
is unchanged by the latest layout correction. The window now uses a centered native
anchor plus initial placement, and a 20-pixel Window::Content inset. Excessive town
separation gets an actionable prototype-resolution message; no construction
feasibility claim is made. These visual adjustments still require native review.
See the report's final **Window alignment, padding and status UX** section for the
three-file staging patch and visual acceptance checklist.

See the [Phase 4B.2 implementation report](docs/phase_4b2_user_planning.md) for verified
registration evidence, ownership, exact diagnostics, limitations and manual tests.
The [Phase 4B.1 report](docs/phase_4b1_live_planning.md) remains historical evidence;
its automatic selection and seven-file deployment have been superseded.

- The Game Script owns requests/results; the UI uses verified GUI script events.
- Busy/replayed requests and stale or identical IDs are rejected. No fallback pair.
- Each request collects its own fresh terrain. Short grids remain 32x32 at
  32/64/128-unit spacing; long requests use 512-unit guides and 64-unit refinement.
  Each live search step caps at 64 expansions. See the Phase 4B.3 report for total
  sample/search/section budgets and explicit endpoint approximation.
- Source coordinates are approximate town centers, not stations. Default water
  exclusion remains. Buildings/infrastructure obstacles are unaccounted for.
- `getApplicationTime` has no verified resolution guarantee. Zero work deltas mean
  insufficient measurement, not zero cost. Scheduling-inclusive elapsed time and
  observed callback gaps are reported separately; 50 ms is not a proven latency cap.
- No construction, overlays, economy changes, save persistence or automatic staging.
  Future economic/road-alternative decisions remain outside this phase.

Run the existing cached test runtime:

```powershell
uv run --no-project --offline --with lupa==2.8 python tests/run_lua_tests.py
```

The suite includes 22 original planning tests, 20 railway tests, 20 hierarchical
planning tests, 6 pure preview tests, 25 topology tests, 10 pure worklist tests and 120 live-planning/UI tests
(223 total). Static checks cover 46 Lua files. Mock tests do not prove native rendering
or callback latency. Stop after Phase 5C.1 for code review.

## Phase 4A planning core

The [planning contract, algorithm, example and Phase 4B proposal](docs/phase_4a_planning.md)
describe the accepted algorithm in detail. Its single authoritative source now
lives in `oz_railway_network_architect/content/planning/`. TF3 loads it through
`ug_require("oz_railway_network_architect::/planning/corridor_planner.lua")`.
Phase 4B.3 adds resumable start/step entry points while preserving the synchronous
wrapper and search rules. Offline tests use these same files via a resource-loader shim.

- Explicit world-coordinate endpoints on a rectangular sample grid; finite height,
  water, blocked cells, soft obstacles, constraints and configurable weights.
- Three deterministic A* profiles: distance, terrain and balanced. Shared scoring
  ranks complete paths, then merges duplicates and suppresses similar alternatives.
- Ordered world-coordinate waypoints, approximate length, elevation gain/loss,
  maximum sampled grade, water indicators and transparent score components.
- At most 16,384 cells and 49,152 expansions across the three searches. Unknown
  samples are excluded, diagonal corner cutting is prevented, and search exhaustion
  is distinguished from computational limits. No buildability or game-cost claims.

All inventory GUI callback states are separate. The 24x24 terrain snapshot is too
coarse for construction-ready alignment. Town centers are not verified station
sites, and railway adjacency does not establish operational routing. The prototype
owns its local snapshot and reports these limits; it does not validate construction.

Run `uv run --no-project --offline --with lupa==2.8 python tests/run_lua_tests.py`.
This reuses the existing cached development runtime. The suite covers 223 tests
across core planning, hierarchy, railway, presentation and live/UI behavior, and prints a
three-corridor synthetic comparison. **Do not copy tests or repository documentation
into staging. Stop after Phase 5C.1 for code review.**

## Documented API invocation correction

Runtime diagnostics reported all five required engine bindings as Lua tables.
The scanner incorrectly required `type(value) == "function"`. The documented
call signatures do not establish that runtime representation requirement.
The correction checks presence and invokes the documented calls inside `pcall`;
it makes no claim about internal binding representation and does not inspect or
modify metatables. The corrected city scanner was subsequently verified in-game.

- [Official engine signatures and state access](https://wiki.transportfever3.com/script-doc/api/engine.html):
  `getEntitiesWithComponent(componentType, filters?)` returns entity IDs;
  `forEachEntityWithComponent(callback, componentType)` iterates entities;
  `getComponent(entity, componentType)` returns a component or nil;
  `entityExists(entity)` returns a boolean. These use dot calls, without `self`.
  Engine reads are documented for both GUI and Engine states.
- [Official engine utilities](https://wiki.transportfever3.com/script-doc/api/engine/util.html):
  `api.engine.util.getWorld()` returns the world entity and
  `api.engine.util.getEntityName(entity)` returns a name or nil.
- Installed `gui.zip/gui/statistics/statistic_towns.tl:468` uses the same
  `getEntitiesWithComponent(api.type.ComponentType.TOWN)` call. Installed
  `gui/entity_window/view_manager.tl` uses `api.engine.entityExists` and
  `town_util.tl:1562` delegates names to `api.engine.util.getEntityName`.

Read failures retain their API path and original runtime error. Town name and
position failures also identify the shipped helper and its underlying engine read.
The optional timer uses the same protected direct-call pattern; a timer exception
leaves duration unavailable and adds an `error` field to the existing `DURATION`
line. Returned data validation, lifecycle and the terminal guard are unchanged.

The current staging procedure below updates three files and adds three files. All accepted inventory,
manifest, metadata and bootstrap files remain unchanged.

If a readiness read throws, expect `WAIT_WORLD` followed by a diagnostic such as:

```text
[RNA:CITY:2B] SCAN_ABORTED <API path>: <original runtime error>
```

The placeholders are illustrative. Enumeration errors use `SCAN_ERROR`; per-town
errors remain on the affected `TOWN` record. Capture the complete line and build.
If reads succeed, the unchanged readiness gate and normal scan output below apply.

## Files

```text
railway-architect/
  .gitignore
  AGENTS.md
  README.md
  docs/
    phase_4a_planning.md
    phase_4b1_live_planning.md
    phase_4b2_user_planning.md
  tests/
    run_lua_tests.py
    rail_inventory_test.lua
    corridor_fixtures.lua
    corridor_planner_test.lua
    live_plan_test.lua
  oz_railway_network_architect/
    mod.json
    _metadata/modinfo.json
    content/
      planning/
        corridor_grid.lua
        corridor_search.lua
        corridor_planner.lua
      live_plan.gs.lua
      live_plan.script.lua
      live_plan_api.lua
      live_plan_data.lua
      live_plan_request.lua
      live_plan_ui.res.lua
      live_plan_ui.script.lua
      mod.script.lua
      city_inventory.gs.lua
      city_inventory.script.lua
      city_inventory_api.lua
      city_inventory_data.lua
      industry_inventory.gs.lua
      industry_inventory.script.lua
      industry_inventory_api.lua
      industry_inventory_data.lua
      terrain_inventory.gs.lua
      terrain_inventory.script.lua
      terrain_inventory_api.lua
      terrain_inventory_data.lua
      rail_inventory.gs.lua
      rail_inventory.script.lua
      rail_inventory_api.lua
      rail_inventory_data.lua
```

The manifest and bootstrap are unchanged. The accepted descriptors register live
callbacks; `city_inventory.script.lua` handles readiness, deduplication and logging;
`city_inventory_api.lua` contains game integration; `city_inventory_data.lua`
contains pure normalization and formatting. The industry files follow the same
separation. Metadata still describes the accepted Phase 2B baseline and is
deliberately unchanged. `cosmetic=true` and add/remove severity `None` remain
consistent with read-only diagnostics. Phase 3C enumeration is now runtime verified;
Phase 4B.2 preserves these accepted inventory resources and adds user-controlled planning.

## Railway contracts and source evidence

The official [engine reference](https://wiki.transportfever3.com/script-doc/api/engine.html)
documents GUI-state read access and BaseEdge/BaseNode fields. The official
[system reference](https://wiki.transportfever3.com/script-doc/api/engine/system.html)
documents track-specific enumeration and station systems. Definitions and shipped
scripts were inspected read-only under `D:\SteamLibrary\steamapps\common\Transport Fever 3`
before implementation:

| Contract | Installed definition / shipped evidence |
| --- | --- |
| `api.engine.system.streetSystem.getNode2TrackEdgeMap() -> {Entity: {Entity}}` | `api/tealdef/api/engine/system.d.tl:303-304`: base nodes to connected base track segments. Used once for global discovery; repeated references are expected. No shipped caller was found in the searched GUI/scripts/game-mechanics/mission archives; the API contract itself documents this call. |
| `getNodeTrackSegments(nodeEntity) -> {Entity}` | Same definition, lines 313-315; `gui.zip/gui/entity_window/view_manager_util.tl:7-31` reads connected BASE_EDGE components. This is a per-node query, not global enumeration; not needed by the scanner. |
| `entityExists(entity) -> boolean`, `getComponent(entity, ComponentType) -> component or nil` | `api/tealdef/api/engine.d.tl:1690,1723`; the GUI helper above uses BASE_EDGE; `mission.zip/mission/tasks/auto_builder/track_builder.tl:20` reads BASE_NODE. Direct dot calls, protected by pcall. |
| `BaseEdge.node0/node1: Entity`, `position0/position1: Vec3f` | `engine.d.tl:111-114`. The shipped track builder assigns endpoint positions from the same world-position inputs as its base nodes (lines 16,24,31-38). Retain edge and node positions separately; do not substitute missing values. |
| `BaseEdge.roadType: RoadType`, `roadTemplate: ResName` | `engine.d.tl:124-127`; `api/type.d.tl:1954-1957` declares STREET and TRACK. `track_builder.tl:42-47` assigns the track template and `api.type["enum"].RoadType.TRACK`. No numeric enum values are used. `BaseEdge.type` concerns normal/bridge/tunnel geometry and is not the rail discriminator. |
| `BaseNode.position: Vec3f` | `engine.d.tl:157-162` explicitly documents world coordinates. Vec3f x/y/z fields are copied to plain Lua numbers. |

These contracts select a track-only map over enumerating every street edge or
every base node. Each unique edge is still rechecked for existence, BASE_EDGE and
the symbolic TRACK enum. No TF2 assumption or binding-function-type requirement
is introduced. `BaseEdge.distance` is deliberately unused: its field declaration
alone does not establish the desired geometric length semantics.

### Station research: deferred

`stationGroupSystem.getStationGroup(stationEntity)` and
`getCarriers(stationGroup, stationIndex, terminalIndex)` are documented in
`api/tealdef/api/engine/system.d.tl:87-102`. The shipped
`gui.zip/gui/entity_window/make_entity_window.tl:57-70` requests `(-1,-1)` and
checks `api.type["enum"].Carrier.RAIL` to label a station. That request returns
group-level carrier information; it is not a verified rule for treating every
station in a mixed group as rail.

`stationSystem.getVehicleNodeId2StationTerminalsMap()` associates transport-network
NodeIds with station/terminal pairs (`system.d.tl:57-82`). NodeId and EdgeId contain
a TransportNetwork entity and a zero-based subindex (`api/type.d.tl:1148-1175`),
not a directly interchangeable BASE_NODE/BASE_EDGE identifier. The missing verified
contract is a conversion from a **rail-classified terminal's transport-network
nodes/edges to its physical BASE_EDGE track entities**. No such usage was found
in the searched shipped examples. `catchmentAreaSystem.getStation2edgesMap()`
describes reachable edges, not station-owned track (`system.d.tl:437-441`).
Consequently Phase 3C adds no station inventory or station-to-track mapping and
logs this deferral explicitly. It does not classify every STATION as railway.

## Railway lifecycle, graph and performance

`rail_inventory.gs.lua` registers `rail_inventory.script@guiUpdate`. Its separate
GUI callback uses the accepted valid-world/advancing-tick gate and reuses only
`world()`/`seconds()` from the city adapter. No accepted file changes. Initial
polling is first callback then every 30 callbacks, with a terminal abort after 60
consecutive unavailable-world checks. A paused world waits without repeated logs.

Discovery captures the node-to-track map once, deduplicates and sorts edge IDs,
then processes **32 records every fourth GUI callback**: edges first, unique nodes
second. A batch makes at most 64 entity/component reads plus the existing world
check. Node requests include both indexed nodes and verified segment endpoints.
Every batch validates the same world ID and nondecreasing tick. No queries run
after completion/abort and no automatic retry occurs. Once the initial readiness
gate passes, scanning can continue while paused; no game-speed command is issued.

Limits are **20,000 unique segments, 40,000 nodes and 100,000 references/index
entries**. Exceeding a limit aborts explicitly; no truncated graph is accepted as
complete. Discovery's native map return, ID sorting and final graph normalization
are synchronous once per scan. The API has no verified pagination contract here;
the Lua limits cannot bound the native map allocation or its latency. Measure GUI
latency in-game, particularly on large saves. Component reads are batched to limit
per-callback work. Logs contain summaries and at most four diagnostic examples.

The completed plain Lua result remains in this Game Script's
`guiState:get().rail`, with `segments`, `nodes`, `adjacency`, counters, diagnostics,
`status` and `complete`. Work arrays are released. Nothing is saved/exported.
During collection the result is explicitly `status=scanning, complete=false`;
abort retains `status=aborted, complete=false`, without an apparently complete
graph. The session guard never uses engine state or GUI SaveData. Same-process
reload of this new descriptor remains a required acceptance test.

- Segment records: ID, node0/node1, separate position0/position1 `{x,y,z}`, template,
  topologyValid, status and optional chordLength. Nodes: ID, position, degree, status.
  Missing/nonfinite positions are nil, not zero. Zero and negative numbers survive.
- Nodes/segments sort by numeric entity ID; each adjacency list sorts by segment
  ID and contains `{segment, neighbor}` incidences. Both referenced BASE_NODEs must
  exist before adding an edge to adjacency. Missing geometry does not invent a
  position or erase otherwise verified topology; it makes the record incomplete.
- Degree counts distinct incident segments (a self-loop counts once). Degree 1
  gives an endpoint candidate; degree >=2 a multi-segment node; degree >=3 a
  junction candidate. These do not establish permitted movements, switches, signals,
  direction, ownership, track gauge compatibility or route availability.
- Components are undirected connected components of the accepted adjacency,
  including isolated available nodes. They are physical graph statistics only.
  `graph_segments` can be lower than `segments` when endpoints are missing.
- `duplicates` counts extra map references after the first reference to each edge;
  an ordinary segment listed at both ends contributes one. This is normal and does
  not degrade status. `rejected` counts malformed index entries/references or rejected
  edge/node records. `incomplete` counts missing node records plus accepted node/edge
  records with unavailable fields/errors (not a count of unique engine calls).
- `isolated_nodes` counts available nodes with no accepted incidence; missing nodes
  are reported separately. A rejected street edge never enters the segment graph.
  `partial` means collection ended but data is incomplete; `complete=true` refers
  to processing completion, not a claim that the graph is fully reliable.
- Chord length is the 3D Euclidean distance between a segment's endpoint positions,
  in world-coordinate units. The total covers `chord_segments` only and is **not
  curved track length**, travel distance or cost. No fallback geometry is used.
- A successful empty enumeration yields zero segments/nodes and `status=ok`.
  An unavailable/invalid enumeration aborts instead of masquerading as an empty map.

The map can change across batches; this is not an atomic engine snapshot. Avoid
building/removing tracks during acceptance. Entity checks detect disappearance,
but a successful result does not prove no concurrent modification occurred. The
inventory covers documented base track segments, not an asserted complete model
of station-internal transport networks. It never monitors later changes.

## Terrain contracts and source evidence

The official [engine reference](https://wiki.transportfever3.com/script-doc/api/engine.html)
documents GUI-state read access and the terrain operations. The official
[type reference](https://wiki.transportfever3.com/script-doc/api/type.html) documents
Box2f and Vec2f. Installed evidence was inspected before implementation under
`D:\SteamLibrary\steamapps\common\Transport Fever 3`:

| Contract | Installed definition / shipped usage |
| --- | --- |
| `api.engine.terrain.getBoundingBox() -> Box2f` | `api/tealdef/api/engine.d.tl:1754`; `game_mechanics.zip` / `game_mechanics/fun_elements/custom_entity_util.tl:79` reads the returned box. |
| `box.min.x/y`, `box.max.x/y` | `api/tealdef/api/type.d.tl:856-865` declares min/max corners; the same shipped helper reads these four fields at lines 81-85. The definitions label the corners Vec3f despite the Box2f name; only verified x/y fields are used. |
| `api.type.Vec2f.new(x, y) -> Vec2f` | `api/tealdef/api/type.d.tl:511`, with x/y fields at 519/521; `gui.zip` / `gui/map_editor/map_editor.tl:1746` constructs a vector, then validates it. |
| `api.engine.terrain.isValidCoordinate(position) -> boolean` | `engine.d.tl:1729`; same GUI file at 1747; `mission.zip` / `mission/tutorial/tutorial_story_util.tl:419` validates before a water query. Coordinates are world X/Y relative to map center. |
| `api.engine.terrain.getHeightAt(position) -> number` | `engine.d.tl:1734`; `game_mechanics/fun_elements/custom_entity_util.tl:74` uses a Vec2f. Out-of-bounds reads can return the nearest map height. |
| `api.engine.terrain.getBaseHeightAt(position) -> number` | `engine.d.tl:1740`; `game_mechanics/company/explorations/exploration_plane.script.tl:62`. Excludes non-permanent terrain alignments; documented 4 m resolution. Also clamps outside the map. |
| `api.engine.terrain.isOnWater(position) -> boolean` | `engine.d.tl:1745`; `mission/tutorial/tutorial_story_util.tl:422`. Tests whether the point is below water level. No height-sign heuristic is used. |

No native binding is required to have Lua type `function`. Documented direct calls
are protected with `pcall`. Invalid return types and nonfinite numbers are treated
as unavailable; runtime errors preserve their API path and original message.

## Terrain grid, lifetime and performance

The separate `terrain_inventory.gs.lua` registers `terrain_inventory.script@guiUpdate`.
It reuses the accepted world-readiness and timer helpers without changing either
existing scanner. Initial readiness polling and the advancing-tick gate match the
accepted pattern. No terrain reads occur at module load time.

Bounds are read once and must have finite, strictly increasing X/Y ranges. The
grid has **24 columns x 24 rows**, with cell centers computed as
`min + (index + 0.5) / count * (max - min)`, using zero-based row/column indices.
X varies fastest, then Y. There is no random sampling or assumption of a centered,
square or fixed-size map.

Each point is constructed with Vec2f.new. Its actual x/y values are retained to
account for float rounding. `isValidCoordinate` must return **true**, and the point
must still be strictly inside the captured bounds, before any height/base/water
query. A false validity result causes no terrain queries. Validation failure also
causes no terrain queries; clamped heights can never validate a coordinate.

Work is limited to **16 points every fourth GUI callback**, at most 36 batches.
A normal batch makes at most 80 vector/terrain calls plus three world-readiness
reads. There is no sampling on intervening callbacks or after termination. Each
batch checks that the world is still available, its ID matches and time has not
gone backwards; otherwise it aborts. Sampling can continue while paused once the
initial tick gate has passed. It does not change game speed.

Normalized data lives at `guiState:get().terrain` for this Game Script. It contains
bounds, grid dimensions, up to 576 plain Lua sample records, aggregates, completion
status and at most four error examples. Each sample retains actual x/y, height,
baseHeight, onWater, coordinate validity, status and failed-read count. Missing
values are nil; zero and negative heights and false water flags are preserved.
There are no native vectors in retained results, file writes, engine-state writes,
GUI SaveData calls or terrain exports. Results remain available after completion
until that GUI session is discarded; same-process reload must be verified.

While running, `status=scanning` and `complete=false`. A finished traversal sets
`complete=true` and status `ok`, `partial` or `error`. An aborted traversal retains
the collected subset with `status=aborted`, `complete=false`, and does not retry.
No progress or per-point lines are emitted. At most four exact sample-error
examples are logged; further occurrences are counted as suppressed. Setup/world
failures use a separate `SCAN_ABORTED` diagnostic.

Summary definitions:

- `valid`: points with valid coordinates and all three terrain values available.
- `invalid`: points explicitly rejected by coordinate/bounds validation.
- `failed_samples`: points with construction/validation errors or unavailable reads.
  These three counts sum to `processed`, which never exceeds `requested=576`.
- `failed_reads`: failed sample operations, including bad return values; it can
  exceed failed_samples. Setup/world errors are reported separately, not counted
  as sample reads. No sample operations have occurred if setup aborts.
- Height min/max/mean use available heights only from validated points, including
  partial records. `height_samples` is their denominator. All three statistics
  are unavailable when that denominator is zero.
- Water count uses known true flags; `water_reads` counts known booleans. The
  water count is unavailable if there were no successful water reads.
- Duration measures application elapsed time, including waits between callbacks;
  it is not CPU time. It may be zero or unavailable at the timer's resolution.

For an unchanged map, sample order and data/statistics are deterministic; duration
is not. A scan spans callbacks and is not an atomic terrain snapshot. Avoid editing
the map during verification. This coarse inventory cannot resolve narrow rivers,
local slopes or a viable railway alignment and makes no connection decisions.

## Industry data and verified sources

Research was completed before implementation against the official
[engine API](https://wiki.transportfever3.com/script-doc/api/engine.html),
[engine utilities](https://wiki.transportfever3.com/script-doc/api/engine/util.html)
and [matrix/vector types](https://wiki.transportfever3.com/script-doc/api/type.html).
The following installed sources are under
`D:\SteamLibrary\steamapps\common\Transport Fever 3`:

| Field / operation | Installed evidence and semantics |
| --- | --- |
| Entity IDs | `api/tealdef/api/engine.d.tl:1713` and `base/content/gui.zip` / `gui/statistics/statistic_industries.tl:392`: `api.engine.getEntitiesWithComponent(api.type.ComponentType.INDUSTRY)`. |
| Display name | Same GUI file, lines 356 and 454: `api.engine.util.getEntityName(industryEntity)`. `api/tealdef/api/engine/util.d.tl:1040` documents a name or nil. |
| Level | `api/tealdef/api/engine.d.tl:447`: `Industry.level` is the current construction level, an integer. GUI `gui/entity_window/industry/industry.tl:72` reads it. Report the raw value; no UI offset or inferred range. |
| Construction entity | `api/tealdef/api/engine.d.tl:455`: `Industry.construction`. GUI `gui/line_vehicle_mgmt/manager_window.tl:382` reads its `CONSTRUCTION` component. |
| Resource identifier | `api/tealdef/api/engine.d.tl:307`: `Construction.fileName` is the construction name, or ID for dynamic constructions. `ResName` is a string (`api/type.d.tl:15`). `game_mechanics.zip` / `game_mechanics/fun_elements/ufo_util.tl:82-85` follows Industry -> Construction -> fileName. |
| X/Y/Z | `Construction.transf` is the world transformation (`engine.d.tl:312`). `Mat4f.getTransl` returns its translation (`type.d.tl:782`). `game_mechanics.zip` / `game_mechanics/celebrations/celebrations.script.tl:211` uses `construction.transf:getTransl()`; Vec3f exposes x/y/z. |

The resource field identifies the associated construction; it is not an inferred
industry category. Dynamic IDs need not be filesystem paths. Coordinates are the
construction's world origin, not the industry bounding-box center, cargo terminal,
or terrain height. Multiple industry entities may share a construction: records
remain keyed by industry ID, with no deduplication by construction or name.

`industry_inventory.gs.lua` registers a separate GUI Game Script using the verified
city lifecycle pattern. Its callback has its own GUI-state run-once guard. The
adapter reuses only `world()` and `seconds()` from the unchanged city adapter; it
does not invoke city collection or require TOWN/BOUNDING_VOLUME capabilities.
No engine reads occur during module loading. It waits for a valid world and a
later tick, marks the attempt finished, then reads industries exactly once.
City and industry scan order is unspecified; a failure in one does not set the
other's completion flag.

Each industry record contains plain Lua values: ID, name, resource, raw level,
construction ID and X/Y/Z. All engine calls and native field reads are protected;
errors identify the read and preserve the runtime message. A failed name lookup
does not hide construction fields. Invalid IDs are rejected before engine calls;
duplicate IDs are counted as rejected during normalization. Disappeared entities
retain a `read_error` record. Missing data prints `unavailable`, zero stays zero,
and nonfinite coordinates are missing. Records sort numerically by industry ID.
`incomplete` counts accepted records with missing data or errors, while `rejected`
counts malformed/duplicate IDs. An empty enumeration succeeds with zero counts.

## Lifecycle and source evidence

Official TF3 references:

- [Resource types](https://wiki.transportfever3.com/doku.php?id=modding:general:resourcetypes): `.gs.lua`, `.script.lua`, namespaces and UTF-8 without BOM.
- [GameScriptDesc and vector types](https://wiki.transportfever3.com/script-doc/api/type.html).
- [Game Script types](https://wiki.transportfever3.com/script-doc/content/scripts/gamescript.html): this page returned HTTP 429; installed definitions supplied the callback evidence.
- [Engine API](https://wiki.transportfever3.com/script-doc/api/engine.html): read-only engine access is available from GUI and Engine states.
- [Town utilities](https://wiki.transportfever3.com/script-doc/content/game_mechanics/towns/town_util.html).
- [Mod scripts](https://wiki.transportfever3.com/doku.php?id=modding:general:modscripts): resource hooks remain separate from live-game callbacks.
- [Staging directory](https://wiki.transportfever3.com/doku.php?id=modding:general:publishing): use local staging without uploading.

Read-only evidence from `D:\SteamLibrary\steamapps\common\Transport Fever 3`:

| Source | Verified evidence |
| --- | --- |
| `api/tealdef/api/type.d.tl`, `GameScriptDesc` | `guiUpdateScript` is a script reference. |
| `base/tealdef/scripts/gamescript.d.tl`, `GameScriptWithGui` | Callback arguments are user/capture parameters, read-only engine state, and GUI state. |
| `base/content/game_mechanics.zip`: `game_mechanics/celebrations/celebrations.gs.lua` | Descriptor links `.script@guiUpdate`. |
| Same archive: `celebrations.script.tl` and `achievements/achievements.script.tl` | GUI callbacks read engine data and initialize state using `guiState:get()` / `guiState:set()`. |
| `base/content/gui.zip`: `gui/hud/happy_change_display.script.tl` | GUI callback state deduplicates handling; persistent GUI SaveData is a separate interface. |
| `api/tealdef/api/engine.d.tl` and `api/engine/util.d.tl` | Town enumeration, entity checks, world lookup, game-time and name reads. |
| `api/tealdef/api/util.d.tl` | `api.util.getApplicationTime()` returns seconds since application start; GUI thread only. |

Octocode's previously verified path restriction excludes the installed game.
PowerShell/ripgrep and Python's ZIP reader inspected these files without extracting
or modifying game content. No TF2 contracts are assumed.

The integration is:

1. TF3 discovers `content/city_inventory.gs.lua` as a Game Script resource.
2. `guiUpdateScript.fileName` references
   `oz_railway_network_architect::/city_inventory.script@guiUpdate`.
3. The first GUI callback logs `WAIT_WORLD` and checks required read APIs.
4. It requires an existing world entity and `GAME_TIME.tickCount`, records a
   baseline, then waits for a later callback to observe an increased tick.
5. It marks the GUI callback state finished before attempting one scan. Further
   callbacks return immediately without world reads. No engine update hook is added.

Using a GUI callback does not add UI. No town queries run during script evaluation
or from `runScript`. Readiness checks occur on the first callback and every 30
callbacks thereafter. Sixty consecutive checks without a usable world abort once.
A valid paused world waits indefinitely without repeated messages: **briefly
unpause to scan**. Missing required APIs or thrown readiness errors abort safely.

The guard uses only Game Script **GUI callback state**, following shipped
initialization/deduplication patterns. The code never writes engine state, calls
`setGuiSaveData`, saves userdata or writes files. Public definitions do not
explicitly guarantee GUI-state reset on every load path: same-process save reload
is a mandatory acceptance test. There is no persistent engine-state completion
flag. Repeat that acceptance test for the new railway Game Script in Phase 3C.
Tick advancement is an additional readiness condition, not a verified callback
for the textual `Game is ready` log line; confirm actual timing in-game.

The accepted bootstrap remains unchanged and may still repeat across workers.
Its messages are not city scans. No unverified cross-worker suppression was added.

## Town data

The adapter uses
`api.engine.getEntitiesWithComponent(api.type.ComponentType.TOWN)` and rechecks
each entity's existence and TOWN component. It imports:

```text
::/game_mechanics/towns/town_util.tl
::/scripts/entity_util.tl
```

Imports use `ug_require`, with `::` selecting base-game content. Installed Lua files
`economy.zip/economy/placementparamsutil.lua` and `gui.zip/gui/main/builtin.lua`
demonstrate importing `.tl` modules this way; no Teal compiler is needed here.
The shipped town utility's `getTownName` delegates to `getEntityName`, and its
`getTownsToPositions` calls `entity_util.getPosition`. The adapter uses that position
helper per entity to isolate failures. In `scripts.zip/scripts/entity_util.tl`, it
returns the bounding-volume midpoint, or nil when that component is missing.
Thus X/Y/Z mean **town bounding-volume center**, not station position or terrain
height. `Vec3f.x/y/z` are declared in the installed API types.

Records are sorted numerically by ID. Zero remains zero; missing/empty names and
missing/nonfinite coordinates become `unavailable`. Invalidated entities retain a
record with `read_error`; any recovered fields remain available. Malformed or
duplicate IDs are rejected and counted. Control characters in names/errors are
removed before logging. No population or ongoing monitoring is implemented.

## Safe update of the installed development copy

After code review, close TF3 completely and follow the Phase 4B.4 report's
[staging and native acceptance instructions](docs/phase_4b4_corridor_preview.md).
The older six-file Phase 4B.2 procedure is historical and does not include the
new hierarchy module. No staging update has been run. Do not copy tests/docs,
create another active mod with the same ID, or click Mod Hub Upload/Update.

## Manual verification

For the new UI, follow the [Phase 4B.2 acceptance procedure](docs/phase_4b2_user_planning.md#manual-acceptance) and collect `[RNA:PLAN:4B2]` logs. The scenarios below remain regression checks for the accepted inventories.

### Railway acceptance: two separate maps

1. Close TF3 and use the guarded staging instructions above. Enable revision 1.
2. **Empty network:** generate a disposable map with no railway construction.
   Roads alone must not become railway segments. Briefly unpause after loading;
   expect one railway scan with zero segments, nodes, endpoints, components,
   incomplete and rejected counts, followed by `SCAN_COMPLETE status=ok`.
   An enumeration failure is not an acceptable empty result.
3. **Non-empty network:** load an existing test save with tracks, or use the normal
   game UI to create a small railway layout in a disposable save, save it and reload
   it so the once-only scanner sees the layout. The agent performs no construction
   or save operations. Include a simple line, a branch and a separate disconnected
   line if convenient; leave the layout unchanged during collection. Expect
   positive segment/node counts and sensible endpoint/junction candidates and
   disconnected components. Engine segment subdivision can differ from the number
   of user drawing actions; do not expect one entity per drawn stroke. Station
   internal paths and operational connectivity are not acceptance claims here.
4. Wait for batches to finish. Confirm `SCAN_COMPLETE status=ok complete=true` and
   zero incomplete/rejected records on an ordinary unchanged layout. Duplicate
   references are expected from the node map; they are not scan errors. A partial
   result requires review of diagnostics and missing-node/isolated counts.
5. Confirm the accepted city, industry and terrain scans still complete. Continue
   normal gameplay, pause and unpause: railway scanning must not repeat. Test
   same-process save reload, menu-to-game load and fresh launch; each loaded session
   should receive exactly one new railway scan. Compare summaries excluding duration
   on an unchanged map. Observe GUI responsiveness while scanning.
6. Retain `[RNA:RAIL:3C]` lines and any surrounding engine errors for review. Do not
   proceed beyond Phase 4B.4. Zero segments on a visibly tracked map is a failed test.

Expected empty-network output (illustrative, not runtime evidence):

```text
[RNA:RAIL:3C] WAIT_WORLD waiting_for_valid_world_and_tick_advance; unpause_to_scan
[RNA:RAIL:3C] SCAN_START
[RNA:RAIL:3C] DISCOVERY unique_segments=0 references=0 batch_size=32 callback_interval=4
[RNA:RAIL:3C] SUMMARY segments=0 nodes=0 endpoints=0 junction_candidates=0 multi_segment_nodes=0 graph_segments=0 components=0 isolated_nodes=0 self_loops=0
[RNA:RAIL:3C] VALIDATION duplicates=0 incomplete=0 rejected=0 missing_nodes=0
[RNA:RAIL:3C] GEOMETRY chord_total=0.000000 chord_segments=0 measure=endpoint_distance_not_track_length
[RNA:RAIL:3C] STATIONS status=deferred reason=station_terminal_to_base_edge_mapping_unverified
[RNA:RAIL:3C] DURATION seconds=0.150000 clock=application_time includes_callback_waits=true
[RNA:RAIL:3C] SCAN_COMPLETE status=ok complete=true
```

A hypothetical three-segment Y plus one separate segment could produce these
summary lines (actual entity subdivision and counts depend on the game):

```text
[RNA:RAIL:3C] SUMMARY segments=4 nodes=6 endpoints=5 junction_candidates=1 multi_segment_nodes=1 graph_segments=4 components=2 isolated_nodes=0 self_loops=0
[RNA:RAIL:3C] VALIDATION duplicates=4 incomplete=0 rejected=0 missing_nodes=0
[RNA:RAIL:3C] SCAN_COMPLETE status=ok complete=true
```

Errors retain paths and original messages, for example:
`DIAGNOSTIC detail="segment 123: api.engine.getComponent(123, BASE_EDGE): <runtime message>"`.
At most four examples are printed; `DIAGNOSTICS_SUPPRESSED` reports the remaining
count. Failed discovery/readiness/limits produce `SCAN_ABORTED`, progress counts
and `SCAN_END status=aborted complete=false`, never a successful zero summary.

### Accepted scanner regression checks

1. Update staging, launch TF3 and confirm the mod is enabled as revision 1. Use a
   disposable test game and disable unrelated optional mods.
2. Wait for loading to finish, then briefly unpause if necessary. Allow several
   seconds for polling. No custom UI is expected.
3. For each prefix, `[RNA:CITY:2B]` and `[RNA:IND:3A]`, find one `SCAN_START`,
   records in ascending numeric ID order, counts, duration and completion. Compare
   the unchanged town output with the accepted baseline and industry names/counts
   with the game's industry list. Inspect several industries in different locations
   and their levels; the log reports raw engine levels and construction origins.
   For `[RNA:TERRAIN:3B]`, verify one GRID (24x24), SCAN_START, BOUNDS and summary
   sequence. Allow several seconds for all batches. Expect 576 processed samples;
   do not interpret a missing SCAN_COMPLETE or complete=false as a finished map.
   Check valid + invalid + failed_samples = processed. For a normal map, expect
   status=ok and failed_reads=0. Compare bounds and height/water ranges with the map.
4. Let the simulation run, pause and resume. There must be no additional scan.
5. **Essential:** using the game's normal UI and a disposable test save, reload in
   the same TF3 process. Expect one new scan for that load. Also test returning to
   the menu and loading a different test game, then a fresh application launch.
   The agent does not access or edit saves; the user controls these manual tests.
6. If available, compare an existing flat/dry map and one with water and negative
   terrain heights. Zero and negative heights must remain numeric; dry points
   must remain false, not missing. For an unchanged map, repeat after reload and
   compare terrain statistics excluding duration. Do not alter a valued map for tests.
7. Exit normally and retain the relevant log excerpt before another launch can
   replace it. Stop at Phase 4B.4 for review; do not proceed to another milestone.

```powershell
$rnaLog = 'C:\Program Files (x86)\Steam\userdata\175442176\3493540\local\crash_dump\stdout.txt'
Select-String -LiteralPath $rnaLog -SimpleMatch '[RNA:CITY:2B]', '[RNA:IND:3A]', '[RNA:TERRAIN:3B]', '[RNA:RAIL:3C]', '[RNA:PLAN:4B2]'
```

Illustrative output; IDs, names, coordinates and time will vary:

```text
[RNA:CITY:2B] WAIT_WORLD waiting_for_valid_world_and_tick_advance; unpause_to_scan
[RNA:CITY:2B] SCAN_START
[RNA:CITY:2B] TOWN id=101 name="Example Town" x=0.000000 y=-300.000000 z=12.000000 status=ok
[RNA:CITY:2B] TOTAL count=1 incomplete=0 rejected=0
[RNA:CITY:2B] DURATION seconds=0.001000 clock=application_time includes_record_logging=true
[RNA:CITY:2B] SCAN_COMPLETE status=ok
```

Industry example (illustrative values, not a recorded runtime result):

```text
[RNA:IND:3A] WAIT_WORLD waiting_for_valid_world_and_tick_advance; unpause_to_scan
[RNA:IND:3A] SCAN_START
[RNA:IND:3A] INDUSTRY id=201 name="Example Industry" resource="example_resource_id" level=0 construction=200 x=0.000000 y=-300.000000 z=12.000000 status=ok
[RNA:IND:3A] TOTAL count=1 incomplete=0 rejected=0
[RNA:IND:3A] DURATION seconds=0.001000 clock=application_time includes_record_logging=true
[RNA:IND:3A] SCAN_COMPLETE status=ok
```

Terrain example (illustrative values, not a recorded runtime result):

```text
[RNA:TERRAIN:3B] WAIT_WORLD waiting_for_valid_world_and_tick_advance; unpause_to_scan
[RNA:TERRAIN:3B] GRID columns=24 rows=24 requested=576 batch_size=16 callback_interval=4
[RNA:TERRAIN:3B] SCAN_START status=scanning
[RNA:TERRAIN:3B] BOUNDS min_x=-4096.000000 min_y=-2048.000000 max_x=4096.000000 max_y=2048.000000
[RNA:TERRAIN:3B] SUMMARY processed=576 requested=576 valid=576 invalid=0 failed_samples=0 failed_reads=0 suppressed_errors=0
[RNA:TERRAIN:3B] HEIGHT min=-12.000000 max=240.000000 mean=83.500000 height_samples=576
[RNA:TERRAIN:3B] WATER count=48 water_reads=576
[RNA:TERRAIN:3B] DURATION seconds=2.400000 clock=application_time includes_callback_waits=true
[RNA:TERRAIN:3B] SCAN_COMPLETE status=ok complete=true
```

Terrain sample failures add `READ_ERROR sample=<index> detail="<API>: <message>"`
before the summary. Fatal interruption logs SCAN_ABORTED and ends with
`SCAN_END status=aborted complete=false`; retained samples are an incomplete scan.

Missing fields print `unavailable`, not `0`. Partial records yield completion
status `partial`. Enumeration/import failure yields `SCAN_ERROR`, an unavailable
count and completion status `error`. Readiness/API failure yields `SCAN_ABORTED`
without a successful completion marker. Attempts are not retried automatically.
Duration is an application-time difference including imports, normalization and
record logging; it may be zero at timer resolution, or unavailable if the timer
cannot be read. It is not CPU profiling.

| Symptom | Action |
| --- | --- |
| Accepted scanners run, no railway marker | Check all four rail files, references, activation and resource errors. Discovery alone is not execution. |
| `WAIT_WORLD` only | Unpause. If still stuck while time advances, capture the build and log errors. |
| `SCAN_ABORTED` or `SCAN_ERROR` | Capture the error, resolve it, then reload to retest. |
| Repeated scans in one load, or no scan on same-process reload | Session-state lifecycle failed acceptance; stop and report it. |
| `status=partial` or terrain `status=error` | Inspect the capped error details, counts and available-data denominators. |
| Terrain SCAN_START without completion | Wait for batching to finish; inspect SCAN_ABORTED/SCAN_END and other script errors. |
| Rail limit exceeded | The scan is explicitly aborted; retain the log and review before changing limits. |
| Zero railway count on a visibly tracked map | Treat as a failure; inspect discovery, API errors and infrastructure coverage. Zero is valid only when no base track network is expected. |
| Zero industry count on a map with industries | Treat as a failure; inspect enumeration and lifecycle timing. |
| Repeated Phase 2A worker messages | Known bootstrap behavior; count each inventory prefix separately. |

## Development validation and unresolved risks

Run the development-only checks from the repository root:

```powershell
Set-Location -LiteralPath 'D:\code\transport-fever-3\railway-architect'
uv run --no-project --with lupa==2.8 python tests/run_lua_tests.py
```

This uses Lua 5.4 through Lupa in uv's isolated cache; no mod dependency, project
manifest or virtual environment is added. The runtime was obtained for these
explicitly requested tests because no standalone Lua interpreter/compiler was
available. With the cache populated, `--offline` can be added. Do not copy tests
or Python/Lupa into staging. The Lua version is a development check, not a claim
about TF3's embedded Lua version.

Validation covers Lua syntax, local references/import targets, strict JSON and
UTF-8 without BOM. Twenty accepted railway tests cover all seven requested
graph cases, negative/zero/nonfinite coordinates, missing data, limits, bounded
diagnostics, API errors, symbolic track filtering, readiness, batching, once-only
behavior and explicit aborts. Mocks exercise our logic; they do not verify native
bindings or the engine's GUI-state lifetime. Final review also checks descriptor
callback exports, unchanged accepted inventory/core files versus ea318ea, PowerShell
example syntax and the absence of world-changing calls. No staging commands are
executed during validation.

The additional 22 planning tests run in a separate Lua VM without TF3 mocks and
include all required scenarios, analytic geometry checks, 48 reference shortest-path
comparisons and a maximum-size stress fixture. See the Phase 4A document for the
contract, actual synthetic outputs and limits. Syntax checks now cover 40 Lua files.
Six pure presentation tests validate summary gates. The 20 hierarchy tests cover
long routes and incremental work; 70 live-planning/UI
tests use mocked engine/React facilities and the real recipes, callbacks and core.

The user verified all four inventories; railway enumeration reported 2,021 segments
and 2,014 nodes. Special layout coverage and lifecycle edge cases remain subjects
for the retained manual scenarios. There is no proven atomic snapshot across GUI
batches or station-terminal-to-base-edge mapping. Phase 4B.2 communication and
user-selected planning were verified in-game. Phase 4B.3 still needs native timing,
long-route and reload verification. Nothing was changed in the original game,
staging or saves; no commit, tag, push or publication was made. Stop after Phase
4B.4 for review and real-game verification.
