# Phase 4A: synthetic corridor planning core

Original Phase 4A baseline: `988b756`; accepted core commit: `05f7fd4`.
Phase 4B.1 moves the authoritative source to the mod's `content/planning/` and
changes only dependency imports to the verified resource loader. The algorithm
still performs no engine reads, logging, file writes or construction. See the
[live prototype](phase_4b1_live_planning.md) for its separate collection session.
In TF3 use:

```lua
local planner = ug_require "oz_railway_network_architect::/planning/corridor_planner.lua"
local result = planner.plan(input)
```

## Input contract

Input is a plain Lua table; all nested records/arrays must have no metatables.
Unknown fields are rejected, including misspelled constraints. Arrays must be
dense and indexed from 1. Validation copies the needed data; neither input nor
module defaults are mutated. Separate calls share no search state.

```lua
local input = {
    start = {x = 0, y = 0},
    destination = {x = 20, y = 10},
    grid = {
        columns = 3, rows = 2,
        originX = 0, originY = 0, -- first SAMPLE, not a cell-boundary corner
        spacingX = 10, spacingY = 10,
        unit = "m", -- caller declares the common linear unit of X/Y/height
        cells = { -- row-major, X increasing fastest
            {height = 0, water = false},
            {height = 1, water = false, obstaclePenalty = 0.5},
            {height = 0, water = false},
            {height = 0, water = false, blocked = true},
            {height = 0, water = true},
            {height = 0, water = false},
        },
    },
    constraints = {
        allowDiagonal = true, -- default
        waterPolicy = "penalize", -- default; alternatively "exclude"
        -- maxGradient = 0.25, -- OPTIONAL illustrative rise/run cap, NOT a TF3 limit
    },
    -- Optional partial overrides; omitted fields use the documented defaults.
    profiles = {balanced = {distance = 1, gradient = 8, water = 2, obstacle = 2}},
    rankingWeights = {distance = 1, gradient = 8, water = 2, obstacle = 2},
    minDifference = 0.25,
    limits = {maxCells = 16384, maxExpansions = 49152},
    infrastructureHints = {
        {id = "fixture_node", x = 10, y = 0, verified = true, source = "synthetic_fixture"},
    },
}
```

Sample ID = `(row - 1) * columns + column`. Sample world position is
`(originX + (column - 1)*spacingX, originY + (row - 1)*spacingY, height)`.
Rectangular spacing is supported. All linear quantities must use the same unit;
the core cannot verify a caller's unit declaration. Synthetic fixtures use metres.

Start/destination X/Y must coincide with grid samples. The check permits a
world-coordinate residual up to `spacing * 1e-6` for floating-point roundoff,
then uses the reconstructed sample position. Arbitrary endpoints are rejected;
there is no nearest-cell snapping, endpoint extension or height interpolation.
Endpoint Z comes from the terrain sample, not a station/rail elevation assumption.

Each cell supports:

| Field | Contract |
| --- | --- |
| `height` | Finite number, including zero/negative. Omitted means unknown and impassable. NaN, infinity, strings and booleans are validation errors. |
| `water` | Boolean. Omitted means unknown and impassable; false remains false. |
| `blocked` | Optional boolean, default false. A caller-supplied hard obstacle; never inferred from a steepness/height threshold. |
| `obstaclePenalty` | Optional nonnegative dimensionless soft-avoidance value, default zero. Does not override hard obstacles. |

Missing cell records or array holes are invalid input; an explicit cell with
missing height/water is an unknown, excluded sample. `unknownCells` counts samples
with either missing value once, even if also blocked. A blocked/unknown/water-excluded
endpoint is unreachable under the supplied constraints, including identical endpoints.

Infrastructure hints are optional, at most 256 entries. Each requires an ID string
(1..128 bytes), source string (1..256 bytes), finite X/Y, and `verified=true`.
That flag is a **caller assertion**, not independent verification. Hints are
validated and counted only. They do not alter routes/scores or establish station
locations, track attachment, operational connectivity or ownership. Their presence
adds `infrastructure_hints_not_used_for_routing`.

## Algorithm, geometry and scoring

Three A* searches use the same hard feasibility graph. Their weights differ:

