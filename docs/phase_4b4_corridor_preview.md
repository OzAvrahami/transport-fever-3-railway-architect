# Phase 4B.4: corridor presentation with the authorized panel fallback

This phase preserves the complete uncommitted Phase 4B.2/4B.3 workspace. No staging,
game files or saves were changed. No dependency installation, commits, tags or pushes.

**Outcome: an in-panel corridor summary, not world-space visualization.** The rendering
gate did not establish a complete supported mod-owned path drawing contract. The user
explicitly authorized this fallback. This report does not claim map overlays are
impossible in TF3; it identifies the missing evidence rather than inventing APIs.

## Pre-implementation Phase 4B.3 review

All 123 baseline tests passed before production edits. Reviewed the canonical grid,
search, planner, hierarchy, request owner, GUI lifecycle and their regression tests.
Compared the Phase 4B.3 control-flow changes with the existing workspace history;
preservation hashes were captured before this phase's edits.

| Area | Findings |
| --- | --- |
| Resumable A* | Fixed neighbor ordering and indexed-heap tie-breaking remain canonical. Each call advances at most its expansion slice; exhausted open sets and total budgets terminate explicitly. Profiles share the total expansion budget. Synchronous plan/run wrap the same continuations. |
| Serialization | Continuations contain plain data. Existing tests copy them between steps without preserving aliases. Profile references are reconnected only for final result assembly. |
| Coarse/fine continuity | Coarse routes are guides only. Each fine section uses real 64-unit lattice samples. Stitching requires matching XYZ and water; loop erasure removes existing loops without inserting an unsampled chord. Every final edge and diagonal corner is revalidated by the canonical grid module. |
| Alternatives | Complete candidates share a scoring policy and undergo deterministic shared-edge deduplication. Local section selection is greedy and coarse guides are not exhaustive. |
| Cancellation/freshness | The owner checks world/ticks, bounds, selected towns, snapshot age and observed work time. Invalidation clears pending results/cache, including a result produced on the last work slice. Reload resets GUI state. |
| Bounds | At most 3 guides, 32,768 unique samples, 65,536 visits, 49,152 expansions, 128 sections/guide and 4,096 waypoints/candidate. Work slices are 16 sample visits, 64 expansions or 32 final-validation waypoints. |
| Limitations | Model validation, path reconstruction, summarization and native state copying are bounded but not preemptible. The 50 ms guard is observational, not a guaranteed latency cap. No atomic terrain snapshot, global optimality or construction feasibility is established. |

No correctness blocker requiring planner changes was found. The planner, sampling
adapter, request continuation and all inventory modules are byte-for-byte unchanged
in this phase. The new presentation gate conservatively withholds all non-`ok`
results, even when they retain a completed candidate; those results remain in logs.

## Visualization research and gate decision

Primary installed root:
`D:\SteamLibrary\steamapps\common\Transport Fever 3`.
Archive paths below were read directly, without extracting into or modifying the game.
Octocode localSearch rejected the available input schema; focused local reads/searches
were used instead. Official TF3 references were also inspected.

