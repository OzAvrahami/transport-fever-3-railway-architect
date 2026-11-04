# Native acceptance fix: configurable network analysis modes

Targeted correction on `main`, baseline `3249858`; the workspace was clean before
editing. Phase 6D remains the final development milestone. This is an acceptance fix,
not Phase 6E or a new feature phase. Stop after review readiness. No staging, commits,
tags, pushes, native previews, construction or identity/revision changes were made.

## Confirmed evidence and scope of the cause

Owner-supplied native evidence confirms successful mod load, five subscriptions, ten
towns, eleven industries, terrain/rail inventories, a manual corridor and geometry
inspection. Analyze Network evaluated 45 pairs with zero recommendations, no missing
capacities and no rejected towns.

For **Winterton #30562 (residential capacity 125)** and **Southwold #30563 (110)**,
approximately **5,877 XY world units** apart, the recorded decision was
`capacity_proxy_too_small_without_demand_evidence`. Both capacities are below the
existing `minCapacity=200` gate. This explains the inspected pair's decision. It does
not establish economic correctness or the causes of the other 44 decisions.

Source audit confirms:

- `planning/network_input.lua` supplies defaults including minCapacity=200 and copies
  overrides into a new validated preferences table; it is unchanged.
- `planning/network_planner.lua` checks distance, supplied geography/transport and
  physical rail reuse before the capacity gate. Without demand evidence, both known
  capacities must reach the configured minimum and be positive. Failure is represented
  as a **deferred** decision with the recorded reason; no score is computed for it.
- Previously, `network_live_request.lua` supplied only maxTowns=32/maxPairs=496 and
  therefore inherited minCapacity=200. `network_live_data.lua` also hardcoded 200 in
  its policy text. The fix changes the live input and renders effective preferences.
- Worklist, handoff and batch use world/epoch/network request/snapshot identities,
  inclusion and freshness, not a separate hardcoded 200 gate. They remain unchanged.
- Known native contracts are reused from the [Phase 5B.1 integration report](phase_5b1_live_network.md),
  [handoff](phase_5b2_network_corridor_handoff.md) and [batch report](phase_5c2_batch_corridor_studies.md).
  No new engine API, GUI extension, subscription or scheduling mechanism is introduced.
  Exact-file Octocode reads and focused local reads were used; the known localSearch
  schema limitation did not require repeating resolved native integration research.

## Accepted mode contract

The existing `oz_railway_network_architect.plan.analyzeNetwork` payload is:

```lua
{ world = currentWorld, epoch = currentEpoch,
  requestId = previousNetworkRequestId + 1, mode = "standard" } -- or "exploratory"
```

| Input | Accepted mode | Live minCapacity |
| --- | --- | ---: |
| Omitted/nil mode | standard | 200 |
| Exact string `standard` | standard | 200 |
| Exact string `exploratory` | exploratory | 100 |
| Any other string/type | Reject `invalid_analysis_mode` | No request starts |

`network_live_data.analysisMode` is the small shared validation contract. There is no
case folding, trimming, arbitrary threshold input or unknown-mode fallback. The owner
calls the collector's validated start boundary after existing busy/world/epoch/request
checks. An invalid mode does not consume a network request ID, replace a result, clear
edits or discard batch summaries. Missing mode compatibility applies to requests;
completed status metadata must explicitly identify the accepted mode and threshold.

The accepted collector stores `analysisMode` and `minCapacity` as scalars. Its existing
planner input now contains `{maxTowns=32, maxPairs=496, minCapacity=acceptedThreshold}`.
All other preferences remain supplied by the unchanged pure input defaults:

| Preference | Both modes |
| --- | ---: |
| majorCapacity | 1000 |
| minDistance / maxDistance | 1000 / 20000 |
| minScore | 0.25 |
| distanceWeight / geographyWeight | 0.25 / 0.5 |
| unknownDifficulty / maxDifficulty | 0.2 / 0.8 |
| minDemandSupport / adequateTransport | 0.4 / 0.8 |
| railRadius / industryRadius | 300 / 1000 |
| maxDegree / maxEdges | 3 / 32 |
| allowCrossRegion | false |

Live limits remain 32 towns/496 pairs. The pure default limits remain 128 towns/8,128
pairs. No global defaults are mutated, no demand is invented and no topology/scoring
algorithm changes. More candidate pairs may pass the gate in Exploratory, but distance,
evidence, reuse, score, degree, forest and edge-budget decisions still apply.

