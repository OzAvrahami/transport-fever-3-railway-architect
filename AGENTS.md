# Railway Network Architect

## Current milestone

Targeted station-site occupancy acceptance correction on b14ddce. The native test
rejected 46 source-town candidates before terrain reads; their entity classes were
not recorded. Do not claim the retest succeeds. See docs/station_site_occupancy_acceptance_fix.md.

Station-Aware Railway Planning. The owner has verified the cyan route in native TF3
Freeplay. New station reservations and approach-to-approach planning still require one
Midhurst?Morley native acceptance test after review. No construction, terrain changes,
staging deployment, commits, tags, pushes, identity or revision changes.

- Preserve the small native window, launcher, five subscriptions and GUI request owner.
  Production Plan Railway explicitly sends stationAware=true. No automatic planning,
  analytics UI or build controls. Unknown site suitability means unresolved, never a
  fallback to town centers. Legacy hidden network/batch/developer callers remain intact.
- station_site_api.lua normalizes protected native reads; planning/station_sites.lua
  owns pure site/pair scoring. station_plan_request.lua owns the incremental session,
  using the existing live_plan_request and authoritative A*/hierarchy sequentially.
- Derive occupied urban extent from actual TOWN_BUILDING volumes, not the town volume.
  Use planning/station_occupancy.lua consistently for initial/final screening and masks.
  Body: 160x48 plus 4 m per side; facing approach: u=76..132, half-width 16.
  The former 512x64 envelope is inspection evidence, not a mandatory clear footprint.
  Buildings, constructions, roads, tracks and unknowns block the required regions.
  Only positively verified tree metadata on every model instance permits provisional
  vegetation clearance; mixed/missing evidence stays unknown. Never remove vegetation.
  Read-only query caps fail explicitly. Never turn unknown terrain into vacant land.
- Passenger rail station hints require a terminal with TRAIN/ELECTRIC_TRAIN plus a
  passenger load/unload flag. Road endpoint distance is not walking catchment. Physical
  track proximity is not operational connectivity or verified attachment/reuse.
- 160 m length follows four installed 40 m platform sections; 48 m width and 512x64 m
  inspection region are explicit approximations, not native station geometry.
  Cardinal orientations, 128 m approach offsets, 3% sampled grade and other thresholds
  are prototype assumptions. Preserve evidence and unknowns in logs.
- Cap sites at 48/town, terrain checks at 51/site and 16 reads/callback, shortlist at
  three/town, cheap pair ranking at nine, actual sequential corridor studies at two.
  Preserve existing per-corridor budgets and the shared 60 s station snapshot age.
  Keep a 50 ms observed-work guard; native calls/state copies are not preemptible.
- Separate selected town IDs/observations from explicit station approach XYZ. Endpoints
  must match grid samples exactly; reject snaps instead of silently changing the site.
  Revalidate towns/world/bounds and reservation occupancy before publishing.
- Keep existing scores/constraints; prefer known clear straight exits in site/pair
  ordering without treating the inspection neighborhood as another hard footprint.
  Route masks use hard AABBs plus 12 m; verify complete segments independently before
  publication so between-sample buildings cannot be crossed. Check 16 segments/callback.
  Final occupancy classification also processes 16 records/callback. Keep vegetation
  clearance, unknown walking access, source classes and bounded conflict examples in logs.
- Retain only complete routes with correct outward/inward approach direction and no
  crossing of either reserved station body. No fabricated alternatives or smoothing.
  C1 Hermite fitting does not establish safe approaches, curvature or construction.
- route_overlay.lua remains the sole keyed-zone owner. Draw the original cyan route,
  orange source and purple destination reservation/axis/cap polygons. Keep waypoint
  order/coordinates; do not rerun A* for drawing, alternatives or Hide/Show/Focus.
- Use documented GUI mission setZone draw=true, prohibitBuilding=false,
  playAnimation=false, zOffset=1 and matching mod-owned removeZone keys only.
  Max 1024 route segments plus six station polygons, 16 zone operations/callback.
  No truncation, entity removal, global mutable state or shared inventory snapshots.
- Preserve view leases, heartbeat expiry, stale sequence protection, cleanup before
  replacement, close/reload cleanup and fresh reopen. Do not transfer full routes or
  site terrain/occupancy arrays into React polling; only compact current-site metadata.
- No sendCommand, WorldBuildProposal, ProposalViewer or construction tools. Archived
  experimental code under reference/ must never be imported or exposed live.