| Search profile | Distance | Gradient | Water | Soft obstacle |
| --- | ---: | ---: | ---: | ---: |
| `distance` | 1 | 0 | 0 | 0 |
| `terrain` | 1 | 40 | 8 | 8 |
| `balanced` | 1 | 8 | 2 | 2 |

These are configurable, illustrative preferences. There is **no default hard
gradient limit** and no TF3 curve-radius assumption. The fixture's optional 0.25
gradient cap means 25% rise/run, not a proposed railway engineering standard.

Moves connect horizontal, vertical and optionally diagonal neighboring samples.
Both endpoints must be traversable. Diagonal moves require both orthogonal side
samples to be traversable and, if a gradient cap is configured, both two-step
orthogonal paths around the corner to satisfy it. The diagonal itself must also
satisfy the cap. This conservative rule prevents cutting blocked/unknown/water-
excluded/steep corners; it does not resolve unsampled subcell terrain.

For a step with horizontal distance `h` and signed elevation difference `dz`:

```text
length             = sqrt(h*h + dz*dz)
gradient           = abs(dz) / h
gradientExposure   = h * gradient^2
waterExposure      = h if either endpoint is water, otherwise 0
obstacleExposure   = h * (penaltyA + penaltyB) / 2

distanceComponent  = distanceWeight * sum(length)
gradientComponent  = gradientWeight * sum(gradientExposure)
waterComponent     = waterWeight * sum(waterExposure)
obstacleComponent  = obstacleWeight * sum(obstacleExposure)
waterObstacle      = waterComponent + obstacleComponent
total              = distanceComponent + gradientComponent + waterObstacle
```

Water exposure is a conservative sampled-edge indicator, not an exact river width
or bridge span. A height below zero is not automatically water. Hard water exclusion
applies independently of weights. Zero soft weights never relax hard constraints.
Gradient exposure penalizes concentrated steepness quadratically; gain/loss are
also reported separately. Scores are relative planning values, **not construction
costs, operating costs, demand or economic feasibility**.

The A* heuristic is `distanceWeight * horizontal Euclidean distance to destination`.
Every step costs at least its weighted horizontal distance; all added penalties
are nonnegative. The heuristic is admissible and consistent on the allowed graph,
so settled nodes need no reopening. A binary indexed min-heap stores at most one
open entry per sample; decrease-key updates replace priorities instead of adding
stale entries. Selection orders by `(g+h, h, numeric sample ID)`. Neighbor order
is fixed row-major over the surrounding eight cells. Equal-cost updates keep the
first predecessor. No random numbers, wall clocks or hash-order floating sums
enter planning. Identical input gives identical results within the same Lua
numeric runtime; bitwise portability across platforms is not promised.

Each completed profile finds one optimum on this sampled graph. Candidate paths
are rescored with **one common rankingWeights table**, defaulting to balanced
weights independently of search-profile overrides. Ranking orders by total score,
then approximate length, then profile order (distance, terrain, balanced).

After ranking, identical paths merge their `generatedBy` profile names. Similar
paths are suppressed if their difference from any retained path is below
`minDifference` (default 0.25):

```text
difference = 1 - sharedUndirectedEdgeHorizontalLength / min(horizontalLengthA, horizontalLengthB)
```

The value is clamped to [0,1] for roundoff. A zero-length path only represents the
identical-endpoint case. Exact duplicates always merge even with minDifference=0.
The criterion measures distinct grid edges, not geographic separation of wide
corridors. Results contain 0..3 routes. Fewer routes mean fewer materially distinct
profile optima were found, **not proof that every possible alternative was explored**.
No artificial detour is introduced to fill a quota. Suppression is reported in
the per-profile output; near matches do not falsely claim exact shared provenance.

## Output contract

`planner.plan(input)` returns a plain table. Normal validation failures return an
error record; unexpected implementation errors propagate instead of being labeled
bad input or unreachable.