After planning, the live adapter attaches `result.analysisMode`; the existing
`result.preferences` records the effective threshold and all other preferences. The
snapshot also records `analysisMode`/`minCapacity`. The compact summary carries both
fields and validates their exact pairing. Its policy line uses actual result preferences,
not the current selector or a hardcoded threshold. Evidence, original reasons, scores
and classifications are not rewritten. No mode is injected into the pure input schema.

## UI, ownership and freshness

A native ComboBox and label sit immediately above Analyze Network, using existing
ComboBoxItem/TextView and `rna-planner-town` styling. Window centering, focus, padding,
scrolling and manual town controls are unchanged.

- Standard is the initial/default mode. The selection is local form state for the
  **next** explicit click. It survives close/reopen in the same session and resets
  to Standard on an observed world/epoch change. It is not saved to a savegame.
- Changing the selector sends no event, collects nothing, invokes no topology/A*,
  changes no result and mutates no worklist. It is disabled while busy; callbacks also
  check lifetime, session, transport and busy status.
- Analyze Network captures the selected mode in its existing main-thread dispatch.
  One click is one request; repeated/busy/replayed requests retain existing protection.
- A completed result separately displays, for example, `Network analysis mode:
  Exploratory | Minimum residential capacity: 100 | Passenger demand: unknown |
  Economic feasibility: unverified`. Selecting Standard afterward leaves this result
  labeled Exploratory until another analysis is explicitly run.
- Accepted reanalysis replaces the network continuation/result, clears worklist edits,
  old batch results and inspection state, and creates a new request/snapshot identity.
  Old worklist, study and batch tokens cannot target the replacement analysis.
- Individual Study Corridor and Study Marked Corridors continue requiring included
  recommendations, current identities, revalidated endpoint positions/capacities,
  unchanged map bounds/index and the original **60 seconds from collection start**.
  Reanalysis is explicit; changing mode never refreshes the deadline. No automatic A*
  starts on selection or Analyze Network completion.

## Synthetic before/after result

The acceptance fixture uses names/IDs/capacities from the owner report but **synthetic**
positions `(0,0,-2)` and `(5877,0,-2)`, no supplied demand, no geography assessment and
no existing rail. It is not a reproduction of the actual map's infrastructure/terrain.

| Result | Standard | Exploratory |
| --- | --- | --- |
| Capacity gate | Fails 125/110 against 200 | Passes against 100 |
| Gate reason | capacity_proxy_too_small_without_demand_evidence | capacity_proxy_justifies_conditional_study |
| Support | Not evaluated | 0.5 + 0.5 × 110/1000 = 0.555 |
| Distance penalty | Not evaluated | 5877/20000 × 0.25 = 0.0734625 |
| Assumed geography penalty | Not evaluated | 0.2 × 0.5 = 0.1 |
| Total score | None | **0.3815375**, exceeding unchanged minScore 0.25 |
| Final fixture decision | Deferred; zero links | One conditional mainline-study recommendation |

Independent arithmetic checks the original formula. The two-town fixture permits one
forest edge, so selection succeeds without forcing it. A separate pure-caller test
sets maxEdges=0: the same qualifying score is deferred as `selected_edge_budget`.
This tests existing constraints; it does not change live preferences. Another fixture
with physical rail near both anchors in the same component still defers for reuse
inspection. Unknown capacity/demand still produces no invented support.

This does **not** promise a native Winterton/Southwold recommendation. Real reuse hints,
other competing edges, graph constraints or changed snapshot data can alter selection.
Residential capacity remains a screening proxy, not passenger demand or profitability.

## Tests and static validation

Before edits: **328 tests passed**. After the fix: **341 passed**, including 13 new
grouped regression cases in the real-owner/restricted-React mock suite (173 live tests).
All **54 Lua files** pass syntax; resource/import targets, descriptor exports, JSON,
UTF-8 without BOM and unchanged mod identity/revision pass. `git diff --check` passes.
No dependency or test runner change.

```powershell
uv run --no-project --offline --with lupa==2.8 python tests/run_lua_tests.py
git diff --check
```

Coverage includes both modes and omitted default, exact invalid types/strings, global
default immutability and every other effective preference, independent score arithmetic,
graph-budget rejection, actual metadata/summary values, no selector-triggered events/A*,
busy/replay rejection, preserved completed results and edits, reanalysis identities,
stale operation tokens, same-session reopen and world reset, exclusion enforcement,
individual and sequential batch studies, 60-second expiration, unknown demand, reuse
hints, deterministic repeats and malformed-summary polling protection. A mocked live
125/110 pair also completes an explicitly requested hierarchical individual study and
one-link batch without a second capacity gate or construction claim.

