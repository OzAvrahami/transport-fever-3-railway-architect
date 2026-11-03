# Phase 5C.1: editable Network Plan

Implemented for code review; native TF3 verification is pending. No world changes,
construction, station placement, overlays, automatic batch search, persistence,
staging installation, dependencies, commits, tags, pushes or identity/revision changes.

## Review and architecture

Reviewed AGENTS and Phase 5A/5B contracts, topology result/classifications, independent
live snapshot ownership, the GUI request lifecycle and Study Corridor handoff. All
**201 baseline tests passed** before implementation. Existing source evidence and
known paths were reused; no new native API or extension contract was needed.

The existing topology result remains authoritative and unmodified. Completing an
explicit Analyze Network request creates a separate `state.worklist` in the same
GUI Game Script owner. Its new pure-Lua module, `network_worklist.lua`, stores:

- World ID, GUI epoch, network request ID, snapshot ID and edit revision.
- Sorted town IDs and copied original edge IDs/endpoints/classification references.
- An override map keyed by canonical unordered entity-ID pair.
- A recalculated bounded graph, independent of the original topology result.

Scores, evidence and reasons stay in `state.network.result` and its existing summary;
the worklist never rewrites them. The UI reuses the current network connection selector
to view that original evidence alongside edit state. No inventory callback state is
shared, and no global mutable state, engine-state data or GUI save data is introduced.

Only **algorithm-recommended connections** are editable in this phase. Deferred and
rejected pairs remain informational. There is no arbitrary edge creation or promotion
of a rejected pair to a new recommendation.

## Edit semantics and provenance

| Action | Membership | Study flag | Provenance |
| --- | --- | --- | --- |
| Initial recommendation | Included | False | Algorithm/original recommendation |
| Include in plan | Included | Retained | User/include |
| Exclude from plan | Excluded | Retained | User/exclude |
| Mark for further study | Unchanged | True | User/mark_study |
| Restore original recommendation | Included | False | Override removed; algorithm default restored |
| Reset all edits | All original recommendations included | All false | All overrides removed |

Every current override records `actor="user"`, the last action, accepted revision
and GUI world tick. Its enclosing worklist supplies world/snapshot identity. Explicit
Include remains a user override even when it matches the original inclusion choice.
Restore clears both membership and study decisions for that link. There is no separate
unmark action; Restore clears the flag. Marking an excluded link does not include it
or run a search.

Only current decisions are retained, not an unbounded history of every click. Reset
and Restore still advance the revision, preventing replay of earlier operations.
All changes use copy-on-accept: rejected operations cannot partially alter the old
worklist, and accepted changes never mutate the original recommendation tables.

## Event and session contract

The five existing subscriptions, resource descriptors and GUI transport are unchanged.
Edits use the existing namespaced `plan` event with a distinct payload branch:

```lua
{
    world = currentWorld,
    epoch = currentEpoch,
    worklist = {
        networkRequestId = currentNetworkRequestId,
        snapshotId = currentSnapshotId,
        revision = currentWorklistRevision,
        action = "include", -- exclude, restore, mark_study, reset_all
        edgeId = "1:4",     -- omitted for reset_all
    },
}
```

The existing `react.enqueueJoin -> fireGuiScriptEvent -> guiHandleEvent` path carries
both the request and response. See the verified contracts in
[Phase 5B.2](phase_5b2_network_corridor_handoff.md) and
[Phase 5B.1](phase_5b1_live_network.md). This adds no event mechanism or TF3 binding.

The owner synchronizes world identity/ticks, then applies the existing shared busy
guard. It rejects stale world/epoch/network/snapshot identities, unavailable worklists,
unknown links/actions, malformed reset operations and mismatched edit revisions.
Payloads combining worklist edits with network handoff or manual endpoint selection
are rejected as ambiguous. Accepted edits increment the revision once and return
before corridor request-token handling; neither corridor nor network request IDs
are consumed. No A*, terrain sampling or topology-policy rerun occurs.

The UI coalesces pending dispatches, checks lifetime and current snapshot/revision,
and rejects callbacks retained from a replaced or already edited view. The backend
revision check independently prevents duplicate acceptance. Communication errors pause
polling under the existing behavior; malformed worklist responses cannot populate it.

Worklists clear immediately when a new Analyze Network request is accepted, on Refresh,
map reload/reactPostInit or verified world invalidation. A successful replacement
analysis creates a new revision-zero worklist. A failed replacement cannot restore old
edits. Close/reopen preserves session-owned edits but requires a fresh response;
closing drops queued, undispatched UI operations. Nothing is persisted to savegames.

