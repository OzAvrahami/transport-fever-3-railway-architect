# Station-site occupancy: native-acceptance correction

Baseline: `main`, `b14ddce`, initially clean. This is a targeted acceptance fix.
No staging, commits, pushes, installed-file edits or game-world changes were performed.
**Midhurst–Morley success remains unverified until the owner retests TF3.**

## Confirmed cause and limits of the supplied evidence

The supplied native log records Midhurst #30564 → Morley #30571, 37 source-town
buildings, zero sites, 46 `occupied_reservation_or_approach` rejections, and zero site
terrain reads. Thus occupancy rejected those candidates before terrain evaluation.
It does **not** identify their obstructing entities or prove that trees caused them.
No copy of the live spatial snapshot was available during this correction.

At baseline:

- `planning/station_sites.lua:49–56` tested every local object against `c.clearance`,
  a 512×64 m rectangle, and immediately rejected any overlap. That rectangle was
  incorrectly treated as a mandatory clear footprint on both sides of the station.
- `station_site_api.lua:43–57` classified roads/tracks but treated every other
  non-town/world spatial entity as occupied. No positive vegetation classification.
- `station_site_api.lua:80–82` repeated the blanket test in final revalidation.
- `live_plan_request.lua:155–162` blocked samples within 80 m of **every** object box,
  including objects that would now be provisional vegetation clearance.
- Pair filtering also used the broad rectangles as mutually exclusive footprints.

Changing just one of these paths would leave contradictory rejection elsewhere.
They now share `planning/station_occupancy.lua` for region and hard-obstacle policy.

## Verified classification evidence

