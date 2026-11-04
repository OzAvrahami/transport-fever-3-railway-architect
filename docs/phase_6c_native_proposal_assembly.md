# Phase 6C: native proposal assembly and safe preview research

Baseline: `main`, `8adb2a9`, clean working tree. All **290 baseline tests** passed
before edits. This milestone implements an offline symbolic assembly descriptor and
investigates ProposalViewer. No native objects or proposals are instantiated, processed,
previewed or submitted. No game/staging/save files, identity, revision or Git history
are changed. No live module imports the new assembler.

## Phase 6B audit

Reviewed AGENTS, Phase 6A/6B reports, rail_curve.lua, track_geometry_dto.lua and their
tests. Octocode exact file reads worked for the known adapter path; installed archives
were searched/read directly. The earlier localSearch schema limitation did not prevent
verification. No demonstrated defect required modifying the fitter or DTO adapter.

- Coordinates and both forward dP/du tangent vectors are copied without normalization,
  end-tangent reversal, fitting or coordinate snapping. Source indices survive duplicate
  cleanup performed by the earlier fitter.
- Plain-data copies preserve input immutability and bounded provenance. The adapter
  requires exact shared endpoints and derivatives; C1 keeps signed grade continuous
  when horizontal derivative is nonzero. Curvature and gradient-rate can still jump.
- Analytic forward-chord projection and sampled diagnostics are explicit mathematical
  checks, not TF3 engineering standards. Existing independent Bezier tests remain.
- Template references, terrain/collisions, attachments, bridge/tunnel decisions and
  native interpolation/processing remain unknown. No result claims buildability.
- New assembly tests alter DTO coordinates, IDs, tangents and cached diagnostics to
  verify that downstream assembly revalidates actual geometry rather than trusting a
  prior success label or report.

## Evidence categories and native field mapping

**A** = documented declaration; **B** = shipped implementation; **C** = offline policy
or inference; **D** = unresolved native behavior. Installed root:
`D:\SteamLibrary\steamapps\common\Transport Fever 3`.
All references are one-based lines in the installed text; `archive!member` denotes a
read-only ZIP member, with no extraction into the installation.

