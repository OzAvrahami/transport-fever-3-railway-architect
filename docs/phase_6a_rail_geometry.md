# Phase 6A: railway geometry and construction feasibility foundation

Baseline: `main`, `5f508ea`. Initial working tree was clean. All 247 baseline tests
passed before changes. This milestone audits contracts and implements one isolated
pure-Lua mathematical prototype. No live script imports it. No native proposal is
created or evaluated, no command constructor or dispatcher is called, and no staging,
savegame, installed resource, identity, revision or Git history is modified.

## Evidence classification and scope

- **A — explicit contract:** official TF3 documentation or installed API declarations.
- **B — shipped implementation:** behavior visible in installed TF3 Lua/Teal scripts.
- **C — prototype assumption:** our fitting policy, bounds or caller-supplied engineering preference.
- **D — unresolved:** not established by those sources or not verified in a running game.

Inspected read-only root: `D:\SteamLibrary\steamapps\common\Transport Fever 3`.
All line numbers below are one-based in the currently installed files or decoded ZIP
members. Paths before `!` identify archives; paths after it identify members. Archives
were read without extracting into or modifying the installation. Octocode localSearch
rejected its query schema; focused searches/direct reads provided the source evidence.

Reviewed AGENTS, the Phase 4A contract, long-distance hierarchy, preview restrictions,
Phase 5 network/worklist/batch contracts and the existing regression runner. No planner
bug justified changing accepted search, scoring, terrain sampling or request ownership.

## Verified API and shipped-source findings