Installed root: `D:\SteamLibrary\steamapps\common\Transport Fever 3`. Archives were
read directly, not extracted into or modified in the installation. Public references:
[engine](https://wiki.transportfever3.com/script-doc/api/engine.html) and
[resources](https://wiki.transportfever3.com/script-doc/api/res.html).

| Classification | Installed evidence and rule |
|---|---|
| Town building | `api/tealdef/api/engine.d.tl:1304–1325`, TOWN_BUILDING. Positive component presence → building. |
| Construction | Same file `:295` onward and ComponentType.CONSTRUCTION at `:1664`. Positive presence → conservative construction blocker; no unverified compatible-construction exceptions. |
| Road / rail | Same file `:97–130`: BASE_EDGE roadType, positions; use symbolic RoadType.STREET/TRACK. Keep actual endpoint access evidence and conservative world AABB conflict tests. No fabricated chord geometry for curved edges. |
| Model instances | Same file `:615–627`: MODEL_INSTANCE_LIST fatInstances/thinInstances. `api/tealdef/api/type.d.tl:2237–2258`: both instance types reference `modelId` in modelRep. A model list alone does **not** imply vegetation. |
| Verified tree-backed vegetation | `api/tealdef/api/res.d.tl:13–18,75–79,142–143`: modelRep inherits `get(id)` returning Model; `api/tealdef/api/type.d.tl:5009–5012` exposes Model.metadata. `base/content/gui.zip!gui/construction/construction.tl:3703–3706` reads `modelRep.get(...).metadata.tree`. `gui/construction/construction_react_util.tl:2758–2767` separately checks tree/rock metadata. RNA requires **every** referenced model to have tree metadata and no rock metadata. It does not treat rocks as vegetation. |
| Unknown | No supported positive classification, mixed tree/non-tree models, empty/oversized model lists, missing metadata or resource-read error → unknown. No filenames, generic asset flags or guessed TREE component. |

Building/construction/edge classifications take precedence over model metadata.
Vegetation is recognized only for entities consisting entirely of tree-tagged models,
with 1–8 instances. This deliberately does not identify all grass/shrubs/decorations.
Above that cap, evidence remains unknown rather than being partially inspected.
Resource-read errors retain their API path in a bounded classification issue; an
unknown object is still blocked wherever required. Native bindings are called directly
under protected reads, without `type(binding)=="function"` requirements. Model metadata
is read, never changed. No native enum values or resource names are invented.

## Regions and shared conflict policy

These are explicit planning assumptions in world units, not native station geometry:

| Region | Geometry | Role |
|---|---|---|
| Station body | Original 160×48 m reservation plus **4 m per side**: 168×56 m | Hard conflicts reject. Visible reservation remains unchanged. |
| Facing approach | Along signed station axis from platform end u=80 to approach u=128, plus 4 m at both ends: u=76…132; 32 m total width | Hard conflicts remain unresolved/rejected. Includes the selected endpoint. |
| Inspection neighborhood | Existing 512×64 m rectangle | Evidence and ranking only; an object here alone does not invalidate a site. The larger urban query neighborhood is unchanged. |

- Buildings, constructions, roads, tracks and unknowns intersecting body or approach
  remain hard blockers. Unknown approach conflicts use `approach_unresolved_unknown`.
- A road near the body remains access evidence. A road AABB intersecting body/approach
  still blocks. Pedestrian accessibility stays **unknown**; crossings are not authorized.
- Verified vegetation intersecting either required region produces
  `provisional_vegetation_clearance`, not a claim that the site is empty or buildable.
  No tree removal, demolition or construction is executed or authorized.
- Unknown/building objects only in the broader neighborhood are recorded, not rejected.
  If the actual route later crosses them, they remain hard obstacles.
- Candidate-pair overlap uses body and facing-approach regions, not broad neighborhoods.

No candidate expansion was needed or implemented. The 48-candidate pattern, 3-site
shortlist, 2 actual pair studies, exact approach points, road/urban distances, sampled
slope/height limits and water exclusion are unchanged.

The newly admitted sites exposed a regression in the synthetic acceptance fixture:
nearer sites could have a clear body yet face a known obstruction immediately beyond
their approach point. The bounded shortlist now prefers sites whose **straight next
128 m exit** has no known hard intersection (12 m route margin), then uses the existing
site score/ID order. Pair ordering similarly prefers fewer blocked straight exits, then
the existing score/ID. This is a lexicographic evidence preference; it does not reject
all sites with blocked exits, change score weights or promise an A* route. No distance,
gradient or sampling constraint was relaxed to force success.

## Initial screening, final checks and route masks

Initial screening and final revalidation both call `station_occupancy.inspect` on the
same regions and classifications. Final collection queries only the union of the body
and facing approach. It no longer queries an obsolete mandatory 512×64 clearance.
The live owner classifies at most **16 final-query records per callback**, one reservation
at a time; a 256-record query cap remains. `startClear/stepClear` is the incremental
path; `clear` is the synchronous offline-test wrapper over that same implementation.
Final vegetation counts and unresolved conflicts are logged and retained as evidence.

The old 80 m mask is replaced by a **12 m route-ribbon margin** around hard object
AABBs. Verified vegetation is not a hard grid obstacle, but is recorded as potential
clearance work. This narrower mask alone would be unsafe: a segment could cross a small
building between clear grid points. Therefore every complete candidate's original
segments are checked with independent slab/rectangle intersection against all collected
hard boxes plus that margin, **16 segments per callback**, before publication. A collision
rejects the candidate; it is not presented, repaired by deletion, or silently accepted.
Vegetation intersections are reported by `CORRIDOR_OCCUPANCY`.

The search input also masks the proposed station bodies and immediate neighbors that
violate the already accepted endpoint direction test (`dot >= 0.7`). This enforces the
existing approach rule during search instead of allowing a cheap sideways departure
that final validation rejects. It does not change the A* implementation, accepted
gradient policy or endpoint coordinates. Final body/direction checks remain in place.

Checks cover the **collected local neighborhoods**, not all obstacles on a distant
corridor. Native AABBs can overestimate curved roads, constructions and model extents.
No exact native collision geometry, walking catchment, grade separation or buildability
claim follows. Same-world changes between collection and revalidation are not atomic.

## Diagnostics

Logging is once per request/shortlist, not per frame. Counts are labeled
**candidate–entity incidences**, not unique entities: one object may intersect multiple
candidates and both regions. Each class's `rejected_candidates` counts candidates with
at least one required-region hard conflict of that class, so classes can overlap.

```text
[RNA:STATION] OCCUPANCY town=30564 generated=... screened=... body_conflicts=... approach_conflicts=... counts=candidate_entity_incidences
[RNA:STATION] OCCUPANCY_CLASS town=30564 class=building body=... approach=... neighborhood=... rejected_candidates=...
```

Six class rows: `building`, `construction`, `street`, `track`, `vegetation`, `unknown`.
Street/track body and approach counts expose road/track intersections separately from
nearby neighborhood evidence. At most eight distinct entity examples per town:

```text
[RNA:STATION] OBSTRUCTION_SAMPLE town=... candidate=... entity=... region=body|approach class=... source=BOUNDING_VOLUME+... issue=...
[RNA:STATION] REJECT town=... reason=station_body_building|approach_unresolved_unknown|... count=...
[RNA:STATION] SITE ... vegetation_clearance=... clearance_status=... straight_exit_blocked=...
[RNA:STATION] PAIR ... blocked_straight_exits=...
[RNA:STATION] CORRIDOR_CONFLICT candidate=... reason=hard_building entity=...
[RNA:STATION] CORRIDOR_OCCUPANCY candidate=... hard_conflicts=0 vegetation_clearance_unverified=true|false coverage=collected_local_neighborhoods construction=unverified
[RNA:STATION] REVALIDATION town=... clear=true|false body_conflicts=... approach_conflicts=... vegetation_clearance=... reason=...
```

Final rejection additionally logs at most three `REVALIDATION_SAMPLE` records per
reservation. Existing START, SHORTLIST, COMPLETE, PERFORMANCE and renderer markers
remain. Vegetation examples can occur even for passing provisional candidates; they
are evidence of clearance work, not a rejection. Log values are not fabricated from
the supplied 46-rejection report.

## Tests and static validation

Baseline: **394 tests / 60 Lua files** passed before edits. Final: **412 tests / 61 Lua
files** pass: 11 new pure policy tests and 7 new native-adapter/owner integration tests.
All baseline tests remain. Two existing fixture expectations were corrected: the generic
occupancy reason now identifies the unknown body blocker; the no-road fixture removes
both nearby towns' roads, since a neighboring town's road is still real nearby evidence.
Failures in the test harness now include the last 21 diagnostic lines.

Coverage includes all requested body/approach/neighborhood cases; verified versus mixed
or missing tree evidence; empty/heavily occupied sites; bounded classifications/logging;
initial/final policy equivalence; incremental revalidation and cancellation; narrower
sample masks plus between-sample building rejection; unchanged endpoint coordinates,
unknown walking access, water policy, no town-center fallback, cyan/orange/purple display,
hide/show/reload, long corridors and no construction calls.

```powershell
Set-Location -LiteralPath 'D:\code\transport-fever-3\railway-architect'
uv run --no-project --offline --with lupa==2.8 python tests/run_lua_tests.py
git diff --check
```

Lua syntax, JSON, UTF-8, local resources/imports, callback exports, read-only metadata,
identity/revision and forbidden native build calls are checked. The A*, hierarchy,
geometry, inventory modules, compact UI, subscriptions and zone renderer are unchanged.
Mocks are not native acceptance.

## Exact changed files and relevant diff

```text
AGENTS.md
README.md
docs/station_aware_planning.md                    (superseding-policy link)
docs/station_site_occupancy_acceptance_fix.md      (new report)
oz_railway_network_architect/content/
  planning/station_occupancy.lua                  (new shared pure policy)
  planning/station_sites.lua                     (regions, evidence, ranking)
  station_site_api.lua                           (classification, revalidation)
  station_plan_request.lua                       (diagnostics, bounded final checks)
  live_plan_request.lua                          (consistent search masks)
tests/station_sites_test.lua
tests/live_plan_test.lua
```

Core changes, abbreviated from the diff:

```diff
- if sites.intersects(c.clearance, object.box) then reject_any_object() end
+ clear, reason, evidence = occupancy.inspect(candidate, objects)
+ -- Body/facing-approach hard conflicts reject; tree clearance is provisional.

- all non-town/non-edge entities -> occupied
+ TOWN_BUILDING / CONSTRUCTION / BASE_EDGE -> explicit hard class
+ all referenced model.metadata.tree, no rock metadata -> vegetation
+ missing / mixed / unknown evidence -> unknown (not a tree)

- final query: entire 512x64 envelope; reject first object
+ final query: body/approach union; same inspect policy, 16 records/callback

- all object boxes + 80 m -> blocked sample
+ hard object boxes + 12 m -> blocked sample
+ exact complete-segment hard-box check before publishing, 16 segments/callback
```

These snippets explain the change rather than pretend to be a complete applicable
patch; `git diff` plus the new files is the reviewable implementation.

## Minimal native Midhurst–Morley retest

After review, the owner may manually install the complete mod package using the existing
backup/hash procedure. No installation is performed by this task.

1. Load the same map, select Midhurst #30564 and Morley #30571 using their names, and
   click **Plan Railway** once. Preserve the game log from START through COMPLETE.
2. Inspect OCCUPANCY, six class rows and OBSTRUCTION_SAMPLE records. Determine what
   actually intersects body/approach, and what only lies in the inspection neighborhood.
   This is the first evidence that can attribute those native conflicts to entity classes.
3. If candidates pass, expect nonzero `site_reads` and the unchanged terrain/water
   checks. If no site or route passes, retain the precise categories; do not force success.
4. On complete success, visually inspect orange and purple reservations and cyan path
   between their exact facing approach caps. Check buildings, roads, water and trees.
   Trees may remain inside provisional reservations; no clearance has been performed.
5. Pan/rotate, switch any alternative, Hide/Show, close/reopen. All three colors must
   remain aligned and clean up as before. No station, track, removed tree or terrain edit
   should exist. Capture both station close-ups, an overview, and the diagnostic log.

Remaining limitations: real native classification composition is not yet captured;
AABB conservatism remains; non-tree vegetation stays unknown; no native pedestrian or
construction validation; sampling misses unsampled terrain details; finite shortlists
and pair budgets may miss feasible sites; exact final segment checks can reject a
grid path without exploring another search around the obstacle. The native query itself
is not preemptible. Existing 50 ms observed-work and shared 60 s age guards remain.

**Stop for owner review. Do not claim the native pair now succeeds.**