- The new station flow is not native acceptance. Record source evidence and assumptions
  in docs/station_aware_planning.md; preserve all existing regression tests. Stop here
  for owner review and the focused native test, not another feature milestone.

Topology studies consider supplied demand evidence, distance, geography and transport
alternatives. A city or industry does not automatically need rail. Economic feasibility
and actual construction remain unverified; scores are explicit planning preferences.

## Development conventions

- Geometry inspection is owned by the existing planning GUI state in live_plan_geometry.lua.
  Use the existing plan event with a separate inspection token and current corridor ID.
  Inspect Geometry is explicit, applies to one terminal complete candidate, and never
  reruns A*, samples terrain, edits a worklist or invokes native proposal code.
- Copy at most 256 validated XYZ waypoints; reject larger input without truncation.
  Separate fitting and DTO checking into two guiUpdate callbacks, eight diagnostic
  intervals per segment. Preserve the 50 ms observed-work guard; it is not preemption
  and zero clock deltas do not prove zero processing time. Release temporary curves.
- Transfer only ten bounded summary lines, never geometry arrays. Preserve historical
  corridor identity/provenance; no fresh-world engineering claim. Clear on accepted
  replacement requests, Refresh and session reset; reject busy/stale/replayed clicks.
  Window close does not cancel the bounded owner job; reopen requires a fresh response.
- Native preview gate is BLOCKED: no supported mod-owned activation, demonstrated
  non-mutation or deterministic native processing cleanup. Do not activate ProposalViewer,
  resolve guessed resources, or fabricate template/ownership data to bypass this gate.
- Offline assembly lives in content/geometry/track_proposal_assembly.lua. Its descriptor
  is not a native SimpleProposal. Revalidate through Phase 6B; reject noncanonical node
  references instead of welding, fitting or attaching geometry. Preserve source evidence.
- Use one negative temporary-ID namespace: nodes first, then segments. Only explicitly
  isolated new endpoints and NORMAL/TRACK configuration are supported. Never infer
  station positions or existing node IDs from town anchors.
- Require caller-supplied template/style, lane configuration, typeIndex and provenance.
  Enum names are symbolic descriptor data; do not guess native enum values, resolve
  resources implicitly or select defaults. Ownership remains explicitly unresolved.
- Bound assembly to 255 segments, 256 nodes and 8 lanes per segment. Preserve diagnostic
  violations. Native readiness remains blocked even when all offline checks pass.
- ProposalViewer is gated: accepted input declarations do not establish safe RNA tool
  ownership, non-mutation or cancellation/reload cleanup. Do not activate it or process
  proposals in this milestone. Preserve existing UI styles and event subscriptions.
- Phase 6B adapter lives in content/geometry/track_geometry_dto.lua. It is NOT a
  SimpleProposal or processed Proposal. Only explicit inspection imports it live. Preserve all
  endpoint/tangent values and source indices; DTO node indices are not entity IDs.
- Require explicit world-frame provenance; keep caller resource references separate
  from resolved native templates. Never invent lanes, entity IDs, electrification
  fields, bridge/tunnel indices or engine acceptance. No native objects are created.
- DTO joins require exact C0/C1; never silently weld gaps or rescale tangents. Its
  forward-chord derivative guard is a conservative offline policy, not a TF3 rule.
  Report curvature and gradient-rate jumps: C1 preserves grade, not C2 continuity.
- Cap the DTO at 255 segments, 256 nodes, 254 join reports and 64 diagnostic intervals
  per segment. Provenance copying is bounded and rejects cycles/overflow, never truncates.
- Preserve diagnostic violations, report prerequisites, and keep mathematical checks,
  vector-field correspondence and native validation as distinct evidence levels.
- Geometry prototype lives in content/geometry/rail_curve.lua, with no TF3 dependencies.
  Live use is limited to explicit bounded inspection. Input is a metre-unit XYZ projection; preserve the
  original corridor, water/obstacle provenance and endpoint approximations outside it.
- Candidate geometry uses cubic Hermite u in [0,1], both tangents dP/du, not unit
  directions or reversed end tangents. The fitting heuristic is an assumption, not
  TF3's native builder algorithm. C1 in unit intervals does not imply C2 or buildability.
- Bound offline geometry to 256 input points and 8-64 diagnostic intervals/segment.
  Gradient/radius limits are optional caller assumptions, never silently copied from
  resource examples. Numerical minimum chord is not a game minimum segment length.
