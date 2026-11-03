# Phase 5C.2: batch corridor studies for marked Network Plan links

Implemented for review on `main`, baseline `c7dc4df`. All 223 baseline tests passed
before editing. No staging, savegame or installed-game files were changed. No commits,
tags, pushes, dependencies, construction, rendering or identity/revision changes.
Native verification of the latest panel/worklist features remains pending.

## Review and source-backed integration

Reviewed Phase 5A/5B/5C.1 contracts, immutable recommendations, worklist decisions,
handoff freshness, live request continuation, hierarchical search/cancellation and
the existing GUI transport/tests. No scoring or planner correctness change was needed.
Original recommendation `priority` is an ascending, one-based selection rank, not
a descending cost score. Unknown demand, capacity-proxy assumptions and physical-rail
limitations remain exactly as documented in the earlier reports.

Known source paths and prior verified research were reused. Octocode's previously
unusable localSearch schema was not retried; focused direct reads were used instead.
This phase introduces no native API, registration or scheduling mechanism.

Installed root: `D:\SteamLibrary\steamapps\common\Transport Fever 3` (read only).

| Contract | Evidence and use |
| --- | --- |
| GUI callback/state owner | Installed `base/tealdef/scripts/gamescript.d.tl:62-69` defines `guiUpdate(userParams, stateReadOnly, guiState)` and seven-argument `guiHandleEvent(..., src, id, name, param): any`. Re-read for this phase. The existing `live_plan.gs.lua` descriptor resolves both callbacks to the same owner. |
| Event response | Installed `api/tealdef/api/gui.d.tl:50-57`, re-read: `fireGuiScriptEvent(id, name, param): any` targets guiHandleEvent and returns its result. Continue using the existing namespaced plan event. |
| Activation and execution context | Previously verified shipped `game_mechanics/company/company.script.tl:380-389` subscribes GUI events; accepted React enqueueJoin dispatch runs on the main thread. See [Phase 5B.1 evidence](phase_5b1_live_network.md) and [Phase 5B.2 lifecycle](phase_5b2_network_corridor_handoff.md). All five RNA subscriptions and the dispatcher remain unchanged. |
| Bounded continuation | Existing `live_plan_request.start/step/invalidate` advances the authoritative short or hierarchical planner. `planning/corridor_hierarchy.lua` bounds sampling/search/final validation and supports cancellation. No coroutine, retained closure, thread or new native async API is added. |
| Fresh handoff | Unchanged `network_corridor_handoff.prepare/validate`: session/network identity, original age, endpoint XYZ, town index, map bounds and residential capacity revalidation. Existing adapters protect native reads. |

These contracts establish reuse of the existing execution path. Mocked success does
not prove native responsiveness or that four studies will fit the freshness window.

## Ownership and request contract

The existing Game Script owns `state.batch`, separately from `state.request` (manual
or individual Study Corridor) and `state.network`. `network_batch.lua` is a coordinator,
not a second planning algorithm. React owns view/control state only.

```lua
{
    world = currentWorld,
    epoch = currentEpoch,
    batch = {
        action = "start", -- or "cancel"
        requestId = nextBatchId, -- cancel uses the currently active batch ID
        networkRequestId = currentNetworkRequestId,
        snapshotId = currentSnapshotId,
        revision = currentWorklistRevision,
    },
}
```

This payload uses the existing `oz_railway_network_architect.plan.plan` event.
Mixed batch/worklist/network/manual-endpoint envelopes are rejected. Each explicit
start requires a new batch token, independent of corridor and network tokens. A
well-routed idle start consumes its token even if selection/freshness is rejected.
Busy requests cannot replace an active batch or consume its pending work. Cancellation
checks world/epoch and the active batch's ID/network/snapshot/revision; replayed or
obsolete cancellation cannot affect a newer batch.

Only original algorithm recommendations that remain included and explicitly marked
`furtherStudy` are eligible. Deferred/rejected links cannot enter the queue. Deduplicate
by canonical edge ID; sort by ascending original priority, then lexicographic canonical
edge ID. Reject zero or more than four eligible links with a precise message; never
truncate. Excluding a marked link keeps its flag but removes it from eligibility.

Accepted Start records at most four compact edge descriptors and returns immediately.
The next GUI callback validates and opens one request. Subsequent callbacks advance
that one existing continuation. Completion builds a compact summary, drops the entire
active request and returns; the next link cannot start in that same callback.

Running batches block manual Plan, individual Study Corridor, Analyze Network,
worklist edits, Refresh and another batch. Cancel is explicitly routed before the
common busy rejection. No start occurs on load, analysis completion, selection or edits.

## Freshness, cancellation and failure handling

- Every batch step checks world/epoch, network/snapshot identity and worklist revision.
- Before each link, recheck inclusion/study flag and call the unchanged handoff checks,
  read and validate both real towns, and recheck the world before creating a request.
- Network evidence expires more than 60 seconds after **collection began**, not after
  analysis completion, batch creation or the prior study. No deadline is extended.
