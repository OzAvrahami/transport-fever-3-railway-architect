# Phase 5A: evidence-filtered railway topology studies

Implemented a pure-Lua core only. No GUI network execution, inventory changes,
terrain sampling, construction, station placement or world rendering. All existing
uncommitted work is preserved; no staging updates, dependencies, commits or pushes.

## Verified data versus planning assumptions

Installed evidence was read from
`D:\SteamLibrary\steamapps\common\Transport Fever 3` without modification.
The existing inventory and corridor modules, README, AGENTS and prior reports were
reviewed. All 138 preexisting tests passed before implementation. Octocode's local
search schema was unavailable for usable queries in prior investigation; known paths
were inspected with direct reads and focused searches, including ZIP member reads.

| Input | Verified contract / limits |
| --- | --- |
| Town identity/location | Current city records contain ID, optional name, finite XYZ, status/error. Position is the bounding-volume center; it is not a station site. No population or OD demand is collected by the current scanner. |
| Residential capacity / population label | [Official engine utilities](https://wiki.transportfever3.com/script-doc/api/engine/util.html) and installed `api/tealdef/api/engine/util.d.tl:565-637` declare `getTownCapacityUsage(townEntity)` and `used`/`capacity` per land-use type. `game_mechanics.zip → game_mechanics/towns/town_util.tl:14-16,148-150` maps symbolic LandUseType plus one to Lua indices. `gui.zip → gui/statistics/statistic_towns.tl:71-79` uses **residential.capacity** in the Population column. This phase therefore names its optional input `residentialCapacity`, not measured passenger demand. |
| Other town size | [Official engine component reference](https://wiki.transportfever3.com/script-doc/api/engine.html) documents Town.initialLandUseCapacities and sizeFactors. The shipped Size column (`statistic_towns.tl:59-68`) instead derives a level from town cargo-state experience. None is automatically interchangeable with current residents or intercity demand. No new reader is implemented. |
| Reachability | `town_util.tl:153-154` calls `api.engine.util.town.getTownReachability(entity)`. `statistic_towns.tl:81-100` displays averages of commercial/industrial public or private reachability. These are supported metrics but do not establish town-pair passenger volumes, route quality or mode adequacy for a specific pair. |
| Cargo/happiness statistics | Utilities declare town delivery statistics, cargo stock and happiness/travel aggregates. Those declarations do not establish the OD-demand forecast needed here. No unverified passenger-demand API is called or invented. |
| Industries | Accepted normalized records contain ID, resource, level, construction ID, name and XYZ from construction transform translation. They do not supply economic throughput, supply-chain pairings or a reason to build rail. This core accepts a projected subset for context only. |
| Terrain | Accepted world inventory is at most 24x24 samples with height/base height/water and missing-data status. It cannot establish fine-scale alignment feasibility. Topology accepts an explicitly sourced pair-level geography assessment; it does not convert sparse samples into fictional surveyed corridors. |
| Rail topology | Accepted adapter uses `getNode2TrackEdgeMap`, BASE_EDGE/BASE_NODE and symbolic RoadType.TRACK. Normalization retains segments, endpoint IDs/positions, template, physical adjacency and candidate degrees. Connected components prove physical incidence only, not switch routing, service, station access, capacity, ownership or permission to attach. |
| Costs | No construction-cost estimation contract has been validated. No monetary cost or economic-feasibility estimate is produced. |

The pure core cannot authenticate caller claims. Every optional assessment includes
`source` and `basis = "observed" | "assumption" | "synthetic"`; these labels are
preserved in outputs, not upgraded to independently verified facts. `demandSupport`
is a caller's normalized study-support assessment in [0,1], **not a TF3 passenger
count**. The current game inventories cannot supply this field by themselves.

## Algorithm choice

| Approach | Assessment |
| --- | --- |
| MST spanning every town | Rejected: optimizes connectivity after assuming everyone must connect; missing demand, geography and alternatives would disappear from the decision. |
| General constrained/prize-collecting network optimization | Useful later, but requires calibrated benefit/cost data and a more complex solver. Not justified by current evidence. |
| Hub-first star | Rejected as default: choosing a city as a hub before screening links can force unsuitable feeders and confuse population with actual flow. |
| Evidence-filtered greedy forest, then backbone classification | Selected: bounded, explainable, deterministic and dependency-free. Each pair must qualify before graph selection. Disconnected towns/components are normal. |

This is a Kruskal-style **maximum relative-priority forest with additional degree
and edge-budget constraints**, not a minimum-cost railway solution. Those additional
constraints make it a greedy heuristic, with no global optimality claim. No external
algorithm package is used. An attempted Princeton MST reference fetch returned 403;
the decision here rests on the explicit implementation and tests, not that page.

### Pair screening and score

All unordered town pairs are evaluated once, in numeric ID order, within hard limits.
The first applicable exclusion determines the primary omission reason:

1. Coincident anchors or distance below `minDistance`: reject for this policy; compare
   road/local options first. This does not prove an existing road or a general rail ban.
2. Distance above `maxDistance`: defer beyond the study scope.
3. Different supplied regions: defer unless `allowCrossRegion` explicitly permits
   study. Region labels are supplied assessments, not inferred barriers.
4. Supplied blocked/difficult geography: defer. This is not proof of global impossibility.
5. Supplied adequate existing transport: defer new railway study.
6. Both towns near incident nodes in the same physical rail component: defer for
   reuse inspection. Do not infer an operational train service or union that graph
   into the proposed service network.
7. If pair demandSupport exists, require it to be positive and at least the configured
   threshold. Explicit low/zero support takes precedence over large town capacity.
8. Otherwise require positive residentialCapacity at both endpoints, each at least
   `minCapacity`. This only justifies a **conditional corridor study**. Missing capacity
   and missing demand yield `insufficient_evidence_not_zero_demand`, not zero demand.

For a qualifying pair:

```text
support = supplied demandSupport
       OR 0.5 + 0.5 * min(1, min(capacityA, capacityB) / majorCapacity)
distancePenalty = directXYDistance / maxDistance * distanceWeight
geographyPenalty = (supplied difficulty OR unknownDifficulty) * geographyWeight
total = support - distancePenalty - geographyPenalty
```

Missing geography remains absent in evidence; the score separately marks its
configured unknown penalty as assumed. The 0.5 capacity-proxy baseline and linear
scoring form are fixed heuristic choices, not demand estimates. Their thresholds,
scale and penalties are configurable. Only scores at least `minScore` qualify.

### Forest, mainlines and branches

Sort eligible pairs by descending total, then ascending distance, source ID and
destination ID. Add an edge only if it does not create a cycle, exceed `maxEdges`,
or exceed either endpoint's `maxDegree`. Explain every skipped edge. No requirement
exists to span every town, every eligible component or every industry.

For each selected tree, identify towns at or above `majorCapacity`. If at least two
exist, choose the longest unique tree path between those anchors. Otherwise choose
the longest tree path among all component towns. Mark that path **mainline**, and
the remaining selected edges **branch**. Equal path lengths use numeric endpoint IDs.
The length is the sum of straight XY edge distances, not rail alignment length.
These labels are relative to each component; a two-town component has a one-edge
mainline. This heuristic can miss a better traffic-based trunk because flows are unknown.

Towns incident to at least three selected links are **potential interchange hubs**.
Degree does not validate a station, switch or passenger transfer. Branches inherit
their original evidence and priority; classification does not create new demand.

Industries are matched to the nearest town only for bounded context reporting.
Their presence never changes scores or adds edges. Every industry is deferred pending
cargo flow and transport evidence; short distances suggest comparing road options.

## Input contract

Canonical module: `content/planning/network_planner.lua`.
`network.plan(input)` accepts plain tables only, copies normalized fields and never
mutates input. Invalid data returns `invalid_input` or `input_limit` with path/message
and empty decisions/recommendations; it never returns a silently truncated network.

```lua
local input = {
    unit = "world_units",
    snapshotId = "caller-owned-snapshot-id",
    source = "provenance for normalized town anchors",
    towns = {
        {id = 1, name = "Alpha", x = 0, y = 0, z = 0,
         residentialCapacity = {value = 1500, source = "synthetic fixture", basis = "synthetic"},
         region = {value = "west", source = "synthetic region", basis = "synthetic"}},
        {id = 2, name = "Beta", x = 5000, y = 0}, -- size and region may be missing
    },
    pairs = { -- optional; unique unordered pair of known IDs
        {a = 1, b = 2,
         demandSupport = {value = 0.8, source = "illustrative assessment", basis = "assumption"},
         geography = {difficulty = 0.3, blocked = false, source = "illustrative screen", basis = "assumption"},
         transport = {mode = "road", adequacy = 0.2, source = "illustrative assessment", basis = "assumption"}},
    },
    rail = { -- optional projection of valid physical inventory records
        source = "synthetic graph", basis = "synthetic",
        nodes = {{id = 10, x = 20, y = 20}, {id = 11, x = 40, y = 20}},
        segments = {{id = 99, node0 = 10, node1 = 11}},
    },
    industries = {source = "synthetic inventory", basis = "synthetic",
        records = {{id = 50, x = 100, y = 100, resource = "synthetic_logging"}}},
    preferences = {},
}
```

Required town fields: unique nonnegative integer ID and finite XY. Name and Z are
optional. `residentialCapacity.value` is an integer; all assessments require provenance.
No `population`, passenger-count or money field is accepted. Dense arrays, finite
bounded values, known references, valid enums and duplicate IDs/pairs are checked.
Conflicting reversed pair records fail instead of allowing input-order overrides.
No metatables, callbacks, native userdata or implicitly shared GUI state are accepted.

Rail nodes with no incident segment do not generate reuse hints. The nearest incident
node within `railRadius` is used, ties by ID. This is deliberately a conservative,
node-only geometric hint; no point-to-curve projection, station matching or attachment.
Different physical components never become an invented existing connection.

Inventory integration requires explicit projection and status filtering: accepted
town fields -> town anchors; `node.position.x/y` -> rail node XY; topology-valid
segments -> endpoint IDs; industry identity/resource/XY -> context. Raw scanner
states are separate and must not be assumed shared or synchronized. Incomplete
records must be reported by a future collector, not silently converted to zero.

### Default preferences (all illustrative)

| Preference | Default |
| --- | ---: |
| minDistance / maxDistance | 1000 / 20000 world units |
| minCapacity / majorCapacity | 200 / 1000 capacity units |
| minDemandSupport | 0.4 |
| maxDifficulty / adequateTransport | 0.8 / 0.8 |
| unknownDifficulty | 0.2 |
| distanceWeight / geographyWeight | 0.25 / 0.5 |
| minScore | 0.25 |
| railRadius / industryRadius | 300 / 1000 world units |
| maxDegree / maxEdges | 3 / 32 |
| maxTowns / maxPairs | 128 / 8128 |
| allowCrossRegion | false |

No threshold is a TF3 railway standard, calibrated demand rule or economic break-even
point. Exact validated ranges are in `network_input.lua`; structural caps cannot be
raised beyond 128 towns, 8128 pairs, degree 8 and 127 selected edges in this phase.

## Output contract and explainability

`status="ok"` means bounded topology evaluation completed, even when nothing is
recommended. It does not mean an economically viable or buildable network.

- `decisions`: every unordered pair, ID-sorted. Includes source/destination IDs,
  direct XY `distance`, status (`recommended`, `deferred`, `rejected`), ordered reason
  codes, evidence/provenance, limitations, infrastructure hints and optional score.
- `recommendations`: selected decisions in priority order, with classification
  (`mainline`/`branch`), ordinal `priority` (1 first), and `relativePriority=score.total`.
  Every decision carries `constructionStatus="unverified"`, scope `corridor_study_only`.
- `towns`: IDs/names/anchors, selected degree/component, reuse hints and status.
  Unselected towns say `no_new_rail_recommended_now` and aggregate omission reasons.
- `components`: includes isolated towns; selected trees have ordered mainline edge
  IDs, endpoint IDs and classification basis.
- `hubs`: potential interchange town IDs, degree and explicit operational limitations.
- `industries`: deferred context, nearest-town distance and reasons; no cargo links.
- `preferences`, `snapshotId`, `warnings` and operation `stats` make assumptions auditable.

Decision codes describe the policy, not permanent real-world conclusions. Examples:
`short_distance_compare_road_first`, `supplied_demand_support_too_low`,
`insufficient_evidence_not_zero_demand`, `geographic_difficulty_exceeds_preference`,
`existing_transport_assessed_adequate`, `inspect_existing_physical_rail_before_new_corridor`,
`redundant_cycle_in_proposed_topology`, `selected_edge_budget`, `town_degree_preference`.

## Executed synthetic example

The fixture is in `tests/network_planner_test.lua`, function `example()`.
Town 1 is at (0,0), 2 at (-4000,0), 3 at (4000,0), 4 at (0,2500), and small town 5
at (200,0). Towns 6/7 form an eastern region at (13000,6000)/(17000,6000); town 8 at
(14000,7000) has no capacity or demand evidence. All values and assessments are synthetic.

| Priority | Connection | Classification | Direct distance | Relative score |
| ---: | --- | --- | ---: | ---: |
| 1 | 1–2 | mainline | 4000 | 0.8500 |
| 2 | 1–3 | mainline | 4000 | 0.8500 |
| 3 | 6–7 | mainline | 4000 | 0.8500 |
| 4 | 1–4 | branch | 2500 | 0.56875 |

Town 1 is a potential hub with degree 3. There are two selected network components
plus isolated towns 5 and 8. The mainline in the west is 2–1–3; 1–4 is its branch.

Intentionally omitted examples:

- 1–5: only 200 units apart; compare road/local options. Other links involving town 5
  lack adequate size/demand support, so it remains unconnected.
- 2–3: near the same supplied physical rail component; inspect reuse before proposing
  another corridor. That component is not asserted to carry operational train service.
- 3–4: supplied road adequacy is 0.9, above the configured threshold.
- 1–6: different supplied regions; cross-region study is disabled by default.
- 6–8: absent capacity and pair demand; unknown is not zero.
- Nearby logging/sawmill records: no freight flow is established. Both remain deferred;
  their presence does not create a branch or assume a supply-chain relationship.

## Corridor integration boundary

```lua
local network = ug_require "oz_railway_network_architect::/planning/network_planner.lua"
local result = network.plan(input)
local handoff, reason = network.corridorRequest(result, "1:2")
```

The handoff contains snapshot/edge IDs, source/destination IDs, `pair.start` and
`pair.destination` with original XY/Z/name, plus revalidation requirements. It returns
nil for non-recommended edges. It is **not** a planner invocation, station selection,
grid-snapped endpoint or guarantee that an alignment exists.

Future integration, separately approved: user chooses one recommended edge; a single
session owner revalidates world/towns and source snapshot; it collects fresh bounded
terrain and applies the accepted short/hierarchical layout and snapping policy;
the existing corridor core may complete, reject or hit limits. Only then should
alignment findings feed back as sourced geography evidence. No all-pairs A* is run.
A regression test passes an explicit handoff to the unchanged hierarchy on fresh
synthetic terrain and verifies a complete, construction-unverified corridor.

## Performance and validation

Hard limits: 128 towns/8128 decisions; 4096 rail nodes/8192 segments; 512 industries;
160-byte provenance/name strings; coordinates within +/-1,000,000. Invalid or oversized
inputs fail before network evaluation. Edge/degree preferences are intentional network
policy limits, not monetary budgets or computation-time failures.

At most T(T-1)/2 pair screens, T*R node proximity comparisons, T*I industry comparisons
and T² backbone visits. Sorting is bounded by the pair count. Town omission aggregation
is O(T*P); bounded path reconstruction may copy up to O(T³) entries in the worst case.
No persistent cache, engine reads, A*, renderer objects or files are created. This is
a synchronous pure core: future live integration still needs native profiling and,
if necessary, incremental orchestration. No GUI latency claim is made.

Actual synthetic stress: **128 towns, 8128 pairs, 524288 rail-node comparisons,
16384 backbone visits, 127 selected edges**, with deliberately raised edge/degree
preferences and all towns carrying support. This demonstrates limits, not a policy
that real maps should connect every town.

```powershell
uv run --no-project --offline --with lupa==2.8 python tests/run_lua_tests.py
```

**163 tests pass:** all 138 previous tests plus 25 topology tests. **40 Lua files** pass
syntax checks. UTF-8 without BOM, JSON, imports, resources, callback exports, unchanged
identity/revision and `git diff --check` pass. Tests cover all requested scenarios,
including missing versus zero metrics, duplicate names, input permutations/immutability,
branch/mainline/hubs, disconnected regions, physical reuse limits, different preferences,
malformed/oversized inputs, deterministic stress, no native access and explicit corridor
handoff. A fixture expectation initially assumed both industries were nearest town 1;
distance checking correctly identified town 5 for the second industry, and the test
expectation was corrected without changing the algorithm.

## Changed files and review boundary

```text
AGENTS.md
README.md
docs/phase_5a_network_topology.md                         new
oz_railway_network_architect/content/planning/
  network_input.lua                                     new
  network_planner.lua                                   new
tests/network_planner_test.lua                          new
tests/run_lua_tests.py                                   adds suite
```

No existing production Lua module, descriptor, UI, stylesheet, inventory or corridor
algorithm was modified. No registration or staging installation is needed for offline
review; new pure modules are not invoked by the running game.

Next step: review/calibrate the policy on varied synthetic datasets, then separately
design a provenance-aware snapshot collector and explicit user-selected network-edge
handoff. Remaining limits include unknown OD demand/economics, no actual station
locations, unverified terrain between samples, node-only reuse hints, no capacity or
service routing, greediness under degree constraints, omitted useful loops and relative
mainline classification. Stop after Phase 5A for code review.
