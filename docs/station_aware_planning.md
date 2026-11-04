# Station-aware passenger railway planning

Baseline: `main`, `9f3af08`, initially clean. The owner reports the cyan route zones
working in native Freeplay. **The station workflow added here has not been tested in
TF3.** It is ready for code review, not a claim that Midhurst–Morley now passes native
acceptance. Nothing was deployed, built, committed or pushed. Saves and installed
game resources were not modified.

## Verified data and source evidence

Installed root: `D:\SteamLibrary\steamapps\common\Transport Fever 3`. Archive entries
were read directly without changing the installation. Line numbers are one-based.
The [official engine reference](https://wiki.transportfever3.com/script-doc/api/engine.html),
[system reference](https://wiki.transportfever3.com/script-doc/api/engine/system.html)
and [type reference](https://wiki.transportfever3.com/script-doc/api/type.html) describe
the public API; the exact installed declarations and callers below govern this adapter.

| Data | Installed source and interpretation |
|---|---|
| Selected towns | Existing `live_plan_api.lua` reads TOWN, name and entity position. Positions remain town identity/freshness evidence; they are **not** station candidates. |
| Actual town buildings | `api/tealdef/api/engine/system.d.tl:107–128`, specifically `getTown2BuildingMap(): {town:{building}}` at 122. `base/content/gui.zip!gui/hud/marketing_display.script.tl:45–51` iterates the town's buildings; `gui/entity_window/town/town.tl:430–435` reads this map in GUI work. |
| Building ownership and construction | `api/tealdef/api/engine.d.tl:1304–1325`: TOWN_BUILDING has `town`, `construction`, parcels, depth and height. RNA checks the town association; if the building has no bounding volume it reads the associated construction's volume. Missing volumes fail explicitly. It does not infer a full footprint from parcel counts. |
| Conservative occupancy bounds | Same file `:225–230`: BOUNDING_VOLUME.bbox is an axis-aligned Box3f. Its XY projection is used conservatively, not claimed as an exact footprint. Building unions define occupied urban extent; individual building boxes provide proximity measurements. |
| Local spatial query | `api/tealdef/api/engine/system.d.tl:604–610`: `octreeSystem.findIntersectingEntities(Box3f, callback(entity, BoundingVolume))` queries entities with bounding boxes. `api/tealdef/api/type.d.tl:843–852` supplies min/max Vec3f and the constructor; `:3760` exports it as **api.type.Box3**, not Box3f. Query Z spans ±10,000,000, matching the prototype's strict coordinate/height domain. |
| Existing stations | `api/tealdef/api/engine/system.d.tl:57–83`: `stationSystem.getStations(townEntity)`. `:252` supplies `streetConnectorSystem.getConstructionEntityForStation` for a missing station volume. No all-STATION-is-rail assumption. |
| Passenger rail classification | `api/tealdef/api/type.d.tl:1270–1338`: Station.terminals, Terminal.transportModes, passengersLoad/passengersUnload. TRAIN or ELECTRIC_TRAIN **and** a passenger flag on the same terminal is required. `base/content/gui.zip!gui/line_vehicle_mgmt/line_util.tl:1373–1382` uses passenger flags; `:2040–2049` identifies both train modes in a transport-mode set. Existing station proximity is a hint, not verified reuse, line service or an attachment point. |
| Roads and tracks | `api/tealdef/api/engine.d.tl:97–130`: BASE_EDGE world position0/position1 and symbolic RoadType.STREET/TRACK. RNA measures actual endpoint proximity. It does not replace curved roads with fictitious pedestrian paths. All road/track AABBs still block reservations. |
| Terrain and water | `api/tealdef/api/engine.d.tl:1729–1754`: isValidCoordinate(Vec2f), getHeightAt(Vec2f), isOnWater(Vec2f), getBoundingBox(). Reuses the accepted adapter, including coordinate validity **before** height queries. Missing readings never become flat dry terrain. |
| Passenger station dimensions | `base/content/stations/rail.zip!rail/modular_station/modular_station.script.lua:48–49` defines 40 m platform sections and a 5 m lateral grid. `rail/modular_station/modular_station.con.lua:27–35` offers lengths 80,120,160,240,320. The 160 m reservation length is four sections; the **48 m total width is an explicit planning assumption**, not an extracted complete native station footprint. Building modules, roads, platforms and era choices alter the full footprint. |
| Walking access remains unknown | `api/tealdef/api/engine/system.d.tl:439–448` exposes existing catchment edges/stations/catchables. It does not establish catchment for an unbuilt reservation. RNA does not call it to invent walking access or passenger demand. |
| Temporary world display | Existing verified `setZone`/`removeZone` contract, `api/tealdef/api/gui.d.tl:694–702,715–717`; shipped GUI usage and ownership evidence are in [Visible Route Preview](visible_route_preview.md). No new rendering mechanism or subscriptions. |

Every new engine operation is inside a protected call. No documented binding is
required to have Lua type `function`. Returned values are normalized into plain Lua
data. Unknown native entities are occupied, never assumed vacant. An unavailable
required building/spatial/station API fails the request instead of changing transport.

## Algorithm and explicit assumptions

`station_site_api.lua` owns native reads; `planning/station_sites.lua` owns pure spatial
selection and scoring. `station_plan_request.lua` is a continuation owned by the existing
Game Script GUI state. It owns its own data collection; no inventory state is shared.

1. Read the selected towns' actual building IDs, associations and AABBs. Use the union
   to generate candidates around occupied urban edges. Town bounding centers only
   revalidate the selected town identity; they never supply reservation coordinates.
2. Generate at most 48 deterministic candidates per town: four sides, two margins
   (192/384), three along-side offsets (-256/0/256), two cardinal orientations. Quantize
   reservation centers to a world-origin 128-unit lattice. This makes explicit approach
   anchors representable on the existing 32/64/128 and hierarchical 64-unit grids.
3. Reserve **160 × 48 m**, plus a **512 × 64 m** clearance rectangle containing space
   for both through-station approaches. The corridor-facing approach is 128 m from
   the center along the signed station axis. These reservations are approximate.
   The marker is not a native station model, platform set or buildable footprint.
4. Reject map-boundary, water, unknown terrain and known occupied sites. Include every
   local non-town/non-world bounding box conservatively, including unknown objects,
   trees and infrastructure. Require distance to a real town-building box ≤512 m and
   to a real road endpoint ≤256 m. These are proximity preferences, **not catchment**.
   No remote flat-site fallback and no clearance by demolition.
5. Sample each surviving reservation and both approaches at 51 points: 17 longitudinal
   positions every 32 m and three lateral rows at -32/0/32 m. Preserve zero/negative
   heights. Reject missing/invalid/wet points, sampled neighboring rise/run >0.03, or
   total height range >8 m. These are conservative prototype assumptions, not native
   railway limits. Between-sample terrain and exact surface support remain unknown.
6. Site score (lower preferred): building-box distance/128 + road-endpoint distance/128
   + maximum sampled grade/0.02; subtract 1 for a verified passenger train station
   within 512 m, and 0.5 for a physical track endpoint within 256 m. These hints do not
   prove an operational connection, reuse feasibility or a need for an extra station.
7. Keep three spatially distinct sites per town (centers ≥128 m apart), with deterministic
   score/ID ordering. Evaluate at most nine pair-screen scores, excluding overlapping
   clearance rectangles. Pair score adds approach distance/1024 and four times the
   two orientation penalties `2 - dot(sourceAxis,direction) + dot(destinationAxis,direction)`.
8. Run the **best two pairs at most**, sequentially, through the authoritative existing
   short/hierarchical corridor continuation. No new A* algorithm and no concurrent
   searches. Supply exact station approach XYZ, separately from town IDs/original town
   observations. Reject any endpoint snap; never substitute the town centers.
9. The existing sampler adds local known-occupancy masks for these requests only:
   an 80 m AABB buffer (64 m half of the maximum fine-grid step plus the 12 m ribbon
   half-width, rounded conservatively). This is intentionally overconservative. The
   two town query neighborhoods do not cover all distant terrain: obstacles elsewhere
   remain unknown. Existing accepted water/search/terrain resolution policies remain.
10. Keep one complete candidate per evaluated pair, selecting the first ranked route
    that preserves exact approach XYZ, departs/arrives in the correct orientation
    (dot ≥0.7, up to a grid diagonal), and does not cross either station body plus
    the 12 m ribbon allowance. Reject incomplete/limited results. No invented links,
    connectors, truncation or smoothing. A failed bounded search does not prove that
    no real station/railway alignment is possible.
11. Recheck town identity/bounds and both full reservation AABBs before publishing.
    Rank retained complete station/corridor candidates by `corridor.score.total +
    128*(source.siteScore + destination.siteScore)`, tie-breaking by ID. This is an
    explicit relative preference, not money or economic feasibility. Preserve both
    the corridor score and station evidence separately.

For no suitable pair, the UI says **Station planning unresolved. Try another pair of
towns.** Precise rejections and bounded evidence go to `[RNA:STATION]` logs. The selector
only offers distinct successfully evaluated station pairs. Sometimes only one is found.

## Handoff, ownership and presentation

The production player's existing Plan event adds `stationAware=true`; no subscription
changes. Invalid flag types and mixing this flag with a network handoff are rejected.
The coordinator reuses `live_plan_request.start(..., anchorOverride)` with separate
town IDs and `start/destination={townId,x,y,z}` plus verified local occupancy boxes.
The legacy developer/network/batch entry points keep their accepted contracts and
tests; they are not exposed by the small player panel and do not silently act as a
fallback from a failed station request. Their station-aware integration is future work.

Each completed candidate owns its `stationSites.source/destination`: town ID/name,
center XYZ, signed cardinal axis, length/width, approach XYZ, approximate flag and
evidence. `stationSnapshot` records world/start/end ticks/time with `atomic=false`.
Compact polling summaries contain only reservation geometry and endpoints, not
waypoint arrays, building lists, terrain grids or detailed evidence. Original corridor
waypoints are never altered to draw or select a station alternative.

The existing `route_overlay.lua` draws the unchanged cyan polyline, then three keyed
polygons for each station: the body, a thin orientation/approach axis, and an approach
cap where cyan begins/ends. **Orange = source; purple = destination.** The player sees
“Proposed railway route”, “Station near [town]”, and a short approximate-reservation
warning. No IDs, scores, technical errors or analytics controls are reintroduced.

The existing view lease, heartbeat expiry, stale sequence rejection, Hide/Show/Focus,
close/reopen, replacement and reload cleanup cover all six extra polygons. Removing
zones never removes entities or another mod's keys. Alternative selection redraws the
selected candidate's own sites and existing path without terrain queries or A*.

## Limits, freshness and performance

- 512 buildings/town; 64 associated stations/town; 64 terminals/station. Oversize input
  fails explicitly, never silently truncates evidence. Urban union span ≤4096 per axis.
- Two spatial neighborhoods: urban bounds expanded 768 m; at most 2048 returned
  bounding entities each. Final reservation queries cap at 256 each. Native octree
  traversal itself cannot be preempted; callback storage and later work are bounded.
- Building/object processing: 16 records per callback; station classification: four.
  Site terrain: at most 16 points/callback, at most 4896 total site sample visits.
- Three shortlisted sites/town; at most two sequential corridor continuations using
  **unchanged per-corridor budgets**. In the worst case this permits twice the original
  per-request corridor work, but never two active searches/grids simultaneously.
  One shared 60-second age limit starts at the first site-collection callback.
- 50 ms observed-work limit, not preemption. Zero clock delta is reported as unknown
  timing resolution, not zero cost. Native API latency, GUI state-copy time and native
  rendering latency require measurement in acceptance. Query overflow or safety errors
  stop rather than retrying or silently selecting a different map location.
- At most two retained complete route arrays (existing 4096-waypoint cap each).
  Temporary building/object/site/sample/child-search state is released at termination.
- Existing rendering cap remains 1024 path segments; at most **1030 zones** including
  the station polygons, still 16 additions/removals per callback. Oversized paths are
  explicitly unsupported for drawing; never shorten them to fit.
- World/epoch/request guards remain. Selected towns and bounds are revalidated before
  each search and final publication. Final occupancy queries catch changed reservations.
  This is an interval snapshot, not a transactional view or continuous construction
  monitor. Same-world road/terrain changes after collection can invalidate assumptions.
- No automatic planning on load, station selection, polling, hiding or showing. Session
  invalidation cancels the child continuation and clears pending results/owned zones.

## Validation and changed files

Before changes: **362 tests passed**, 56 Lua files compiled. After changes: **394 tests
passed**, 60 Lua files compiled. This includes 14 pure site tests and 18 new integrated
owner/UI/adapter/overlay tests. All prior tests remain, including native communication,
manual and batch planning, network/worklists, inventories, geometry and overlay regressions.

Tests cover actual urban bounds versus town centers; multiple/no sites; water, missing
terrain, slope and occupancy rejection; road evidence versus unknown walking access;
existing passenger/electric-train classification; orientation and reservation crossings;
exact endpoint handoff; pair ranking; deterministic repeated results; two colored site
sets with unchanged cyan waypoint order; alternatives without re-search; 6000-unit
hierarchical handoff; shared age limit; caps; busy/replay; stale towns, world invalidation,
close/reopen and cleanup; no reachable construction commands.

```powershell
Set-Location -LiteralPath 'D:\code\transport-fever-3\railway-architect'
uv run --no-project --offline --with lupa==2.8 python tests/run_lua_tests.py
git diff --check
```

The runner checks Lua 5.4 syntax, UTF-8 without BOM, JSON, local imports, descriptor
exports, unchanged identity/revision/read-only metadata, and forbidden native build
calls. Passing mocked reads/zones does not prove native site quality or visibility.

Exact changed file tree:

```text
AGENTS.md
README.md
docs/station_aware_planning.md                           (new)
oz_railway_network_architect/content/
  planning/station_sites.lua                            (new)
  station_site_api.lua                                  (new)
  station_plan_request.lua                              (new)
  live_plan.script.lua
  live_plan_request.lua
  live_plan_data.lua
  live_plan_preview.lua
  player_plan_ui.lua
  route_overlay.lua
tests/
  station_sites_test.lua                                (new)
  live_plan_test.lua
  run_lua_tests.py
```

The accepted A*, hierarchy, geometry fitting, inventory modules, network algorithms,
worklists, batch coordinator, GUI subscriptions, native window/style resources and
mod metadata have no changes. No installed or staging files were edited.

## One focused native acceptance: Midhurst–Morley

After owner code review, close TF3 and manually replace the **complete** deployable
`oz_railway_network_architect` directory using the established backup/hash procedure
in [Phase 6D acceptance](phase_6d_native_acceptance.md). Do not mix old/new Lua files.
This development run does not perform that installation.

1. Load the current Midhurst–Morley map and open RNA. Confirm town choices populate,
   no site queries/searches occur until the click, and no construction controls exist.
2. Select **Midhurst** as source and **Morley** as destination; click **Plan Railway**
   once. Expect “Planning railway...” while site screening and sequential pair studies
   run. Capture any visible pause and the eventual elapsed/work timing log.
3. On success, inspect **two** reservations: orange near Midhurst, purple near Morley.
   The cyan computed path must begin/end at their facing approach caps, away from the
   town centers. Expect “Station near ...” labels and approximate-reservation warning.
   Save an overview and a close view of each site showing nearby buildings and roads.
4. Inspect the entire reserved rectangles and both approach axes. They should avoid
   visible buildings, water and existing tracks, remain reasonably near town roads,
   and have plausible local terrain. Road proximity does not prove walking access.
5. If alternatives exist, select another Route. The corresponding station pair and
   cyan path must change together, without another `[RNA:STATION] START` or A* search.
6. Pan, zoom and rotate. All polygons must stay aligned with the terrain. Focus Route
   must work without continually moving the camera. Dragging the window still works.
7. Hide Route: both reservations, axes, caps and cyan must disappear. Show Route:
   the same result returns without planning. Close RNA: everything disappears;
   reopen and explicitly Show. A new plan replaces all old markers. Reload clears them.
8. Confirm there are no new native station/track entities or terrain edits. No command
   constructor/dispatcher, construction preview, simulation writes or save persistence
   are reachable through this workflow. Do not mistake the colored polygons for assets.

Useful log markers (not proof of visible success):

```text
[RNA:STATION] START source=... destination=... footprint=approximate walking_access=unknown
[RNA:STATION] SHORTLIST town=... sites=... buildings=... existing_passenger_stations=...
[RNA:STATION] REJECT town=... reason=... count=...
[RNA:STATION] SITE id=... x=... y=... z=... axis=... approach=... urban_distance=... road_endpoint_distance=...
[RNA:STATION] PAIR index=... source=... destination=... screen_score=...
[RNA:STATION] PAIR_RESULT index=... status=... retained=...
[RNA:STATION] COMPLETE status=ok reason=station_pairs_evaluated;reservations_approximate;walking_access_unknown;smoothing_unverified
[RNA:STATION] PERFORMANCE site_reads=... max_work_seconds=... elapsed_seconds=... zero_delta_observed=... timing_resolution=unknown preemptive=false state_copy_excluded=true
[RNA:ROUTE] DRAW_SUBMITTED request=... candidate=... zones=... native_visibility=unverified
```

The renderer's historical `native_visibility=unverified` field means the individual
draw call cannot confirm pixels. The earlier cyan mechanism is owner-verified; these
new station colors/shapes/locations are pending this test. If no sites/pair survive,
capture the START/REJECT/COMPLETE/API error lines and screenshot; **acceptance is not
met**. Do not bypass occupancy, loosen unknowns into zero, or fabricate successful sites.

## Smooth-curve follow-up and remaining limitations

The reviewed Phase 6A fitter uses cubic Hermite with `u∈[0,1]`, shared endpoint
derivatives for C1 continuity and chord-based terminal tangents. It cannot currently
accept prescribed station approach tangents, certify between-sample clearance, preserve
grade everywhere, or establish C2/curvature continuity. Applying it just for appearance
would hide unresolved turns. It is unchanged; the cyan grid path remains authoritative.

After station-site native acceptance, the next focused task is a constrained approach
fitting contract: preserve exact station approach endpoints; fix outward source and
inward destination tangent directions; choose bounded tangent magnitudes; independently
check curvature, vertical alignment and swept clearance against fresh terrain and known
obstacles; reject infeasible fits without replacing the grid preview. Longer routes also
exceed the fitter's current 256-point input limit. Do not silently truncate them.

Other unresolved facts: cardinal-only reservations can miss better rotated sites;
bounding boxes can overreject vacant land; endpoint-only road proximity can miss a
nearby curved road; two pair studies can miss a feasible third alternative; exact native
station/entry geometry and pedestrian network integration remain unverified; existing
stations/tracks supply hints, never attachment or operational routing; sampled suitability
is not full-area ground support; distant corridor obstacles are not inventoried; grades,
clearance and scoring are assumptions, not economic or native construction acceptance.

**Stop after implementation and review. No further milestone or native build is authorized.**