Review edits are allowed on the latest completed snapshot after its 60-second
**corridor handoff** age expires. This is editing historical planning data, not asserting
fresh world evidence. It does not extend the original age, update capacity/demand or
permit a stale Study Corridor request. Reanalysis explicitly discards those edits.

## Graph consistency rules

The edited graph contains only included proposed links. It is an undirected graph
of proposed town-to-town connections, not the game's track graph or train routing.

After creation and every accepted edit:

1. Build deterministic adjacency and count included/excluded edges, user overrides
   and further-study flags.
2. Use union-find to identify components, including isolated towns, and independent
   cycles. Components and their town IDs are sorted deterministically.
3. Recalculate degree; degree zero identifies unconnected towns and degree at least
   three identifies potential interchange hubs. These are not validated stations.
4. Find connected groups of retained **original branch** edges. Report their shared
   town nodes with retained **original mainline** edges. A branch group with no such
   nodes is detached from the remaining original mainline proposal.
5. If membership differs from the original proposal, or source duplicates/cycles
   exist, mark the original Mainline/Branch interpretation
   `historical_only_reassessment_required`. Labels themselves never change.

The interpretation warning is conservative across the worklist; it does not imply
that every unaffected component needs a new label. Restoring all membership clears
that warning when the original source is consistent. A study flag or explicit Include
override alone does not change the graph's membership or invalidate its original
relative interpretation. All classifications remain unverified in either case.

Duplicate references are identified by canonical unordered entity-ID pair. Identical
or reversed repeated references count once; conflicting duplicate classifications are
rejected. Malformed references, missing endpoints, oversized/sparse arrays and invalid
classifications are rejected without truncation. A cycle counter is retained even
though normal editing of a forest subset cannot create cycles. Duplicate/cycle tests
use deliberately malformed/synthetic source proposals; the UI cannot add these links.

No procedure forces all towns to connect, reassigns new mainline labels or fabricates
economic justification. Missing demand remains unknown and original capacity proxy
assumptions remain unchanged.

## UI and corridor behavior

The existing centered, draggable and scrollable native window and stylesheet are
unchanged. A **Network Plan** section shows included/excluded/override/study counts,
components, unconnected town IDs, potential hub IDs, duplicate/cycle counts and the
classification warning. Original network counts/reasons remain visible above it and
are distinguished from edited counts.

The existing selector appends inclusion, decision actor and further-study status to
proposed entries. Selecting a link shows its original Mainline/Branch classification,
current override action and branch attachment relationship. The section adds five
existing-style native buttons: Include, Exclude, Restore, Mark for further study and
Reset all edits. Link-specific buttons are disabled for deferred/rejected entries;
Reset all remains available for the current worklist. All edits are disabled while
a corridor or network job is running.

Study Corridor is disabled and rejected by the backend for an excluded link. Restoring
or including it re-enables the accepted handoff, subject to all previous freshness
checks. The original recommendation classification/evidence remains unchanged; a
separate `networkOrigin.worklistDecision` captures the revision, decision/provenance
and interpretation warning at acceptance. Later edits never rewrite that record or
recompute a completed corridor. Existing completed summaries can remain visible and
are explicitly historical; excluding their link does not erase the study.

Manual town-pair Plan remains independent and does not auto-include links in the
worklist. No edit, flag, selector switch or reset automatically runs corridor planning.

## Bounds and verification

- At most 32 towns and 31 original proposed links per worklist.
- At most one override record per link, one graph and one compact response; no edit
  history or route/terrain arrays are added. Revision limit: 1,000,000, then reanalyze.
- Graph recomputation happens only on creation/accepted edits. Graph and branch
  traversals are bounded by those caps; current lookup/projection helpers may do at
  most quadratic work in 31 edges. Status polling only builds a small presentation.
- Responses contain at most 31 entry states and six summary lines. The existing
  original-network summary bounds and corridor budgets remain unchanged.
- Edits add no native reads beyond the existing event owner synchronization/response
  checks. Native state copying, UI layout and event handling remain non-preemptible;
  no native latency guarantee is claimed.

Executed:

```powershell
uv run --no-project --offline --with lupa==2.8 python tests/run_lua_tests.py
git diff --check
```

**223 tests pass:** all 201 baseline tests, 10 new pure worklist tests and 12 new
live/GUI integration tests. **46 Lua files** pass syntax checks. UTF-8 without BOM,
JSON, resource/import references, callback exports and unchanged metadata checks pass.

