# Visual Railway MVP

Implementation from `e034516` on `main`. Stop for owner review and one native test.
No game command, staging deployment, save modification, commit, tag or push was
performed during development. **Actual visible placement remains unverified.**

## Player experience

The normal launcher opens the existing centered, draggable native window, now
520 by 360 logical units, with unchanged scoped padding, wrapping and scrolling.
It contains Source town, Destination town, **Plan Railway**, simple status and
**Build Test Track**. Duplicate names have small ordinal suffixes; entity IDs remain
internal. No raw scores, grid statistics, worklist diagnostics or snapshot identities
are shown. Detailed planner and construction evidence stays in the game log.

Plan Railway runs the accepted read-only planner. A completed route enables a separate
test experiment; it does **not** establish that route as buildable. The test track is
an isolated 80-metre straight segment at the camera centre, not a section of the A*
route and not connected to either town. This deliberate separation avoids treating
sampled corridor points as native railway geometry.

Build Test Track first performs read-only site checks, focuses the site and displays:

> This changes the map: one 80-metre track at the site now in view. It may adjust ground
> and charge your company. Only proceed on a disposable save copy you made. This does
> not build the planned route.

Only **“This is my disposable copy — build one track”** authorizes submission. Cancel
does not submit anything. No save has been identified as disposable by the assistant.

The developer controls and backend algorithms remain in source and regression tests.
The production launcher never supplies the `development=true` recipe parameter;
only the legacy UI test fixture does. Thus existing behavior remains testable without
exposing the analytics application in the player window. Network, batch, worklist,
geometry, A*, hierarchical planning and all four inventory implementations are unchanged.

## Native source evidence