- If expiry or changed evidence prevents the next handoff, stop and discard pending
  work. Explain that Analyze Network must be rerun; never rerun it automatically.
  Existing worklist edits and completed batch summaries remain available for review.
- An already accepted study uses the existing corridor continuation's own 60-second
  age/world/endpoint/bounds checks. Network age is checked again before the next link;
  expiration does not retroactively label a finished historical study invalid.
- `unsupported`, `unreachable`, `search_limit` and `incomplete` are recorded separately
  and may continue. They have zero presented complete candidates and no preferred
  summary. Partial alternatives are never promoted to success.
- Resource, timing, performance, invalidation or unexpected errors stop pending work.
  Even a purported `ok` result must pass the existing complete-candidate validator;
  malformed/unfinished success becomes an error and stops the queue.
- Cancel invalidates/releases the active continuation, labels it cancelled, discards
  the pending queue and retains earlier completed summaries. Cancellation is cooperative
  between GUI callbacks, never preemptive interruption of a native call.
- Map/world/tick invalidation or reactPostInit clears all batch state. Refresh and a new
  Analyze Network clear completed/cancelled batches. Closing/reopening the panel does
  not cancel owner work; fresh responses are required before displaying it again.

Stopped or cancelled batches have `remaining=0`; `notStarted` counts discarded links
that never ran. These links are not fabricated studies and have no route result.
There is no resume, automatic retry or cross-batch history. A new explicit start
replaces the old batch, subject to the same original evidence deadline.

Freshness is not atomic: same-world rail/industry edits and other-town metric changes
have the existing handoff limitations. No new data source or demand inference is added.

## Compact output and UI

Each of at most four attempted studies retains:

```lua
{
    edgeId, sourceId, destinationId, classification, priority,
    status, reason, candidateCount,
    preferred = { -- only for terminal validated complete/ok results
        id, rank, profile, length, gain, loss, gradient,
        water, waterRuns, waterExposure, score,
        start, destination, waypointCount, sections, spacing,
        sourceSnap, destinationSnap,
    },
    origin, -- copied original handoff provenance, evidence, limitations and edit decision
    constructionStatus = "unverified",
    limitations,
}
```

No completed result retains terrain grids, sample arrays, route waypoint arrays,
search state or closures. Original topology scores/classifications and worklist
decisions are never rewritten. Origin metadata is independent of subsequent edits.
`candidateCount` counts only candidates admitted by the existing complete preview
validator. Preferred means the existing rank-one candidate; no reranking is performed.

The panel adds **Study Marked Corridors** and **Cancel Batch** beneath the existing
Network Plan controls. An oversized selection has an explicit limit message and
server rejection. Existing source/destination selections, styles, centering, scrolling,
individual handoff and manual corridor summaries remain intact. Batch summaries are
separate; no route selector triggers A* or fresh sampling.

Up to 12 text lines report total selected, current edge, successful completed count,
processed count (including non-success/cancelled attempts), unsupported/unreachable
counts, pending count, not-started count, overall status and per-route outcomes/metrics.
The underlying response contains at most four compact result records. Transport failure
hides batch summaries under the existing failure/recovery behavior. Historical Mainline/
Branch labels do not become verified construction or economic recommendations.

## Performance bounds

| Scope | Limit |
| --- | --- |
| Selection | Existing maximum 31 recommendations / 32 towns; at most four accepted |
| Concurrent corridor work | Exactly one active request; never a terrain search per network pair |
| Per callback | Existing up to 16 sample visits, 64 expansions or 32 final-validation waypoints; short studies retain every-fourth callback cadence |
| Per long study | 32,768 unique samples, 65,536 visits, 49,152 expansions, three guides, 128 sections per guide, 4,096 waypoints per candidate |
| Four-study upper cumulative work | At most four times those per-study budgets, sequentially; no shared terrain cache across studies |
| Retained batch state | One bounded active continuation, four queue descriptors and at most four compact finished records; no history |
| Clock policies | Unchanged 50 ms observed-work guards and per-request age; original network collection deadline checked for every handoff |

No search/sampling/scoring limits were increased. Synchronous native enumeration,
state copying, cancellation cleanup and complete-summary validation remain nonpreemptible.
The existing work timer excludes GUI state copying and summary/log overhead; its
effective resolution is unknown. Zero readings do not prove zero work or sub-50ms
callback latency. A four-link batch may stop after one or two studies because the
network snapshot expires. Native measurements are required before changing policy.

## Automated verification and synthetic example

Executed the existing offline runner:

```powershell
uv run --no-project --offline --with lupa==2.8 python tests/run_lua_tests.py
git diff --check
```

**247 tests pass**: all 223 baseline tests plus 24 batch regression cases. Breakdown:
20 railway, 22 corridor, 20 hierarchy, 6 preview, 25 topology, 10 worklist and 144 live/GUI.
**47 Lua files** pass syntax validation. Resource/import targets, descriptor callback
exports, JSON, UTF-8 without BOM and unchanged identity/revision checks pass.