Existing UI tests now identify town/candidate/link ComboBoxes separately from the new
mode selector, instead of assuming all ComboBoxes belong to those groups. The generic
native widget mock is unchanged; new tests assert both exact mode options, the total
initial form control count, default, enabled state, captured payload and selection
lifecycle. No prior regression cases were removed or skipped.

The full geometry, A*, hierarchy, rail, topology, worklist, batch and event regressions
pass. Mock success does not establish native rendering or that a real map will recommend
a specific connection. No runtime test of this fix has been performed by the assistant.

## Exact changed files

```text
AGENTS.md                                  targeted acceptance-fix scope
README.md                                  modes, reported evidence, report link
docs/native_acceptance_network_modes_fix.md new report
oz_railway_network_architect/content/
  network_live_data.lua                     strict mode contract, effective summary
  network_live_request.lua                  request preference + metadata/logging
  live_plan.script.lua                      validated start before result replacement
  live_plan_ui.script.lua                   selector and existing event payload
tests/live_plan_test.lua                    13 regressions and named control grouping
```

No changes to network_input/network_planner, worklist/handoff/batch implementations,
inventories, A*/geometry, sampling/search limits, stylesheet, event registration,
resource descriptors, manifest or metadata. Full changes are available in `git diff`;
the new report is untracked until the owner's manual commit.

## Minimal owner native retest

Next sequence: owner code review, owner manual commit/push, owner staging update and
targeted TF3 retest. Nothing was deployed automatically. With TF3 fully closed, use
the [Phase 6D complete-directory backup/hash-verified staging procedure](phase_6d_native_acceptance.md#complete-package-staging-procedure--owner-only-after-review).
The package still has 45 files; four runtime files above changed. Use the full package
procedure to avoid mixing versions. Mod identity/revision remains unchanged.

1. Load the same acceptance map and open RNA. Confirm real towns and **Standard —
   capacity threshold 200** selected. No analysis should start before clicking.
2. Click Analyze Network. Capture its START/RESULT/COMPLETE markers and result summary.
   It must show Standard/200. If conditions are unchanged, inspect pair 30562:30563
   when available in the bounded decision list and record its capacity-gate reason.
3. Make a worklist edit if this Standard result has any recommendations. Select
   Exploratory **without clicking Analyze Network**. The existing summary must still
   show Standard/200, with unchanged edits, no new request and no A*. A zero-link
   Standard result is allowed; omit the edit check if no recommendation is available.
4. Click Analyze Network once. Require a new request, Exploratory/100 in the completed
   result and cleared prior edits/batch. Inspect real decisions/reasons, not just the
   recommendation count. Record capacity, score and physical-rail evidence for the
   reported pair if exposed; the panel intentionally shows at most 24 deferred links.
5. Select Standard without analyzing again: the completed result must remain labeled
   Exploratory/100. If recommendations exist, exclude one and confirm Study is disabled;
   restore it and explicitly Study Corridor. With a fresh explicit analysis if needed,
   mark an included link and Study Marked Corridors. Capture endpoint IDs and outcomes.
   Expired evidence must ask for Analyze Network; do not extend its deadline.
6. Close/reopen to confirm form stability; load a different existing map without saving
   test changes to verify default reset and stale result/worklist cleanup. Preserve
   screenshots and stdout before another game launch overwrites the log.

Expected new log fields (counts and IDs depend on the map):

```text
[RNA:NETWORK:5B1] request=1 START world=... tick=... max_towns=32 max_pairs=496 mode=standard min_capacity=200
[RNA:NETWORK:5B1] request=1 RESULT towns=10 connections=... pairs=45 astar_searches=0 mode=standard min_capacity=200
[RNA:NETWORK:5B1] request=2 START world=... tick=... max_towns=32 max_pairs=496 mode=exploratory min_capacity=100
[RNA:NETWORK:5B1] request=2 RESULT towns=10 connections=... pairs=45 astar_searches=0 mode=exploratory min_capacity=100
```

Require the subsequent `COMPLETE status=ok`; RESULT precedes final existing safety
guards. Unexpected mode/threshold, auto-analysis, retained stale edits, bypassed expiry,
communication failures or construction claims are failures. Zero recommendations alone
is not a failure: record the actual decisions rather than relaxing another threshold.

Remaining uncertainties: mode-selector rendering and payload behavior in the actual
native runtime, real full-map graph choices under Exploratory, sampled historical
evidence and native callback timing. All prior geometry/native preview/construction
limitations remain. Stop here for owner review and targeted acceptance.