| Capability | Source evidence and decision |
| --- | --- |
| Arbitrary edge renderable records | [Official Builtin reference](https://wiki.transportfever3.com/script-doc/content/scripts/builtin.html); `base/tealdef/scripts/builtin.d.tl:46-57,1317-1329`; `base/content/gui.zip → gui/main/builtin.lua:222-229` expose EdgeRenderable.Edge and a native recipe. This proves the records exist, not that attaching them to our ordinary Window creates an active world render pass. |
| Edge geometry | [Official types](https://wiki.transportfever3.com/script-doc/api/type.html); `api/tealdef/api/type.d.tl:1029-1120` defines XY shapes, height, vertical tangents and length. No shipped arbitrary EdgeRenderable construction example was found in the inspected GUI/mission sources to establish all required geometry/default semantics for this use. No values were guessed. |
| Renderer binding | `builtin.d.tl:1303-1310` exposes bindAction/unbindAction; `gui.zip → gui/line_vehicle_mgmt/cargofilter_window.tl:277-290` binds/unbinds a supplied game-context action on mount/unmount. This demonstrates scoped native binding but does not establish arbitrary edge activation alongside the mod's existing window and active native tools. |
| Internal activation helper | `base/tealdef/scripts/react.d.tl:371-375` marks useAction/setActiveOwner internal and deprecated in favor of ToolStack. `gui.zip → gui/main/react.lua:593-640` performs binding/cleanup; `builtin.lua:1162-1193` activates ToolStack owners. RNA does not call these internal helpers or take over the tool stack. |
| Shipped world arrows | `mission.zip → mission/mission_framework/mission_framework_react.tl:491-518` constructs MissionArrowRenderable and passes it through the task's selector/action mechanism. This is source-backed arrow rendering, but not a verified drop-in mod-owned ordered polyline lifecycle. |
| Mission markers/zones | [Official GUI reference](https://wiki.transportfever3.com/script-doc/api/gui.html); `api/tealdef/api/gui.d.tl:694-739`; `mission.zip → mission/mission_sim.script.tl:1089-1117,1154-1162` creates and removes keyed markers/zones. These are genuine APIs. The shipped mission owner reconciles them; zones also have building-prohibition semantics. We do not repurpose them to fabricate a track/path preview or assume arbitrary marker types. |
| Movement-path visualization | The GUI reference limits setMovePathVisualizationAtEntity to ships. It visualizes an existing entity's movement path, not our plain-Lua corridor waypoints. |
| LineViewer / map preview | `builtin.d.tl:1424-1482` describes existing transport-line/terminal/edge references and generated-map previews. These do not establish a free-form active-map corridor overlay. |

The precise missing contract is **supported ownership/activation of arbitrary route
geometry alongside the existing mod window and native tools, complete geometry
construction semantics, and deterministic removal on all owner/session exits**.
There is no claim that the C++ renderer lacks such a capability. No experimental
render registration, new event transport, construction command or marker workaround
was added. A future world-space phase needs an official mod example or equivalent
installed evidence covering this complete chain.

## Verified fallback integration

The fallback reuses the runtime-verified native Window, BoxLayout, ScrollArea,
ComboBox/ComboBoxItem and TextView. `builtin.d.tl:768-775,1033-1049` declares text,
item values and selection callbacks; `gui.zip → gui/main/builtin.lua:16,159-170`
registers native text/window/scroll content. The existing mod plugin remains a
horizontal layout with one launcher, consistent with `main_mod_button_area.tl:7-39`.

The Game Script remains authoritative. `base/tealdef/scripts/gamescript.d.tl:40-68`
defines transient GUI state and the existing guiUpdate/guiHandleEvent contracts.
The working engine subscriptions, namespaced event routing, main-thread join dispatch
and synchronous status response are unchanged. Only an optional bounded `preview`
field is added to the existing response.

### Data and ownership

1. A request runs normally. Only after terminal `ok` and result `complete=true` does
   the owner call `preview.build` once. World/request provenance, candidate status,
   finite coordinates, endpoints, lattice adjacency, bounds and ranks are checked.
2. The owner stores a compact plain-Lua DTO in that request: epoch/world/request ID,
   source/destination IDs and names, original XY anchors and up to three summaries.
   Each summary has snapped XYZ endpoints, snap distances, approximate length,
   gain/loss, maximum sampled gradient, water runs/exposure, score components,
   fine spacing, section count and ordered-waypoint count.
3. No full route, terrain cells, search continuation or render userdata crosses the
   polling channel. Complete ordered waypoints remain in the original planner result.
4. React chooses a candidate locally using its ID. It displays ten wrapped text rows
   beneath a clearly labeled heading: **Corridor summary (in-panel only; not a map
   overlay)**. Source/destination labels retain IDs for duplicate town names.
5. The existing stylesheet, title bar, centered placement, dragging, closing and
   vertical scrolling are unchanged. No new styling or window registration.

Approximate world coordinates are shown numerically (one decimal), not projected
onto a map. Zero/negative heights remain numbers. The UI expressly states that no
path is drawn and construction feasibility is unverified. It is not a schematic,
line overlay, track model or economic cost estimate.

### Lifecycle and bounded work

- A new accepted request immediately hides the previous summary. Its eventual
  complete result replaces it. Failed or incomplete results show no candidate picker.
- A consumed but rejected click token cannot relabel the old summary as a new request.
- Refresh, world/tick invalidation and reactPostInit drop the owning request through
  the existing lifecycle. There are no external objects to remove.
- Closing unmounts the panel. Reopening waits for a fresh status response before
  showing cached data. Candidate selection starts with the first rank on reopen;
  source/destination selections keep their existing behavior.
- Candidate callbacks check window lifetime and epoch/world/request identity, so
  delayed callbacks cannot restore an obsolete selection/result. Communication or
  malformed-payload errors hide the summary and retain explicit Refresh recovery.
- At most three candidates and 4,096 waypoints per candidate are inspected once on
  completion. Status validation is at most three compact records; display is one
  dropdown and ten text rows. No A*, terrain query or render-object creation occurs
  during local candidate selection/redraw. Existing polling remains 0.5 seconds.
- Summary preparation and widget layout are bounded synchronous work. Their native
  cost and added GUI-state-copy cost have not been measured; no sub-50ms claim.
- A summary is a completed snapshot, not a live terrain monitor. Arbitrary subsequent
  terrain changes in the same session are not detected by this phase.

## Changed files and relevant diff

Relative to the preserved pre-Phase-4B.4 workspace (not clean Git HEAD):

```text
AGENTS.md
README.md
docs/phase_4b4_corridor_preview.md                   new
oz_railway_network_architect/content/
  live_plan_preview.lua                            new pure summary gate/formatting
  live_plan.script.lua                             build once; optional response field
  live_plan_ui.script.lua                          candidate picker and summary text
tests/
  preview_test.lua                                 new pure tests
  live_plan_test.lua                               9 added integration tests
  run_lua_tests.py                                 runs preview suite
```

Relevant production changes:

```diff
+local preview = ug_require "oz_railway_network_architect::/live_plan_preview.lua"
 -- Existing response:
-candidates = r and r.result and #r.result.candidates or 0}
+candidates = r and r.result and #r.result.candidates or 0,
+preview = r and preview.valid(r.preview, state) and r.preview or nil}

 -- Only when a request finishes:
 state.status = r.status
+r.preview, previewReason = preview.build(state)
+-- One bounded PANEL_SUMMARY diagnostic; no event handler/subscription changes.

 -- Existing window, after status text:
+text("Corridor summary (in-panel only; not a map overlay)")
+-- ComboBox selects a candidate ID locally; existing style reused.
+for _, line in ipairs(preview.lines(summary, candidate:old())) do
+    children[#children + 1] = text(line)
+end
```

The new module validates full candidate completion before constructing compact
copies. Existing renderer/tool stacks and all native world-writing APIs are unused.
The complete prior Phase 4B.2/4B.3 changes are retained; no reset or cleanup of them.

## Automated verification

```powershell
uv run --no-project --offline --with lupa==2.8 python tests/run_lua_tests.py
```

**138 tests passed**: 20 railway, 22 canonical planning, 20 hierarchical planning,
6 pure presentation and 70 live/UI tests. All 123 preexisting tests still pass.
**37 Lua files** pass Lua 5.4 syntax checks; JSON, UTF-8 without BOM, imports,
resources, callback exports and mod identity/revision pass. `git diff --check` passes.

New tests cover canonical multiple alternatives, coordinates and zero/negative
values, incomplete/unsupported/unreachable/search-limit suppression, malformed
and oversized data, discontinuities, request identity, local candidate switching,
16,000-unit summaries, replacement, refresh, reload/world invalidation, unmount and
reopen, stale callbacks, rejected tokens, communication failure/recovery and no
new planning or terrain reads during redisplay. Pure formatting is tested with
engine/GUI API access forbidden. Existing tests still enforce restricted React
contexts, main-thread dispatch, one request per click and no automatic planning.

Tests validate the **fallback summary**, not a world-space preview. No mock result
proves native TF3 rendering, focus, text fit or timing.

## Review, staging and native acceptance

Stop for code review now. No staging update was performed.

After review, close TF3. For a staging copy already matching the current Phase 4B.3
workspace, add `content/live_plan_preview.lua` and replace only
`content/live_plan.script.lua` and `content/live_plan_ui.script.lua`, preserving their
relative paths under the existing `oz_railway_network_architect` mod. Back up those
two staging files first. Do not copy tests/docs or replace metadata, stylesheet,
subscription resource, descriptor, planner or inventories for this incremental patch.
If staging still contains Phase 4B.2, review/install the separate Phase 4B.3 prerequisites
first; this three-file patch does not include the hierarchy implementation.

Manual criteria:

1. Load a map, open the centered planner window and verify its existing padding,
   dragging, controls and title-bar close. No plan or map object appears on load.
2. Plan a known short pair. After `ok`, see the labeled in-panel summary, source and
   destination IDs, snapped XYZ, metrics and construction-unverified warning.
3. Where multiple candidates exist, switch ranks. Metrics should change without a
   new REQUEST_START, terrain scan or plan. Do not expect fabricated alternatives.
4. Try a long pair. During work, only existing progress/status appears. A successful
   result shows the full refined section/waypoint counts and 64-unit resolution.
5. Repeat planning, then try an unsupported/unreachable pair. Old results must not be
   presented as the new request. No picker on failed/limited/incomplete outcomes.
6. Close/reopen, Refresh towns and reload another map. Summary must disappear until
   a current completed response is available; selections follow existing reset rules.
7. Check scrolling and long town names at different UI scales. The window remains
   bounded and no text is clipped/overlapping. Record responsiveness; static tests
   cannot prove this native behavior.

One new bounded diagnostic per finished request:

```text
[RNA:PREVIEW:4B4] PANEL_SUMMARY request=1 candidates=1 reason=complete_snapshot map_overlay=false
[RNA:PREVIEW:4B4] PANEL_SUMMARY request=2 candidates=0 reason=request_not_complete_ok map_overlay=false
```

Existing planner logs retain precise failure reasons and candidate details. Remaining
uncertainties: complete world-space render integration, native layout/performance,
and the existing Phase 4B.3 terrain/search approximation limits. This phase adds no
construction, world objects, map drawing, economy or national network planning.
