# Phase 5B.2: network recommendation to corridor study

Implemented for review, without staging deployment or native-runtime claims. Existing
work is preserved. No construction, station placement, terrain changes, overlays,
dependencies, commits, tags, pushes or mod identity/revision changes.

## Correctness audit

Reviewed AGENTS, Phase 5A/5B.1 contracts and implementation, the canonical topology
core, GUI descriptors/subscriptions, request owner, UI, corridor lifecycle and tests.
All **185 baseline tests** passed before extension. Known paths and prior verified
source evidence were reused; Octocode's previously rejected localSearch schema was
not retried. No new TF3 API or registration contract is introduced.

| Audit item | Finding |
| --- | --- |
| Provenance | Town anchors are bounding centers, capacity is explicitly observed residential capacity, industry origins/resources and physical rail have source labels. Interval snapshots are not atomic. |
| Missing demand | Absent, never synthesized as zero. Existing Phase 5A evidence/limitations remain unchanged. |
| Capacity | A configurable screening proxy, not passenger demand. The fixed support formula and unknown-geography penalty remain assumptions; no economic claim follows. |
| Physical rail | Node proximity/component membership prompts reuse inspection only; no station access or operational connection is asserted. |
| More than 32 towns | Explicit unsupported result, without silently selecting a truncated network. Baseline regression retained. |
| Automatic A* | Analyze Network performs zero A* searches. Link/candidate selection also never runs a search. |
| Cross-feature response consistency | **Demonstrated blocker:** after completing a corridor, Analyze Network made `busy=true` while returning its old corridor preview. The UI's existing preview validator rejects busy previews, pausing polling. |

The blocker was reproduced with a new test (expected nil, received preview table)
before changing production code. The one-line fix suppresses corridor previews in
any busy response. Completed results remain retained by their owner and can be shown
again after the network job ends. No planner or validation rule was relaxed.

The live network snapshot now also retains its original sorted enumeration IDs, at
most 32, for handoff index comparison. Optional-inventory omission and warning
behavior is unchanged. Historical snapshots without this new field require Analyze
Network again rather than silently skipping validation.

## Architecture and verified integration

```text
Select a network link (local UI only)
  -> click Study Corridor
  -> existing React enqueueJoin + fireGuiScriptEvent(...plan, payload)
  -> existing live_plan.guiHandleEvent and shared corridor click token/busy guard
  -> resolve owner recommendation through network_planner.corridorRequest
  -> validate snapshot + reread endpoints using accepted adapters
  -> existing live_plan_request.start(world, sourceId, destinationId, requestId)
  -> existing resumable short/hierarchical terrain planning in guiUpdate
  -> existing candidate summary + separate recommendation-origin text
```

The five subscriptions and `live_plan.gs.lua` are byte-for-byte unchanged. Both GUI
callbacks still use the same script-owned GUI state. No inventory state sharing,
global mutable state, new event name, async mechanism or save data is introduced.