- Keep sampled curvature/gradient diagnostics distinct from certified extrema and
  engine validation. Fitted curves leave terrain samples; clearance, earthworks,
  bridges/tunnels, stations and connections require future independent assessment.
- Do not equate construction edgeLists, SimpleProposal and processed Proposal.
  makeProposalData accepts Proposal, not a documented SimpleProposal overload.
  Phase 6D must not execute it, create WorldBuildProposal commands or send commands.
- Batch coordination lives in network_batch.lua, in the existing GUI owner only.
  Reuse the plan event with a separate batch envelope/token; no extra subscription.
  Start only on Study Marked Corridors. Marking/editing never triggers a search.
- Select included + furtherStudy algorithm recommendations; sort ascending original
  priority, then canonical edge ID. Reject more than four without truncation.
- Run one live_plan_request continuation at a time. Do not create a second planner
  or keep previous terrain grids/routes in batch results. Retain at most four compact
  terminal summaries and original origin metadata, separate from manual results.
- Check world/epoch/snapshot/worklist revision every batch step. Before EACH study,
  reuse handoff.prepare/validate, including the original 60-second collection age.
  Never refresh the deadline or auto-reanalyze. Expiry discards pending work only;
  an already accepted route retains its existing per-request validity checks.
- Busy batches block Plan, individual Study, Analyze Network, edits, Refresh and other
  batches. Cancel is the only control allowed through busy, with matching identity.
  Cancel releases the active continuation, discards pending work and retains labeled
  completed summaries; reload discards everything. No persistence or implicit retry.
- Only validated terminal complete/ok candidates count as completed studies. Ordinary
  unsupported/unreachable/search_limit/incomplete outcomes may continue; invalidation,
  timing/resource/performance errors stop. Start the next study in a later callback.
- Network Plan owns only copied endpoint/classification references and separate
  user overrides. Never mutate algorithm result scores, evidence or classifications.
  Only algorithm-recommended links are editable; do not add arbitrary/deferred links.
- Include/exclude changes membership; mark_study is an independent flag, never a
  search trigger. Restore clears one override; reset_all clears all. Retain only
  current user decisions (actor/action/revision/tick), not an unbounded edit history.
- Use the existing plan event with a distinct worklist envelope, before corridor
  token processing. No new subscription. Validate world/epoch/network snapshot and
  expected revision; reject busy, stale and replayed operations atomically.
- Recalculate the bounded proposal graph on accepted edits: components including
  isolates, degrees/potential hubs, original-branch attachments, duplicate references
  and independent cycles. Membership changes make original labels historical-only;
  never assign verified new Mainline/Branch labels or force connectivity.
- Worklists are at most 32 towns/31 proposed links. Clear on reanalysis, Refresh,
  reload/world invalidation. Do not persist edits. Review edits may outlive the
  60-second handoff age, but never refresh source evidence or bypass handoff checks.
- Excluded recommendations cannot use Study Corridor. Manual Plan remains independent.
  Capture the worklist revision/decision separately in corridor origin; later edits
  must not rewrite a completed study or run another search.
- Study Corridor uses the existing plan event with a network selector; do not add
  a subscription or parallel transport. Resolve IDs through the owner's recommended
  edges and canonical corridorRequest descriptor. Deferred/rejected edges are inert.
- Preserve the shared corridor click token/busy guard. Never plan on network
  completion, link selection, summary switching or load. Do not retry automatically.
- Handoff validates world/epoch/network request/snapshot IDs, a 60-second age from
  network collection start, bounded town index, map bounds, endpoint identity/XYZ
  and current residential capacities. This is not atomic freshness; same-world
  rail/industry and other-town metric changes remain unverified. Reanalyze explicitly.
- Store an independent plain-data networkOrigin on the corridor request. Do not
  rewrite topology classification or scores using corridor geometry. Retain provenance
  even if a later network study replaces its source result; label it historical.
- Suppress corridor previews in busy responses, including while network analysis is
  active, to satisfy the existing preview validator. Keep status, origin and terrain
  candidate validity distinct. Preserve manual source/destination selections.
- Live network integration lives in network_live_api/data/request.lua. Reuse accepted
  read adapters and normalizers without sharing inventory script GUI states. The
  GUI request owner holds a separate network request ID, continuation and result.
  Analyze Network is explicit and mutually exclusive with active corridor work.