| Top-level field | Meaning |
| --- | --- |
| `status` | `ok`, `unreachable`, `search_limit`, `invalid_input` or `input_limit`. |
| `complete` | All three searches settled/exhausted for ok/unreachable; false for limits/input errors. |
| `error` | Input failures only: `{code,path,message}`. Candidates/profiles are empty. |
| `candidates` | Ranked, distinct completed routes only; never an unfinished search path. |
| `profiles` | Fixed distance/terrain/balanced order; name, effective weights, found/unreachable/search_limit status, expansions, optional reason/searchScore. Found routes also report retained/duplicate/similar disposition and candidateId or representedBy/difference. |
| `grid`, `unit`, `constraints`, `rankingWeights`, `minDifference` | Effective input assumptions without retaining the cell array. |
| `unknownCells`, `infrastructureHintCount` | Explicit input quality/context counts. |
| `stats` | cells, total expansions, peakOpen, maxCells, maxExpansions. An expansion includes popping the goal. |
| `warnings` | Stable limitation codes, including unknown samples, disabled grade cap, ignored hints or budget exhaustion where applicable. |

Each candidate contains:

- `id`: `corridor_<originating profile>`, stable for identical inputs, not a globally
  unique route identity across requests; `rank`; `generatedBy` for exact matches.
- Ordered `sampleIds` and `waypoints` containing `{sampleId,x,y,z,water}`.
- `length`: approximate 3D sampled polyline length; `horizontalLength`.
- `elevationGain`, `elevationLoss`, `cumulativeElevationChange` (their sum),
  `maxGradient` (absolute rise/run, not percent).
- `gradientExposure`, `waterExposure`, `obstacleExposure` raw scoring metrics.
- `touchesWater`, `waterSegments`, `waterRuns` (contiguous sampled wet runs), and
  `waterTransitions` with `{fromIndex,toIndex,entering}`. These indicate sampled
  water involvement; they are not bridge counts or proven crossing locations.
- `score = {distance,gradient,water,obstacle,waterObstacle,total}` under shared ranking
  weights; `searchScore` under the originating profile's weights.
- `feasibility="sampled_constraints_satisfied"`, `constructionStatus="unverified"`,
  and limitation `warnings`. There is no `buildable` claim.

On budget exhaustion, already completed candidates may remain ranked among that
subset, with status search_limit and complete=false. A truly exhausted open set is
unreachable only in this input graph, not evidence that no real-world railway is
possible. An identical, traversable start/end returns one waypoint, zero length,
zero score and a warning. Missing data is never replaced with zero elevation.

## Synthetic comparison

`tests/corridor_fixtures.lua:comparison()` uses an 11x9 grid at 10 m spacing,
start (0,40), destination (100,40). A ridge at X=50 has a high direct pass at
Y=40/Z=5, a lower pass at Y=20/Z=2 and a distant flat pass at Y=0/Z=0.
Other ridge samples have Z=20; surrounding terrain is flat. There is no water or
soft obstacle. These deliberately illustrative slopes are not railway standards.

Actual test output, common default ranking:

| Rank / candidate | Pass (X,Y,Z) | Approx. length | Gain / loss | Maximum gradient | Distance score | Gradient score | Water/obstacle | Total |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 balanced | (50,20,2) | 116.849985 | 2 / 2 | 0.141421 | 116.849985 | 4.525483 | 0 | 121.375468 |
| 2 terrain | (50,0,0) | 133.137085 | 0 / 0 | 0 | 133.137085 | 0 | 0 | 133.137085 |
| 3 distance | (50,40,5) | 102.360680 | 5 / 5 | 0.500000 | 102.360680 | 40 | 0 | 142.360680 |

The shortest route is not ranked first because the common score penalizes its
steeper sampled grade. Changing rankingWeights changes ranking independently of
the three search objectives. The tests print this table's values on every run.

## Computational and numeric limits

- Dimensions: integers 1..256; total cells at most 16,384 (configurable downward).
- Global expansion budget: 1..49,152 across all three searches. Later profiles
  can be starved by a smaller budget; output explicitly identifies this.
- At most eight neighbor attempts per expansion: at most 393,216 attempts.
  Corner checks and score calculations are constant work. Unknown/blocked samples
  never enter the heap. No search retries, random perturbations or unbounded K-path search.
