# Phase 5B.1: explicit live network topology study

Implemented for code review; not yet tested in native TF3. No staging deployment,
save writes, construction, dependency installation, commits, tags or pushes.
The existing event transport, window, corridor algorithms and four inventories remain
in place. Only an explicit **Analyze Network** click starts network work.

## Policy audit before implementation

The complete Phase 5A core, schema and tests were reviewed alongside the inventory
contracts and Phase 4B lifecycle/reports. All 163 baseline tests passed. Octocode
localSearch rejected the available query schema; focused direct reads and ZIP member
inspection were used instead. No production policy was changed for style or convenience.

Verified policy behavior:

- Missing demand is absent, not zero. Capacity can justify a conditional study only
  when both towns satisfy its threshold. A supplied explicit zero demand assessment
  overrides capacity; this integration supplies no demand assessment at all.
- Capacity support `0.5 + 0.5 * min(1, min(capacityA,capacityB)/majorCapacity)` has a
  **fixed heuristic baseline of 0.5**. It is not a passenger forecast. Default minimum
  capacity 200, major capacity 1000, distance range 1000-20000 and minimum score 0.25
  are illustrative policy assumptions, not calibrated TF3 economics.
- Score subtracts normalized distance times 0.25 and difficulty times 0.5. Unknown
  geography uses the explicitly assumed 0.2 difficulty. This gives equal unknown
  geography penalties; it does not establish geographic suitability.
- Greedy degree-limited forest selection (degree 3, edge budget 32) can leave towns
  disconnected and omit useful loops. Its mainline is a longest path within each
  selected tree, biased toward major-capacity anchors when available. Classification
  does not establish traffic, infrastructure capacity, switch connectivity or profit.
- Same-component physical-node proximity defers a link for reuse inspection. It may
  be overly conservative: there may be no station or usable service. Industry proximity
  supplies context only and never changes selection or score.

These limitations are visible in the panel. Live geography/regions/road adequacy and
OD demand are omitted because no verified collector establishes those assessments.
The live model therefore proposes **conditional corridor studies**, not an economically
validated national network. The original configurable defaults remain authoritative.

## Verified native evidence and data provenance

