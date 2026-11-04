# Phase 6D: native preview safety gate and consolidated acceptance

**Development complete for owner review. Native preview gate: BLOCKED. Native acceptance: pending.**
Do not proceed to Phase 6E or further feature development. The next activity is owner
review, followed by one consolidated Transport Fever 3 installation and acceptance test.
The installation commands below have NOT been executed.

Baseline: `main`, `44edf90`, clean working tree at inspection. All **312 baseline tests**
passed before edits. Phase 6D preserves the original geometry modules, inventories,
network/corridor algorithms, batch coordinator, subscriptions, styles, metadata and revision 1.
No native objects, preview processing, build commands, save writes or staging writes occur.

## Phase 6C audit

Reviewed AGENTS, Phase 6A/6B/6C reports, all three geometry modules and their complete
tests. Exact-file Octocode reads and read-only installed-file/archive inspection were
used; the previously documented Octocode localSearch schema limitation was not a
reason to infer contracts. No demonstrated Phase 6C correctness blocker was found.

- The assembly descriptor uses one negative temporary-ID namespace: canonical nodes
  first, then segments. At the cap this is nodes -1 through -256 and segments -257
  through -511. Adjacent segments reference the same canonical node, without welding.
- Position and tangent values survive unchanged. Both Hermite tangents are forward
  derivatives dP/du on u in [0,1]. Exact C0 and C1 are checked; C1 does not establish
  C2, continuous curvature or native rail interpolation. Independent Bezier/derivative
  tests remain in the existing suites.
- Resource configuration is explicit caller data, not resolved native indices. Normal
  edge mode, TRACK classification and template/lane/style prerequisites remain separate
  from the mathematical DTO. No ownership or bridge/tunnel defaults are invented.
- Bounded plain-data copying preserves inputs and provenance. Invalid joins, duplicated
  node references, altered diagnostics and malformed resources are already tested.
- The assembler creates no native objects and calls no engine APIs. Its result is a
  symbolic descriptor, not an accepted SimpleProposal. No changes to these modules
  were necessary. Phase 6D does not import the assembler into the live path.

## Final native investigation and gate

This is the final bounded investigation for the consolidated test, not an invitation
to repeat event/tool experiments. Installed root for every path below:
`D:\SteamLibrary\steamapps\common\Transport Fever 3`.
Line numbers are one-based; `archive!member` identifies text read directly from ZIP.