- Live limits: 32 towns/496 pairs, 128 industries, 4096 rail nodes/8192 segments;
  four town/industry reads or sixteen rail reads per callback. Oversized town input
  fails; oversized/unavailable optional inventories are omitted with warnings.
  Keep the unchanged core synchronous under the smaller cap, the 50 ms observed
  work guard and 60-second snapshot limit. No native latency guarantee follows.
- Native capacity uses getTownCapacityUsage and symbolic LandUseType.RESIDENTIAL + 1.
  Preserve provenance; capacity is not demand. Omit unknown demand, geography,
  regional barriers and transport adequacy. Never supply synthetic live assessments.
- Revalidate world/ticks per callback and town anchors/index/bounds before topology.
  This is an interval snapshot, not atomic; report missing data and same-world edits
  that cannot be detected. Reload invalidates results; no save persistence.
- Network UI transfers only nine summary lines and up to 55 compact connection
  entries: all proposed links, then at most 24 deferred/rejected links in ID order.
  Keep epoch/world/network-request matching, transport failure hiding and fresh
  reopen response. Preserve the existing window/ComboBox/TextView styles.
- Network topology is pure data processing under content/planning/network_*.lua.
  It must not invoke native APIs, A*, terrain sampling, GUI events or file writes.
  The explicit corridorRequest handoff is a descriptor, never automatic execution.
- Require provenance (source and observed/assumption/synthetic basis) for optional
  capacity, demand-support, region, geography, transport and inventory inputs.
  Missing metrics stay nil/unknown, not zero. Reject unsupported population fields;
  TF3's shipped Population column uses residential capacity, not pairwise demand.
- Default topology recommendations require supplied positive demand support or a
  sufficient capacity proxy at both endpoints. Leave unsupported towns disconnected.
  All thresholds/weights are configurable planning assumptions, not game standards.
- Select a degree/budget constrained forest of eligible pairs, then label a mainline
  path per component and remaining branches. No global optimum, passenger demand,
  operational rail route, station or buildability claim follows from these labels.
- Rail hints use proximity to incident nodes and physical components only. Same-
  component proximity defers duplicate corridor studies for inspection; do not merge
  that physical graph into proposed operational service or assume station access.
  Industry presence alone supplies no cargo flow and never triggers a new branch.
- Bound topology to 128 towns / 8,128 pairs, 4,096 rail nodes / 8,192 segments and
  512 industries. Validate limits before evaluation. Default selected edge budget is
  32 and town degree limit 3; neither is a monetary or engineering constraint.
  Keep deterministic ID tie-breaks, input immutability and an explanation per pair.
- Preserve the existing pure/scanner/UI regression suites. Network fixtures must be
  labeled synthetic; live inputs require fresh, independently verified adapters.
- The deployable mod is `oz_railway_network_architect/`; repository documentation
  and development tools stay outside it.
- Keep `modId` as `oz_railway_network_architect`, the display name as
  `Railway Network Architect`, and the current revision as `1`.
- Use plain Lua. Do not add a compiler, package manager or
  other dependency without a demonstrated need.
- Use four spaces in Lua and two spaces in JSON. Encode text as UTF-8 without BOM.
- Use lowercase file and directory names inside the deployable mod.
- Follow verified TF3 resource references and lifecycle contracts. Never assume
  TF2 compatibility. Keep documentation links and local evidence in README.md.
- A resource-loading diagnostic does not prove live-world readiness. Never put
  city queries into the bootstrap hook. Use the verified Game Script callback.
- Keep engine API integration separate from pure data normalization. Sort records
  by entity ID. Distinguish missing data from zero and avoid repeated scans/logs.
- Planning takes explicit plain data; inventory Game Script GUI states are separate.
  Do not infer shared snapshots, station locations from town centers, operational
  routing from physical adjacency, or construction geometry from a 24x24 terrain grid.
- The live prototype owns its town reads, grid, samples, timestamps and result in
  its own GUI state. Reuse read functions, never another scanner's session state.
- Load game modules using verified mod-qualified ug_require paths. Offline tests
  adapt imports to the same canonical files; never independently edit generated copies.
- Never plan on load. A mod-owned generic React plugin in MainModButtonAreaExtension
  sends namespaced fireGuiScriptEvent requests to the existing Game Script's
  guiHandleEvent. Verify registration and interaction contracts against installed
  sources; do not replace native recipes or invent cross-state communication.
- MainModButtonAreaExtension returns a horizontal BoxLayout containing only a launcher button. Open the form in a
  native Window via the verified default window container. ModEntryPointExtension
  is hosted in an invisible entry-point subtree, not a visible panel container.
  Keep close/Back/unmount cleanup scoped to this window recipe; never replace native
  controls. Use component-local refs for reopen state and revalidate session identity.