The established contracts are recorded in
[Phase 5B.1's native evidence](phase_5b1_live_network.md) and
[Phase 4B.2's event ownership evidence](phase_4b2_user_planning.md):

- [GUI API](https://wiki.transportfever3.com/script-doc/api/gui.html): documented
  fireGuiScriptEvent(id,name,param) and response. Installed `api/tealdef/api/gui.d.tl:50-57`.
- Installed `base/tealdef/scripts/gamescript.d.tl:67-69`: GUI update/event callback
  state and signatures. `game_mechanics/company/company.script.tl:380-389,507-508`
  establishes subscribed GUI event names and handler ownership. Existing registration
  remains `status`, `refresh`, `plan`, `analyzeNetwork`, `reactPostInit`.
- Existing `live_plan_api` supplies protected TOWN existence/component/name/position,
  bounds and world/time reads. `network_live_api` supplies protected residential capacity
  via getTownCapacityUsage and the symbolic residential index; see installed
  `api/tealdef/api/engine/util.d.tl:571-574,629` and
  `game_mechanics/towns/town_util.tl:14-16,148-150`.
- Existing Button/ComboBox/TextView styles and enqueueJoin/unmount guards are reused.
  No native window, focus, centering, scrolling or lifecycle implementation changes.

## Request and provenance contracts

The manual Plan request is unchanged. Study Corridor uses the **same** namespaced
plan event with a different payload branch:

```lua
{
    world = currentWorld,
    epoch = currentEpoch,
    requestId = currentCorridorRequestId + 1,
    network = {
        requestId = currentNetworkRequestId,
        snapshotId = currentNetworkSnapshotId,
        edgeId = "sourceId:destinationId",
    },
}
```

The client does not supply authoritative endpoint IDs or classification. The owner
resolves the ID pair from its current `recommendations` and the existing canonical
`network_planner.corridorRequest` descriptor. The edge must still be recommended.
Deferred, rejected, unknown and malformed selections fail without terrain reads.
The existing corridor token is consumed even on validation failure, so replay cannot
restart work. Busy rejection does not consume the token or replace an active job.

The accepted corridor request receives a separate plain-data `networkOrigin` copy:

- network request/snapshot/edge IDs, world/epoch and source/destination IDs;
- original anchor coordinates, classification, priority and direct geographic distance;
- original reasons, limitations, capacity/source evidence and physical reuse hints;
- original snapshot tick interval, validation timestamp, constructionStatus=unverified.

This metadata never changes corridor weights, water policy, constraints or result
classification. It survives a later replacement network analysis without aliasing its
tables. Manual Plan starts a new corridor request without network origin. The response
carries only four origin lines with matching world/epoch/corridor request ID, separately
from the existing corridor preview. No extra full graphs or routes enter status polling.

## Freshness and safety rules

Before acceptance:

1. Require a complete successful current network snapshot and matching world, epoch,
   network request, snapshot and recommendation IDs.
2. Require application time within **60 seconds of network collection start**. This
   reuses the conservative age assumption, not a claim of atomic freshness. Missing
   timing or reversed clocks reject. Status polling disables the action on expiry.
3. Confirm the endpoint IDs are in the current catalog and both still exist with TOWN
   components. The common existing reader checks this, independent of display names.
4. Compare current endpoint XYZ with their snapshot anchors, current map bounds with
   snapshot bounds, and a fresh bounded town enumeration with the retained ID list.
5. Reread both residential capacities. Missing, invalid or changed values reject and
   ask for reanalysis; missing demand remains unknown throughout.
6. Apply the observed 50 ms handoff-work guard and recheck world identity/ticks before
   invoking the existing corridor request constructor.

After acceptance, the unchanged corridor lifecycle collects fresh terrain, applies
the existing snapping policy, advances resumably and performs its own freshness and
resource checks. It does not reuse the network snapshot as a terrain grid. The network
origin remains historical evidence rather than being overwritten by alignment results.

**Limits of the freshness claim:** no verified atomic revision exists in this
integration. Same-world rail edits, industry edits, other towns' capacity/position
changes and transport-demand changes are not exhaustively rechecked at handoff.
The selected endpoint/index/bounds checks and short age window are the explicit
acceptance policy. They do not prove that the whole topology recommendation is still
optimal or every original observation is unchanged. No operational/economic conclusion
is inferred. If broader evidence changes, Analyze Network again explicitly.

Map reload/world invalidation clears owner requests/results. Close/reopen requires a
fresh response; queued callbacks check lifetime and snapshot identity. Failed studies
do not auto-retry. Original network and current corridor status remain distinguishable.

## UI behavior

The current network selector retains Mainline/Branch labels, ID-distinguished duplicate
town names, direct distance, score and reasoning. A small **Study Corridor** button
below it is enabled only for a recommended link, a usable snapshot and an idle owner.
Deferred/rejected links remain inspectable but cannot trigger Study Corridor.

The source/destination dropdown selections are not changed by a network study.
Completed alternatives use the existing corridor selector and summary. Selecting
another completed alternative performs no terrain query or A* work. Origin text
identifies the studied network edge and its classification, even if the network
selector now points at another link. Unsupported/unreachable/search_limit/invalidated
outcomes retain their actual status and do not display a successful preview.

The panel explicitly states that construction and economic feasibility are unverified.
No route visualization, building placement, station inference or world modification is
performed. Network results remain conditional studies, not approved railway projects.

## Performance and verification

Handoff work is bounded by the existing 32-town network limit and at most 31 selected
edges. It rereads only two town entities/capacities, one town index and map bounds;
there is no all-pairs terrain analysis or new global rail scan. One explicit action
starts one existing corridor continuation. Sampling, search, hierarchy and memory
budgets are unchanged. The observed 50 ms guard is not preemptive; native reads and
GUI-state copying can still block. Timer resolution and native performance remain
unverified, and zero deltas are not proof of zero work.

Executed:

```powershell
uv run --no-project --offline --with lupa==2.8 python tests/run_lua_tests.py
git diff --check
```

**201 tests pass**, comprising all 185 previous tests and 16 new cases. The existing
live/mock suite now has 108 tests. **44 Lua files** pass syntax validation. JSON,
UTF-8 without BOM, import/resource targets, descriptor exports and identity/revision
checks pass. No dependencies or test-runner changes were needed.

New regression coverage:

- Busy corridor-preview audit failure, reproduced before the one-line fix.
- Mainline/Branch handoff, exact endpoint IDs, capacity provenance and unknown demand.
- Deferred/rejected/unknown/malformed selections without terrain reads.
- One request per click, shared replay/busy protection, sequential and manual studies.
- Replaced network identity, expiry/reversed/unavailable clock, deleted/non-TOWN entities.
- Changed endpoint/capacity/index/bounds, reload and validation-time world/work failures.
- 8000-unit request using the actual hierarchy, and unsupported/unreachable/search-limit
  results using actual planners. The unsupported fixture was narrowed to exclude a
  representable fine-grid column after the first fixture correctly produced a route;
  no production constraints were altered to make the test pass.
- Restricted-context UI dispatch, duplicate names, preserved manual selection,
  candidate inspection without new reads, unmount/reopen and stale callbacks.
- Independent origin metadata after network replacement and copied GUI continuation
  state without table-identity assumptions.

The mock suite cannot establish native UI placement, subscription delivery, capacity
binding behavior or latency. Existing subscription and native read mechanisms are
reused; a real-game acceptance run is still required.

## Changed files and relevant diff

```text
AGENTS.md
README.md
docs/phase_5b2_network_corridor_handoff.md                  new
oz_railway_network_architect/content/
  network_corridor_handoff.lua                           new
  live_plan.script.lua                                  owner routing + audit fix
  live_plan_ui.script.lua                                button + origin display
  network_live_data.lua                                  snapshot/recommended UI fields
  network_live_request.lua                               retain enumeration IDs
tests/live_plan_test.lua                                 16 regressions
```

Relevant owner changes:

```diff
-preview = r and preview.valid(r.preview, state) and r.preview or nil
+preview = not busy(state) and r and preview.valid(r.preview, state) and r.preview or nil

+local sourceId, destinationId, origin = param.sourceId, param.destinationId, nil
+if param.network ~= nil then
+    origin, reason = handoff.prepare(state, param.network)
+    if not origin then return end
+    sourceId, destinationId = origin.sourceId, origin.destinationId
+end
 -- Existing endpoint checks, plus bounded handoff validation when origin exists.
-state.request = request.start(world, param.sourceId, param.destinationId, param.requestId)
+state.request = request.start(world, sourceId, destinationId, param.requestId)
+state.request.networkOrigin = origin
```

No changes to event subscriptions, descriptors, stylesheet, inventory modules, native
read adapters, topology algorithm, A*, hierarchy, terrain sampler or limits. The
handoff module is the only new deployable file. Full tracked diff is available with
`git diff --`; review the new module explicitly because untracked files are not
included in that command's output.

## Review boundary and native acceptance

Do not install until owner review. After review, fully close TF3 and update these
**five content files together**, retaining every other accepted Phase 5B.1 file:
network_corridor_handoff.lua (new), network_live_request.lua, network_live_data.lua,
live_plan.script.lua and live_plan_ui.script.lua. Keep the existing five-event
registration file and revision. Do not copy tests or documentation into staging.
No staging copy was inspected or changed by this task.

For the existing development mod, the content destination remains:
`C:\Program Files (x86)\Steam\userdata\175442176\3493540\local\staging_area\oz_railway_network_architect\content`.
Use source files from
`D:\code\transport-fever-3\railway-architect\oz_railway_network_architect\content`.
Verify baseline compatibility and copied file hashes. Restart and run a fresh Analyze
Network; an old in-memory snapshot lacks the newly retained enumeration IDs.

Acceptance steps:

1. Verify five subscriptions and all existing inventory scans. Open RNA: no network
   or corridor job starts automatically.
2. Analyze Network, inspect a Mainline or Branch and its reasons. Observe zero corridor
   searches until Study Corridor is clicked. Deferred/rejected selection disables it.
3. Click once. Require exactly one marker such as:
   `[RNA:HANDOFF:5B2] START request=1 network=1 edge=1:4 classification=branch snapshot=...`.
   Existing `[RNA:PLAN:4B2]` logs then show endpoint validation, sampling and search.
4. Compare IDs and classification with the selected recommendation. On completion,
   inspect alternatives in the existing panel. Require construction-unverified text;
   changing alternatives must not start another search.
5. Study another recommended link, including a longer pair. Confirm manual town
   selections remain intact and manual Plan still works afterward.
6. Test a failure (water barrier/limits), a snapshot older than 60 seconds, repeated
   clicks and reload during work. Require clear failure/reanalysis messages, no
   auto-retry, no concurrent work and no stale summaries after reload.
7. Run Analyze Network after a completed corridor. Status polling must remain healthy
   while the prior preview is temporarily withheld (the audit regression).
8. Check close/reopen, dragging, scrolling and actual GUI responsiveness. Record
   native logs; do not increase budgets to work around a timing failure.

Next recommended milestone: owner code review, followed by native end-to-end
acceptance of network selection -> fresh corridor -> summary, including stale-data
and mixed manual/network workflows. Broader snapshot revision tracking or geographic
feedback should be a separate scoped design after that evidence. Stop after Phase 5B.2.