Pure tests cover defaults, include/exclude/restore/reset, original and prior-state
immutability, user provenance, independent study flags, detached branches, hub/component
recalculation, reversed duplicates/conflicts, cycles, stale/replayed operations,
empty/disconnected graphs, deterministic permutations and hard limits.

Integration tests cover independent creation, immutable original result/summary,
sequential edits, world/snapshot/revision rejection, busy jobs, ambiguous/deferred
operations, Refresh/reload/world invalidation, copied GUI state, Study Corridor gating
and historical provenance, expired-snapshot review without refreshed evidence, UI
actions/selection/centering, stale callbacks, close/reopen and communication failure.
Height-read counters and request markers verify no automatic corridor work. All
existing topology, rail inventory, A*, hierarchy and GUI tests still pass.

The mock suite does not prove native layout, delivery or responsiveness. Real TF3
verification is still needed for the longer scrollable form and state-copy overhead.

## Changed files and relevant diff

```text
AGENTS.md
README.md
docs/phase_5c1_network_worklist.md                       new
oz_railway_network_architect/content/
  network_worklist.lua                                 new pure module
  live_plan.script.lua                                owner lifecycle/edit routing
  live_plan_ui.script.lua                             Network Plan controls/view
  network_corridor_handoff.lua                         inclusion/provenance guard
tests/
  network_worklist_test.lua                            new pure suite
  live_plan_test.lua                                   12 integration regressions
  run_lua_tests.py                                     registers pure suite
```

Relevant owner flow (the original result is not overwritten):

```diff
 network.step(state.network)
+if state.network.finished and state.network.status == "ok" then
+    state.worklist, state.worklistError = worklist.create(state.network.result, state)
+end

+if param.worklist ~= nil then
+    -- After existing world/busy checks; validate envelope and current snapshot.
+    edited, reason = worklist.edit(state.worklist, param.worklist, state.tick)
+    if not edited then return end
+    state.worklist = edited
+    accepted = true; return -- never reaches corridor request creation
+end
```

Relevant handoff guard:

```diff
+decision = worklist.decision(state.worklist, selected.edgeId)
+if decision and not decision.included then
+    return nil, "connection_excluded_from_network_plan"
+end
 local descriptor, why = core.corridorRequest(n.result, selected.edgeId)
```

No changes to subscription/resource descriptors, native read adapters, inventory
modules, network selection policy, A*, hierarchy, terrain sampling, budgets or
stylesheet. Full tracked changes are available through `git diff --`; inspect the
new module/test/report explicitly because untracked files are not shown there.

## Native review checklist and next step

No staging installation was performed. After owner review, any approved update must
include the new network_worklist.lua and the three changed content files together,
on the complete accepted Phase 5B.2 baseline. Leave identity/revision and the five
event subscriptions unchanged. Restart TF3 and Analyze Network to create a new
worklist; do not expect old in-memory results to be migrated.

1. Confirm no new searches on load or edits. Require one
   `[RNA:WORKLIST:5C1] CREATE network=... status=ok` per successful analysis.
2. Exclude a hub-adjacent link and check components, unconnected towns, candidate hubs
   and the original-classification warning. Verify reasons/evidence have not changed.
3. Mark an excluded link: it remains excluded and runs no search. Include it, Restore
   it and Reset all; verify explicit revision changes and original defaults.
4. Require one bounded `[RNA:WORKLIST:5C1] EDIT network=... revision=... action=... included=... components=...`
   per accepted click, with no per-frame graph logs.
5. Try editing during network/corridor work and replaying a stale view. Confirm no
   conflicting operation, duplicated acceptance or automatic retry.
6. Study an included recommendation, inspect its historical worklist provenance, then
   edit after completion. Verify no re-search. Manual Plan must still work independently.
7. Close/reopen, Refresh, reanalyze and reload another map. Edits survive window close
   only; replacement snapshots/reset clear them. Verify scrolling and wrapped text.

Known limits: worklists edit only existing recommendations; no arbitrary new links,
undo history or persistence; conservative global classification warning; branch
relationships are proposed shared-town topology only; world evidence remains an
interval snapshot with Phase 5B.2's known freshness limitations. No construction or
economic feasibility follows from inclusion.

Next recommended milestone: code review and native acceptance of editing, graph
warnings and Study Corridor interaction. Evaluate any broader edit/persistence design
only after that evidence. Stop after Phase 5C.1.