- Dispatch fireGuiScriptEvent through react.enqueueJoin, never directly from restricted
  React deferred/timer work. Guard queued dispatch and responses against unmount,
  expired state/container and obsolete window generations. Coalesce pending requests;
  pause polling on communication failure until an explicit retry. Keep window styles
  mod-scoped, bounded and scrollable; mock layout success is not native verification.
- Register planner GUI event names through the Game Script engine state's
  subscriptions: the shipped company script explicitly subscribes `-- gui events`.
  Keep the engine update resource registration-only: no simulation commands, data
  writes or saved planner state. All planning remains in the existing GUI owner.
  Subscribe only status, refresh, plan, analyzeNetwork and reactPostInit, guarded by
  hasEventSubscriptions as in shipped update examples. Native delivery and explicit
  planning are runtime verified; preserve this communication architecture.
- The completed A/B probe found nil/no handler entry for both component IDs. It is
  removed. Keep normal routing unchanged; no further component-ID experiments.
  Keep bounded correlation diagnostics and one registration-entity lookup per GUI
  session. Lookup success alone does not prove handler delivery.
- Use Window initialX/initialY and the window-container creation parameters for
  initial normalized placement, with a mod-scoped centered anchor. Never reposition
  the open window each frame or change unrelated viewport controls. Apply form
  padding to Window::Content; preserve native title-bar styles and vertical scrolling.
- Unsupported UI messages describe prototype sampling limits, not railway feasibility.
  Keep the precise reason in diagnostics and distinguish excessive axis span from
  boundary-margin failures. Do not change planning limits to improve message wording.
- The Game Script owns town lists, session epoch, request IDs and results. React
  owns only transient form/view state. Reject busy, replayed, stale and identical-town
  requests; no closest-pair fallback. Refresh/reload clears form selection.
- Build compact panel summaries once from terminal status=ok, complete results only.
  Exclude incomplete-data, unsupported, unreachable, search/resource-limited and
  invalidated results, even if they contain some completed candidates. Never describe
  a corridor as buildable. Retain source IDs, original anchors and snapped XYZ endpoints.
- Cap presentation at three candidates, 4,096 checked waypoints per candidate and
  ten summary lines for the locally selected candidate. Transfer no waypoint arrays,
  terrain grids or continuation state through GUI status polling. Do not rerun A* to
  switch candidates. Use existing ComboBox/TextView styles and scrolling.
- Match epoch/world/request IDs before showing summaries. Require a fresh response
  on reopen; hide on transport errors, new requests, refresh and session reset. Guard
  candidate callbacks with existing owner lifetime plus request identity. The panel
  shows a completed snapshot, not ongoing terrain validity or a live map overlay.
- EdgeRenderable type declarations alone do not establish a complete supported
  mod-owned polyline integration. React useAction/setActiveOwner are marked internal
  in installed definitions. Do not invent geometry defaults or take over native tools.
  Verify rendering, ownership and cleanup together before future world-space work.
- Entity IDs distinguish duplicate names. Revalidate selected TOWNs and world before
  accepting each request; sample fresh terrain. Report bounding centers as approximate
  anchors and every endpoint snap. No hardcoded save IDs.
- Preserve the short-route 32x32 grid and 32/64/128 spacing policy. Only the existing
  coverage/margin failure enters hierarchy; no silent fallback from invalid endpoints.
- Hierarchy uses actual 512-unit coarse samples in a bounded neighborhood and actual
  64-unit samples in overlapping windows (32x32 maximum). No interpolation from old
  inventory data. Validate coordinates through the unchanged adapter before reads.
- Plain-Lua planner start/step continuations advance in existing guiUpdate callbacks.
  Never retain closures, threads, userdata or coroutine state in GUI session tables.
  Do not rely on table aliases surviving guiState copies. planner.plan remains the
  synchronous offline wrapper over the same authoritative incremental search.
- Limit each live step to 16 sample visits, 64 expansions or 32 final-validation
  waypoints. Coarse models cap at 64x64; fine models cap at 32x32. Bound a request to
  32,768 unique samples, 65,536 visits, 49,152 expansions, 128 sections per guide,
  4,096 waypoints per candidate and three coarse guides. Per-window search caps are
  12,288 coarse / 3,072 fine. One wider-window retry only; no unbounded retries.
