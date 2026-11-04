# Phase 6B: TF3 track geometry compatibility and proposal contract

Baseline: `main`, `ed4b667`; working tree initially clean. Phase 6A's 267 tests passed
before edits. This phase adds an offline intermediate geometry DTO and 23 tests.
It does not create native objects, register resources for execution, evaluate proposals,
change existing planners or execute any construction/command API. No staging, game
installation, savegame, identity, revision or Git history is changed.

## Decision and evidence boundary

Ordinary track record fields and a shipped authoring example are verified. Exact native
processing of arbitrary Phase 6A XYZ Hermite curves is not. Therefore the implementation
is **intermediate_track_geometry**, expressly neither SimpleProposal nor Proposal.
Its structural claim is limited to numeric endpoint/tangent field correspondence.
It cannot be passed to native proposal APIs. No result is labeled accepted or buildable.

Evidence categories below: **A** declaration/documentation; **B** installed example;
**C** our explicit mathematical/policy assumption; **D** unresolved native behavior.
Installed root is `D:\SteamLibrary\steamapps\common\Transport Fever 3`.
Line numbers are one-based in installed text or decoded archive members. `!` separates
archive and member paths. All reads were read-only, without extraction into the game.
The previously identified Octocode query-schema limitation remains; focused direct
source reads and archive searches were used instead.

## Native contracts and exact evidence