- Per-search complexity O(N log N), since E <= 8N. Three searches and path comparison
  remain O(N log N) time and O(N) memory, with at most three N-waypoint routes and
  N open entries per search. The normalized grid is copied once per request.
- Coordinates and reconstructed bounds: [-1e9,1e9]; height [-1e6,1e6]; spacing
  [0.001,1e6]; distance weight [1e-6,1e6]; other weights and obstacle penalties
  [0,1e6]; optional gradient cap [0,1e6]. These numerical bounds prevent overflow
  and degenerate movement; none is a railway standard. Unit strings are 1..32 bytes.
- Cell arrays are checked before copying and over-limit grids are rejected before
  scanning cells. Missing/invalid input errors identify their path. No arbitrary
  keys, native vectors, metatables, functions or userdata are accepted as cell values.

The planner is synchronous; Phase 4A validated it on fixtures only. Hard work
limits are not a GUI latency guarantee. The 128x128 isolated-destination stress
fixture exhausts 49,134 expansions with peakOpen=348, without violating the cap.
Future GUI integration must profile and, if necessary, make search resumable before
running this workload in callbacks. No game performance claim is made.

## Validation

Run the existing harness from the repository root:

```powershell
uv run --no-project --offline --with lupa==2.8 python tests/run_lua_tests.py
```

The already cached Lua 5.4/Lupa runtime is reused; there is no new dependency or
project manifest. The suite contains 22 planning tests and 20 accepted railway
tests. It checks all requested scenarios, corner cutting, rectangular diagonals,
fine grids at large offsets, score arithmetic, independent weight overrides,
unknown data, malformed input, input immutability, determinism and hard limits.
An independent O(V^2) shortest-path selector checks all three A* profile scores
on 16 varied small fixtures (48 comparisons); it shares the transition contract,
whose geometry is separately checked against analytic expectations. Planning tests
run in a fresh Lua VM without the railway tests' TF3 mocks.

The harness also checks Lua syntax, JSON, UTF-8, package references, identity and
revision. Phase 4A preserved accepted deployable files against baseline 988b756.
Phase 4B.1 uses this same core under smaller limits and requires its own live-game
verification. The test loader resolves resource imports to the canonical files;
the original 22 synthetic tests remain unchanged.

## Original Phase 4B proposal

Phase 4B.1 implements a small subset with explicit limits. This remains the broader
design context, not a claim that all integration work is complete.

1. Establish one explicit snapshot owner/coordinator using a verified TF3 lifecycle.
   Do not read another Game Script's GUI callback state as shared storage. Prefer
   coordinated read adapters; verify any cross-script transport contract before use.
2. Define a request with world/session identity, explicit endpoint provenance and
   snapshot completeness. Town bounding-box centers are not station locations.
   Verify unit/coordinate conversions and make endpoint-to-sample approximation
   explicit; do not silently manufacture station positions.
3. Collect a bounded local terrain grid at finer, declared resolution through the
   verified read APIs, validating coordinates before sampling. Retain unknowns and
   report resolution limits; do not interpolate the existing 24x24 snapshot into
   purportedly detailed terrain. Refine the geographic area or resolution within
   the core's cell cap rather than silently truncating a map.
   Verify obstacle-data sources and masks; unavailable obstacle information must
   be reported explicitly rather than treated as an obstacle-free map.
4. Record world ID and start/end ticks, detect reload/invalidation, and document
   snapshot freshness. Multiple callback batches are not an atomic world snapshot.
   Verify an appropriate read-only consistency policy; do not pause or change the
   simulation programmatically.
5. Profile copying, sampling and planning. Add resumable, bounded search execution
   if needed, preserving deterministic results and the existing synthetic tests.
   Verify GUI state ownership and same-process reload using installed TF3 evidence.
6. Feed plain copied data to the core and log a small comparison summary. Keep
   infrastructure hints informational until operational routing/attachment contracts
   are verified. Validate against known locations and terrain in disposable games.
7. Keep construction, station placement, curves, bridges/tunnels, economics and
   automatic track attachment deferred. Verify those contracts in separate approved
   phases; a successful corridor search never authorizes world mutations.

Phase 4A was accepted. The current live prototype stops at Phase 4B.1 for review.
