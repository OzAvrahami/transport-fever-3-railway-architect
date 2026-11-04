# Visible Route Preview

Baseline: `e732b79`. Construction is disabled. Implementation is ready for owner
review, **not yet accepted as visibly working in native TF3 freeplay**. No staging,
commit, push, save modification or game-world command was performed during development.

## What the player gets

Select Source town and Destination town, then **Plan Railway**. Only a terminal,
complete successful corridor is eligible for drawing. The first candidate is displayed
automatically while the RNA window is open. **Hide Route**, **Show Route** and
**Focus Route** operate on that completed result. If there are alternatives, the small
selector shows Route 1, Route 2, etc. The names of the displayed route's towns remain
visible, including when the player changes the selectors for a future plan.

The overlay is a bright cyan, 24 m-wide ribbon made of adjoining convex polygons along
every consecutive original waypoint pair. Its centreline is exactly the computed XY
polyline. There is no shortcut, interpolation of old terrain inventories, curve fitting,
smoothing or simplification. The zone renderer projects it onto terrain with a 1 m
visual offset; it does not depict engineered track elevation, bridges or tunnels.
Original XYZ waypoint data remains unchanged in the planning owner.

The native window, centering, dragging, padding, scrolling and launcher are unchanged.
No raw IDs, scores, sampling statistics or technical status codes are added to the
player view. Drag the window aside while inspecting the terrain. Closing it removes
the overlay; reopening requires **Show Route** for an already completed result.

## Construction removal

- `content/track_test.lua` is moved to repository-only `reference/track_test.lua`.
  It is outside the deployable package and no active resource imports it.
- The owner no longer calls the construction adapter. Old `track` request envelopes
  are explicitly rejected with `construction_disabled`.
- Build Test Track, confirmation controls and test-track response fields are removed.
- The active package contains no `api.cmd.sendCommand` or
  `api.cmd.makeWorldBuildProposalCmd` calls; the regression runner enforces this.
- Metadata now has `cosmetic=true`, with existing add/remove severity None. Identity
  and revision 1 are unchanged. The player description states that no railway is built.
- No ProposalViewer, construction tool, terrain-edit API, entity removal or save-data
  persistence is used. Zones always pass **prohibitBuilding=false**.

## Verified source contracts and the remaining native gate

Installed root: `D:\SteamLibrary\steamapps\common\Transport Fever 3`.
ZIP entries were inspected directly, without modifying the installation.