| Contract | Installed source and finding |
| --- | --- |
| BaseEdge vectors **A** | `api/tealdef/api/engine.d.tl:97-130`: node0/node1 are entity IDs; position0/position1 and tangent0/tangent1 are Vec3f; roadType, roadTemplate, roadStyle and laneConfigs are distinct fields. `:156-163` declares BaseNode.position in world space. [Official engine documentation](https://wiki.transportfever3.com/script-doc/api/engine.html). |
| Serialized vectors **B** | `base/content/mission.zip!mission/tasks/auto_builder/prepare_track_building_util.tl:5-16` copies existing BASE_EDGE vectors into four XYZ arrays without normalizing or negating them. Its file-writing functionality was not invoked. |
| Ordinary track authoring **B** | `base/content/mission.zip!mission/tasks/auto_builder/track_builder.tl:7-56` creates SimpleProposal, NodeAndEntity and SegmentAndEntity. Lines 31-38 copy node IDs, positions and both tangents directly into the component. Lines 42-47 resolve a street_template, copy laneConfigs and streetStyle, and assign symbolic RoadType.TRACK. |
| Direction **B** | `base/content/gui.zip!gui/entity_window/view_manager_util.tl:7-21`, especially `:15`, uses tangent0 at node0 and **negated** tangent1 at node1 for outward node directions. The stored end tangent itself points forward along the segment. |
| Hermite convention **B** | `base/content/scripts.zip!scripts/mathutil.lua:39-55` implements normalized-parameter Hermite position and derivative. `scripts/construction/constructionutil.lua:48-61` converts 2/3/4 control points with derivative multipliers 1/2/3. These support derivative magnitudes, not unit-vector tangents; they do not prove the ordinary engine's entire interpolation pipeline. |
| Native geometry is a separate layer **A/D** | `api/tealdef/api/type.d.tl:1028-1109` declares EdgeGeometry ARC/STRAIGHT/CUBIC_SPLINE/CUBIC_OFFSET_SPLINE, XY spline data, separate vertical tangent/height, length, and calcPos(geom, param) returning position, tangent and second derivative for param in [0,1]. No inspected implementation maps an arbitrary BaseEdge to that representation. |
| Simple track graph **A** | `api/tealdef/api/type.d.tl:2511-2533` defines NodeAndEntity.entity/comp and SegmentAndEntity.entity/comp, with discriminator 0=street, 1=track. `:2761-2804` defines SimpleStreetProposal.nodesToAdd/edgesToAdd and removal fields. `:2820-2824` distinguishes existing nonnegative entity IDs from decreasing negative temporary IDs and describes remove/add modification semantics. `:2857-2858` embeds it as SimpleProposal.streetProposal. [Official type documentation](https://wiki.transportfever3.com/script-doc/api/type.html). |
| Processed track graph **A** | `api/tealdef/api/type.d.tl:2492-2495,2543-2572,2659-2679`: Proposal is the more complete native record, with Proposal.proposal containing StreetProposal.addedNodes/addedSegments and processed removal records. It is not interchangeable with SimpleStreetProposal. |
| Construction-owned edge lists **A/B** | [Construction Basics: edge lists](https://wiki.transportfever3.com/doku.php?id=modding:constructions:basics#edge_lists) and `base/content/scripts.zip!scripts/construction/constructionutil.lua:40-87`: paired local positions/tangents, construction parameters and zero-based snap/free indices. These are not ordinary world node entities or DTO indices. |
| Templates **A/B** | `api/tealdef/api/type.d.tl:5478-5555` specifies StreetTemplate. In particular laneConfigs `:5495`, streetStyle `:5511`, slope/shape settings `:5520-5523`, speedCoeffs/radius/build slope `:5530-5539`, and catenary substitutions `:5552-5555`. The mission builder's template lookup at `:42-47` supplies these data; no BaseEdge catenary boolean is established. |
| Existing attachments **B/D** | `track_builder.tl:10-24,31-32,49-56` can reuse supplied existing nodes and add only new nodes. It does not establish safe snapping, mid-edge splitting, ownership, switches, station positioning or operational connectivity. Those remain prerequisites. |
| Edge mode **A/B/D** | `api/tealdef/api/type.d.tl:462-465` declares NORMAL/BRIDGE/TUNNEL. The mission builder uses NORMAL/TUNNEL at `:35` and a fixed typeIndex at `:36`; that index is example-specific, not a general default. Carrier resource, portal, pillar, support and clearance decisions are not derived from the curve. |
| Context **A** | `api/tealdef/api/type.d.tl:2477-2489`: checkTerrainAlignment, cleanupStreetGraph, gatherBuildings/gatherFields, player, refundableEntities and extendProposalRedoPillars. The declaration does not establish a complete safe context for our authored geometry. |
| Diagnostics **A** | `api/tealdef/api/type.d.tl:2693-2758`: ProposalData includes collisionInfo, terrain preview, transport network data, costs and errorState with critical/messages/warnings/infos. These are future engine outputs, not values invented from mathematical checks. |

The same four vector names can be copied without changing values. That observation
does **not** prove that TF3 preserves the exact double-precision XYZ polynomial after
Vec3f conversion, graph cleanup, vertical interpolation, snapping or subdivision.
No universal minimum segment length, speed-radius equation, full gradient enforcement
policy or accepted native tolerance has been established. None is invented here.

## Phase 6A mathematical audit

No correctness defect requiring a change to rail_curve.lua was found. All original
geometry code and tests remain unchanged. Phase 6B adds independent checks.

For each coordinate, with D = P1 - P0 and u in [0,1]:

```text
P(u)   = P0 + D(3u²-2u³) + M0(u³-2u²+u) + M1(u³-u²)
P'(0)  = M0                     P'(1)  = M1
P''(0) = 6D - 4M0 - 2M1        P''(1) = -6D + 2M0 + 4M1
```

Phase 6A uses the same position and tangent at each adjacent join. It is exactly C0/C1
on consecutive **unit parameter intervals**, not arc-length intervals or constant-speed
motion. End tangents are chord vectors. An interior tangent averages adjacent
horizontal-chord-normalized XYZ vectors, scaled by half the shorter horizontal chord.
This fitting rule is **C**, not the native TF3 builder algorithm.

Provided horizontal speed is nonzero, equal derivatives also imply equal signed grade
z'/sqrt(x'²+y'²). C1 does not in general imply equal second derivatives, curvature or
grade-rate. The regression fixture (0,0,0) -> (100,0,10) -> (180,30,0) has exact C1,
continuous grade and nonzero curvature/grade-rate jumps. Tests derive derivatives from
independent cubic Bezier controls and de Casteljau evaluation, not the adapter formula.

The report uses signed horizontal curvature (x'y''-y'x'') / h³ and signed grade z'/h,
where h=sqrt(x'²+y'²). Grade-rate per horizontal metre is
`(z'' - z'*(x'x''+y'y'')/h²) / h²`. C2 is an exact floating-point equality diagnostic,
not a tolerance-based engineering certification. Uniform samples are not extrema bounds.

## Adapter input and output

`content/geometry/track_geometry_dto.lua` exports `convert(input)`; its sole import is
the existing curve evaluator. It does not re-fit the corridor or duplicate the fitter.

```lua
local result = adapter.convert({
    candidate = curve.fit({unit = "m", points = worldXYZ, options = explicitAssumptions}),
    provenance = {
        source = "synthetic_fixture", coordinateFrame = "world",
        candidateId = "example:1", water = "unknown", obstacles = "unknown",
        -- Optional caller-owned snapshot, anchor approximation and evidence metadata.
    },
    -- Optional references ONLY; no existence or compatibility assertion:
    template = {roadTemplate = templateResourceName, roadStyle = styleResourceName},
})
```

`candidate` must use the Phase 6A kind/unit/parameter/status contract, plain dense
segments, source indices and validated assumptions. Failed Phase 6A outputs are not
eligible. Unknown wrapper/candidate/segment/vector/template fields are rejected,
including native proposal/entity fields. Candidate diagnostics are not trusted: the
adapter recomputes them. Original candidate status and warnings remain separate;
an original diagnostic_violation is never upgraded to candidate.

World-frame provenance and a nonempty source are mandatory. It is caller evidence,
not verified live freshness. All supplied bounded provenance, source warnings and
assumptions are copied without mutation. Source point indices preserve Phase 6A's
consecutive duplicate removal; the original A* corridor remains outside the adapter.
An adapter cannot recover evidence omitted before projection into Phase 6A.

Optional template input requires both resource-name strings. The DTO copies those
two verified field names, but cannot resolve resource existence, TRACK classification,
availability, lanes or style compatibility. Missing template input is allowed and
reported; incomplete/malformed supplied references fail validation. No template default,
resource enum, lane list, catenary flag, bridge/tunnel typeIndex or player is invented.

Output on success:

```text
kind = intermediate_track_geometry
status = candidate | diagnostic_violation
unit = m; parameter = u_in_0_1_tangents_dP_du
sourceCandidateStatus; sourceRemovedDuplicates; provenance; assumptions; sourceWarnings
templateReferences? = {roadTemplate, roadStyle}
nodes[] = {index, position={x,y,z}, sourcePointIndex}
segments[] = {index, node0Index, node1Index, position0, position1, tangent0, tangent1,
              sourceStartIndex, sourceEndIndex, diagnostics}
report = {inputGeometry, endpointContinuity, tangentCompatibility, structuralCompatibility,
          sampledDiagnostics, joins[], trackTemplateReadiness, bridgeTunnelDecisions,
          existingInfrastructureConnections, terrainAndCollisions,
          nativeProposalVerification, constructionStatus, missingPrerequisites[], warnings[]}
```

DTO node/segment indices are one-based local array identities, **not** engine entity
IDs or construction snap indices. A future native serializer would need its own
verified temporary-entity allocation and resource/context resolution. None exists here.

Position0/position1 map by identity to the corresponding BaseEdge vector fields;
tangent0/tangent1 also map by identity as forward dP/du candidates. The correct DTO
magnitude conversion is **factor 1**, not unit normalization, chord-length multiplication
or end-tangent negation. For independent Bezier checks only, handles are M0/3 and M1/3;
those handles must not be passed as tangents. No native float rounding is simulated.

## Validation policy and feasibility report

The adapter preserves exact coordinates and refuses to repair geometry silently:

- Finite XYZ vectors, absolute components at most 1e8; horizontal chord above the
  explicit Phase 6A minChord (at least 1e-6). These are **C** numerical guards.
- Exact shared position/source index and exact shared derivative required. A tiny gap
  is not welded. Same-direction unequal-magnitude tangents are G1 but fail this C1
  input contract. This is not a claim that TF3 forbids G1 joins.
- For each segment, the derivative projected onto the horizontal chord is a quadratic.
  Its minimum over [0,1] is evaluated analytically at endpoints and an interior minimum,
  when present. A value <=1e-9 is unsupported. This conservatively excludes backwards
  progress/stationary geometry; it is not a general TF3 restriction. Sample evaluation
  also guards near-zero horizontal derivatives against floating-point error.
- The original diagnostic resolution is used. Per-segment and total approximate 3D
  length, maximum sampled absolute grade and horizontal curvature are recomputed.
  Caller gradient/radius violations stay visible. Join reports include both sides'
  signed grade, curvature and grade-rate, plus jumps and C0/C1/C2 diagnostics.

Report meanings:

| Report field | Successful DTO meaning |
| --- | --- |
| inputGeometry | Mathematically validated for this DTO contract, not native constraints. |
| endpointContinuity / tangentCompatibility | Exact C0 / exact C1 and forward derivatives. |
| structuralCompatibility | BaseEdge vector fields only; no native object/type acceptance claim. |
| sampledDiagnostics | Sampled information, not certified worst-case bounds or construction costs. |
| trackTemplateReadiness | missing or references_supplied_not_resolved. |
| bridgeTunnelDecisions / existingInfrastructureConnections | not_assessed. |
| terrainAndCollisions | not_verified. |
| nativeProposalVerification / constructionStatus | not_run / unverified, always. |

Failures return invalid_input, unsupported or resource_limit, a precise reason and the
report, with **no nodes or segments**. Reports may contain already checked joins but
are not a partial usable geometry result. Invalid input and unknown data never become
zero elevations, fabricated templates or positive engine acceptance.

## Non-mutating native validation: evidence and unresolved gate

`api/tealdef/api/engine/util.d.tl:924-925` declares exactly:

```text
makeProposalData(proposal : Proposal, context? : Context) : ProposalData
```

The [official utility reference](https://wiki.transportfever3.com/script-doc/api/engine/util.html)
also lists Proposal, Context and ProposalData. The engine module documents read-only
access from GUI and engine states. That supports a non-applying processing surface,
but does not supply a SimpleProposal overload or the native implementation.

The four inspected script archives contain **no direct makeProposalData use**: scripts
(86 Lua/Teal members), mission (230), GUI (635), game_mechanics (258). This is scoped
negative search evidence, not proof that the API cannot be used.

A working native preview path is visible at
`base/content/gui.zip!gui/entity_window/bridge_and_tunnel.tl:126-138`: ProposalViewer
receives an existing processed proposal and returns costs/errorState via
onCreateProposalData. `base/tealdef/scripts/builtin.d.tl:1450-1456` accepts simpleProposal
or proposal and declares callback `(ProposalData, Proposal)`. The separate application
action is at `bridge_and_tunnel.tl:187-195`.

These examples establish native preview behavior, not a complete mod-owned, headless
SimpleProposal-to-processed-Proposal lifecycle. The accessible declarations/examples do
not prove all side effects, initialization requirements or precision/geometry transforms
inside the native processor. **No sufficiently verified end-to-end non-mutating
validation path for our authored DTO is established.** Nothing in this phase invokes
makeProposalData, ProposalViewer, a command constructor or a command dispatcher.

`api/tealdef/api/cmd.d.tl:953-962` declares separate build-command overloads for Proposal
and SimpleProposal. They apply proposals when dispatched and are not dry-run validation.
[Official command documentation](https://wiki.transportfever3.com/script-doc/api/cmd.html).

## Tests, limits and changed files

Run from the repository root:

```powershell
uv run --no-project --offline --with lupa==2.8 python tests/run_lua_tests.py
```

Result: **290 tests pass** (267 preserved + 23 DTO regressions); **51 Lua files** pass
Lua 5.4 syntax checks. The harness also validates UTF-8/no BOM, JSON, local import/resource
targets, descriptor callback exports and unchanged mod identity/revision. No native TF3
load, runtime geometry comparison or engine validation is claimed.

Final review: all 42 pre-existing mod files match their start-of-task SHA-256 hashes;
the tracked mod diff is empty. The adapter has no live imports and no engine, command,
proposal-evaluation or file-I/O calls. `git diff --check` passes; new files also have
no trailing whitespace. No unrelated source changes were found.

Coverage includes straight/diagonal/curved/multi-segment cases; independent Bezier
positions, first/second derivatives, length, grade and curvature; C1 with curvature and
grade-rate discontinuity; reversed end tangents versus a correctly reversed route;
unequal join tangent magnitudes; exact endpoint gaps; zero chords/tangents; interior
reversal despite positive endpoint tangents; missing and unresolved templates; malformed
native fields; nonfinite/missing/sparse inputs; preserved/recomputed violations; duplicate
source provenance; non-aliasing/immutability; determinism; long routes; resource limits;
cyclic/oversized metadata; and engine/file-access traps. These are mathematics and
plain-data contract tests, not mocks claiming native acceptance.

Hard limits: 255 segments, 256 nodes, 254 joins, 8-64 diagnostic intervals per segment.
At the maximum: 16,575 sampled evaluations plus 508 join endpoint evaluations = 17,083
curve evaluations. Time is O(segments * diagnosticSteps), memory O(segments); no sample
arrays or terrain grids are retained. Provenance/warnings/assumptions combined have
256 metadata entries, depth 6, strings <=1024 bytes and total string bytes <=16384.
Template strings are individually <=512 bytes. Limits reject, never truncate. The
module is synchronous offline code and has no claimed GUI latency guarantee.

Changed files (all existing runtime modules, Phase 6A fitter/tests and metadata unchanged):

```text
AGENTS.md                                         updated scope and DTO conventions
README.md                                         updated milestone/results links
docs/phase_6b_track_proposal_contract.md             new audit and contract
oz_railway_network_architect/content/geometry/
  track_geometry_dto.lua                           new isolated adapter/report
tests/track_geometry_dto_test.lua                   new 23-case suite
tests/run_lua_tests.py                              one test-suite registration
```

## Proposed Phase 6C scope

First perform a separately approved, bounded **read-only native geometry comparison**:
verify the mapping from existing BASE_EDGE records to transport-network EdgeGeometry,
then compare declared interpolation samples and orientations against the offline math.
Resolve track template/lane/style/constraint provenance without proposing new tracks.
Preserve world/session ownership and report precision/parameterization differences.

Only after that evidence, design native DTO serialization with real resource lookups,
temporary node IDs and explicit connection/support decisions. A native validation
experiment additionally requires verified processor/preview registration, execution
context, lifecycle and non-application guarantees; do not route through build commands.
Absent that evidence, keep the gate closed. Construction, stations, terrain changes,
save persistence and UI integration are not part of this Phase 6B delivery.