Official references: [type/proposal records](https://wiki.transportfever3.com/script-doc/api/type.html),
[engine components](https://wiki.transportfever3.com/script-doc/api/engine.html),
[proposal utility](https://wiki.transportfever3.com/script-doc/api/engine/util.html).
The attempted public builtin documentation pages were unavailable; installed builtin
definitions and GUI sources provide the preview evidence below.

| Descriptor/native target | Verified evidence and boundary |
| --- | --- |
| SimpleProposal / streetProposal | **A:** `api/tealdef/api/type.d.tl:2827-2828,2857-2858` declares constructor and SimpleStreetProposal member. **B:** `base/content/mission.zip!mission/tasks/auto_builder/track_builder.tl:8,49-56` constructs it and assigns nodesToAdd/edgesToAdd. RNA emits only a descriptor with the corresponding field names. |
| SimpleStreetProposal arrays | **A:** `type.d.tl:2786-2804` declares constructor, add/remove node/edge/object/config arrays and node2rcType. RNA emits only nodesToAdd and edgesToAdd; it creates no removal or modification instructions. |
| NodeAndEntity | **A:** `type.d.tl:2511-2517`: entity and comp: BaseNode. **B:** mission builder `:10-24` gets initialized comp from NodeAndEntity.new and writes comp.position. |
| BaseNode.position | **A:** `api/tealdef/api/engine.d.tl:156-163`: Vec3f in world coordinates. Descriptor uses copied plain XYZ, not a native Vec3f. |
| SegmentAndEntity | **A:** `type.d.tl:2519-2533`: entity, comp: BaseEdge, type, streetEdge, optional emissionEmitter/playerOwned. **B:** builder `:28-47` initializes and assigns the rail component fields. |
| Segment type = 1 | **A:** `type.d.tl:2524-2525` explicitly documents 0 street / 1 track. **B:** builder `:40`. This discriminator is verified, not a guessed RoadType enum value. |
| BaseEdge.node0/node1 | **A:** `engine.d.tl:111-112`; **B:** builder `:31-32`. Adjacent descriptor edges refer to the same canonical temporary node ID. Multi-record sharing is an **inference C** from entity-reference/array contracts; this exact multi-segment assembly has not run natively. |
| BaseEdge positions/tangents | **A:** `engine.d.tl:113-116`; **B:** builder `:33-38` copies all four vectors directly. `gui.zip!gui/entity_window/view_manager_util.tl:15` negates tangent1 only for an outward end-node direction. Descriptor preserves both forward vectors and magnitudes exactly. |
| Edge mode/typeIndex | **A:** `engine.d.tl:103-104`, `type.d.tl:462-465`: BaseEdgeType and integer index. **B:** builder `:35-36` uses NORMAL/TUNNEL and literal index 1. RNA requires explicit NORMAL and an explicit index; it supplies no default. The meaning/relevance of typeIndex in NORMAL mode remains **D**, and copied caller values are not validated native resource indices. |
| roadType TRACK | **A:** `engine.d.tl:124-125`, `type.d.tl:1954-1957`; **B:** builder `:47` uses symbolic RoadType.TRACK. Descriptor contains the name TRACK, not a native enum or guessed integer. |
| Template/style | **A:** `engine.d.tl:126-129`; **B:** builder `:42-46` resolves streetTemplateRep, copies laneConfigs and streetStyle, and sets roadTemplate/roadStyle. RNA requires both resource names and checks syntax; it does not resolve their existence, availability or compatibility. |
| LaneConfig | **A:** `type.d.tl:5377-5390`: speed, width, height, forward, transportModes map keyed by TransportMode, offset. `:2217-2233` declares mode symbols. RNA stores a symbolic-name-to-boolean map; native enum-key conversion is pending. |
| Serialized lane example | **B:** `base/content/infrastructure/track.zip!track/standard/standard.street_template.lua:25-34,55-58` has one lane, TRAIN/TRAM_TRACK names and roadType/style. Resource-file mode name arrays differ from resolved LaneConfig enum maps. Tests use an explicitly synthetic normalized fixture; RNA never substitutes those values as defaults. |
| Negative temporary IDs | **A:** `type.d.tl:2787,2820-2821`: new entities use decreasing negative IDs from -1, old entities nonnegative IDs. **B:** builder uses edge -1 and nodes -3/-4. RNA's contiguous nodes-first allocation is **C** within that contract, with no duplicated IDs across record kinds. |
| BaseEdgeStreet | **A:** `engine.d.tl:146-154` contains two precedence fields; `type.d.tl:2526-2527` declares streetEdge. The shipped rail builder never assigns it explicitly. RNA omits it and records native constructor/default verification as a prerequisite; an empty fabricated component would not resolve this. |
| Ownership | **A:** `type.d.tl:2531-2532` marks playerOwned optional; `engine.d.tl:855-860` defines PlayerOwned.player. The shipped builder does not assign it. RNA explicitly requires ownership=unresolved and omits playerOwned; it does not assert the future track is unowned or permitted. |

The declarations use **Engine.Component.BaseNode/BaseEdge/BaseEdgeStreet**. The verified
builder accesses comp through NodeAndEntity/SegmentAndEntity constructors; no lower-case
`api.engine.component.*` constructor invocation is needed or introduced here.

This is not the processed Proposal graph: `type.d.tl:2492-2495,2543-2559,2662-2663`
uses Proposal.proposal with addedNodes/addedSegments. Construction edgeLists are another
contract with local coordinates and snap/free indices; see the previous phase reports.
Neither is substituted for ordinary SimpleStreetProposal records.

## Offline assembly contract

New pure module: `content/geometry/track_proposal_assembly.lua`, export `assemble(input)`.
It imports only the existing Phase 6B adapter and reuses its mathematical validation.

```lua
assembly.assemble({
    geometry = phase6bDTO,
    endpoints = {start = "isolated_new", finish = "isolated_new"},
    ownership = "unresolved",
    track = {
        roadTemplate = explicitTemplateName, roadStyle = explicitStyleName,
        roadType = "TRACK", edgeMode = "NORMAL", typeIndex = explicitCallerValue,
        laneConfigs = normalizedExplicitLaneSnapshot,
        provenance = {source = explicitSource, basis = "synthetic"},
    },
})
```

Resource provenance basis may be synthetic, installed_source or live_snapshot, with a
nonempty source <=512 bytes. This is caller provenance, not a proof of live lookup or
freshness. No engine state is consulted. All lanes require finite numeric speed, width,
height and offset; a boolean forward; and a symbolic map containing TRAIN or ELECTRIC_TRAIN
enabled. The narrow supported mode set additionally includes TRAM_TRACK/ELECTRIC_TRAM_TRACK.
Other modes, extra fields, missing configuration and invalid values fail explicitly.

Only isolated newly allocated endpoints are supported. Station/existing-track roles,
live entity references, bridge/tunnel modes and ownership assertions are rejected.
Town IDs may remain historical geometry provenance; they never become endpoint entities.
If the DTO has template references, the explicit track resource names must match them.

Geometry is projected into a Phase 6A-shaped input and passed to the unchanged Phase 6B
validator. This does not refit curves. Canonical DTO node/segment indices, source indices
and node XYZ are then checked against the recomputed result. Duplicate references,
sparse arrays, disconnected joins and conflicting node positions fail. Existing
diagnostic violations survive; stale input diagnostics cannot conceal new violations.

Successful offline output:

```text
kind = offline_track_proposal_assembly
status = descriptor
representation = symbolic_fields_not_native_objects
nativeReadiness = blocked
nativeObjectsCreated = false
nativeProcessing = not_run
constructionAcceptance = unverified
geometryStatus; geometryReport; geometryProvenance; geometryAssumptions; geometrySourceWarnings
sourceCandidateStatus; sourceRemovedDuplicates; resourceConfiguration; endpoints; ownership
segmentSources[] = {entity, sourceStartIndex, sourceEndIndex}
streetProposal.nodesToAdd[] = {entity, comp={position}}
streetProposal.edgesToAdd[] = {entity, type=1, comp={node0,node1,position0,position1,
    tangent0,tangent1,type="NORMAL",typeIndex,roadType="TRACK",roadTemplate,roadStyle,laneConfigs}}
missingPrerequisites[]
```

`status=descriptor` means the offline assembly completed, **not** native compatibility
or acceptance. Symbolic strings, mode-map keys and plain vectors still require native
conversion. The descriptor is deliberately not a callable/instantiable native proposal.
Missing NORMAL typeIndex semantics, constructor defaults and ownership/context keep the
native mapping blocked; this phase does not fill them with guesses.

For N segments, N+1 nodes receive IDs -1 through -(N+1); edges receive -(N+2) through
-(2N+1). Edge i references nodes -i and -(i+1). Two sections therefore use node IDs
-1/-2/-3 and edge IDs -4/-5. The shared node -2 is created once. Reversal preserves
the supplied reversed point order and forward derivatives; no extra tangent negation
occurs. All geometry/resource output data is copied, with independent lane maps per edge.

Failures return invalid_input and a specific reason, without streetProposal. They do
not return a partially usable assembly. Limits also reject without truncating.

## ProposalViewer research and safety gate

| Question | Installed evidence / conclusion |
| --- | --- |
| Accepted input | **A:** `base/tealdef/scripts/builtin.d.tl:1450-1456` declares simpleProposal: SimpleProposal, proposal: Proposal, controlPointInfo, onCreateProposalData(ProposalData, Proposal), entityForRefundableContext and proposalId. `:1481` declares Recipe<ProposalViewerParam>. SimpleProposal is an accepted declared input; no actual viewer is created by RNA. |
| Implementation visibility | **B/D:** `base/content/gui.zip!gui/main/builtin.lua:220` registers ProposalViewer with DeclareBuiltinWithUserdata. `gui/main/react.lua:422-427` obtains a native builtin recipe ID. The Lua wrapper returns an empty table; native processing/rendering/destruction internals are not exposed by it. |
| Working recipe ownership | **B:** `gui/entity_window/bridge_and_tunnel.tl:43,65-86,126-142` owns a processed proposal in React state, supplies an ActionDescriptor through param.setActionFn and places ProposalViewer inside that action. It uses a bridge/tunnel-specific proposal utility, not a general SimpleProposal conversion. |
| Proposal data ownership/results | **A/B/D:** callback declaration at builtin.d.tl:1454 returns ProposalData and Proposal. Shipped callback `bridge_and_tunnel.tl:132-137` reads costs/errorState.messages into state. Native processing owns creation; lifetime, async completion ordering, cancellation and data retention are not specified there. |
| Errors/collisions | **A:** `api/tealdef/api/type.d.tl:2705-2727,2743-2758` specifies collisionInfo, errorState critical/messages/warnings/infos, terrain preview and costs. The example reads messages/costs only. No single invented isBuildable flag is introduced. |
| Activation/focus | **B:** `gui/entity_window/view_manager.tl:122-142` routes the active entity window's actionFn, falling back to the default selector. `:299-303` changes the active window/action on focus. A preview action participates in native tool ownership, beyond an ordinary window's content. |
| Close/deactivation | **B:** `view_manager.tl:169-172` closes and propagates the current action; `:386-401` pops non-pinned windows, clears the entry and removes the window. Pinned windows can remain; `:404-437` handles shelving and action restoration. These are entity-window behaviors, not a proven RNA integration contract. |
| Unmount/reload | **A/B/D:** `gui/main/react.lua:555-557` forwards onUnmount registration to native context. That generic hook does not establish ProposalViewer's native disposal/cancellation behavior. No inspected wrapper proves that old processing results cannot survive map reload or restore obsolete render objects. |
| Can preview modify the world? | **B/D:** `bridge_and_tunnel.tl:184-195` submits changes in a separate explicit click handler. This supports separation in that shipped flow but is not complete proof of all native viewer side effects. The non-mutation requirement is therefore still gated. No build command or dispatcher was executed. |
| RNA coexistence | **D:** RNA uses its existing WindowContainer singleton path (`content/live_plan_ui.script.lua:434-478`), not EntityDetailsTool/setActionFn. Safe action arbitration, restoration, focus coexistence and cleanup for RNA are not established. The existing window and communication architecture are unchanged. |

The GUI archive search found one ProposalViewer use (the processed bridge/tunnel example)
and its builtin declaration, but no shipped GUI example supplying simpleProposal to it.
This is a scoped search finding, not proof that the declared input is unusable.

**Gate remains closed:** no live ProposalViewer registration, native object factory or
proposal processing has been added. A word such as viewer or preview does not prove
non-mutation. Existing native declarations alone do not establish an RNA ownership,
cancellation, unmount or reload contract.

## Four distinct validation levels

1. **Offline geometry:** finite coordinates, C0/C1 continuity, bounded sampled diagnostics.
2. **Structural assembly:** canonical negative IDs, referential consistency and documented
   field correspondence with symbolic placeholders. Resource semantics remain unresolved.
3. **Native processing:** not run. `api/tealdef/api/engine/util.d.tl:924-925` declares
   `makeProposalData(proposal: Proposal, context?: Context): ProposalData`; there is no
   established direct SimpleProposal overload or general conversion API in the inspected
   sources. Engine GUI/engine-state read access does not resolve the viewer lifecycle gate.
4. **Construction acceptance:** unverified. No application command, save mutation,
   terrain change, station placement or native build test is authorized/performed.

## Tests, limits and changed files

Run from the repository root:

```powershell
uv run --no-project --offline --with lupa==2.8 python tests/run_lua_tests.py
```

**312 tests pass**: all 290 prior tests plus 22 assembly tests. **53 Lua files** pass
syntax checks. The harness verifies UTF-8/no BOM, JSON, local resources/imports,
descriptor exports and mod identity/revision. Native TF3 behavior is not mocked as
accepted or inferred from these results.

Final review: all 43 pre-existing mod files match their start-of-task SHA-256 hashes.
`git diff --check` and new-file whitespace checks pass. Static inspection confirms no
engine, file-I/O, native-processing or command calls in the assembler and no live import
of it. Existing runtime modules and geometry implementations have no changes.

Coverage: straight/two-section/curved alignments; unique shared negative IDs; independent
Bezier handle checks for reversal; exact coordinates/tangents/provenance; isolated roles;
missing/invalid templates, lanes, modes and ownership; duplicate/disconnected references;
node/edge disagreement; malformed/degenerate geometry; recomputed diagnostics; immutable
inputs and independent output copies; deterministic repeats; maximum-length input;
sparse arrays/metatables; and traps forbidding native or file APIs.

Bounds are project policy, not TF3 limits: 255 segments, 256 nodes, 511 temporary IDs,
8 lanes per segment (2,040 edge lane records plus the 8-record resource snapshot), and
the Phase 6B maximum 17,083 curve evaluations. Numeric lane fields are bounded to
absolute 1e6 with positive speed/width. Explicit typeIndex is bounded to 0..2147483647
as an offline payload restriction, not a claim about native integer widths or valid
resource indices. Resource names/source strings are capped at 512 bytes. Phase 6B
metadata bounds remain in force. Work/memory remain bounded; this synchronous offline
module makes no GUI responsiveness claim and is not wired into live requests.

Changed files:

```text
AGENTS.md                                                    scope and safety conventions
README.md                                                    current milestone/results
docs/phase_6c_native_proposal_assembly.md                       this report
oz_railway_network_architect/content/geometry/
  track_proposal_assembly.lua                                 new offline assembler
tests/track_proposal_assembly_test.lua                         22 new tests
tests/run_lua_tests.py                                        one suite registration
```

Existing geometry, inventories, planners, network/worklist/batch behavior, GUI and event
subscriptions are preserved. No installation, native preview, command execution, save
modification, Git commit/tag/push or revision change is part of this milestone.

## Recommended Phase 6D

Resolve the remaining gates with a source-backed design before live activation:

1. Verify native constructor defaults (including streetEdge), NORMAL typeIndex semantics,
   symbolic-to-native enum/vector conversion and caller resource snapshot provenance.
2. Design a bounded read-only collection/comparison of existing rail geometry and actual
   template lanes/styles, keeping freshness and resource identity explicit.
3. Establish the mod-owned tool/action contract and how it coexists with the RNA window,
   restores prior controls and destroys preview processing/rendering on cancel/reload.
   Obtain explicit evidence for non-application and stale callback rejection.
4. Only when those contracts are established, seek separate authorization for a small
   native preview experiment with no application action. Observe proposal errors/collisions
   and cleanup; do not route around blockers through construction commands.

If native viewer internals or authoritative guarantees remain inaccessible, retain the
offline descriptor and record the blocker. Offline tests cannot substitute for those
contracts or establish construction feasibility.