The [official GUI API](https://wiki.transportfever3.com/script-doc/api/gui.html)
documents keyed polygon zones, color, drawing, building prohibition and removal. The
implementation uses that public API rather than an internal React rendering action.

| Contract | Exact installed source | Finding |
|---|---|---|
| Edge renderable types | `base/tealdef/scripts/builtin.d.tl:46-55,1303-1328` | EdgeGeometry constructor, colors, width, offsetZ, stepSize and ignoreDepth are declared; RendererComponent requires a toolStack and exposes action binding. These types alone do not establish mod ownership. |
| Native edge binding | `base/content/gui.zip!gui/main/builtin.lua:222-225,435-532` | Builtin rendering and action bookkeeping exist. They do not supply an RNA-owned renderer via the mod button extension. |
| Action lifecycle | `base/content/gui.zip!gui/main/react.lua:593-640`; `base/tealdef/scripts/react.d.tl:371-375` | useAction binds/unbinds on mount/unmount, but useAction/setActiveOwner are explicitly internal and deprecated. We do not use them or take over the tool stack. |
| Main renderer ownership | `base/content/gui.zip!gui/main/game.tl:466-488`; `gui/main/mod_entry_point.tl:1-7` in that ZIP | Main renderer is tied to the game's toolStack. The inspected mod extension registration supplies no demonstrated supported renderer reference/action activation contract. **EdgeRenderable path blocked here.** |
| Polygon zone call | `api/tealdef/api/gui.d.tl:694-702` | `setZone(key:string, polygon:{Vec2f}, draw:boolean, drawColor:Vec4f, prohibitBuilding:boolean, playAnimation?:boolean, zOffset?:number)`. Offset defaults to terrain level. |
| Explicit removal | Same file, `:715-717` | `removeZone(key:string)`, using exactly the key supplied for creation. No entity IDs or bulldozing. |
| Vector and color preparation | `base/content/mission.zip!mission/legacy_ui_util.tl:3-13` | Constructs Vec2f polygon points and Vec4f color, forwards draw/prohibit flags, removes by the same key. |
| GUI-state zone ownership | `base/content/mission.zip!mission/mission_sim.script.tl:1103-1117,1159-1162` | Shipped GUI work calls setZone with draw/color/prohibit/animation/offset and tracks its own keys; obsolete owned keys are passed to removeZone. RNA uses its own key ledger, not the mission framework. |
| Main-thread teardown dispatch | `base/tealdef/scripts/react.d.tl:400-401` | enqueueJoin runs on the main thread after parallel React work. Existing event transport is retained; teardown queues only a lease-specific close event. |
| Camera | `api/tealdef/api/gui.d.tl:426-451` | `focusPosition(Vec3f, distance)` is available. RNA uses an actual middle waypoint, with an overview distance derived from route extent. It does not refocus every frame. |

**Freeplay limitation:** the public zone API has no mission parameter or documented
mission-only precondition. Its shipped caller proves the GUI-state invocation pattern,
but the examples inspected are mission scripts. The underlying native renderer is not
present in these Lua sources, and no inspected freeplay example independently proves
visibility there. Consequently, the implementation makes the documented call from
RNA's existing freeplay GUI owner, but actual freeplay drawing, camera persistence,
color/width and cleanup must pass the one native test below. No claim of native success
is inferred from an error-free API return or mocks.

If TF3 rejects the call, the precise API error is logged and partial owned zones are
removed. If it silently accepts the call but draws nothing, **the acceptance test fails**:
the remaining blocker is the native freeplay zone-rendering/visibility contract. Do not
fall back to construction, an internal tool, points, a static image or a numeric report.

## Ownership, rendering and cleanup

`route_overlay.lua` is loaded by the existing `live_plan.script.lua` GUI owner. It reads
`state.request.result.candidates[index].waypoints` directly. It reuses the accepted pure
preview validator to check completion, world, endpoints and sampled-grid continuity.
It never calls A*, rereads terrain or transfers route arrays to React.

Each segment A to B becomes a counterclockwise rectangle using a perpendicular of
length 12 m. The midpoint of its first/end cross-section is exactly A/B. Adjacent
rectangles share the original waypoint, giving a connected ribbon at bends. Bounds,
finiteness, degenerate segments, count and candidate identity are validated. No route
is silently truncated. Zones are not railway components or native construction proposals.

Native call for each rectangle:

```lua
api.gui.mission.setZone(key, polygon, true,
    api.type.Vec4f.new(0, 1, 1, 0.85), false, false, 1)
```

Keys start with `oz_railway_network_architect.route.` and contain epoch, world, request,
render serial and segment index. Only keys actually submitted by this owner are removed.
The key is recorded before submission so an ambiguous exception also enters cleanup.
Other mods' or missions' keys are never enumerated, overwritten or cleared.

The existing **five subscriptions are unchanged**. UI status opens a server-issued
view lease; subsequent normal 0.5-second status polling renews that lease. Overlay
actions use the existing `plan` event with a separate envelope:

```lua
{world=worldId, epoch=epoch,
 overlay={action="show", lease=viewLease, sequence=previousSequence+1,
          requestId=corridorRequestId, candidateId=completedCandidateId}}
```

Actions are show, hide, focus and close. World/epoch/request and monotonic sequence
checks reject stale actions. Close checks its captured view lease independently of
corridor changes, and only clears owned drawing. A stale close from an earlier window
cannot clear a newly opened view. Replay does not rerun planning.

Drawing occurs in the verified GUI update lifecycle. Creation and removal share a
16-operation callback budget. Replacements drain old keys before adding new ones.
A new accepted Plan clears the old rendering; only the next complete result schedules
new drawing. Intermediate submission is labelled **Showing route...**, not a completed
or partial planner result. Once all polygons are submitted the UI reports the proposed
alignment on the map; this status still requires native visual confirmation in testing.

Window unmount queues a main-thread close event without touching expired React state.
If that event cannot be delivered, five seconds without a matching status heartbeat
expires the view; the owner clears its zones on subsequent GUI updates. Session/world
reset carries pending owned keys into the new cleanup state and discards drawing work.
The renderer is not redrawn in response to camera motion. Hide/show reuses the result.

Drawing failures cancel the job and clean partial submissions. Removal failures retain
the unresolved keys, log the exact API error and pause cleanup to avoid per-frame error
storms. An explicit action or session reset can retry bounded cleanup. If native GUI
execution has already stopped or removeZone itself fails, immediate cleanup cannot be
guaranteed by Lua; this is a native acceptance condition, not silently claimed success.

## Limits

- At most **1,024 segments / 1,025 original waypoints** in a rendered route. Larger
  completed routes receive an explicit unsupported result, without shortening them.
- At most **16 setZone/removeZone calls per GUI update**; one active displayed candidate.
- At most 1,024 owned key strings and one small drawing cursor/job; waypoints remain
  in the already bounded request. No extra full route copy, grid or native proposal.
- Pure revalidation uses the existing preview validator (up to the planner's three
  bounded candidates). No new search or terrain queries for rendering/selection/focus.
- A 50 ms observed rendering-work guard cancels drawing and schedules cleanup on
  overrun. It cannot preempt an individual native call; native zone allocation/render
  cost and the combined GUI callback cost still require measurement in TF3.
- The 24 m width, cyan color, 1 m offset and overview distance are display choices,
  not railway engineering constraints. Native camera distance clamping is unverified.
- Terrain projection is not 3D rail alignment. Town anchors remain approximate; no
  station position, economic feasibility or construction readiness is asserted.

## Automated verification

The complete **353-test baseline passed before changes**. The twelve superseded
construction/player-build tests are preserved as repository-only reference text; they
are no longer assertions of desired behavior. All **341 non-construction regressions**
remain active, including network, worklist, batch, geometry, corridor and existing GUI
communication tests. Twenty-one new overlay/player tests bring the active total to
**362 passing tests** (194 live integration/UI tests). **56 Lua files** pass Lua 5.4
syntax, plus resource/import references, JSON, UTF-8, identity/revision and callback
export checks. Native command calls and construction imports are banned by static checks.

New tests cover actual ordered segment endpoints; connected convex ribbons; offset and
negative coordinates; no mutation of corridor input; no shortcut/A* or terrain reread;
alternatives; a real hierarchical synthetic 4,600 m route; bounded batches; invalid,
incomplete, unsupported, search-limit and oversized results; replacement; hide/show;
camera-independent polygon coordinates; focus; world/reload/close cleanup; stale window
leases; renderer/removal failures; heartbeat expiry; budget exhaustion; compact UI;
explicit planning; teardown and reopening. Native drawing is mocked, not accepted.

```powershell
uv run --no-project --offline --with lupa==2.8 python tests/run_lua_tests.py
git diff --check
```

## Changed files

```text
AGENTS.md                                              read-only scope and overlay rules
README.md                                              current player behavior
docs/visible_route_preview.md                          this report and native test
oz_railway_network_architect/
  mod.json                                             cosmetic=true
  _metadata/modinfo.json                                read-only description
  content/live_plan.script.lua                          owner/render lifecycle, build rejection
  content/live_plan_ui.script.lua                       view lease and teardown dispatch
  content/player_plan_ui.lua                            route controls, no build controls
  content/route_overlay.lua                             new bounded zone renderer
  content/track_test.lua                                removed from deployable package
reference/track_test.lua                                archived experiment, never live-loaded
reference/visual_mvp_tests.lua.txt                      archived superseded construction tests
tests/live_plan_test.lua                                overlay/player regressions
tests/run_lua_tests.py                                  read-only package assertions
```

Inventories, planning/geometry algorithms, network/worklist/batch modules, terrain/search
budgets, Game Script descriptor/subscriptions, window stylesheet and mod identity/revision
are unchanged. The legacy developer recipe remains hidden from the production launcher.

## One focused native acceptance test — owner only, after review

No automatic deployment. Replace the **whole** deployable
`oz_railway_network_architect` directory after backup, with TF3 closed. Do not merge a
few files into the previous construction experiment. Use the full-package backup and
hash-verification procedure in [Phase 6D](phase_6d_native_acceptance.md), section
“Complete-package staging procedure — OWNER ONLY, AFTER REVIEW”. Verify that installed
`content/track_test.lua` is absent and `content/route_overlay.lua` is present. Never copy
`reference/`, tests or docs into staging. Do not follow the old construction acceptance
steps. The owner performs installation only after review.

1. **Load the existing test map.** Open RNA. Verify only town selectors and Plan Railway
   are initially shown; no Build Test Track or confirmation UI. Capture map/save name,
   TF3 build, resolution/UI scale and startup errors, if any. No overlay appears at load.
2. **Select Midhurst and Goole; click Plan Railway once.** Wait for planning to finish
   and the bounded drawing pass to finish. Drag RNA aside without closing it.
3. **Look at the terrain.** A continuous bright cyan route must follow multiple computed
   bends, not just a direct line between town anchors. Capture a screenshot and, ideally,
   a short video including the town selections and visible route. Text saying “shown”
   or a DRAW_SUBMITTED log alone is **not** success.
4. **Pan, zoom and rotate.** The same route must remain aligned to the terrain without
   being screen-anchored, disappearing unexpectedly or causing a severe stall. Use
   Focus Route if needed; it should move the camera once, not fight subsequent movement.
5. **Hide Route, then Show Route.** The entire overlay must disappear, then return along
   the same path without a new planning request. If multiple routes exist, select another
   and verify the displayed geometry changes to that candidate. No recomputation expected.
6. **Confirm this is not track or terrain construction.** Hiding the overlay leaves the
   original terrain and infrastructure unchanged; no selectable rail segments, stations
   or earthworks appear. Retain before/after views. The active source/package contains
   no command execution, and no BUILD DISPATCH marker may appear. If an existing native
   debug/entity-count facility is available, capture the unchanged railway entity count
   as additional evidence; do not add commands or rely only on log absence.
7. **Close and reopen RNA.** All its zones must disappear after bounded cleanup. Reopen
   should keep the old result available with Show Route, without automatically restoring
   drawing. After leaving/reloading the map there must be no stale RNA zones. Do not
   change or save the map to perform this test.

Expected bounded diagnostic markers:

```text
[RNA:ROUTE] START request=... candidate=... segments=... prohibitBuilding=false
[RNA:ROUTE] DRAW_SUBMITTED request=... candidate=... zones=... native_visibility=unverified
[RNA:ROUTE] CLEARED
```

Failure markers are `UNAVAILABLE reason=...`, `ERROR api=api.gui.mission.setZone ...`,
`ERROR api=api.gui.mission.removeZone ...`, `rendering_work_budget_exceeded`, or
`CLEANUP_DISPATCH_ERROR`. `VIEW_EXPIRED` indicates missing UI heartbeats and triggers
cleanup. Record the full stdout and exact message. Failed/unsupported corridor planning
correctly produces no overlay; capture the planner's reason instead of fabricating one.

**Acceptance is the visible continuous route on the real terrain while moving the camera,
with no track built.** If freeplay silently does not render zones, report that precise
native blocker and stop. Do not treat this implementation or its mocks as satisfying
the visibility criterion before the owner observes it.