- Long requests advance once per GUI callback; short requests preserve the every-fourth
  cadence. Keep the 50 ms observed-work guard and 60 s snapshot age guard. Native API
  calls, state copying, validation and summary work are not preemptible; zero timing
  deltas do not prove zero cost. Measure native GUI state-copy overhead in acceptance.
- Shared lattice/checkpoint samples come from one request cache. Stitch only equal
  X/Y/Z/water endpoints. Erase loops deterministically and revalidate every final edge
  and diagonal corner via the canonical grid rules; rank complete routes with common
  weights. Never publish an unfinished section chain as a candidate.
- Keep source IDs, original anchors, explicit fine-grid snaps, resolution/section
  counts and snapshot provenance in outputs. Coarse routes are search guides only;
  fixed checkpoints and bounded neighborhoods can miss feasible paths. Unknown
  samples stay excluded, never become zero-height land. Water stays excluded unless
  explicitly configured otherwise; gradient thresholds remain caller assumptions.
- Revalidate world/ticks, bounds and selected-town coordinates throughout long work.
  Cancellation clears pending search/cache/results. No persistent cache or save data.
- A corridor is a sampled-grid path, never a buildable railway. Scores are planning
  preferences, not game construction costs. Gradient assumptions and weights must
  be explicit/configurable. No invented TF3 gradient or curvature standards.
- Keep planner inputs immutable, tie-breaking deterministic, and CPU/memory bounded.
  Exclude unknown samples, prevent diagonal corner cutting, distinguish search
  limits from unreachable destinations, and deduplicate similar alternatives.
- Use the existing isolated Lua test harness; include synthetic route scenarios,
  independent shortest-path comparisons and tests at computational limits.
- Railway adjacency describes shared BASE_NODE endpoints only. Degree >= 3 is a
  junction candidate, not operational switch connectivity or route availability.
  Empty railway networks must succeed. Never classify all STATION entities as rail.
- Keep synthetic graph tests outside the mod package. An isolated development
  Lua runtime is permitted for tests; add no game dependency or project manifest.
- Documented TF3 bindings may report Lua type "table". Check presence and use
  documented direct calls inside pcall; never require type(value) == "function".
- The accepted world terrain inventory stays capped at 24x24 cell centers. Validate coordinates before
  height/water queries; clamped out-of-bounds heights are not valid samples.
  Use bounded batches, retain explicit partial/completed status and log summaries
  plus capped error examples, never every sample.
- Inventory once-only flags and planning request/session state stay out of engine
  state and GUI SaveData. Reset on verified gameUI/reactPostInit and world/tick
  invalidation; verify same-process reload in-game. Repeated plans require new clicks.
- Do not introduce globals except the documented resource entry point `data`.
- Validate JSON, metadata, script references and encoding after relevant edits.
  Use an existing Lua checker if available; do not claim static checks prove a
  successful TF3 load. Record checks that were unavailable or not run.

## Safety and scope

- Treat installed game files, shipped examples and API definitions as read-only.
- Do not execute or expose world-changing commands or change simulation configuration.
  No active module may create or send construction commands.
- Do not persist mod state or modify user saves in this milestone.
- Do not install or overwrite a local mod copy without a user request to do so.
  Document installation steps for the user instead.
- Do not publish, upload, commit or push without explicit user authorization.
- The deployable mod is read-only again: cosmetic=true; add/remove severity None.
  Zone drawing must never prohibit building or persist simulation/save state.
- Keep changes small and report verified behavior separately from assumptions.

<!-- OCTOCODE-GLOBAL-START -->
## Octocode MCP — Codebase Research

Prefer Octocode for unfamiliar or complex codebases, architecture and dependency
analysis, locating implementations and callers, cross-file changes, regressions,
and relevant external repositories or npm packages. Do not invoke it for simple
localized edits or questions already answered by verified evidence.

1. Start focused discovery with localSearch.
2. Read relevant source with localGetFileContent.
3. Use localAnalyzeGraph when dependencies matter.
4. Use lspGetSemantics when symbol-level verification is needed.
5. Verify conclusions against source and distinguish evidence from assumptions.

Prefer narrow searches and reuse findings. Graphs are structural evidence, not
runtime proof. Do not modify files merely to investigate. Never expose credentials,
tokens or private repository contents. Preserve repository-specific instructions
and do not change Git, release, testing or deployment workflows. If Octocode is
unavailable for a path, report the limitation and use appropriate read-only tools.
<!-- OCTOCODE-GLOBAL-END -->