Read-only inspection root: `D:\SteamLibrary\steamapps\common\Transport Fever 3`.
Official references: [engine](https://wiki.transportfever3.com/script-doc/api/engine.html),
[engine utilities](https://wiki.transportfever3.com/script-doc/api/engine/util.html),
[systems](https://wiki.transportfever3.com/script-doc/api/engine/system.html),
[GUI](https://wiki.transportfever3.com/script-doc/api/gui.html).
The new API use is grounded in installed definitions/examples, not TF2 compatibility.

| Input / lifecycle | Installed contract and use |
| --- | --- |
| Town IDs, existence, components | `api/tealdef/api/engine.d.tl:1692,1713`: getComponent(entity, ComponentType), getEntitiesWithComponent(ComponentType). Reuse live_plan_api.ids/town and their protected reads. |
| Town names and anchors | Existing verified `live_plan_api.town`, loading `::/scripts/entity_util.tl` getPosition. Copy bounding-volume-center XYZ; these are approximate town anchors, never stations. Preserve duplicate names using IDs. |
| Capacity | `api/tealdef/api/engine/util.d.tl:571-574,629`: TownCapacityUsage.used/capacity and getTownCapacityUsage(townEntity). `base/content/game_mechanics.zip -> game_mechanics/towns/town_util.tl:14-16,148-150` indexes by symbolic LandUseType + 1. New reader copies only residential.capacity, with observed source provenance. |
| Capacity meaning | `base/content/gui.zip -> gui/statistics/statistic_towns.tl:71-79` displays residential.capacity in Population. This does not establish OD passenger demand or interchangeable resident counts. Zero capacity remains zero; unavailable/noninteger/out-of-range capacity is omitted with a warning. |
| Industry enumeration | `engine.d.tl:1713`; `gui.zip -> gui/statistics/statistic_industries.tl:392` uses INDUSTRY enumeration. |
| Industry positions/resources | `engine.d.tl:447,455,307,312`: Industry.level/construction, Construction.fileName/transf. `type.d.tl:782`: getTransl. Existing verified shipped patterns: `game_mechanics/fun_elements/ufo_util.tl:82-85`, `game_mechanics/celebrations/celebrations.script.tl:211`; documented in README's Phase 3A evidence table. Construction resource can be a dynamic identifier; origin is not a cargo terminal. |
| Physical rail | `api/tealdef/api/engine/system.d.tl:304`: getNode2TrackEdgeMap(): entity -> entity array. Reuse unchanged rail_inventory_api discover/edge/node and rail_inventory_data normalization, including symbolic RoadType.TRACK and BASE_EDGE/BASE_NODE semantics. Incomplete graphs are omitted entirely from hints with diagnostics. |
| World and timing | Reuse accepted world entity/GAME_TIME tick and api.util.getApplicationTime readers. Record world ID, epoch, request ID, begin/end tick and interval age. Timing resolution remains unverified. |
| Event activation | `game_mechanics.zip -> game_mechanics/company/company.script.tl:380-389` explicitly subscribes GUI names; achievements.script.tl:181 onward initializes under hasEventSubscriptions. Extend the same RNA whitelist with `.analyzeNetwork`; do not replace dispatch or introduce another transport. |
| GUI ownership/return | `base/tealdef/scripts/gamescript.d.tl:67-69` and company.script.tl:507-508 define the seven-argument GUI event callback. `api/tealdef/api/gui.d.tl:50-57` defines fireGuiScriptEvent and returned value. Existing request handler owns the network state, and existing React enqueueJoin dispatch/status polling carries a compact response. |

Native reads use documented calls inside protected execution. No binding is rejected
because Lua type is table. Tests intentionally model the capacity binding as callable
table. No production metatable or speculative fallback is introduced.

The accepted industry adapter's collect() reads all entities in one call. To keep
it unchanged and allow batching, the new adapter has a narrow one-industry reader
using the same verified fields. **Normalization is reused**, not copied. The other
town and rail readers are directly reused. No scanner GUI state is accessed.

## Architecture and request contract

```text
React Analyze Network click
  -> existing enqueueJoin -> fireGuiScriptEvent
     id = oz_railway_network_architect.plan
     name = oz_railway_network_architect.plan.analyzeNetwork
     param = {world, epoch, requestId = networkRequestId + 1}
  -> subscribed live_plan guiHandleEvent
  -> separate network continuation in that same GUI owner
  -> bounded native collection -> pure projection -> unchanged network.plan
  -> bounded networkSummary in existing status response -> native panel controls
```

`network_live_api.lua` contains only reads; `network_live_data.lua` projects normalized
records and builds the panel response; `network_live_request.lua` advances phases.
The pure Phase 5A core remains the single algorithm implementation. There is no new
Game Script descriptor, renderer, cross-script sharing or global mutable state.

Network and corridor jobs have independent request IDs/results but share a busy guard.
Duplicate/replayed, stale-world/epoch and concurrent requests are rejected. Refresh
is rejected while busy, and clears completed results/catalog selections afterward.
Closing the window does not cancel an already accepted request; reopening obtains
a fresh status response. A queued, undispatched click is dropped when the window
expires, using the existing join/lifetime guards. There is no automatic retry or plan.

Collection phases: town index/bounds; four town/size reads per callback; industry
index; four industry reads; rail index; sixteen edge reads; sixteen node reads;
rail normalization; four town revalidations; index/bounds verification; topology;
summary. Invalid town positions are counted and excluded. Missing optional metrics
remain absent. Unavailable or oversized optional inventories are omitted with warnings,
not presented as verified empty inventories. Valid empty maps complete successfully.

The snapshot is an **interval observation**, not atomic. World/tick checks occur before
and after each work callback; town IDs, positions and bounds are rechecked before
topology. World change, reverse tick, reactPostInit or age expiry invalidate work and
clear results. Same-world industry/rail/capacity edits are not fully revalidated;
their observed interval and uncertainty remain explicit. Completed results describe
that snapshot, not continuously current infrastructure. Reanalyze explicitly for fresh data.

The owner retains normalized town capacity/provenance, snapshot metadata, full bounded
topology decisions and compact presentation. Raw rail/industry working arrays are
released at phase completion; the full physical graph is consumed for proximity,
then released after planning. No persistence or external export occurs.

## Panel output and limitations

The existing window, padding, centered placement, scrolling, source/destination
controls, corridor summaries and stylesheet are unchanged. Add one Analyze Network
button and a network results section using the already verified Button/ComboBox/TextView.

- Nine summary lines: town/link/mainline/branch counts, hub IDs, unconnected town IDs,
  deferred/rejected counts, missing evidence, industry counts, tick interval, warnings
  and key policy assumptions.
- Every selected connection in priority order (at most 31 with 32 towns); at most
  the first 24 omitted pairs in deterministic ID order. The truncation is labeled.
- Select a link by stable pair ID to inspect endpoint names/IDs, direct distance,
  relative score, reasons, capacity evidence, physical rail hints and limitations.
- No full graph, waypoint array, terrain grid or A* state crosses the event response.
  No replan occurs when changing the inspected link.
- Hide summaries on communication failure, refresh, reset and new network request;
  require a fresh response on reopen and match world/epoch/network request ID.
  The complete bounded set of omitted decisions stays in owner memory; the UI does
  not expose all 496 decisions or add paging in this milestone.

## Performance bounds

| Work | Limit |
| --- | ---: |
| Live towns / pair decisions | 32 / 496 |
| Industry IDs | 128 |
| Physical rail nodes / segments | 4096 / 8192 |
| Reads per collection callback | 4 towns or industries; 16 rail nodes or edges |
| Rail proximity comparisons | 131072 |
| Industry-town comparisons | 4096 |
| Snapshot age | 60 application seconds |
| Observed callback work guard | 0.05 seconds |
| Distinct warning examples | 4, with total occurrence count |
| UI link records / text lines per selected link | 55 / 6 |

Oversized town enumeration returns unsupported and never plans a truncated set.
The reused rail discover normalizer itself has its existing 100000-reference,
20000-edge/40000-node defensive caps before the smaller network caps apply. Native
bulk enumeration cannot be paged by the verified APIs used here. Discovery,
normalization, the capped synchronous topology call, summary generation and state
copying are not preemptible. The guard detects measured overrun **after work**, and
discards the result; it cannot guarantee sub-50-ms native callbacks. Zero deltas
are reported as unverified resolution, not free work. Native profiling is required.

Mock maximum test: 32 towns, 4096 nodes, 8192 segments, 496 decisions and 131072 rail
comparisons completed in **792 callback steps**. A local test run measured **0.160
CPU seconds total** in the offline Lua mock; this excludes native API and GUI-state
serialization overhead and is not a TF3 performance promise. No A* search ran.

## Validation and examples

```powershell
uv run --no-project --offline --with lupa==2.8 python tests/run_lua_tests.py
git diff --check
```

**185 tests passed**: all 163 baseline tests plus 22 network integration tests in the
existing live harness. **43 Lua files** passed Lua 5.4 syntax, resource/import target,
callback-export, JSON, UTF-8 without BOM and unchanged identity/revision checks.
No test dependencies added. Existing inventory, planning-core, terrain-sampling and
stylesheet hashes match the pre-edit baseline. Production changes contain no commands
or world/save writes. Mock success does not establish native rendering or latency.

Coverage includes symbolic capacity index and callable-table binding; missing/zero
capacity; duplicate names; empty/single-town maps; mainline/branch/hub decisions;
deliberately omitted small towns; physical reuse and incomplete rail; industry origin
and resource reads; separated distant groups; deterministic repeat; explicit-only
execution; busy/replay/stale tokens; map reload; town/index/bounds changes; town and
optional inventory limits; age/work limits including final-callback overrun; restricted
React dispatch, result inspection, transport failure/recovery, reopen, malformed
responses, stale callbacks and continuation copying without shared table identity.

Mocked live example (synthetic native API fixture, **not actual game output**):

| Town ID (all named Twin) | Anchor | Residential capacity |
| --- | --- | ---: |
| 1 | 0,0,-2 | 2000 |
| 2 | -4000,0,-2 | 2000 |
| 3 | 4000,0,-2 | 2000 |
| 4 | 0,2500,-2 | 400 |
| 5 | 200,0,-2 | 50 |

With no rail or pair assessments: mainlines 1-2 and 1-3; branch 1-4; potential hub 1;
town 5 deliberately unconnected. 1-5 is too near under the study preference and its
other pairs lack the capacity proxy. A two-town variant with a physical track component
near both anchors defers 1-2 for reuse inspection. A missing capacity fixture produces
no recommendation without claiming zero demand. The unchanged Phase 5A example also
tests supplied region barriers/road evidence; the live adapter does not invent them.

## Changed files and relevant diff

```text
AGENTS.md
README.md
docs/phase_5b1_live_network.md                         new
oz_railway_network_architect/content/
  network_live_api.lua                               new
  network_live_data.lua                              new
  network_live_request.lua                           new
  live_plan.script.lua                               request owner extension
  live_plan_events.script.lua                        one additional subscribed name
  live_plan_ui.script.lua                            action and result inspection
tests/live_plan_test.lua                             22 cases, five-name assertion
```

Relevant registration change:

```diff
 state:subscribeToEvent("oz_railway_network_architect.plan.plan")
+state:subscribeToEvent("oz_railway_network_architect.plan.analyzeNetwork")
 state:subscribeToEvent("reactPostInit")
-EVENT_SUBSCRIPTIONS_READY count=4
+EVENT_SUBSCRIPTIONS_READY count=5
```

The owner additionally accepts analyzeNetwork, checks the separate next request ID,
starts a continuation, includes it in the existing busy/reset handling and advances it
from guiUpdate. The UI adds one button and a local link selector. Full tracked changes
are available with `git diff --` for the files above; the three new modules are listed
explicitly because untracked files do not appear in plain git diff.

## Safe staging update after review only

No staging files were touched. Fully close TF3 before copying. For a staging copy
already matching the accepted Phase 5A workspace, replace/add the following six files
only; the command verifies all other deployed package files first and stops on an
older or mismatched baseline. Back up the existing mod outside staging first if desired.

```powershell
$rnaSource = 'D:\code\transport-fever-3\railway-architect\oz_railway_network_architect'
$rnaTarget = 'C:\Program Files (x86)\Steam\userdata\175442176\3493540\local\staging_area\oz_railway_network_architect'
$rnaPatch = @('content\network_live_api.lua', 'content\network_live_data.lua',
    'content\network_live_request.lua', 'content\live_plan.script.lua',
    'content\live_plan_ui.script.lua', 'content\live_plan_events.script.lua')
if (-not (Test-Path -LiteralPath (Join-Path $rnaTarget 'mod.json'))) { throw 'Existing RNA staging mod not found' }
foreach ($rnaItem in Get-ChildItem -LiteralPath $rnaSource -File -Recurse) {
    $rnaRelative = $rnaItem.FullName.Substring($rnaSource.Length + 1)
    if ($rnaRelative -in $rnaPatch) { continue }
    $rnaInstalled = Join-Path $rnaTarget $rnaRelative
    if (-not (Test-Path -LiteralPath $rnaInstalled) -or
        (Get-FileHash -LiteralPath $rnaItem.FullName).Hash -ne (Get-FileHash -LiteralPath $rnaInstalled).Hash) {
        throw "Staging baseline differs: $rnaRelative. Review a full package update first."
    }
}
foreach ($rnaRelative in $rnaPatch) {
    $rnaFrom = Join-Path $rnaSource $rnaRelative
    $rnaTo = Join-Path $rnaTarget $rnaRelative
    Copy-Item -LiteralPath $rnaFrom -Destination $rnaTo
    if ((Get-FileHash -LiteralPath $rnaFrom).Hash -ne (Get-FileHash -LiteralPath $rnaTo).Hash) { throw "Hash mismatch: $rnaRelative" }
}
```

Do not copy repository tests/docs into staging, edit saves, or change revision.
The new subscription requires a fully restarted game/session. Native persistence of
an old subscription set across save reload is not established here: require the
five-event activation marker. If it is absent or analyzeNetwork returns nil, stop
and collect the log rather than experimenting with routing or modifying a save.

## Manual native acceptance

1. Launch after reviewed update; use a disposable test session or existing save
   without saving changes. Verify all four accepted inventories still complete.
2. Require `EVENT_SUBSCRIPTIONS_READY count=5`. Open RNA and briefly unpause for
   world readiness. Observe `Network: idle | No network analysis requested.` No
   `[RNA:NETWORK:5B1] ... START` should appear before a click.
3. Leave source/destination selections set; click Analyze Network once. Require one
   start marker and visible phase progress. Repeated clicks and Plan while busy
   must not start concurrent work. No terrain sampling should be triggered.
4. Require completed or a precise failure status. Compare town count/names/IDs and
   sampled capacity meaning with the game; inspect several recommended and omitted
   links. All zero recommendations may be legitimate with small/unknown capacities.
5. Verify potential hubs, mainlines and branches are labeled conditional; errors and
   unknown geography/demand/transport remain visible. Rail hints must not claim service.
6. Reanalyze explicitly, refresh after completion, close/reopen, then load a different
   map. Old network results must not survive session reset. Test a map over 32 towns:
   expect unsupported, not a partial national proposal. Test empty/no-rail maps.
7. Use Plan afterward to verify the existing corridor workflow. Confirm centering,
   dragging, scrolling and wrapped explanations still behave normally.
8. Collect callback timing logs and observe responsiveness, especially with large
   physical rail graphs. Record native state-copy overhead if observable. If callbacks
   visibly stall or hit the work limit, do not increase limits; review resumable
   topology/normalization before expanding scope.

Expected marker format (values depend on the map):

```text
[RNA:PLAN:4B2] EVENT_SUBSCRIPTIONS_READY count=5
[RNA:NETWORK:5B1] request=1 START world=... tick=... max_towns=32 max_pairs=496
[RNA:NETWORK:5B1] request=1 PROGRESS phase=towns
[RNA:NETWORK:5B1] request=1 PROGRESS phase=industries
[RNA:NETWORK:5B1] request=1 PROGRESS phase=rail_edges
[RNA:NETWORK:5B1] request=1 PROGRESS phase=rail_nodes
[RNA:NETWORK:5B1] request=1 PROGRESS phase=topology
[RNA:NETWORK:5B1] request=1 RESULT towns=... connections=... pairs=... astar_searches=0
[RNA:NETWORK:5B1] request=1 COMPLETE status=ok reason=Completed conditional network study. Inspect proposed and deferred links below. max_work_seconds=... timing_resolution=unverified
```

Additional phase and bounded READ_WARNING markers are expected; no per-entity dump.
Errors use `unsupported`, `error`, `invalidated`, `timing_unavailable` or
`performance_limit`, with no successful summary. The RESULT marker precedes final
guards; only COMPLETE status=ok establishes that the guarded request completed.

```powershell
$rnaLog = 'C:\Program Files (x86)\Steam\userdata\175442176\3493540\local\crash_dump\stdout.txt'
Select-String -LiteralPath $rnaLog -Pattern '\[RNA:NETWORK:5B1\]|EVENT_SUBSCRIPTIONS_READY|HANDLER_ROUTE|GUI_RESULT'
```

Remaining uncertainty: native capacity binding behavior, new subscription activation
on older saved sessions, actual GUI latency/state serialization and native scrolling
with the added text. No map overlay, automatic network-edge corridor execution,
construction or economic feasibility is added. Stop for review and real-game testing.
