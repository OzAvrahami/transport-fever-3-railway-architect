# Grouped model classification: native acceptance correction

Baseline: `main`, `c6fad5d`, initially clean. This is a targeted classification fix,
not another feature milestone. No staging, installed-file changes, construction,
save edits, commits, tags, pushes, identity or revision changes.

## Cause and supplied native evidence

The owner reported Midhurst #30564: 46 candidates, one retained, 36 rejected for
unknown conflicts, 37 town buildings. Morley #30571: 48 candidates, none retained,
33 rejected for unknown conflicts, 108 buildings. Required-region building conflict
counts were zero; many MODEL_INSTANCE_LIST records reported
`model_count_unknown_or_above_8`.

At baseline, `content/station_site_api.lua:59-76` materialized fat/thin Lua lists and
refused any total above eight before model metadata classification. Unknowns then
correctly blocked required regions through `planning/station_occupancy.lua`.
The defect was the classification cutoff, not proof that those groups were trees
or that every rejected candidate was otherwise suitable. Final revalidation used
the same adapter and inherited the cutoff. The route mask also consumed its unknowns.

No native snapshot or new real-game result was produced during this fix. **Morley
having suitable sites and a completed Midhurst-Morley corridor remain unverified.**

## Verified native contracts

Installed root: `D:\SteamLibrary\steamapps\common\Transport Fever 3`.
References below are exact relative paths and one-based installed-source lines;
`archive!member` means a read-only ZIP member, not an extracted or modified file.
Public references: [engine](https://wiki.transportfever3.com/script-doc/api/engine.html),
[types](https://wiki.transportfever3.com/script-doc/api/type.html),
[resources](https://wiki.transportfever3.com/script-doc/api/res.html).

| Contract | Installed source evidence and use |
|---|---|
| Model group vectors | `api/tealdef/api/engine.d.tl:615-627`: fat/thin instances and their native Vector variants, explicitly described as more performant access. No eight-instance limit is declared. |
| Indexing | `api/tealdef/api/type.d.tl:29-39`: `Vector:at(i)` is **one-based**, `size()` returns integer. RNA uses size/at, never bulk arrays or asTable in live classification. |
| Model IDs | `api/tealdef/api/type.d.tl:2237-2258`: both instance types' modelId references modelRep. This resource ID is not a one-based vector position and is not incremented. Zero is accepted; invalid/nonfinite/fractional/negative IDs are rejected. |
| Shipped access pattern | `base/content/gui.zip!gui/entity_window/make_entity_window.tl:710-712` uses `fatInstances_native:size()`, `:at(1).modelId`, `api.res.modelRep.get(modelId).metadata`. `gui/entity_window/view_manager_util.tl:70-77,285-300` provides further examples. |
| Resource lookup/cache scope | `api/tealdef/api/res.d.tl:9-18,75-79,142-143`: resources are generally static, IDs are repository-local, ModelRep has get(id). Read only; never mutate returned resources. All native calls are protected, with named error paths. |
| Tree versus rock | `api/tealdef/api/type.d.tl:5009-5018` declares Model.metadata. `base/content/gui.zip!gui/construction/construction.tl:3703-3706` reads metadata.tree; `gui/construction/construction_react_util.tl:2758-2767` distinguishes tree/rock metadata. RNA deliberately does not consider rock metadata provisional tree clearance. |
| Incompatible metadata | `api/tealdef/api/type.d.tl:3897-3900,3994,4053-4058` declares optional Animal, TransportVehicle, Person and Tree metadata types. `base/content/gui.zip!gui/entity_window/animal/animal_eow.script.tl:25` reads metadata.animal; `gui/entity_window/vehicle/vehicle.tl:184` reads metadata.transportVehicle. Tree plus rock/animal/person/transportVehicle is conservatively non-tree. |
| Changes during incremental reads | `api/tealdef/api/engine.d.tl:15-18,1715-1718`: getRevision(entity) returns three revision numbers tracking entity changes. `base/content/gui.zip!gui/line_vehicle_mgmt/line_manager_panel.tl:504-506` explicitly copies all three numbers. RNA compares copies before/after each chunk and across chunks, and also verifies both vector lengths. |
| Component precedence | `api/tealdef/api/engine.d.tl:97-130,295,1304-1325`: existing BASE_EDGE, CONSTRUCTION and TOWN_BUILDING contracts are unchanged. These positive hard-obstacle classifications take precedence over model metadata. |

Native bindings are invoked directly inside protected calls, with no Lua-function
type requirement. No new guessed component types, filenames or asset-name heuristics.

## Classification and continuation

`station_model_classifier.lua` owns a plain-data job. For each spatial model group:

1. Reacquire the native component/vector for this callback and verify revision/counts.
2. Inspect fat instances then thin instances in native index order.
3. Resolve each referenced model through modelRep or the current request's verified
   cached classification. Even repeated model references count as inspected visits.
4. Only a **complete** group whose every referenced resource has tree metadata and
   no listed incompatible metadata becomes `vegetation` / `all_tree`.
5. A resolved non-tree makes the outcome `mixed_non_tree`, normalized occupancy
   `unknown` (hard). An inaccessible/invalid model or revision/count change makes
   it `unknown`. No partially inspected prefix becomes vegetation.

Rocks and other assets retain hard blocking, rather than an invented precise subtype.
Missing metadata differs from a valid metadata table without tree evidence; both
remain hard, with separate diagnostics. No vegetation is removed or declared vacant.

`station_site_api.startObjects/stepObjects` supplies the existing owner with incremental
classification. A pending group's normalized record is exposed only after it finishes.
`startClear/stepClear` uses that exact implementation for final reservation checks.
Synchronous `object/clear` wrappers remain for offline contract tests only; no live
owner invokes them. No native vectors, resources, transforms, functions or coroutines
are retained in GUI continuation data.

A cache maps model ID to a small plain classification/error, scoped to the request's
world. Native resource metadata is generally static, as documented. Before final
revalidation, clear the cache and resolve encountered resources again. **Spent budgets
are not reset.** This detects changed metadata between initial and final collection;
it does not claim to detect another mod changing metadata within a collection phase.
Termination/world invalidation releases the pending job and cache. Existing freshness
and cancellation mechanisms remain authoritative; no polling or retries are added.

## Explicit work and memory limits

The API establishes variable-size vectors, not a suitable mod workload. These numbers
are conservative **RNA engineering budgets**, not TF3 capacity or railway limits:

| Limit | Meaning and rationale |
|---|---|
| 4096 instances per entity | At most 64 full 64-visit chunks; counts are checked before indexing. Larger groups remain unknown without inspecting a prefix. |
| 64 visits per GUI callback | Shared across **all groups** processed in that callback, not per entity. At most 64 resource cache misses/calls in the callback. No copied full native vectors. |
| 16 entity records per callback | Preserved existing record cap; applies even to groups rejected before inspecting instances. |
| 65536 visits per station request | At most 1024 full chunks across both town collections and final reservation checks, including repeated references/revalidation. Exhaustion leaves the remainder unknown. |
| 1024 model resource lookups per request | Includes failed and refreshed reads; cache has at most this many entries. Repeated model IDs reuse cached plain classifications, including failures. |
| Model ID 0..2147483647 | Defensive input range, not a documented repository-size maximum. No coercion or index adjustment. Out-of-policy IDs remain unknown. |

Existing caps remain: 2048 spatial records/town, 256 records/final reservation query,
48 site candidates/town, three retained sites/town, two sequential corridor studies,
16 site terrain reads/callback, 50 ms observed-work guard and **60-second** shared
station snapshot age. No timeout, terrain slope, clearance, search or score changes.

Resource-budget exhaustion fails classification conservatively; affected required-region
unknowns still block. Unrelated neighborhood-only unknowns do not automatically reject
a site. Snapshot/time guard failures stop the request under existing behavior.
Native reads, the capped spatial query and GUI state serialization are not preemptible.
Timing resolution/latency and the practical model distribution require native testing;
these caps do not prove that a callback always completes within 50 ms.

## Spatial precision and shared safety policy

Source establishes fat `transf0/transf` and transformator at
`api/tealdef/api/type.d.tl:2237-2245`; thin world position, radians rotation and uniform
scale at `:2248-2258`; Mat4f columns/transformPosition/scaleRotZTransl at `:746-829`.
`BoundingInfo` is at `:4943-4954`, and Model exposes boundingInfo **and separate collider
data** at `:5009-5016`. The BoundingInfo field comments also reverse the constructor's
min/max descriptions. Knowing these fields is not a complete conservative occupancy
contract for every grouped, transformed, animated or collider-bearing asset.

The audited shipped examples do not establish that transforming model render bounds
covers the entire physical occupancy represented by a grouped entity's native volume.
Therefore this fix **retains the original native aggregate AABB**, records
`spatialPrecision=aggregate_AABB_unresolved`, and invents no per-instance vacant gaps.
Mixed/unknown large boxes can still over-block sites or corridor samples. A separate
future contract investigation would be needed to safely narrow those boxes.

`station_occupancy.lua` changes only diagnostic flags. The shared policy is unchanged:
buildings/constructions, incompatible roads/tracks and unknowns block body/approach;
verified vegetation is provisional clearance; neighborhood-only objects are evidence.
Initial screening, final revalidation, grid masks and complete-segment validation use
equivalent normalized classes. The original 160x48 reservation, margins, road evidence,
urban observations, orientations, approach endpoints and no-town-center fallback remain.

## Diagnostics

All markers use `[RNA:STATION]`; no new React diagnostics or full arrays are sent.
Numeric placeholders below are **not predicted native results**:

```text
[RNA:STATION] MODEL_GROUPS town=30564 unique_entities=N multi_instance_groups=N instances_inspected=N all_tree=N mixed_non_tree=N unknown=N instance_limit_failures=N budget_failures=N groups_with_errors=N classification_errors=N spatial_precision=aggregate_AABB_unresolved
[RNA:STATION] MODEL_CANDIDATES town=30564 affected=N unknown_group_blocked=N total_screened=N counts=candidates_not_entities
[RNA:STATION] SHORTLIST town=30564 sites=N buildings=N existing_passenger_stations=N
[RNA:STATION] REJECT town=30564 reason=... count=N
[RNA:STATION] OBSTRUCTION_SAMPLE town=30564 candidate=... entity=... region=... class=unknown source=BOUNDING_VOLUME+MODEL_INSTANCE_LIST issue=...
[RNA:STATION] REVALIDATION town=... clear=... body_conflicts=N approach_conflicts=N vegetation_clearance=N reason=...
[RNA:STATION] MODEL_BUDGET visits=N lookups=N cache_hits=N lookup_errors=N max_group=4096 max_visits=65536 max_lookups=1024 per_callback=64 spatial_precision=aggregate_AABB_unresolved
[RNA:STATION] COMPLETE status=... reason=...
```

- MODEL_GROUPS is once per completed town collection. Unique entities include singleton
  model lists; multi_instance_groups counts only size >1. Counts are per town, so a
  group overlapping both town queries is counted in each. Higher-priority building,
  construction or edge records are reported by the existing occupancy classifications.
- instances_inspected counts actual references, not unique model resources. all_tree,
  mixed_non_tree and unknown partition normalized model-group outcomes. mixed_non_tree
  includes wholly non-tree groups and uses hard unknown occupancy.
- groups_with_errors counts unique groups; classification_errors counts failure
  occurrences, including repeated references to cached failures. lookup_errors in
  MODEL_BUDGET counts actual failed resource lookups, not cached repetitions.
- MODEL_CANDIDATES counts each candidate once if a model group intersects a required
  region. unknown_group_blocked counts candidates with at least one hard unknown model
  conflict. Neither is a unique entity count, nor necessarily the sole rejection cause.
- Existing OBSTRUCTION_SAMPLE remains at most eight unique examples/town. Final
  revalidation examples are bounded by the unchanged occupancy report. Precise issue
  paths/reasons are truncated to 240 characters. No per-instance logging.
- MODEL_BUDGET is once at terminal cleanup, including failed/invalidated requests.

## Exact changed files and relevant behavior diff

| File | Change |
|---|---|
| `oz_railway_network_architect/content/station_model_classifier.lua` | New protected native-vector continuation, revision checks, complete-group classification, shared budgets and request cache. |
| `oz_railway_network_architect/content/station_site_api.lua` | Replace eight-instance bulk classification with startObjects/stepObjects; final checks use same path. |
| `oz_railway_network_architect/content/station_plan_request.lua` | Own classifier context/jobs, incremental collection, refresh final cache, release on termination, bounded logs. |
| `oz_railway_network_architect/content/planning/station_occupancy.lua` | Two diagnostic flags per candidate; no conflict-policy change. |
| `tests/station_models_test.lua` | 14 focused native-vector/resource/revision mock tests. |
| `tests/live_plan_test.lua` | Native vector/revision fixtures, update oversized fixture, six integration regressions. |
| `tests/run_lua_tests.py` | Register classifier suite. |
| `AGENTS.md` | Current acceptance scope and classification budgets. |
| `README.md` | Current status, validation totals and report link. |
| `docs/station_site_occupancy_acceptance_fix.md` | Historical eight-instance policy explicitly marked superseded. |
| `docs/grouped_model_classification_acceptance_fix.md` | This evidence, implementation and retest report. |

Behavioral diff: `n>8 -> unknown` and synchronous bulk arrays are removed. Completed
1..4096 groups are classified incrementally using verified native indexed reads;
larger/partial/error groups remain unknown. Initial/final policy no longer differs in
how many model instances it can inspect. `git diff` contains the full tracked diff;
the new classifier, test suite and report are untracked additions until owner review.

No changes to the four inventory modules, A*/hierarchy, live terrain sampler, site
scoring, grid masks, compact player UI, event subscriptions, route/station rendering,
mod identity or revision. No call to native construction or mutation APIs was added.

## Automated verification

Baseline before edits: **412 tests**, **61 Lua files**. After changes: **432 tests**,
**63 Lua files**. Run from the repository:

```powershell
uv run --no-project --offline --with lupa==2.8 python tests/run_lua_tests.py
git diff --check
```

The harness validates Lua 5.4 syntax, local imports/resource references, callback
exports, UTF-8 without BOM, JSON, read-only metadata/identity/revision, and forbidden
construction-call patterns. Full regression suite includes all accepted planners,
inventory normalization, UI event handling, exact station approach handoff and colored
overlay lifecycle tests. Native drawing remains established only by real-game evidence.

New tests cover 1/8/9/513/4096 instances; 4097 rejection without indexing; fat/thin
one-based boundaries; last-index non-tree; rocks/incompatible tags; missing metadata,
resource failures and cached failures; zero/invalid model IDs; no partial vegetation;
revision/count changes; visit/resource budgets; cache ownership/final refresh; shared
64-visit limit across groups; initial/final/route-mask consistency; aggregate-bound
preservation; exact endpoints; no world mutation; cancellation during partial reads.

Synthetic live flow: a 129-instance all-tree aggregate spanning both neighborhoods
can produce provisional sites and a complete route, using two native resource reads
(initial and refreshed final phase). Replacing the final instance with a rock blocks
the affected sites; changing metadata to rock before final checks rejects publication.
These demonstrate the policy and continuation under mocks, **not native site success**.

## One minimal Midhurst-Morley native retest

After owner review and manual installation of the updated complete mod package
(including the new classifier), load the **same map**. No installation was run here.

1. Open RNA, select Midhurst and Morley, click **Plan Railway once**. No special UI or
   automatic retry is added. Capture the log from STATION START through COMPLETE.
2. Inspect MODEL_GROUPS for both town IDs. Confirm full inspected counts and honest
   tree/mixed/unknown outcomes; record limits/errors instead of treating them as clear.
   Compare MODEL_CANDIDATES separately from unique entities. The old
   `model_count_unknown_or_above_8` must not be produced by this code.
3. Success requires at least one shortlisted suitable site in each town **and** a
   completed station-to-station corridor. Confirm an orange source reservation, purple
   destination reservation and continuous cyan path on actual terrain. Capture a wide
   screenshot and endpoint closeups showing the route meeting each station approach.
4. Pan/rotate, Hide/Show, try a genuine available alternative, then close RNA. Check
   the existing marker cleanup and that no tracks/stations/terrain changes were created.
5. If Morley still has zero sites, capture its exact SHORTLIST, REJECT, OCCUPANCY_CLASS,
   MODEL_GROUPS, MODEL_CANDIDATES and bounded OBSTRUCTION_SAMPLE lines. Report the
   remaining categories/counts and aggregate-box precision limitation; do not lower
   slope thresholds, discard unknown blockers, invent sites or fall back to centers.

Acceptance is native visible geometry plus honest source evidence, not a passing mock
or a log claiming completion. Stop for owner review and this single focused retest.