Installed root: `D:\SteamLibrary\steamapps\common\Transport Fever 3`.
ZIP paths below identify entries read directly without modifying/extracting the game.
Official references: [Command API](https://wiki.transportfever3.com/script-doc/api/cmd.html)
and [type declarations](https://wiki.transportfever3.com/script-doc/api/type.html).
The installed implementation supplies the concrete railway pattern.

| Operation | Exact installed source | Verified contract used |
|---|---|---|
| Native railway proposal | `base/content/mission.zip!mission/tasks/auto_builder/track_builder.tl:8-56` | `SimpleProposal.new`, `NodeAndEntity.new`, `SegmentAndEntity.new`; nodes -3/-4, edge -1, segment discriminator 1 for rail, forward endpoint tangents, `NORMAL`, `typeIndex=1`, `RoadType.TRACK`, template/style/lane fields. |
| Shipped submission | Same entry, `:60-74` | `makeWorldBuildProposalCmd` then `sendCommand`; callback receives command data and success. Mission uses non-player context; RNA uses the separate verified GUI player-context pattern below. |
| GUI execution timing | `api/tealdef/api/cmd.d.tl:2-10`, `:591-600` | Available in GUI state; executes on the next simulation step; callback follows execution when GUI reads can see changes. No speculative asynchronous mechanism. |
| Factory overload | `api/tealdef/api/cmd.d.tl:953-962` | Explicit `SimpleProposal` overload: `(proposal, context, ignoreErrors, playerInitiated, doDust?)`. RNA passes `false,true` and leaves optional dust at native default. |
| Callback data | `api/tealdef/api/cmd.d.tl:509-524` | `WorldBuildProposalCommandData` has processed `proposal`, `resultProposalData` and `resultEntities` entity/revision pairs. RNA does not mistake these for the input SimpleProposal. |
| Player context in GUI | `base/content/gui.zip!gui/entity_window/bridge_and_tunnel.tl:187-205` | `Context.new`, `context.player=api.engine.util.getPlayer()`, player-initiated command and result-entity read-back from a GUI callback. RNA does not copy its infrastructure-replacement proposal. |
| Context switches | `api/tealdef/api/type.d.tl:2478-2489` | Terrain check, player, graph cleanup, gather buildings/fields and pillar relocation fields. RNA enables terrain checking and disables cleanup/gather/relocation. No refundable entities supplied. |
| Proposal records | `api/tealdef/api/type.d.tl:2511-2533`, `:2786-2804`, `:2820-2858` | Node/segment records, negative new entity IDs, add/remove arrays and constructors. All removal arrays and construction lists are empty. |
| Base track resource | `base/content/infrastructure/track.zip!track/simple/simple.street_template.lua:3-6,23-32,53-56` | Available for all years; one TRAIN lane, width 4, ordinary TRACK classification and `::/infrastructure/track/simple/simple.street` style. This is the non-catenary sibling of the mission example's template. |
| Resource lookup | `api/tealdef/api/res.d.tl:13-28,147,160`; `api/tealdef/api/type.d.tl:5387,5479-5511`; `base/content/gui.zip!gui/construction/construction_react_util.tl:2034,2091` | Repository `find/get`, missing index -1; StreetTemplate has roadType, laneConfigs and streetStyle. Lane transportModes is an enum-keyed boolean map, used that way in shipped GUI code. Native enum bindings are accessed directly, without requiring Lua type `function`. |
| Occupancy screen | `api/tealdef/api/engine/system.d.tl:604-610`; `api/tealdef/api/type.d.tl:843-847` | `octreeSystem.findIntersectingEntities(Box3, callback)` and min/max Vec3 box construction. This is a read, not construction validation. |
| Camera | `api/tealdef/api/gui.d.tl:426-451` | `getCameraData` centre X/Y and `focusPosition(Vec3f, distance)`. Focus happens once on preparation and once on verified success, never every frame. |
| Error messages | `api/tealdef/api/type.d.tl:2705-2727` | ProposalData errorState contains string messages. Log up to four verbatim sanitized messages; absent messages are explicitly reported as unavailable. |
| GUI owner state | `base/tealdef/scripts/gamescript.d.tl:40-49,66-68` | Existing GUI callback state get/set. Command callback reads latest state and checks world/epoch/job identity before updating it. Native command objects are not stored in the state table. |
| Mod flags | `api/tealdef/api/type/mod.d.tl:70-84` | Cosmetic means purely cosmetic; add/remove severities describe save instability. `cosmetic` is now false. |

`typeIndex=1` follows this shipped NORMAL-track example exactly. It is not a claim
that index 1 has a general resource meaning for bridges, tunnels or other edge modes.
No bridge/tunnel lookup, construction `edgeLists`, symbolic DTO conversion or native
ProposalViewer is used. Constructors and resource mapping are source-backed; native
acceptance of this particular proposal still requires the owner's game test.

## State, geometry and safeguards

The existing five subscriptions and GUI event transport are unchanged. The existing
`plan` event accepts a separate `track` envelope with action (`prepare`, `cancel`,
`confirm`), monotonic request ID, corridor request ID, confirmation ID and, for confirm,
`disposableCopy=true`. Outer world/epoch checks, normal busy guards and replay checks
remain in the authoritative Game Script. No global mutable communication state.

1. A current successful completed corridor is required. No construction happens at
   load, town selection, Plan, Analyze Network, geometry inspection or status polling.
2. Preparation rounds the camera centre to a metre and samples 27 real terrain points:
   nine along an 80 m east-west line, repeated at Y offsets -10, 0, +10 m. Every point
   must be valid, finite, readable and dry. Height range must be at most 0.4 m across
   the strip. This is a conservative **experiment assumption**, not a railway limit.
3. An octree box extending 20 m beyond the segment ends and 20 m to either side
   rejects intersecting entities except the world and non-physical TOWN volumes.
   Trees, roads, tracks, buildings, constructions and unknown objects therefore block
   the test. Above 256 hits it rejects without additional component reads. No clearing,
   bulldozing, attachment or automatic search for another location occurs.
4. The unchanged pure curve fitter checks two real centreline endpoint heights. The
   native straight segment uses positions `(x-40,y,z0)` / `(x+40,y,z1)` and both forward
   tangents `(80,0,z1-z0)`. Ground may be aligned by native construction; sampling is
   not a guarantee about unsampled terrain or collisions.
5. The resource must resolve to the exact verified TRACK template/style, one TRAIN
   lane with positive finite width/speed. No guessed fallback. The owner sees the
   confirmation and may cancel. It expires after 30 seconds.
6. Confirm consumes the one-attempt session allowance **before** further validation.
   It rechecks the same site, all sampled heights, occupancy, resource, clock and world.
   Changed terrain or evidence rejects the action; no silent relocation. Native nodes
   -3/-4 and edge -1 are new, unique, isolated entities; no positive existing IDs enter
   proposal endpoints. The current player is obtained from the engine and validated.
7. The factory receives the genuine native SimpleProposal, explicit player context,
   `ignoreErrors=false`, `playerInitiated=true`. There is exactly one sendCommand call.
   No removal operations, custom assets, stations, terrain-edit commands or retries.
8. After success, inspect at most 16 returned entity/revision entries. Require exactly
   one matching TRACK/NORMAL edge with the exact resource and expected endpoint
   positions, plus two distinct BASE_NODEs at those endpoints (0.02 m comparison
   tolerance). Only then report **Track built successfully**, log its entity and focus
   the camera. Native success with missing/mismatched read-back is **unverified**.

Only compact status/sequence/eligibility information is sent to React. The site holds
27 heights and two endpoints; it is released after cancellation, expiry or a result.
No native command or proposal object is retained in GUI state or save data. The map
itself will contain the track after a successful authorized command and normal game
saving would persist it; this is why the owner's disposable copy is mandatory.

Both preparation and confirmation have a measured 50 ms pre-dispatch work guard.
This is not preemption: an individual native read, octree traversal or command
constructor cannot be interrupted by Lua. Octree traversal may still visit more than
256 hits even though subsequent component reads are capped. Native execution cost and
callback latency are not claimed to be below 50 ms. Existing planning budgets remain
unchanged. A paused simulation must be unpaused to process the GUI command.

**Submission is not cancellable by this implementation.** Close before an enqueued UI
confirmation dispatches prevents that UI request; closing after send does not undo the
command. Wait for its terminal result before loading another map. World/epoch changes
discard stale callbacks, but this does not establish native queue cancellation or
rollback. If native callback/state access fails, the log records CALLBACK_ERROR and
the UI may remain pending; do not retry or assume no track was built. Ambiguous send
exceptions lock out additional attempts. All transient state resets on session reload.

An occupancy preflight and empty removal lists are not a world lock: changes between
the preflight and next simulation step remain a native-runtime risk. Use a quiet,
disposable test map and do not build anything else while this command is pending.
Native collision/error handling remains authoritative; nothing uses ignoreErrors=true.

## Metadata

`cosmetic=false` replaces the obsolete read-only cosmetic flag. Add/remove severity
remains `None`: enabling the mod performs no construction and created track uses only
base-game resources, not assets that disappear with RNA. Those flags concern save
instability, not permission to change the world; native removal/save compatibility is
not yet tested. The visible mod description now warns about the test, ground alignment
and company cost. Identity `oz_railway_network_architect`, name and revision 1 are unchanged.

## Changes and automated validation

```text
AGENTS.md                                              updated authorized scope
README.md                                              current product/test instructions
docs/visual_railway_mvp.md                              new evidence and acceptance report
oz_railway_network_architect/
  mod.json                                             cosmetic=false
  _metadata/modinfo.json                                accurate player description
  content/track_test.lua                                native experiment owner adapter
  content/player_plan_ui.lua                            compact player controls
  content/live_plan.script.lua                          guarded plan envelope/status
  content/live_plan_ui.script.lua                       player view, response validation
  content/live_plan_ui.css.lua                          initial height 360 (was 520)
tests/live_plan_test.lua                                12 focused regression tests
tests/run_lua_tests.py                                  enforce non-cosmetic manifest
```

Baseline before edits: **341 tests passed**. Final: **353 passed**, including 185 live
integration/UI tests; **56 Lua files** compile with Lua 5.4. UTF-8 without BOM, JSON,
resource/import targets, callback exports and unchanged identity/revision are checked.
`git diff --check` passes. No TF3 process or construction command was run by the tests.

The command mock queues callbacks explicitly; it checks native-shaped new nodes/edge,
empty removals and false ignoreErrors, but cannot prove native binding behavior. New
tests cover compact controls; no automatic commands; explicit disposable confirmation;
cancel/expiry; one command per click/session; busy/replay; missing/invalid resource and
terrain; occupancy; observed-work guard; world change before submission; native failure
messages; successful callback with invalid read-back; stale callbacks; ambiguous send
failure; close/reopen; malformed responses; and no stale success display. Existing
rail/planner/network/worklist/batch/geometry and developer UI regression cases remain.

```powershell
uv run --no-project --offline --with lupa==2.8 python tests/run_lua_tests.py
git diff --check
git diff -- oz_railway_network_architect tests AGENTS.md README.md
Get-Content oz_railway_network_architect/content/track_test.lua
Get-Content oz_railway_network_architect/content/player_plan_ui.lua
```

The last two reads expose new untracked modules that plain `git diff` does not show.
Do not stage files merely to inspect their contents.

## One-session native acceptance procedure

Do not run this until owner review. No staging commands were run. Owner installation
must replace the **complete** `oz_railway_network_architect` package, not mix these new
modules with an old owner/UI. With TF3 closed, use the existing guarded full-package
backup/copy/hash-verification procedure in
[Phase 6D acceptance](phase_6d_native_acceptance.md), section
“Complete-package staging procedure — OWNER ONLY, AFTER REVIEW”.
Its historical test counts/read-only wording do not apply to this construction MVP.
Do not copy repository tests/docs or dependencies into staging. Keep the prior package
backup. The owner separately makes a disposable save copy; no script here copies saves.

1. **Owner identifies and loads that disposable copy.** Capture its name and the mod
   revision in a screenshot. Do not load the original for the experiment. Native
   startup should show the existing five event subscriptions, real town list and normal
   inventories, with no `[RNA:BUILD:MVP] DISPATCH`.
2. **Open RNA.** Expect the small centered window, two town dropdowns, Plan Railway,
   status and disabled Build Test Track. Close/reopen/drag/scroll once. No recipe errors,
   visible raw entity IDs or developer summaries. Capture the window.
3. **Select two different towns, then click Plan Railway once.** Expect “Planning
   railway...” then “Route found” for a feasible test pair. Existing `[RNA:PLAN:4B2]`
   planning diagnostics remain. There must still be zero BUILD DISPATCH markers.
   An unsupported/unreachable plan leaves Build Test Track disabled; it is not success.
4. **Pan to empty, dry, nearly flat land.** Avoid trees, roads, buildings and tracks.
   The test will span 40 m either side of the camera centre along world X. Click Build
   Test Track once. Expect a focused site and the disposable-copy confirmation, plus
   `SITE_READY confirmation=... x=... y=... length=80`. No track exists yet and no
   command has been sent. `SITE_REJECTED reason=...` means preflight rejected the site;
   record that exact reason, do not interpret it as native construction failure.
5. **Confirm only if this is the owner's disposable copy.** Click “This is my
   disposable copy — build one track” once within 30 seconds. This authorizes one map
   change and possible charge/ground alignment. Expect “Placing test track... Unpause
   to finish.” Unpause if needed. Do not reload, quit, change maps or concurrently build.
6. **Wait for the native result.** Required success evidence, with the same test:

   ```text
   [RNA:BUILD:MVP] SITE_READY confirmation=<id> x=<x> y=<y> length=80
   [RNA:BUILD:MVP] DISPATCH confirmation=<id> world=<id> ignoreErrors=false
   [RNA:BUILD:MVP] NATIVE_RESULT success=true reason=<native messages or no_native_error_messages_available>
   [RNA:BUILD:MVP] VERIFIED entity=<new track entity>
   ```

   The camera refocuses and UI says “Track built successfully”. **Inspect an actual
   ordinary track in the world**: after the terminal status, close RNA if it obscures
   the camera centre, and preferably select the track with normal game controls.
   Capture a screenshot of the visible segment and full surrounding clear site. Verify
   no pre-existing object was removed; this must be an isolated segment, not a station
   or an entire route. A mocked callback, log alone or mathematical line is not acceptance.
7. **Failure is a terminal result, not a retry instruction.** `NATIVE_RESULT
   success=false` records up to four native messages; UI says “Cannot place track here”.
   `VERIFY_FAILED` or a send exception means placement cannot be confirmed; visually
   inspect the map and retain the full log. `CALLBACK_ERROR`, no callback, or a stale
   callback is inconclusive, not success. Do not submit another build in that session.
   Do not reload to bypass the one-attempt limit in this acceptance run.
8. **After a terminal result**, close/reopen the window: no additional command and
   Build Test Track stays disabled for this loaded session. Manual planning may still
   be used without construction. Count exactly one DISPATCH for the confirmed test
   (zero if final revalidation failed). Capture the complete stdout, native messages,
   screenshot and whether camera focus/read-back matched the actual track. Only then
   leave the disposable map. Do not overwrite the original save.

For an already located TF3 stdout file, filter without modifying it:

```powershell
# Set this to the actual stdout path for the test; do not assume a Steam account ID.
$rnaLog = 'REPLACE_WITH_ACTUAL_TF3_STDOUT_PATH'
Select-String -LiteralPath $rnaLog -Pattern '\[RNA:BUILD:MVP\]'
```

## Remaining work before full corridors

- First establish the one-segment native success/failure and visual evidence above.
- Native collision behavior, actual cost, earthworks, resource userdata assignment,
  callback timing/result contents and state-wrapper lifetime still need that test.
- All-site screening is deliberately conservative and may reject otherwise buildable
  terrain. It does not identify a station site or search a route automatically.
- Full corridors need native-validated horizontal/vertical alignment, curvature,
  clearances, terrain effects, resource decisions, bridge/tunnel handling and staged
  user-reviewed proposals. A sampled A* path or successful single straight track does
  not validate any of those contracts.
- Existing-track/station attachments, rollback/cancellation after native submission,
  complete network construction and world-space overlays remain out of scope.

Stop here for owner review and the single in-game experiment. Do not expand construction
or change the accepted planner to force a successful native result.