Official references: [proposal types](https://wiki.transportfever3.com/script-doc/api/type.html),
[engine components](https://wiki.transportfever3.com/script-doc/api/engine.html),
[proposal utilities](https://wiki.transportfever3.com/script-doc/api/engine/util.html),
[commands](https://wiki.transportfever3.com/script-doc/api/cmd.html).
Declarations establish signatures; shipped code establishes usage, not hidden native
implementation guarantees. The previous public builtin-page availability limitation
remains; installed declarations and implementation are the primary viewer evidence.

| Required operation | Installed source and required input | Context, ownership, effects and cleanup evidence |
| --- | --- | --- |
| Construct native proposal records | `api/tealdef/api/type.d.tl:2511-2533,2786-2804,2820-2828,2857-2858`: NodeAndEntity, SegmentAndEntity, SimpleStreetProposal, SimpleProposal constructors and members; new entities use decreasing negative IDs. | Native objects differ from our descriptor. `base/content/mission.zip!mission/tasks/auto_builder/track_builder.tl:8-56` builds an isolated two-node track in a mission builder. This does not establish every native constructor default or a preview ownership context. No construction occurs in RNA. |
| Populate node/edge geometry | `api/tealdef/api/engine.d.tl:97-130,146-163`; mission builder `:10-24,28-40`: BaseNode.position, BaseEdge node references/positions/tangents, SegmentAndEntity.type=1. | Builder copies both forward tangents directly. Multi-segment canonical sharing follows entity-reference structure, but RNA's multi-segment assembly is still offline. No node attachment is inferred from town anchors. |
| Resolve track configuration | Mission builder `:35-47`: NORMAL/TUNNEL, literal typeIndex=1; streetTemplateRep.find/get, template lanes/style and symbolic RoadType.TRACK. | Template lookup usage is verified; the example's index is not a universal default or proof of a valid user-selected configuration. Normal-mode typeIndex semantics, ownership and complete resource readiness remain unresolved. RNA performs no lookup or guessed configuration. |
| Supply viewer input | `base/tealdef/scripts/builtin.d.tl:1450-1456,1481`: ProposalViewer accepts SimpleProposal or processed Proposal, controlPointInfo, onCreateProposalData, entityForRefundableContext, proposalId. | `base/content/gui.zip!gui/main/builtin.lua:220` declares the native-userdata wrapper. `gui/main/react.lua:422-427` delegates to `_react.builtin`. These expose no complete native processing/destruction implementation. The type declaration alone is insufficient for activation. |
| Own and activate viewer action | `gui.zip!gui/entity_window/bridge_and_tunnel.tl:43,65-86,126-142`: a registered entity-window recipe owns a processed bridge/tunnel Proposal and passes an ActionDescriptor containing ProposalViewer through param.setActionFn. | This is an existing entity tool's action. It does not establish a supported RNA plugin registration contract for taking ownership of that action. RNA's ordinary WindowContainer is not this EntityDetailsTool. Internal action helpers are not treated as supported mod extension points. |
| Receive proposal diagnostics | Same file `:130-141`: onCreateProposalData reads costs/errorState.messages. `api/tealdef/api/type.d.tl:2705-2727,2743-2758` declares collisionInfo, errorState, terrain preview and costs. | Callback data is native ProposalData after processing. Errors are not equivalent to mathematical DTO diagnostics. Callback lifetime and obsolete processing suppression are not established for an independent RNA tool. No callback or processing is invoked by this milestone. |
| Deactivate/cancel/unmount | `gui.zip!gui/entity_window/view_manager.tl:122-142,169-172,299-303,386-437`: propagates active actions, handles close/tool-pop/focus and shelves/restores windows. `gui/main/react.lua:555-557` forwards onUnmount to the native context. | These show entity-window lifecycle coordination, not a complete native ProposalViewer cancellation/destruction guarantee for RNA. Native queued-work cleanup on reload/unmount and interaction with the RNA singleton window remain unverified. |
| Separate preview from applying | Bridge/tunnel recipe `:184-195` applies only in a separate button handler; `api/tealdef/api/cmd.d.tl:953-962` describes world build commands and Proposal/SimpleProposal overloads. | Separate apply is evidence of separation in that shipped tool, not proof that viewer creation/processing has no other engine side effects. RNA neither creates nor sends a build command. No world-changing path is added. |
| Non-applying proposal processing | `api/tealdef/api/engine/util.d.tl:924-925`: makeProposalData(proposal: Proposal, context?: Context): ProposalData. Processed Proposal arrays are distinct at `api/tealdef/api/type.d.tl:2492-2495,2543-2559,2662-2663`. | No documented direct SimpleProposal overload or verified general conversion was established. Native preview internals are inaccessible in the supplied Lua wrappers. No speculative conversion or dry-run is attempted. |

Gate decision:

| Gate | Result |
| --- | --- |
| A. Correct native proposal construction | PARTIAL: record shape and builder example known; complete processing/default requirements unverified. |
| B. Resource/type-index resolution | PARTIAL: template lookup pattern known; no verified complete resource configuration for our geometry. |
| C. Supported mod-owned activation | BLOCKED: entity-tool example is not a documented RNA window action integration. |
| D. Non-mutating preview | BLOCKED: Lua wrapper/declarations do not prove all native processing side effects. |
| E. Deterministic close/cancel/reload cleanup | BLOCKED: native processing cancellation and stale callback contract unavailable. |
| F. Separation from build commands | Established in shipped UI and enforced by RNA's absence of command calls. |
| G. No unverified state modifications | Enforced by the fallback; cannot establish it for a hypothetical native viewer. |

**Overall BLOCKED.** No ProposalViewer registration, activation, native proposal
construction, resource resolution or engine proposal evaluation is implemented.
No world-space overlay is claimed. Offline validity, structural resemblance, native
processing and native construction acceptance remain four distinct evidence levels.

## Implemented read-only inspection

The existing Game Script GUI state owns `inspection` and a separate monotonic
`inspectionRequestId`. The React panel adds **Inspect Geometry** beneath its completed
corridor summary, using the existing Button/TextView styles and scrolling. No window,
focus, centering, subscription or event transport mechanism is changed.

The existing `oz_railway_network_architect.plan` event carries:

```lua
{
    world = currentWorld,
    epoch = currentEpoch,
    inspection = {
        requestId = previousInspectionId + 1,
        corridorRequestId = completedCorridorRequestId,
        candidateId = selectedCompletedCandidateId,
    },
}
```

The handler rejects mixed operation envelopes, busy work, stale session/corridor IDs,
replays, unavailable candidates and nonterminal/non-ok corridor results. It validates
the retained request's world/request identity, candidate completion, source/destination
IDs, grid step continuity and exact endpoints against the compact corridor summary.
The current code's serialized request/GUI-state ownership is preserved; no global
mutable state or cross-inventory sharing is introduced.

One accepted job copies at most 256 finite XYZ points from the selected retained
candidate, preserving their order/coordinates and the original corridor object. Water
presence, source/destination IDs, snaps, spacing and historical snapshot identity/ticks
are retained separately. Coordinates are bounded by the prototype's 1e7 absolute limit.
No heights, stations, resource data or obstacle assessments are fabricated.

1. First later `guiUpdate`: unchanged `rail_curve.fit`, metre units, eight diagnostic
   intervals per segment. Release the copied point array after fitting.
2. Second later `guiUpdate`: unchanged `track_geometry_dto.convert` validates actual
   vectors/joins and recomputes diagnostics with explicit historical provenance.
3. Retain only compact metrics and bounded text; release temporary curve/DTO arrays.
   Unsupported fits, invalid geometry, timing errors or performance failures expose
   their precise reason and retain no successful metrics.

The assembler is intentionally not called: the live workflow has no verified explicit
track configuration or isolated native endpoint designation. The UI lists missing
template/lanes/style, ownership, bridge/tunnel decisions, clearance/collisions and native
validation. Construction status is always **unverified**, including successful math.
No optional gradient/radius threshold is invented for inspection. Sampled maximum
gradient/curvature is diagnostic, not an engineering acceptance limit or certified extremum.
Exact C0/C1 is reported separately from non-C2 joins. Curves may leave the sampled terrain.

### Compact output and lifecycle

Status response `inspection` contains world, epoch, corridorRequestId, inspection id,
candidateId, status/running, `nativePreview="blocked"`, `constructionStatus="unverified"`
and at most ten lines of at most 512 bytes. No waypoints, curves, DTOs, grids or native
objects enter React responses. UI response validation rejects mismatched/malformed data.

Terminal inspection statuses: complete, unsupported, error, invalidated,
performance_limit, timing_unavailable. `complete` means mathematical conversion only.
Unsupported corridors remain valid historical corridor results if they were so before;
the new feature never rewrites the corridor status or changes worklist decisions.

There is no automatic inspection at load or corridor completion. Candidate selection
does not run inspection. Each click is guarded by mount lifetime, fresh response,
world/epoch/request/candidate identity and an independent click token. Duplicate clicks
do not create another job. Further inspection is allowed after completion.

Accepted new manual/network studies, network analysis, batch start, worklist edits and
Refresh clear old inspection summaries; world change/reactPostInit resets all inspection
state. Conflicting operations are rejected while inspection is running. Window close
does not cancel the two-stage owner job; it may finish while closed. Reopen must receive
a fresh status response before displaying it. Expired UI callbacks cannot start or
restore work. No results are written to saves or external files.

Only the retained individual/manual completed corridor has inspectable arrays. Batch
results intentionally retain compact summaries, not previous routes. To inspect a batch
link, perform an explicit individual Study Corridor after fresh Analyze Network if
needed. The feature does not secretly recompute a discarded batch route.

## Limits and performance

- At most 256 input points / 255 segments, one candidate and one inspection job.
  Oversized input is **unsupported**, never simplified or truncated behind the user's back.
- Two bounded math stages: at most 2,295 fit diagnostic evaluations; DTO validation at
  most 2,295 sample evaluations plus 508 join endpoint evaluations. No A* or terrain reads.
- Event handling copies/validates at most 256 points. Each math stage occurs in a later
  existing GUI callback. There are no threads, coroutines or unverified schedulers.
- The unchanged application clock and 0.050-second observed-work guard measure each
  math stage. Missing/non-monotonic clocks stop work; exceeding the guard discards
  diagnostics. This is a post-call guard, **not preemptive cancellation**. Clock resolution
  and TF3 state-copy/native overhead are unverified; 0.000000 is not zero processing cost.
- Temporary memory is linear in 256 points/255 segments plus bounded join diagnostics.
  Completed state is compact. No accumulating history or cached geometry is retained.
- Original sampling/search/batch limits and the network handoff's **60-second age from
  collection start** are unchanged. Inspection describes an existing historical corridor;
  it does not renew evidence or assert fresh-world terrain/obstacle validity.

## Automated verification and changed files

Baseline: 312 tests before edits. Final: **328 passed**, including 16 new live integration
regression cases; **54 Lua files** pass Lua 5.4 syntax. UTF-8 without BOM, JSON, imports,
local resource targets, manifest identity/revision and descriptor exports pass.
The isolated runner uses the existing cached Lupa dependency; no new project/game dependency.
SHA-256 comparison against the task-start package confirms that only live_plan.script.lua
and live_plan_ui.script.lua changed among its 44 existing files; the new adapter brings
the package to 45 files. All geometry/planning/inventory modules, subscriptions, styles
and metadata are byte-identical. `git diff --check` passes. The four PowerShell blocks
below passed syntax parsing only; the staging, rollback and log-copy commands were not run.

```powershell
uv run --no-project --offline --with lupa==2.8 python tests/run_lua_tests.py
git diff --check
```

The new tests cover explicit-only execution; selected candidate IDs; no A*/terrain
reread; unchanged input; 256/257-point boundaries; missing coordinates/discontinuities;
incompatible reversals; exact C0/C1/diagnostics; missing resource reporting; busy/replay,
mixed and stale envelopes; repeated inspection; world/reset cleanup; new manual/Refresh
requests; close/reopen/queued unmount; malformed response recovery; timing/performance
failure; protected math exceptions; individual network studies, worklist edits and
sequential/cancelled batches; ineligible corridor statuses. The full prior rail, planner,
hierarchy, topology, worklist, GUI, batch and geometry suites run unchanged.

Complete changed-file list for this milestone:

```text
AGENTS.md                                             modified scope/conventions
README.md                                             modified current milestone
docs/phase_6d_native_acceptance.md                      new report and acceptance plan
oz_railway_network_architect/content/
  live_plan_geometry.lua                              new pure inspection adapter
  live_plan.script.lua                                modified owner/dispatch/steps
  live_plan_ui.script.lua                             modified action/compact display
tests/live_plan_test.lua                               modified 16 regression cases
```

Relevant diff: one pure adapter, one import plus inspection state/envelope/two-stage
execution in the existing owner, and one UI action/summary. No new Game Script descriptor,
event subscription, CSS, native API, constructor or resource default. Exact production
and test diffs are reviewable with `git diff --` for the three modified Lua files;
read the new adapter directly with `Get-Content -LiteralPath
oz_railway_network_architect/content/live_plan_geometry.lua`. Do not stage files merely
to view their diff.

Offline/mocked passing results do not demonstrate native callback speed, recipe rendering,
state copying, game interpolation, collision clearance or construction acceptance.

## Complete-package staging procedure — OWNER ONLY, AFTER REVIEW

Do not execute during development. Quit TF3 completely first. This replaces the **whole
deployable directory**, not selected Lua files. Source and destination are the existing
project/install locations; verify the Steam user ID if running on a different account.
No original game content or save file is touched. Existing enabled revision remains 1.

Run the following as one PowerShell block. It prepares a fresh copy outside staging,
records exact file-set/SHA-256 manifests, moves the old complete mod to backup, then
promotes the verified directory. It never merges into an old mod folder or deletes it.
Backup/evidence directories are outside staging, so TF3 cannot discover duplicate copies.

```powershell
$ErrorActionPreference = 'Stop'
$rnaName = 'oz_railway_network_architect'
$rnaSource = (Resolve-Path -LiteralPath 'D:\code\transport-fever-3\railway-architect\oz_railway_network_architect').Path
$rnaStage = (Resolve-Path -LiteralPath 'C:\Program Files (x86)\Steam\userdata\175442176\3493540\local\staging_area').Path
$rnaTarget = Join-Path $rnaStage $rnaName
$rnaLocal = Split-Path -Parent $rnaStage
$rnaEvidenceRoot = Join-Path $rnaLocal 'rna_acceptance_backups'
$rnaStamp = (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N')
$rnaEvidence = Join-Path $rnaEvidenceRoot $rnaStamp
$rnaPreparedParent = Join-Path $rnaEvidence 'prepared'
$rnaBackupParent = Join-Path $rnaEvidence 'previous'
$rnaPrepared = Join-Path $rnaPreparedParent $rnaName
$rnaBackupMod = Join-Path $rnaBackupParent $rnaName

function Assert-RnaFolder([string]$Path, [string]$ExpectedParent) {
    $actual = (Resolve-Path -LiteralPath $Path).Path.TrimEnd('\')
    if ($actual -ne [IO.Path]::GetFullPath($Path).TrimEnd('\') -or
        (Split-Path -Parent $actual) -ne $ExpectedParent.TrimEnd('\')) {
        throw "Unexpected directory boundary: $Path"
    }
    $items = @((Get-Item -LiteralPath $actual)) + @(Get-ChildItem -LiteralPath $actual -Recurse -Force)
    if ($items | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint }) {
        throw "Refusing reparse points in $actual"
    }
}
function Get-RnaManifest([string]$Root) {
    $prefix = $Root.TrimEnd('\') + '\'
    @(Get-ChildItem -LiteralPath $Root -File -Recurse -Force | ForEach-Object {
        [pscustomobject]@{ Path = $_.FullName.Substring($prefix.Length); Hash = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash }
    } | Sort-Object Path)
}
function Assert-RnaSame($A, $B) {
    if (@($A).Count -eq 0 -or @($B).Count -eq 0) { throw 'Empty mod manifest' }
    if (Compare-Object -ReferenceObject $A -DifferenceObject $B -Property Path,Hash) {
        throw 'File-set or SHA-256 mismatch; do not launch TF3'
    }
}

Assert-RnaFolder $rnaSource (Split-Path -Parent $rnaSource)
if ((Get-Item -LiteralPath $rnaStage).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Staging is a reparse point' }
if ($rnaSource -eq $rnaTarget) { throw 'Source and target coincide' }
$rnaMetadata = Get-Content -LiteralPath (Join-Path $rnaSource 'mod.json') -Raw | ConvertFrom-Json
if ($rnaMetadata.modId -ne $rnaName -or $rnaMetadata.revision -ne 1) { throw 'Unexpected identity/revision' }
if (Test-Path -LiteralPath $rnaEvidence) { throw 'Backup location already exists' }
New-Item -ItemType Directory -Path $rnaPreparedParent,$rnaBackupParent -Force | Out-Null
$rnaBefore = @(Get-RnaManifest $rnaSource)
$rnaBefore | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $rnaEvidence 'source.json') -Encoding UTF8
Copy-Item -LiteralPath $rnaSource -Destination $rnaPreparedParent -Recurse -Force
Assert-RnaFolder $rnaPrepared $rnaPreparedParent
$rnaPreparedHash = @(Get-RnaManifest $rnaPrepared)
Assert-RnaSame $rnaBefore $rnaPreparedHash
Assert-RnaSame $rnaBefore @(Get-RnaManifest $rnaSource)
$rnaPreparedHash | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $rnaEvidence 'prepared.json') -Encoding UTF8

if (Test-Path -LiteralPath $rnaTarget) {
    Assert-RnaFolder $rnaTarget $rnaStage
    $rnaOld = @(Get-RnaManifest $rnaTarget)
    $rnaOld | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $rnaEvidence 'previous.json') -Encoding UTF8
    # Both absolute endpoints are confined to the explicitly named mod/backup directories.
    if ((Split-Path -Parent ([IO.Path]::GetFullPath($rnaBackupMod))) -ne $rnaBackupParent -or
        (Test-Path -LiteralPath $rnaBackupMod)) { throw 'Unexpected backup destination' }
    Move-Item -LiteralPath $rnaTarget -Destination $rnaBackupMod
    Assert-RnaFolder $rnaBackupMod $rnaBackupParent
    Assert-RnaSame $rnaOld @(Get-RnaManifest $rnaBackupMod)
}
Assert-RnaFolder $rnaPrepared $rnaPreparedParent
if ((Split-Path -Parent ([IO.Path]::GetFullPath($rnaTarget))) -ne $rnaStage -or
    (Test-Path -LiteralPath $rnaTarget)) { throw 'Unexpected install destination' }
Move-Item -LiteralPath $rnaPrepared -Destination $rnaTarget
Assert-RnaFolder $rnaTarget $rnaStage
$rnaInstalled = @(Get-RnaManifest $rnaTarget)
Assert-RnaSame $rnaBefore $rnaInstalled
Assert-RnaSame $rnaBefore @(Get-RnaManifest $rnaSource)
$rnaInstalled | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $rnaEvidence 'installed.json') -Encoding UTF8
Write-Host "Verified $($rnaInstalled.Count) files. Complete backup/evidence: $rnaEvidence"
```

If any step fails, **do not launch TF3**. The prior directory remains either in staging
or at the printed/computed `$rnaBackupMod`; nothing is deleted. If a prior backup exists,
the following optional rollback block in the same shell preserves any failed/new install
in quarantine and restores the previous whole directory. Keep TF3 closed.

```powershell
Assert-RnaFolder $rnaBackupMod $rnaBackupParent
$rnaQuarantine = Join-Path $rnaEvidence 'rejected-install'
if (Test-Path -LiteralPath $rnaQuarantine) { throw 'Quarantine already exists' }
if ((Split-Path -Parent ([IO.Path]::GetFullPath($rnaQuarantine))) -ne $rnaEvidence) { throw 'Unexpected quarantine path' }
if (Test-Path -LiteralPath $rnaTarget) {
    Assert-RnaFolder $rnaTarget $rnaStage
    Move-Item -LiteralPath $rnaTarget -Destination $rnaQuarantine
}
if ((Split-Path -Parent ([IO.Path]::GetFullPath($rnaTarget))) -ne $rnaStage) { throw 'Unexpected target path' }
Move-Item -LiteralPath $rnaBackupMod -Destination $rnaTarget
Assert-RnaFolder $rnaTarget $rnaStage
$rnaPrevious = @(Get-Content -LiteralPath (Join-Path $rnaEvidence 'previous.json') -Raw | ConvertFrom-Json)
Assert-RnaSame $rnaPrevious @(Get-RnaManifest $rnaTarget)
```

## One consolidated native acceptance procedure

Use one known map/save with several towns and preferably existing rail. Do not construct
test infrastructure or overwrite saves. Record TF3 build, display resolution/UI scale,
map identity, installed manifest hashes, date and source/destination IDs. Briefly unpause
if readiness is waiting for tick advance. Observe normal simulation separately from RNA:
normal game changes while unpaused are not evidence of mod mutation.

The steps below are one consolidated test session, not iterative deployment cycles.
Network handoff/batch evidence expires 60 seconds after collection starts. Capture
worklist screenshots promptly, then explicitly re-run Analyze Network before the study
and batch sections if needed. Reanalysis clears edits; reapply only the marks required
for that section. Expiry is expected rejection, never permission to extend limits.
If the map yields too few recommendations/feasible corridors, record that fixture
limitation; do not invent links or increase budgets to force a pass.

| Check / exact owner action | Expected UI/result and relevant log marker | Failure interpretation and evidence to capture |
| --- | --- | --- |
| 1. Launch TF3 with RNA revision 1 enabled; load the chosen map. | No Lua/recipe errors. `[RNA:PLAN:4B2] EVENT_SUBSCRIPTIONS_READY count=5`, `UI_SESSION_READY`, `TOWNS available=...`; inventory SCAN_COMPLETE markers under CITY:2B, IND:3A, TERRAIN:3B, RAIL:3C. | Record full stdout, build/mod list and first stack trace. Repeated bootstrap load hooks alone are not a failure or proof of live readiness. No automatic planning/inspection START should occur. |
| 2. Click RNA launcher; close with title-bar X; reopen, drag, scroll all sections. | One centered initial native window; bounded padded/wrapped content; dragging retained while open; reopen centered; `UI_INIT` on initialization. | Screenshot full viewport and scrolled bottom; record clipping, lost focus, duplicate windows or recipe errors. Layout mocks cannot prove pixels. |
| 3. Inspect both town dropdowns. | Real names and IDs, including distinct entries for duplicate names. `TOWNS available=N`; HANDLER_RESPONSE/GUI_RESULT tables when bounded tracing emits them. | Capture list/count and status; nil/restricted API response or perpetual waiting is communication/readiness failure. Later requests need not repeat exhausted trace-budget logs. |
| 4. Select two nearby distinct towns and click Plan once. Do not click other actions while busy. | Explicit progress then complete candidates or a precise supported failure. `[RNA:PLAN:4B2] REQUEST_START`, ENDPOINT_VALIDATION, GRID, SEARCH, CANDIDATE, COMPLETE. | Capture endpoints/snaps, candidate panel, reason and PERFORMANCE/TIMING lines. No completed candidate may be shown for incomplete/unreachable/search_limit results. |
| 5. Select a longer pair (e.g. Morley/Winterton only if actually present); click Plan. | `[RNA:PLAN:4B2] LONG_DISTANCE mode=hierarchical`, `[RNA:PLAN:4B3] PROGRESS`, SUMMARY/CORRIDOR; explicit terminal outcome. UI remains responsive. | Record IDs/distance, section count, elapsed/work measurements, timing warning and any visible stall. A bounded unsupported/unreachable result is not proof rail is impossible; at least one completed long fixture is needed to verify that success path. |
| 6. Click Analyze Network once. | Bounded analysis progress; `[RNA:NETWORK:5B1] request=N START` then COMPLETE. No new corridor REQUEST_START or A* just from analysis. | Capture counts/provenance/warnings; >32-town rejection is expected, not silent truncation. Missing demand must remain unknown. |
| 7. Select proposed/deferred links in network result controls. | Mainline/Branch proposals, hub candidates, reasons, distance and omitted evidence visible; capacity is not passenger demand, nearby tracks not operational connectivity. | Screenshot selected and deferred reasoning. Zero proposals may be correct; record fixture limitation instead of forcing all towns connected. |
| 8. In Network Plan select a proposed link: Exclude, Include, Mark for further study, Restore original recommendation, then Reset all edits. | Membership/override/graph summary changes; original classifications/reasons preserved. `[RNA:WORKLIST:5C1] EDIT ... action=... revision=...`. No terrain study starts. | Capture before/excluded/restored summaries, unconnected towns and historical classification warning. Unexpected A* or mutated original scores is failure. |
| 9. Exclude one selected proposed link and attempt Study Corridor. | Action disabled; server-side exclusion enforcement remains. No corridor START. `REQUEST_REJECTED` only if an event actually reaches the owner. | Capture disabled action/status and unchanged request count. Do not inject native events to bypass the UI; backend rejection is regression-tested offline. |
| 10. With fresh analysis, select an included recommended link and click Study Corridor once. | Existing corridor workflow uses its exact endpoint IDs, preserves original recommendation origin; REQUEST_START/ENDPOINT_VALIDATION then COMPLETE. | Capture selected edge ID/classification, endpoint IDs, provenance and terminal result. No automatic retries. Stale snapshot must ask for Analyze Network. |
| 11. With fresh analysis, mark 2-4 included links and click Study Marked Corridors once. | `[RNA:BATCH:5C2] START total=N`, one STUDY_START at a time, RESULT per edge, COMPLETE. Compact completed/failure counts accurate. | Capture deterministic order and final summaries, including unsupported/unreachable outcomes if present. More than four must reject, not truncate. No concurrent searches. If snapshot expires, STOP with reason is correct. |
| 12. Start another explicitly marked batch. After one result and while another is active, click Cancel Batch. | STOP status=cancelled; active/pending work stops; already completed summaries remain labeled; manual controls become available. | Capture before/after result counts and absence of later STUDY_START. If routes finish too quickly to cancel after one, record incomplete coverage and cancel an active batch without claiming retention was natively verified. No limit changes. |
| 13. Complete a short manual/individual corridor if none remains, choose a candidate and click Inspect Geometry once. Switch candidate and inspect explicitly again if available. | `[RNA:GEOM:6D] START` then COMPLETE; no A* START or terrain queries caused by inspection. Panel shows source/destination/candidate, segments, C0/C1/non-C2, sampled diagnostics, missing prerequisites, preview BLOCKED, construction unverified. | Capture candidate IDs, inspection IDs/status/reason and measured work. >256 points or incompatible curve must show unsupported without truncation. Close/reopen should require fresh response and not rerun work. Zero timing delta is insufficient timing evidence. |
| 14. Check preview policy; do not activate game build tools for this test. | Native preview remains BLOCKED; no world-space RNA geometry, ProposalViewer, build/apply button or native proposal acceptance. | Any automatic world preview or construction claim violates the gate. Screenshot explicit limitation. This step verifies absence, not rendering functionality. |
| 15. Start a study if useful, then load another existing map/save without saving test changes; reopen RNA. | Session reset, fresh town list, no old proposals/worklist/batch/inspection. `[RNA:PLAN:4B2] SESSION_RESET`; `[RNA:GEOM:6D] CLEAR` if inspection existed at reset. No resumed pending work. | Capture old/new world/town IDs and reset logs. Check no RNA-created track/station/terrain changes; normal game/autosave behavior is outside mod control. Shut down normally and preserve log before another launch. |

Expected geometry examples (IDs/counts/times are actual-run values, not fixed fixtures):

```text
[RNA:GEOM:6D] START inspection=1 corridor=3 candidate=<selected-id> status=running
[RNA:GEOM:6D] COMPLETE inspection=1 corridor=3 candidate=<selected-id> status=complete reason=mathematical_conversion_only segments=<N> max_work_seconds=<measured> timing_resolution=unverified native_preview=blocked construction=unverified
```

An oversized route can terminate immediately:

```text
[RNA:GEOM:6D] START inspection=2 corridor=4 candidate=<selected-id> status=unsupported
[RNA:GEOM:6D] COMPLETE inspection=2 status=unsupported reason=waypoints_must_be_dense_and_at_most_256 native_preview=blocked construction=unverified
```

Capture stdout after normal shutdown, before starting TF3 again. Run in the same
PowerShell session as installation (or set `$rnaEvidence` to its recorded directory):

```powershell
$rnaLog = 'C:\Program Files (x86)\Steam\userdata\175442176\3493540\local\crash_dump\stdout.txt'
Copy-Item -LiteralPath $rnaLog -Destination (Join-Path $rnaEvidence 'acceptance-stdout.txt')
Select-String -LiteralPath $rnaLog -Pattern '\[RNA:|Recipe child|API is currently restricted|stack traceback' |
    Select-Object LineNumber,Line |
    Out-File -LiteralPath (Join-Path $rnaEvidence 'acceptance-markers.txt') -Encoding UTF8
```

Preserve the full log, screenshots and both deployment manifests; filtered markers alone
can omit the cause of a native error. Do not treat absence of bounded per-event trace
messages as absence of delivery when functional status/results prove it.

## Readiness and remaining limitations

Ready for code review and owner-controlled complete-package deployment; **not yet native
accepted**. The consolidated test is the next step, not more development. Main remaining
limits: blocked world preview; no engine validation/construction; unknown native geometry
interpolation/defaults/resources/ownership; no stations/attachments/bridges/tunnels/clearance;
sampled diagnostics and non-C2 joins; 256-point inspection cap; historical terrain evidence;
unknown clock resolution and GUI copying/latency; batch/network 60-second freshness;
pending native acceptance of accumulated network/worklist/batch/UI features. No economic
feasibility, operational routing or construction-ready geometry claim is made.