Tests cover eligibility/exclusion/unmarked/deferred links; ascending priority/ID ties;
rejection of five links and successful four-link completion; no automatic search;
single active continuation; sequential results; unsupported/unreachable/search_limit;
incomplete and malformed success; expiry between studies; next-link capacity change;
deleted/moved towns/index/bounds changes; revision changes; cancellation before/during
work; replay/busy/mixed envelopes; manual/individual studies; map reset; an 8,000-unit
route with copied GUI state; deterministic repeats; compact state; UI events/progress,
stale callbacks, unmount/reopen and malformed-response recovery. Fault-injected safety
outcomes are labeled in tests and are not claimed native events.

One executed mocked-live fixture has duplicate town names and three marked links:

| Link | Synthetic geography | Outcome |
| --- | --- | --- |
| 1:2 | Westward route; water strip from X=-2500 to -1000 across sampled region | unreachable, no preferred candidate |
| 1:3 | Eastward flat land | ok, complete preferred summary |
| 1:4 | Northward flat land | ok, complete preferred summary |

The batch reports `completed_with_failures`, selected=3, completed=2, unreachable=1,
processed=3, remaining=0. There is no retry, bridge invention or water-policy change.
These are synthetic test results, not measurements from a running TF3 map.

## Changed files and relevant diff

```text
AGENTS.md                                           scope and batch invariants
README.md                                           controls, freshness and validation
docs/phase_5c2_batch_corridor_studies.md               new report
oz_railway_network_architect/content/
  network_batch.lua                                 new coordinator
  live_plan.script.lua                              owner, routing, busy/reset/response
  live_plan_ui.script.lua                           two actions and compact status
tests/live_plan_test.lua                            24 tests and module isolation
```

Relevant integration changes (full source/diff remains in the workspace):

```diff
+local batch = ug_require "oz_railway_network_architect::/network_batch.lua"
 local function busy(state)
-    return (state.request ~= nil and not state.request.finished) or (state.network ~= nil and not state.network.finished)
+    return batch.running(state.batch) or (state.request ~= nil and not state.request.finished)
+        or (state.network ~= nil and not state.network.finished)
 end
+-- update(), once per callback after existing work:
+batch.step(state.batch, state)
+-- response():
+batchRequestId = state.batchRequestId, batch = batch.summary(state.batch),
+-- reset():
+batch.stop(state.batch, "invalidated", reason)
```

The plan-event branch validates a distinct batch envelope before the existing busy
guard, permitting identity-checked Cancel only. Start still requires idle/ready state.
All other event routes retain their guards. UI buttons use the established `send`
helper; no transport, subscription, descriptor or stylesheet is changed.

Inspect tracked changes with `git diff --` and explicitly inspect the two new files
(untracked files do not appear in ordinary git diff). Inventories, read adapters,
handoff, worklist core, A*, hierarchy, topology policy, sampling configuration and
mod metadata remain unchanged.

## Review and native acceptance

No deployment has been performed. After review, fully close TF3 and update only these
three content files together on the accepted c7dc4df staging baseline:
`network_batch.lua` (new), `live_plan.script.lua`, `live_plan_ui.script.lua`.
The previously documented local target is
`C:\Program Files (x86)\Steam\userdata\175442176\3493540\local\staging_area\oz_railway_network_architect\content`.
Verify that target/baseline before copying. Do not replace metadata, subscriptions,
styles, other content, saves or installed game resources. Restart TF3 afterward;
old in-memory worklists/batches are not migrated.

1. Confirm the existing five subscriptions and no batch START on load, Analyze
   Network, link selection or Mark for further study.
2. Quickly mark two or three included recommendations and explicitly start. Require
   `[RNA:BATCH:5C2] START batch=... total=... revision=...` once per click.
3. Require sequential `STUDY_START batch=... index=... edge=...`, then one `RESULT`
   with exact status/candidate count/reason per attempted study. There must never be
   overlapping starts; a completed batch ends with `COMPLETE ... status=...`.
4. Verify source/destination IDs and original classifications, preferred metrics,
   readable scrolling, retained manual selections and disabled conflicting actions.
5. Cancel during work; require `STOP ... status=cancelled`, no next start, preserved
   labeled completed summaries and responsive manual/individual planning afterward.
6. Let the original snapshot expire before another start; require a STOP reason
   containing `network_snapshot_expired_or_clock_unavailable; Analyze Network again`.
   Verify no automatic Analyze Network and no discarded edits.
7. Test four eligible links and explicit rejection of five, an unreachable layout,
   close/reopen while running, explicit reanalysis, and map reload. Old callbacks and
   summaries must not revive cleared state.
8. Collect actual callback/state-copy overhead and timing warnings on a large map.
   Mock execution time cannot establish native responsiveness or pixel layout.

Recommended next milestone: review this coordinator, then native acceptance of the
worklist/handoff/batch lifecycle and performance. Do not expand execution, persistence,
overlay or construction scope until that evidence exists. Stop after Phase 5C.2.