| Subject | Evidence, exact location and interpretation |
| --- | --- |
| Ordinary rail representation **A** | `api/tealdef/api/engine.d.tl:97-130`: BaseEdge has node0/node1, position0/position1 and tangent0/tangent1 as Vec3f, edge type/typeIndex, laneConfigs, distance, roadType, roadTemplate and roadStyle. `:156-163`: BaseNode.position is world-space. TRACK versus STREET is a symbolic RoadType distinction. [Official engine reference](https://wiki.transportfever3.com/script-doc/api/engine.html). |
| Ordinary track authoring example **B** | `base/content/mission.zip!mission/tasks/auto_builder/track_builder.tl:7-56`: creates SimpleProposal, NodeAndEntity and SegmentAndEntity; sets endpoint node IDs and XYZ positions, both tangents, symbolic NORMAL/TUNNEL, segment discriminator 1 for rail, laneConfigs/template/style and symbolic RoadType.TRACK. It reuses supplied existing node entities or adds new nodes. `:60-74` obtains resolved nodes only after a separately dispatched build command. Those command calls were read, never executed or copied into RNA. |
| Existing-edge geometry transfer **B** | `base/content/mission.zip!mission/tasks/auto_builder/prepare_track_building_util.tl:5-16` copies all four vectors directly from BASE_EDGE into a serialized segment. Its later file-writing helper is not used. This establishes vector identity, not an engine interpolation proof. |
| Tangent orientation **B** | `base/content/gui.zip!gui/entity_window/view_manager_util.tl:7-21` uses tangent0 at node0 and negated tangent1 at node1 to get outward directions. Thus tangent1 itself follows the segment's forward direction; it is not already the backwards/outward end vector. |
| Construction-owned edges **A/B** | [Construction Basics, Edge Lists](https://wiki.transportfever3.com/doku.php?id=modding:constructions:basics#edge_lists) describes paired local positions/tangents, template references and zero-based snap/free-node indices. `base/content/scripts.zip!scripts/construction/constructionutil.lua:40-87` builds edgeLists, independently of the ordinary SimpleProposal mechanism. Construction-local points require a transform to world space; lists/indices cannot be substituted for native node entity references. |
| Hermite convention **B** | `base/content/scripts.zip!scripts/mathutil.lua:39-55` gives scalar cubic Hermite interpolation and its derivative on a normalized parameter. `scripts/vec2.tl:74-111` implements the vector counterpart; `base/tealdef/scripts/vec2.d.tl:66-81` explicitly declares parameter [0,1]. `scripts/construction/constructionutil.lua:48-61` maps straight, quadratic and cubic control points to endpoint derivatives using factors 1, 2 and 3. Both endpoint tangents are forward derivatives, with dimensions of position per dimensionless parameter. |
| Shipped fitting choices **B, not universal rules** | `base/content/scripts.zip!scripts/construction/street_util_serialized.tl:5-15,18-67` scales tangent hints by chord/angle, assigns a chord vector to straight-edge tangents and creates ramp endpoint tangents. `base/content/infrastructure/street_construction.zip!street_construction/street_constructions.script.lua:34-73` explicitly uses a cubic Hermite midpoint. Its subsequent ramp/subdivision shaping is not adopted as an exact general subdivision algorithm. |
| Transport-network geometry **A** | `api/tealdef/api/type.d.tl:1028-1109` exposes XY ARC/STRAIGHT/CUBIC_SPLINE/CUBIC_OFFSET_SPLINE, separate vertical tangents/heights, and calcPos(geom, param) returning position/tangent/second derivative. `:1112-1123` stores geometry and speedLimit/curveSpeedLimit on a transport-network Edge. This is a different record from BaseEdge. No exact ordinary BaseEdge-to-transport-geometry conversion, arc-length parameterization or vertical reinterpretation was established. [Official type reference](https://wiki.transportfever3.com/script-doc/api/type.html). |
| Resource-derived constraints **A** | `api/tealdef/api/type.d.tl:5478-5555`: StreetTemplate controls lanes, embankment slope settings, maxSlope, maxSlopeShape, minCurveRadius, minCurveRadiusBuild, maxSlopeBuild, speedCoeffs and catenary template substitutions. Comments distinguish the resulting shape from player-build constraints. The comments do not expose every native acceptance rule or the speedCoeffs equation. |
| Concrete track configuration **B** | `base/content/infrastructure/track.zip!track/standard/standard.street_template.lua:25-38,48-59`: lane speed about 44.44, maxSlope about 0.13, maxSlopeBuild about 0.085, maxSlopeShape about 0.16, minCurveRadius 40, minCurveRadiusBuild 55, trackDistance 5 and three speed coefficients. These are installed resource values, not universal railway standards, proof of enforcement, or defaults introduced into RNA. |
| Incline UI **B** | `base/content/gui.zip!gui/construction/construction_react_util.tl:241-251,294-301,2267-2285` derives the incline slider from maxSlopeBuild and formats it as a percentage. `api/tealdef/api/type/transformator.d.tl:442` describes slope 1 as 45 degrees. This supports a rise/horizontal-run interpretation; exact native sampling/enforcement remains unresolved. |
| Electrification **B** | Ordinary mission builder `track_builder.tl:42-47` resolves a catenary street_template and copies its lanes/style. Standard template `:10` points to catenaryAdd; `track/standard/standard_catenary.street_template.lua:10,25-32` defines catenaryRemove and electric transport modes. Do not invent a standalone BaseEdge catenary boolean by copying construction edgeLists examples. |
| Terrain and earthworks **A** | `api/tealdef/api/type.d.tl:2422-2435` declares TerrainAlignment; `:2478-2489` Context includes checkTerrainAlignment, cleanupStreetGraph, gatherBuildings/gatherFields, player and pillar-redo options; `:2654-2679` separates proposal terrain modifications. `:2750-2758` exposes terrain-preview cut/fill data and costs. StreetTemplate embankment fields are at `:5516-5523`. Construction Basics documents construction edge alignTerrain; it is not a BaseEdge field. No earthwork solver or volumetric/cost estimate is implemented. |
| Bridges/tunnels **A/B** | `api/tealdef/api/type.d.tl:462-465` declares edge modes; `:5036-5074` declares carrier compatibility, speed cap, tunnel height, pillar and abutment dimensions. `api/tealdef/api/res.d.tl:124,147,154` declares bridge/street-template/tunnel repositories. `base/content/infrastructure/bridge.zip!bridge/steel.bridge.lua:259-273` has speed/pillar configuration; `base/content/infrastructure/tunnel.zip!tunnel/tunnel_a.tunnel.lua:154-155,196` defines portal configuration and height. [Official bridges/tunnels documentation](https://wiki.transportfever3.com/doku.php?id=modding:infrastructure:bridgestunnels) explains these resources and generated geometry. Carrier, clearance, portal and pillar acceptance cannot be inferred merely from an edge mode. |
| Connecting existing nodes **B/D** | Mission `track_builder.tl:10-24,31-32,49-56` reuses supplied node entity IDs and adds only missing nodes. It does not establish nearest-track snapping, safe mid-edge splits, ownership permissions, station suitability or operational switch connectivity. Its fixed tunnel typeIndex=1 at `:36` is example-specific and must not become a general resource index. |
| Native proposal layers **A** | `api/tealdef/api/type.d.tl:2511-2559`: processed Proposal.StreetProposal stores addedNodes/addedSegments and removed records. `:2761-2804`: SimpleStreetProposal uses nodesToAdd/edgesToAdd/removal IDs with negative temporary IDs. `:2662-2663` embeds the processed graph as Proposal.proposal; `:2857-2858` embeds the simple graph as SimpleProposal.streetProposal. These contracts differ from each other and from construction edgeLists. |
| Applying proposals **A** | `api/tealdef/api/cmd.d.tl:953-962` declares separate Proposal and SimpleProposal overloads of makeWorldBuildProposalCmd(proposal, context, ignoreErrors, playerInitiated, doDust?). Command execution applies changes; it is not a validation call. `:2-10` distinguishes immediate engine-state execution from deferred GUI/console execution. [Official command reference](https://wiki.transportfever3.com/script-doc/api/cmd.html). No constructor/dispatcher is called in Phase 6A. |

### Rules that remain unresolved

**D — minimum usable segment length:** no general ordinary-rail minimum was found
in the inspected declarations, scripts, templates or official pages. Bridge model
interval/subdivision sizes are not a general minimum track edge length. The prototype's
minimum horizontal chord is a numerical guard, not a claimed TF3 threshold.

**D — radius/speed and gradient enforcement:** resources expose settings and resulting
network edges expose curvature speed limits, but the precise radius-to-speed equation,
measurement points, switch exceptions, hard/soft rejection policy and interactions
between slope fields were not found in accessible implementation code. Do not substitute
a real-world speed formula, a TF2 formula or a chosen percent limit.

**D — full geometry equivalence:** shipped Hermite helpers and ordinary endpoint/tangent
records justify an offline candidate representation. They do not prove that every
ordinary track uses precisely the prototype's XYZ polynomial internally. Native XY
geometry and vertical data may be processed independently. Conversion to native float
precision, subdivision, snapping, distance fields and validation tolerances remain open.

**D — clearance/terrain/buildability:** endpoint heights and sampled gradients cannot
prove swept clearance, cut/fill acceptability, ground support, water crossing permission,
portal placement, pier spacing or attachment topology. No such claim follows from tests.

## Non-mutating validation audit and future gate

The documented engine module offers read-only access in GUI and engine states. Its
installed declaration at `api/tealdef/api/engine/util.d.tl:924-925` is exactly:

```text
makeProposalData(proposal : Proposal, context? : Context) : ProposalData
```

[Official proposal utility reference](https://wiki.transportfever3.com/script-doc/api/engine/util.html).
It exposes proposal-data processing without a command submission. The signature accepts
**processed Proposal**, not a documented SimpleProposal overload. No direct shipped call
was found in the inspected base/scripts/GUI/mission/game-mechanics and relevant infrastructure
archives. That absence is a scoped search result, not proof the API is unusable.

`api/tealdef/api/type.d.tl:2693-2758` describes collisionInfo, errorState (critical,
messages, warnings, infos), entity2tn, terrain preview and costs. These are the future
result fields to inspect, not a single invented `isBuildable` boolean. The declarations
do not state that an empty error list certifies operational routing or future success.

**B — native preview path:** `base/content/gui.zip!gui/entity_window/bridge_and_tunnel.tl:126-138`
passes an existing processed proposal to builtin.ProposalViewer, then reads costs and
error messages in onCreateProposalData. The separate click at `:187-195` creates context
and dispatches a command. `base/tealdef/scripts/builtin.d.tl:1450-1456` accepts simpleProposal
or proposal and declares an onCreateProposalData(ProposalData, Proposal) callback. This
establishes a native preview/evaluation stage separate from applying changes. It does
not establish a complete mod-owned viewer registration/ownership mechanism or a direct
headless SimpleProposal-to-Proposal normalizer. No new viewer or overlay is implemented.

For a **separately approved** evaluation phase, first establish:

1. A complete processed Proposal construction/normalization contract for ordinary
   rails. Do not pass a SimpleProposal to makeProposalData based on matching names.
2. Verified permitted callback context in the loaded world. Module-level read access
   is not proof that a call is permitted inside restricted parallel React work.
3. Explicit Context semantics: current player, checkTerrainAlignment, graph cleanup,
   building/field gathering, pillar relocation and refundable data. Context defaults
   and whether all fields are necessary are not documented sufficiently here; do not
   guess a supposedly safe set of booleans. Never reuse example-specific entity IDs.
4. Bounded proposal complexity and protected error handling. Collect collision/error/
   warning/terrain outputs without submitting anything; record world/revision identity.
5. Evidence that the intended path does not apply changes and a runtime read-only
   comparison against known existing geometry. Keep any mutation command outside it.

Conclusion: a documented non-applying processing API and native preview stage exist;
a fully verified general validation adapter for RNA's authored rail candidates does
**not** yet exist. None was exercised here. This distinction is the construction gate.

## Proposed conversion architecture

```text
immutable complete corridor + snapshot/provenance
  -> explicit XYZ projection / anchor-role validation
  -> waypoint cleanup
  -> candidate curve fitting and endpoint derivatives
  -> vertical alignment design
  -> curvature / gradient evaluation
  -> fresh terrain and swept-obstacle assessment
  -> resource-specific railway geometry description
  -> future native proposal normalization and read-only evaluation
  -> review (construction remains a separate, unapproved operation)
```

Only cleanup, elementary fitting and sampled diagnostics are implemented. Future
vertical/terrain/resource/proposal modules must remain outside topology selection and
A*. A completed corridor already describes an approximate sampled path, not permission
to interpolate surrounding terrain or treat town centers as stations. Preserve source
IDs, original/snap coordinates, water/obstacle knowledge and snapshot provenance in the
caller; never replace that evidence with an offline fit.

The current fitter interpolates given heights, rather than designing a surveyed
vertical alignment. Curves can leave the sampled polyline, including its surveyed
water/terrain cells. Future reassessment must sample the fitted geometry and its swept
width with verified readers; old corridor feasibility does not transfer automatically.

## Isolated prototype and mathematical conventions

`content/geometry/rail_curve.lua` contains pure Lua, no imports or native bindings.
No Game Script, GUI recipe, resource descriptor or accepted planner loads it. The test
runner loads this one authoritative implementation; there is no generated duplicate.

Input:

```lua
{
    unit = "m",
    points = {
        {x = 0, y = 0, z = 0},
        {x = 100, y = 20, z = 2},
        {x = 200, y = 0, z = 0},
    },
    options = {
        diagnosticSteps = 32, -- integer 8..64
        minChord = 1e-6,       -- numerical/prototype guard, NOT engine minimum
        -- maxGradient = 0.02, -- OPTIONAL illustrative caller assumption
        -- minRadius = 500,   -- OPTIONAL illustrative caller assumption in metres
    },
}
```

Plain tables, dense arrays and finite XYZ are required; coordinate magnitude is
bounded to 10,000,000 metres per component. Unknown fields are rejected, so a caller
must explicitly project corridor waypoint XYZ rather than silently dropping water or
other provenance. Units must be declared as metres. There is no implicit conversion,
live adapter, station resolution, gap filling or engine float coercion.

Remove only consecutive exact duplicate XYZ points. Preserve source indices. A
vertical-only or too-short horizontal chord is unsupported, not rewritten to flat
ground. Reject fewer than two remaining points and reversing/near-stationary tangents.

For each chord `D_i=P_(i+1)-P_i`, let `L_i=sqrt(D_ix^2+D_iy^2)`. Endpoint tangents
equal the adjacent chord. At an interior point use the shared derivative

```text
M_i = 0.5 * min(L_(i-1), L_i) * (D_(i-1)/L_(i-1) + D_i/L_i)
```

This is **C**, a simple bounded averaging heuristic, not the native railway builder.
It averages horizontal directions and grades and damps sharp turns. It does not
optimize curvature, preserve arc length or provide a railway transition curve.

For each segment `u in [0,1]`, positions/tangents use the shipped Hermite convention:

```text
P(u) = P0 + (P1-P0)(3u^2-2u^3) + M0(u^3-2u^2+u) + M1(u^3-u^2)
P'(u) = (P1-P0)(6u-6u^2) + M0(3u^2-4u+1) + M1(3u^2-2u)
P''(u) = (P1-P0)(6-12u) + M0(6u-4) + M1(6u-2)
```

Thus P(0)=P0, P(1)=P1, P'(0)=M0 and P'(1)=M1. Tangents are **not unit vectors**;
their lengths change the shape. Both point forward along increasing u. Coordinates
and dP/du use metres since u is dimensionless; u is not arc-length fraction or time.
The position formula subtracts endpoints first to reduce offset-related cancellation.

Reusing one derivative at each shared point gives C0 and C1 continuity across consecutive
unit parameter intervals, including Z. It does **not** give C2 continuity, constant speed,
bounded curvature derivative, smooth superelevation or buildability. Exact reversals
produce zero derivatives and are rejected. Non-reversing fitted segments have monotone
Bezier control projection onto their own chord; tests check this independently. Global
self-intersections between different segments remain unchecked.

Diagnostics evaluate analytic first/second derivatives at fixed samples:

```text
signed grade = z' / sqrt(x'^2+y'^2)
horizontal curvature = abs(x'y''-y'x'') / (x'^2+y'^2)^(3/2)
sampled radius = 1 / horizontal curvature
```

Approximate 3D length sums chords between evaluated samples. Gradient/radius results
are sampled observations, **not certified extrema**. A configured threshold violation
sets `diagnostic_violation`; absence of one yields `candidate`, never `buildable`.
Zero curvature has no finite radius: radius is nil with `sampled_straight`. Reciprocal
overflow remains nil with `numeric_overflow`, distinct from zero radius or missing
height. Near-zero horizontal derivative returns unsupported, never a zero gradient.

Output includes kind/status, unit/parameter convention, explicit assumptions, warnings,
removed-duplicate count and at most 255 records with position0/position1/tangent0/tangent1,
original input indices and per-segment diagnostics. Global diagnostics aggregate length,
maximum sampled grade/curvature, radius status, violation counts and evaluation count.
`constructionStatus="unverified"` and `engineValidation="not_run"` are always explicit.
Vectors are plain XYZ tables, not native Vec3f objects or Proposal components.

## Bounds and tests

- At most 256 input points before cleanup; oversized input fails without truncation.
- At most 255 segments, 8..64 diagnostic intervals each; maximum 16,575 evaluations.
- Linear work/memory in point count for bounded diagnostic resolution; no searches,
  iterative optimization, retained sample arrays, callbacks, terrain caches or I/O.
- Synchronous offline use only. No claim that this is suitable for a native GUI callback.
- minChord defaults to 1e-6 and may be raised to 1e6; derivative guard is 1e-9. These
  are numerical restrictions, not engine construction rules. Optional gradient/radius
  assumptions are validated and retained; absent constraints remain absent.

Executed:

```powershell
uv run --no-project --offline --with lupa==2.8 python tests/run_lua_tests.py
git diff --check
```

**267 tests pass:** all 247 baseline tests plus 20 geometry cases. **49 Lua files**
pass syntax checks. UTF-8 without BOM, JSON, import/resource existence, callback exports
and identity/revision checks pass. The baseline planners and live modules remain unchanged.

Geometry tests cover straight/diagonal/negative-direction segments, gentle and sharp
curves, S bends, signed uphill/downhill grades, caller threshold violations, exact
duplicates, vertical/degenerate/reversal cases, offset coordinates, input immutability,
repeatability, finite/sparse/unknown-field validation, hard bounds and precision overflow.
The independent oracle converts Hermite endpoint data to cubic Bezier controls and
uses de Casteljau interpolation; derivative curves and join derivatives are checked
separately. This is an independent mathematical test, not a mocked native builder.
API/I/O traps also confirm the prototype needs no engine during evaluation.

## Changed files

```text
AGENTS.md                                      Phase 6A scope and geometry rules
README.md                                      milestone and limitations
docs/phase_6a_rail_geometry.md                   this new audit/report
oz_railway_network_architect/content/geometry/
  rail_curve.lua                               new isolated pure-Lua prototype
tests/rail_geometry_test.lua                    new independent geometry tests
tests/run_lua_tests.py                          registers the new suite
```

No existing deployed source changes: no UI, event subscriptions, inventories, network
policies, worklists, batch coordinator, handoff, A*, hierarchy, terrain limits, styles
or metadata changes. No proposal serializer or native geometry converter is added.

## Recommended Phase 6B scope

First review this evidence boundary and prototype. A subsequent bounded phase can
improve offline fitting diagnostics (certified extrema/regularity and curvature/grade
continuity), and separately verify native existing-edge geometry with read-only fixtures.
Establish how BaseEdge endpoint derivatives relate to TransportNetwork.EdgeGeometry,
including vertical interpolation, reversed edges and float precision. Do not present
current C1 fits as final track geometry or infer endpoint attachments from town centers.

Only after the processed-proposal contract and permitted context are established
should a separately approved native evaluation adapter be designed. It must expose
collisions/warnings/terrain effects with provenance, remain non-applying, and have no
command-dispatch capability. Construction, bridges/tunnels as buildable structures,
station placement and existing-track attachment remain outside that milestone.

Native acceptance of newer live network features is still pending. This offline
prototype neither resolves that acceptance nor establishes construction feasibility.
Stop after Phase 6A for review; no staging update is required to review these results.
