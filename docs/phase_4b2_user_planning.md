> Current correction: see **Window alignment, padding and status UX** at the end.
> GUI communication is runtime verified. Earlier A/B instructions are historical.

# Phase 4B.2: user-controlled town selection and planning

Baseline: **ea318ea**, main. Phase 4B.1 was verified by the user (Goole to Morley).
Latest runtime: the window opens with readable layout and without restricted-API
errors; the owner collected 10 towns, but the UI rejects its event result. The final
section records the unresolved communication failure, bounded diagnostics and initial
centering. **Town-list delivery is not claimed fixed.** Earlier corrections are historical.
No staging deployment, world/save writes, commits, tags, pushes or revision changes.

## Verified GUI architecture and critical gate

The gate passed before runtime edits. All local evidence below was inspected
read-only under `D:\SteamLibrary\steamapps\common\Transport Fever 3`.

| Contract | Evidence |
| --- | --- |
| Generic `.res.lua` resources and mod-qualified references | [Official resource documentation](https://wiki.transportfever3.com/doku.php?id=modding:general:resourcetypes). |
| Named mod GUI extension points | [MainModButtonArea](https://wiki.transportfever3.com/script-doc/content/gui/main/main_mod_button_area.html), [ModEntryPoint](https://wiki.transportfever3.com/script-doc/content/gui/main/mod_entry_point.html). These declarations alone are insufficient; the registration chain below establishes actual loading. |
| Registration descriptor | `base/content/gui.zip` ? `gui/game_bar/game_bar_display_earnings_plugin/game_bar_display_earnings.res.lua:3-6`: type `react-plugin ::GameBarInfoDisplayExtension`, data.filePath points to a named script export. Its `.script.tl:7,43-47` registers the recipe and returns its export table. |
| Extension identity and resource discovery | Same archive, `gui/main/react.lua:67-76,92-117`: identity is modId + `::` + name; `getPlugins` enumerates generic resources of type `react-plugin <identity>` and resolves `data.filePath` using util.useFn. `RegisterPluginRecipe:401-407` creates the recipe; registration alone does not place it in an extension. |
| Extension instantiation | `gui/main/main_mod_button_area.tl:7,13` registers the base extension and invokes usePlugins; `gui/main/gui_react_util.tl:513-564` invokes registered recipes. `gui/main/game.tl:380-388,558` includes the mod area; `gui/game_bar/game_bar.tl:174-177` exposes Mods in the radial menu. |
| GUI request/response | [Official GUI API](https://wiki.transportfever3.com/script-doc/api/gui.html), installed `api/tealdef/api/gui.d.tl:50-57`: fireGuiScriptEvent(id,name,param) invokes Game Script guiHandleEvent and returns its result. This is not a simulation command. |
| Shared owner for GUI update/event callbacks | `base/tealdef/scripts/gamescript.d.tl:61-68`: both callbacks receive the script's GUI state. `game_mechanics.zip` ? `game_mechanics/company/company.gs.lua:12-14`, `.script.tl:507-545` demonstrates event dispatch, GUI-state access and response data. No sharing with other scripts is inferred. |
| Reload lifecycle notification | `mission.zip` ? `mission/mission_sim.script.tl:922-925` resets GUI state for `id="gameUI", name="reactPostInit"`. This is handled by RNA, never emitted by RNA. |
| Form controls and component-local hooks | [Official React definitions](https://wiki.transportfever3.com/script-doc/content/scripts/react.html); `base/tealdef/scripts/builtin.d.tl:859-862,1033-1045` defines Button/ComboBox/items; `gui.zip/gui/game_bar/game_bar_widgets.tl:460-484` supplies actual item/value/onValueChange usage. `scripts/react.d.tl:291-311,340` defines state/ref, onStepTimer and onMount. |

The new `live_plan_ui.res.lua` uses `react-plugin ::MainModButtonAreaExtension`.
Its mod-qualified filePath resolves `live_plan_ui.script@RailwayNetworkArchitect`.
The Lua script exposes that recipe through the documented `data()` script-resource
contract. The shipped Teal example returns its export table; that syntax is not
assumed to establish the Lua loader contract. No native recipe is
replaced. No internal `_react` globals, event fallbacks or mutable module singletons
are added. The corrected extension contains only a launcher; the form lives in the
native window container as detailed below.

## Targeted layout correction: verified native window integration

Independent review identified a real layout mismatch in the initial implementation.
The correction changes only `live_plan_ui.script.lua`, `tests/live_plan_test.lua`,
README, AGENTS and this report. The `.res.lua` registration, Game Script owner,
request work, adapter, sampling/configuration and core are unchanged from the
reviewed Phase 4B.2 working tree. No new resources or registration are needed.

Evidence from `base/content/gui.zip` (plus the installed definitions):

| Finding | Exact native evidence |
| --- | --- |
| Mod area is a button row | `gui/main/main_mod_button_area.tl:29-39`: ScrollArea has horizontal Simple, vertical AlwaysOff, containing a Horizontal BoxLayout. Its focus handler at 15-25 enables/focuses the area. |
| ModEntryPoint is a controller entry, not a visible panel host | `gui/main/mod_entry_point.tl:5` defines the extension. `gui/main/game.tl:73-94` instantiates its plugins in FloatingLayout children; 580-590 places EntryPoints under class `invisible`. Simply moving the form there would not provide a visible window. |
| Supported access to the native container | [Official game_react_globals](https://wiki.transportfever3.com/script-doc/content/gui/main/game_react_globals.html), installed `base/tealdef/gui/main/game_react_globals.d.tl:5-7`; `gui/main/game_react_globals.tl:14-19` checks a default-container reference for nil/hasExpired before get():getApi(). `gui/main/game.tl:413-417,606-608` creates/exposes the container. |
| Singleton creation and removal | [Official Builtin definitions](https://wiki.transportfever3.com/script-doc/content/scripts/builtin.html), installed `scripts/builtin.d.tl:1216-1235`; `gui/main/builtin.lua:970-987,1004-1043,1059-1078` implements add/remove keyed by recipe. Adding reuses a singleton; it is not itself a visibility toggle. |
| Shipped window lifecycle | `gui/main/tool_react_util.tl:34-58` adds a singleton and removes its recipe on close/pop. `gui/main/popover_react_util.tl:67-69,103-117` cleans up on owner unmount and passes an onClose callback that removes the window. No tool stack is needed or changed in RNA. |
| Native window, focus and Back | `scripts/builtin.d.tl:1186-1209` declares Window fields. `gui/layers/layers_button_ridge.tl:32-49` wraps builtin.Window, routes IA_MENU_BACK to onClose, sets closable and autoFocusOnBecomingVisible=true, and disables automatic visibility changes on focus loss. `gui/entity_window/view_manager.tl:280-296` demonstrates movable windows. |
| Returning focus | `gui/game_bar/game_bar.tl:174-177` fires `react.fireEvent(nil, "focusMainModButtonArea")`; the area's handler enables focus and focuses its subtree. RNA uses that existing event after explicit close, without a global keybinding or claim of focusing a particular button among other mods. |

`MainModButtonAreaExtension` returns **a horizontal BoxLayout with exactly one Button**. Its click lazily loads
`::/gui/main/game_react_globals.tl`, obtains/checks the default container reference,
and calls `addSingletonWindow(PlannerWindow, params)`. The import occurs after the
native game UI has initialized, avoiding an eager import cycle through game.tl.
The separate `RegisterWrapperRecipe(..., builtin.Window, ...)` owns the complete
form and is instantiated by the window container, outside the mod area's ScrollArea.
The native title bar is closable/movable, with automatic focus on becoming visible
and no automatic hiding on focus loss. Native layout/placement is used; no guessed
screen coordinates, tool replacement or custom window manager is added.

Title-bar close, scoped IA_MENU_BACK, and a second launcher click all remove only
this recipe's window. Explicit close returns focus to the native mod area. Launcher
unmount removes its window without returning focus. The captured container is
checked for expiry before cleanup, rather than accidentally acting on another map's
new container. Window unmount clears the launcher's open indicator. A component-local
generation token prevents delayed callbacks from a removed window from clearing a
newly opened window's state. Missing/expired container access reports UI_ERROR with
its path and a launcher tooltip; no fallback UI or plan is started.

A launcher-local React ref retains the last form selection/snapshot while the window
is closed. The window receives it through ordinary recipe parameters, with no global
state or cross-Game-Script access. On every mount, the unchanged status event checks
the owner; changed world/epoch/catalog identity clears restored selections. While
mounted, the window polls every 0.5 seconds. Closing stops those polls but does not
cancel work in the Game Script. Reopening retrieves current status, including busy
or completed results, without submitting a request.

Relevant correction diff (schematic; unchanged form handlers omitted):

```diff
-local RailwayNetworkArchitect = react.RegisterPluginRecipe(area.MainModButtonAreaExtension, ...)
-    return builtin.BoxLayout {children = {launcher, expandedForm...}}
+local PlannerWindow = react.RegisterWrapperRecipe("OzRailwayNetworkArchitectWindow", builtin.Window, ...)
+    return builtin.Window {onClose = params.onClose, content = form, ...}
+local RailwayNetworkArchitect = react.RegisterPluginRecipe(area.MainModButtonAreaExtension, ...)
+    return builtin.BoxLayout {orientation = builtin.type.Orientation.Horizontal, children = {
+        builtin.Button {onClick = function()
+            container:get():getApi().addSingletonWindow(PlannerWindow, params)
+        end, ...},
+    }}
```

Five added tests verify separate roots/registration, focus and close properties,
launcher/title-bar/Back paths, reopen selection, closed-window session reset,
background-request completion, refresh, owner/window cleanup, delayed detach safety,
and missing/expired container rejection. All earlier tests are retained. **81 tests
pass (22 planning + 20 railway + 39 live/UI), with 32 Lua syntax checks.** These are
mock tests, not native layout or focus verification. Runtime checks must still cover
window placement at the user's resolution/UI scale, dropdown popup bounds,
controller/keyboard focus including Back when a dropdown is open, close/reopen during
planning, and same-process reload. No staging deployment was performed.

## Ownership and interaction lifecycle

- **React UI:** the launcher owns window lifecycle and the transient reopen ref;
  the separate window owns active form/view hooks and the local submission guard. Entity IDs are ComboBox values; visible labels append
  `[#ID]`, so duplicate names are safe. The other selected town is unavailable in
  each list. The Plan handler and backend independently reject identical IDs.
- **Existing Game Script:** owns the bounded town catalog, world/tick, epoch,
  last request ID, active request and retained result. No inventory GUI state is read.
- **Request module:** accepted sampling/planning work extracted from the previous
  callback into `live_plan_request.lua`; it receives the owner's explicit request
  table. The core and API adapter remain unchanged and have one authoritative copy.
- UI sends only the namespaced events `oz_railway_network_architect.plan.status`,
  `oz_railway_network_architect.plan.plan`, and `oz_railway_network_architect.plan.refresh`
  under component ID `oz_railway_network_architect.plan` using protected fireGuiScriptEvent calls.
  Status returns a small summary and at most 256 town labels, never the grid or paths.
  The window polls status every 0.5 seconds only while mounted; it never initiates
  planning from a timer, mount hook, load or status query.
- Valid-world/advancing-tick readiness precedes town enumeration. Collection is
  capped at 256 references and eight town reads every fourth callback. The UI shows
  waiting/loading/idle/unsupported/error. No terrain reads occur until Plan.
- Each Plan carries world, epoch, next request ID and two numeric entity IDs. Busy
  requests are rejected; tokens cannot replay. Selected IDs must belong to the
  catalog and still exist with TOWN components and finite in-bounds positions.
  IDs becoming invalid are rejected, never replaced by a closest pair.
- Each accepted click creates a fresh request. Only those two entities are reread;
  their current centers become the approximate anchors. Fresh bounds/terrain are
  sampled; positions and bounds are checked again before search. Completed results
  remain in GUI memory until the next accepted request, refresh or reset.
- A new click is allowed after completion/failure. A fatal catalog error requires
  Refresh towns; a failed planning request can be retried directly. Refresh clears
  the displayed selections. The town catalog is not automatically maintained after
  town creation/deletion/renaming; explicit Refresh updates it.
- `gameUI/reactPostInit`, changed world identity or regressed tick invalidates the
  active request, clears catalog/results, advances epoch and requires new selection.
  No GUI SaveData, engine-state writes, files or save persistence. Same-process reload
  still requires native verification; a reused world ID with increasing tick cannot
  prove continuity if the documented notification is absent.

Prototype limits remain unchanged: <=32x32 samples, 32/64/128 world-unit spacing,
<=3,072 expansions, 16 terrain points every fourth callback, <=60 seconds snapshot
age and <=min(96 world units, 10% pair distance) per endpoint snap. Water defaults
to excluded. Town centers are not stations; no buildings/infrastructure obstacle
source, subcell terrain accuracy, construction geometry or actual costs are claimed.

## Timing investigation

`api/tealdef/api/util.d.tl:174-176` defines getApplicationTime as seconds since
application start, GUI thread only. It does **not** define effective resolution,
refresh cadence, monotonicity guarantees or suitability for within-callback profiling.
Shipped uses inspected in `gui.zip/gui/menu/menu_util.tl:35-37` and
`game_mechanics.zip/game_mechanics/celebrations/celebration_react_util.tl:187-225`
measure animation/cooldown intervals across callbacks, not a high-resolution work
benchmark. The public util page was unavailable during this research; the installed
definition is the timing source. `api.gui.benchMark` supplies aggregate frame samples,
not a verified per-request timer, and is not used. No speculative os.clock/native timer
or asynchronous execution mechanism was introduced.

**Effective sub-callback resolution cannot be established from these sources.**
The accepted observation (0.000000 work, 0.660969 elapsed) is consistent with a
cached/frame-updated clock but does not prove that internal explanation. It does
not establish work below 50 ms.

The request logs raw observed work deltas and search delta, plus explicit
`resolution=unknown`. Any zero work delta sets `work_measurement=insufficient_resolution`.
Positive readings still carry `unverified_resolution`. Elapsed time includes scheduling
and callback waits; minimum observed positive gaps between work callbacks are reported
separately and explicitly are **not clock resolution**. The first request validation,
town-list work, React render, state copies and summary logging are not included in
max_work_callback_seconds (town batches separately retain the same observed 50 ms guard).

Observed work >50 ms still aborts/discards candidates. This is a post-return check,
not cancellation, and may miss stalls with an unsuitable clock. No budget was raised.
Real GUI responsiveness remains a required acceptance observation; a stall means
stop and review resumable work, not assume the zero timer proves safety.

## Changed files and relevant diff

```text
AGENTS.md                                      updated scope/conventions
README.md                                      updated use/testing/deployment
 docs/phase_4b2_user_planning.md                 new evidence/report
 oz_railway_network_architect/content/
   live_plan.gs.lua                            adds guiHandleEventScript
   live_plan.script.lua                        session/catalog/request owner
   live_plan_data.lua                          adds explicit-ID pair validation
   live_plan_request.lua                       extracted accepted request work
   live_plan_ui.res.lua                        new generic plugin descriptor
   live_plan_ui.script.lua                     launcher and separate native window
   live_plan_ui.css.lua                        scoped bounded window/form stylesheet
 tests/live_plan_test.lua                       evolved integration/UI tests
 tests/run_lua_tests.py                         event-reference/docs encoding checks
```

```diff
+guiHandleEventScript = {
+    fileName = "oz_railway_network_architect::/live_plan.script@guiHandleEvent",
+}
-pair = flow.select(session.towns, session.bounds, config)
+pair = flow.selected(session.towns, session.bounds, session.sourceId, session.destinationId)
-session.ids = adapter.ids(config.maxTowns)
+session.ids = {session.sourceId, session.destinationId}
+type = "react-plugin ::MainModButtonAreaExtension"
+filePath = "oz_railway_network_architect::/live_plan_ui.script@RailwayNetworkArchitect"
```

The excerpts show the architectural changes; the complete local diff includes
request extraction, owner lifecycle and the recipe. All 19 accepted inventory,
bootstrap/identity files, live_plan_api.lua and all three core files are unchanged.
No duplicated algorithm or competing automatic planner is registered. The old pure
closest-pair helper remains only for historical preparation tests, not the live path.

## Automated validation

Run `uv run --no-project --offline --with lupa==2.8 python tests/run_lua_tests.py`.
No dependency was installed. **96 tests pass:** 22 original planning, 20 original
railway and 54 evolved live preparation/request/UI tests. The old automatic-lifecycle
tests were adapted to explicit requests, retaining coordinate/missing-data/water/
limit checks. Tests exercise the actual recipe, descriptor, handler, request work
and unchanged core through mocks. They cover no automatic planning, duplicate names,
same/stale IDs, replay/busy rejection, sequential fresh plans, world/tick/reload resets,
failed samples, unreachable/search/performance limits and unresolved zero timing.

Static checks: 32 Lua files; JSON; UTF-8 without BOM; local imports and both Game
Script callback exports; plugin descriptor/export through the UI test; reviewed
base-game imports against installed archives. No world-changing operations. Mock
React does not establish native layout, dropdown behavior or cross-resource dispatch.

## Exact staging update

After review, close TF3 and run the following manually from PowerShell. It updates
three files and adds three files under the existing staging copy. It checks all
26 accepted files against ea318ea (line-ending-normalized hashes), permits an
already-copied replacement only if it matches the current source, and validates
existing new files before overwriting. No deletes, recursive copy, save access or
original game changes. The agent has **not** executed these commands.

```powershell
$rnaSource = 'D:\code\transport-fever-3\railway-architect\oz_railway_network_architect'
$rnaTarget = 'C:\Program Files (x86)\Steam\userdata\175442176\3493540\local\staging_area\oz_railway_network_architect'
if (Get-Process -Name TransportFever3 -ErrorAction SilentlyContinue) { throw 'Close TF3 first.' }
$rnaSource = (Resolve-Path -LiteralPath $rnaSource -ErrorAction Stop).Path
$rnaTarget = (Resolve-Path -LiteralPath $rnaTarget -ErrorAction Stop).Path
foreach ($rnaRoot in @($rnaSource, $rnaTarget)) {
    $rnaManifest = Get-Content -LiteralPath (Join-Path $rnaRoot 'mod.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($rnaManifest.modId -ne 'oz_railway_network_architect' -or $rnaManifest.revision -ne 1) {
        throw "Unexpected identity/revision: $rnaRoot"
    }
}
function Get-RnaTextHash([string]$rnaPath) {
    $rnaText = [System.IO.File]::ReadAllText($rnaPath).Replace("`r`n", "`n")
    $rnaSha = [System.Security.Cryptography.SHA256]::Create()
    try {
        return [BitConverter]::ToString($rnaSha.ComputeHash([Text.Encoding]::UTF8.GetBytes($rnaText))).Replace('-', '')
    } finally { $rnaSha.Dispose() }
}
# Accepted ea318ea content, with CRLF normalized to LF solely for comparison.
$rnaBaseline = @{
    '_metadata\modinfo.json' = '2BDB685AED8E88C9E3F74D12EA01A863598C0EDD0D6E66D90C9B9F97A05BEA32'
    'content\city_inventory.gs.lua' = 'CC0CB414A3C9D2D162FE8B139A5A599970B798316B1C48BF43D582691C05628D'
    'content\city_inventory.script.lua' = '5B88B86C466D7F341CF4C15715413EF56721A03142A4631111871648846D0A56'
    'content\city_inventory_api.lua' = 'F99CEF71494BA9F50AB77C1FF61A4DB35DA023451F72DD8C214972398880DF6D'
    'content\city_inventory_data.lua' = '67AD1180E87361E256CE5FE7B53946C77E93E1E084BE69EEBDBA3564C5433C89'
    'content\industry_inventory.gs.lua' = 'E05367C6A7274861A399E833AC15535BB20EB5B1C3478F7A7997C65CF6C92A32'
    'content\industry_inventory.script.lua' = '5B2E5E7A4A7933754BFC3A0DAAB8224A249CA9AEDCDEF39B305CF29D7829351A'
    'content\industry_inventory_api.lua' = 'A1240414294814F3310B33D180B729502D8E28618D609D7B794CCA8FD4D25E96'
    'content\industry_inventory_data.lua' = '8B0A713263F39B4D0ACB32BB647333F74EE0BDF45FE544B1690BEA0EF794F30E'
    'content\live_plan.gs.lua' = '2F9D02DCBA4E674B21939B6A4AC96B3CCCECDAC16207EF224D7C1EA7CDD88A76'
    'content\live_plan.script.lua' = '67DF25B09963186C44B358AEE6074790E6D75655F0D85C98D52D2A9CD7D9F8C5'
    'content\live_plan_api.lua' = '3AC6F03B42AAACC051AE3A79457DCED86E72D6D7C6FF1F327A8D947710CCEF1E'
    'content\live_plan_data.lua' = 'CF2DA8B3E38F6F4CA417C810FD8BA668353444EA59C6D149DAB0062E7B6C01F8'
    'content\mod.script.lua' = 'DC163E644B858760787AEBFC1D3771682CC7ED98B322BE3DCB4DC287BE0A8BBD'
    'content\planning\corridor_grid.lua' = 'B8C51912841FD78E178F13071C11CF78A769E33D2493B7057DB7F3462A4E42C9'
    'content\planning\corridor_planner.lua' = '34BAB9B0DEBE700D5CF1EB85E56723178E51856F1147E1573953F213765559CE'
    'content\planning\corridor_search.lua' = '5BEEB8F46DDB7AA52C4877AD86F31B84B2DFACA48885CFB03D4E132CD416BF83'
    'content\rail_inventory.gs.lua' = 'C73F4EFF72CF1E88CC848510186CDF94ACCCB3D5BEB0A742301059E49ABAF476'
    'content\rail_inventory.script.lua' = '149C5FAF9D3E8C7E8AC5BAE4D6B7F4F17B48A0A55D7FB5C209EB0928792D9B3D'
    'content\rail_inventory_api.lua' = '2FCF5CDF888FBD880A5392296912C2A0A4D7266740FF4EBE3349C82CED74F8E0'
    'content\rail_inventory_data.lua' = '2F928BB031853F5A71C1355A3E1B0D8AA1516F34A6ED8C944DC1194BEC0896D3'
    'content\terrain_inventory.gs.lua' = '1562020F2EB53BE52F02F5C9C8809E87A2B7B49B3DD0EC4FEA902189D4C7068B'
    'content\terrain_inventory.script.lua' = '2A4E2629665EBC78803980A06EE998D194BE5BE5BA081CADEE1725633D3E1870'
    'content\terrain_inventory_api.lua' = '7388AFB96EEA6348BC5CD7DD796B594453EE4A46173AA92168710D633B423C1D'
    'content\terrain_inventory_data.lua' = '33699B5A04F80D7C2607F7CE92B03B50D75E16EAB1BF2379CFACB81DCF268757'
    'mod.json' = 'D2B541EE9A243AFBD3994D138F6D05D1E70FD06BDC7443224B4C7BCACE1AA3C1'
}
$rnaReplaced = @('content\live_plan_data.lua', 'content\live_plan.script.lua', 'content\live_plan.gs.lua')
$rnaAdded = @('content\live_plan_request.lua', 'content\live_plan_ui.script.lua', 'content\live_plan_ui.res.lua', 'content\live_plan_ui.css.lua')
foreach ($rnaFile in $rnaBaseline.Keys) {
    $rnaInstalled = Get-RnaTextHash (Join-Path $rnaTarget $rnaFile)
    $rnaCurrent = Get-RnaTextHash (Join-Path $rnaSource $rnaFile)
    if ($rnaFile -notin $rnaReplaced -and $rnaCurrent -ne $rnaBaseline[$rnaFile]) {
        throw "Unexpected change to preserved source: $rnaFile"
    }
    if ($rnaInstalled -ne $rnaBaseline[$rnaFile] -and
        -not ($rnaFile -in $rnaReplaced -and $rnaInstalled -eq $rnaCurrent)) {
        throw "Staging baseline mismatch; review: $rnaFile"
    }
}
foreach ($rnaFile in $rnaAdded) {
    $rnaCurrent = Get-RnaTextHash (Join-Path $rnaSource $rnaFile)
    if ((Test-Path -LiteralPath (Join-Path $rnaTarget $rnaFile)) -and
        (Get-RnaTextHash (Join-Path $rnaTarget $rnaFile)) -ne $rnaCurrent) {
        throw "Unexpected existing resource; review: $rnaFile"
    }
}
# Dependencies first; the new plugin registration is last. TF3 must stay closed.
$rnaFiles = @('content\live_plan_request.lua', 'content\live_plan_ui.script.lua',
    'content\live_plan_data.lua', 'content\live_plan.script.lua',
    'content\live_plan.gs.lua', 'content\live_plan_ui.res.lua', 'content\live_plan_ui.css.lua')
foreach ($rnaFile in $rnaFiles) {
    Copy-Item -LiteralPath (Join-Path $rnaSource $rnaFile) -Destination (Join-Path $rnaTarget $rnaFile) -Force -ErrorAction Stop
    if ((Get-FileHash -LiteralPath (Join-Path $rnaSource $rnaFile)).Hash -ne
        (Get-FileHash -LiteralPath (Join-Path $rnaTarget $rnaFile)).Hash) { throw "Copy verification failed: $rnaFile" }
}

```

Keep TF3 closed throughout. If interrupted, rerun before launching; matching
already-copied files are permitted. Unexpected mismatches stop for review. On a
different Steam account, substitute its verified staging path first. Do not copy
tests/docs, create duplicate active IDs or publish via Mod Hub. Mod revision stays 1.

## Expected logs

Ordering of UI mount and Game Script initialization depends on native loading.
Values below are placeholders, not runtime evidence.

```text
[RNA:PLAN:4B2] UI_INIT entry=MainModButtonArea launcher_only=true request=none
[RNA:PLAN:4B2] SESSION_RESET reason=reactPostInit
[RNA:PLAN:4B2] UI_SESSION_READY status=waiting request=none
[RNA:PLAN:4B2] TOWNS available=<count> rejected=<count> read_errors=<count>
[RNA:PLAN:4B2] STATE status=idle request=none
```

Nothing resembling REQUEST_START, terrain sampling or search should follow until Plan.

```text
[RNA:PLAN:4B2] REQUEST_START request=<n> source_id=<id> destination_id=<id>
[RNA:PLAN:4B2] START world=<id> tick=<tick> app_seconds=<seconds>
[RNA:PLAN:4B2] ENDPOINT_VALIDATION status=ok source_id=<id> destination_id=<id>
[RNA:PLAN:4B2] SELECT method=user_selected_entity_ids source_distance=<distance>
[RNA:PLAN:4B2] TOWN role=<start|destination> id=<id> name="<name>" source_x=<x> source_y=<y> source_z=<z> position_source=bounding_volume_center
[RNA:PLAN:4B2] GRID columns=<n> rows=<n> spacing_x=<step> spacing_y=<step> origin_x=<x> origin_y=<y> requested=<n> unit=world_units
[RNA:PLAN:4B2] ENDPOINT role=<start|destination> sample_id=<id> x=<x> y=<y> dx=<dx> dy=<dy> snap_distance=<distance> policy=nearest_sample_half_up
[RNA:PLAN:4B2] TERRAIN processed=<n> requested=<n> valid=<n> invalid=<n> failed_samples=<n> failed_reads=<n>
[RNA:PLAN:4B2] SEARCH status=<status> complete=<bool> candidates=<n> expansions=<n> duration_seconds=<observed>
[RNA:PLAN:4B2] PERFORMANCE max_work_callback_seconds=<observed> budget_seconds=0.050000 elapsed_seconds=<elapsed> gui_state_copy_and_summary_logging_excluded=true
[RNA:PLAN:4B2] TIMING resolution=unknown work_measurement=<insufficient_resolution|unverified_resolution> zero_is_not_zero_cost=true elapsed_includes_scheduling=true preemptive=false min_observed_between_work_callbacks_seconds=<gap|unavailable> callback_gap_is_not_clock_resolution=true
[RNA:PLAN:4B2] COMPLETE status=<status> candidates=<n> data_complete=<bool> reason="<reason>"
```

Retained Phase 4B.1 ANCHOR_HEIGHT, SNAPSHOT, PROFILE, CANDIDATE and WARNINGS fields
now use the 4B2 prefix. At most three candidate summaries and four terrain/town
error examples per collection are emitted; no grid or waypoint dumps. Rejections
log `REQUEST_REJECTED reason=<busy|same_town|stale_session|selected_town_unavailable|...>`;
endpoint failures include ENDPOINT_ERROR API paths. Fatal catalog/initialization
errors use ERROR. UI dispatch failures show Interface error; clicks log UI_ERROR.
A communication failure logs once and pauses automatic polling until an explicit retry; status polls do not log continuously. COMPLETED is represented by COMPLETE plus
its status; unsupported/unreachable/search_limit are explicit outcomes, not successes.

## Manual acceptance

1. Review code, then manually update staging with TF3 closed. Enable revision 1.
2. Load a disposable test map. Briefly unpause. Confirm all four inventory scans
   still finish. Expect the town list but **no automatic REQUEST_START/search**.
3. Find the single Railway Network Architect launcher in the native mod-button area;
   the native Mods radial-menu entry also focuses that area. Click to open a separate
   movable native window. Inspect placement, size and dropdown visibility at the
   current UI scale. Close with the title bar, Back and launcher toggle; reopen each
   time. Selections should survive within the same session. Back while a dropdown is
   open must respect native focus/bubbling. Other mods and controls must still work.
4. Select two towns. Verify visible names plus IDs, disabled same-town option and
   disabled Plan until both distinct selections exist. If possible test duplicate names.
5. Press Plan once, then click repeatedly while busy: only one accepted REQUEST_START.
   Observe planning status, responsiveness and final state; verify chosen IDs, grid,
   snap distances, sample counts and candidate summaries. No buildability claims.
6. Close while busy, then reopen: the same request should continue or be completed,
   with no duplicate REQUEST_START. After completion or a no-route result, choose another pair and Plan again.
   Expect a new request ID and fresh terrain scan, not a replay of prior samples.
7. Test distant/poorly represented pairs and water-separated towns. Unsupported or
   unreachable must be explained; Refresh towns must recover a catalog failure.
8. With a disposable map, change/remove a selected town before Plan if convenient.
   The stale selection must fail without choosing another pair. Refresh clears it.
9. Reload the same save within the process, load a different map and relaunch TF3.
   Selections/results reset and no plan occurs until a new click. Watch SESSION_RESET.
10. Capture timing fields and TF3 build, sample/expansion counts and observed latency.
    A zero work reading is inconclusive. Any noticeable freeze requires review.
11. Retain `[RNA:PLAN:4B2]` plus surrounding errors before another launch replaces
    stdout. Stop at Phase 4B.2 for review; no Phase 4B.3 or construction is authorized.

Remaining uncertainty: native GUI layout and dispatch, lifecycle notification coverage,
clock resolution, simultaneous map edits during sampling, and any cross-mod event
interference. Namespacing and session tokens reduce collisions but mocks cannot prove
native behavior. The scan is not atomic; no changes to accepted search limits hide
these risks.


## Restricted GUI API and bounded window correction

This targeted change preserves the Game Script request owner, planner, terrain
sampling, four inventories, plugin registration, identity and revision. The prior
working tree already contained Phase 4B.2 implementation changes; those are not
new changes made by this correction.

### Source-backed diagnosis

Installed root: `D:\SteamLibrary\steamapps\common\Transport Fever 3`.
Archive paths below are entries inside `base/content/gui.zip`; nothing was extracted
into or written to the installation.

| Contract or finding | Installed evidence |
| --- | --- |
| Timer callbacks run restricted | `gui/main/react.lua:525-534` wraps onStepTimer callbacks in enqueueDeferredStep. `base/tealdef/scripts/react.d.tl:400` explicitly describes restricted API access in parallel rendering preparation. This establishes that our former direct call on every poll was invalid. |
| Supported main-thread handoff | `react.d.tl:401` describes enqueueJoin(fn, debugScope) running on the main thread after parallel React work. `gui/main/react.lua:9-53` maintains separate deferred/join queues. `gui/construction/construction.tl:4299-4320` uses onStepTimer -> enqueueJoin(updateParamsVisibility, scope), while its event path invokes that operation directly. |
| GUI event and synchronous response | `api/tealdef/api/gui.d.tl:50-57` and [official api.gui](https://wiki.transportfever3.com/script-doc/api/gui.html) document fireGuiScriptEvent(id, name, param) returning guiHandleEvent's result. `gui/game_bar/game_bar_widgets.tl:446-449` calls it directly from a user onValueChange callback. No alternative transport was introduced. |
| Mount context uncertainty | `gui/main/react.lua:551-557` forwards mount/unmount to native context callbacks; it does not establish their thread/API permissions. The reported line identifies send(), not its caller. We cannot prove whether the initial error was mount or timer. Both now only enqueue the same main-thread dispatch. |
| Expired state guards | `base/tealdef/scripts/react.d.tl:123-141` declares hasExpired for state and refs; `gui/main/builtin.lua:1167-1177` guards a state update with hasExpired. Both before dispatch and before applying its response, RNA checks live state, mount lifetime, window generation and container lifetime. |
| Stylesheet discovery | [Official resource types](https://wiki.transportfever3.com/doku.php?id=modding:general:resourcetypes) identifies .css.lua stylesheets by file extension. `gui/main/stylesheetutil.lua:5-81` parses selectors and returns style entries via makeAdder. |
| Native bounded window and wrapping | `gui/entity_window/entity_window.css.lua:33-38` sets Window minSize/maxSize. `gui/main/internal.css.lua:779-785` demonstrates viewport-relative max height and fixed window size. `gui/context_helper/context_helper.css.lua:138-142` bounds TextView width and enables textAutoWrap. `gui/main/builtin.css.lua:2000-2002` uses innerSpacing; entity-window styles use padding. |
| Native scrollable content | `base/tealdef/scripts/builtin.d.tl:749-766` defines ScrollArea content/policies and Component.layout. `gui/main/main_mod_button_area.tl:29-40` demonstrates ScrollArea -> Component -> BoxLayout and native scrollbar enum constants. RNA uses that same structure vertically within its own Window. |

The event fix uses the documented main-thread handoff; the installed Lua does not
expose the C++ permission checks for fireGuiScriptEvent. Its permission in the
actual join phase must still be verified in TF3. No blanket claim is made that
all lifecycle or all user callbacks have unrestricted access.

The old form had no mod-owned width/height limits, text wrapping or scrolling.
That is a verified omission consistent with the reported symptoms, not proof of
the renderer's precise cause for every overlap. No screenshot was provided in this
request. The new stylesheet targets only RNA classes: 520x520 preferred window,
520 maximum width and 80vh maximum height; scrollable content, 440-unit wrapped
text/dropdowns, 8-unit spacing and 12-unit form padding. Native scaling, title bar,
movement and focus remain in charge. Long diagnostic text stays in the scrollable
form; it cannot determine an unbounded preferred window width. No guessed widget
width/height parameters, clipping API or global style override is used.

### Request behavior and regression checks

Mount and 0.5-second polling only queue status work. Plan/Refresh also queue their
existing namespaced event. At most one event is pending per window; duplicate
clicks/polls cannot queue a storm. Dispatch still calls fireGuiScriptEvent and applies
its returned status. The owner continues to validate world/epoch, IDs and replay tokens.
Nothing plans automatically. Closing before a join discards the pending event;
closing after acceptance does not cancel the Game Script's planning operation.

Communication failure shows the actual error (existing bounded diagnostic length),
logs one `UI_ERROR api=api.gui.fireGuiScriptEvent action=... polling=paused detail=...`,
and stops periodic retries. Plan is disabled while transport is failed. Refresh towns
explicitly retries, including when the last known snapshot was busy; a successful
response restores polling. Closing/reopening also requests fresh status. No town
list is fabricated on failure.

All **81 tests** pass: the original 73 plus eight regression groups. The mock now
runs render/mount/timer work in a restricted context, rejects fireGuiScriptEvent
there, and executes explicit queued joins in a separate permitted context. It rejects
writes to expired hooks. Tests cover initial status, repeated polling, coalescing,
Plan/Refresh duplicate protection, unmount before/during dispatch, expired state,
launcher/container expiry, stale callbacks after reopen, error pause/retry, no automatic
planning, and scoped size/wrap/scroll properties. Existing selection/session reset,
request lifecycle, rail graph and A* scenarios remain covered.

Static validation: 32 Lua files, JSON, UTF-8 without BOM, mod identity/revision,
resource references and callback exports. Native stylesheet rasterization and the
engine's permission enforcement are outside these mocks.

### Minimal staging patch for the already installed Phase 4B.2 UI

These are instructions only; no staging files were changed.

1. Close TF3 completely. In the existing development mod under Steam staging_area,
   verify mod.json still has modId `oz_railway_network_architect` and revision 1.
2. Back up the installed `content/live_plan_ui.script.lua` somewhere outside the mod.
   If `content/live_plan_ui.css.lua` already exists, back it up too and review it
   before replacement. Do not delete the installed mod or touch saves/game archives.
3. Copy **only these two files** from this repository's mod directory into that
   same development mod, preserving their relative paths:
   - `content/live_plan_ui.script.lua` (replace)
   - `content/live_plan_ui.css.lua` (add; replace only after review if already present)
4. Compare source and destination SHA-256 hashes for both files. Leave mod.json,
   metadata, descriptors, request owner, planner and inventories unchanged. Repository
   documentation and tests do not belong in staging.
5. Start TF3, load the test map and briefly unpause for readiness. Open the launcher:
   expect a bounded movable window and a real town list; no REQUEST_START before Plan.
6. Confirm no restricted-API error through several polls. Check dropdowns and long
   status text at the current UI scale, vertical scrolling, title-bar close/Back,
   reopen selection, Refresh, repeated Plan clicks, busy close/reopen and map reload.
   A request closed before dispatch must not start later from a stale window.
7. Preserve `[RNA:PLAN:4B2]` logs. On communication failure expect one UI_ERROR and
   a visible paused-polling message, not errors every 0.5 seconds. Stop for review if
   this occurs. A clean mock run is not native runtime success.

Only runtime verification can establish joined GUI event permission, stylesheet
loading/rendered sizes at different resolutions/UI scales, dropdown popup sizing,
focus/Back behavior and native teardown ordering. Stop at Phase 4B.2.


## Current investigation: missing event response and initial centering

**Outcome: communication root cause remains unverified; diagnostic instrumentation
and source-backed centering are implemented.** Do not treat this as a proven repair
of native town-list delivery or install it before review.

### Evidence and precise boundary of knowledge

Read-only comparison found the installed staging descriptor, owner, UI script,
stylesheet and mod.json identical to the pre-change workspace (normalizing line
endings). A stale staging copy is not supported by that evidence.

The existing `local/crash_dump/stdout.txt` records, on 2026-11-03:

- 10:23:25Z: a GameScript entity was created for the mod's live_plan.gs.
- 10:23:39Z: UI_SESSION_READY from the owner.
- 10:23:41Z: TOWNS available=10 rejected=0 read_errors=0, then STATE status=idle.
- 10:23:45Z: UI status response unavailable; later explicit Refresh attempts failed too.

This proves owner initialization and town collection in that run. It does not prove
entry into guiHandleEvent, successful ID/name matching, or native response propagation.
The earlier generic error did not distinguish nil, wrong response type, missing towns
or invalid epoch. No actual result value was logged. No fabricated fallback or
speculative subscription/event change has been made.

Installed root: `D:\SteamLibrary\steamapps\common\Transport Fever 3`.

| Verified contract | Source evidence |
| --- | --- |
| Descriptor registration | Our live_plan.gs.lua has guiUpdateScript and guiHandleEventScript references to the two data() exports in live_plan.script.lua. `base/content/game_mechanics.zip`, `game_mechanics/company/company.gs.lua:12-14` uses the same event descriptor field. References and exports pass static validation. |
| Callback order and GUI owner | `base/tealdef/scripts/gamescript.d.tl:61-68` declares userParams, read-only engine state, GUI state, src, id, name, param. Both GUI callbacks receive their script's GUI state. [Official Game Script definitions](https://wiki.transportfever3.com/script-doc/content/scripts/gamescript.html). |
| Direct call and return | `api/tealdef/api/gui.d.tl:50-57` documents fireGuiScriptEvent(id,name,param) returning the handler result. [Official GUI API](https://wiki.transportfever3.com/script-doc/api/gui.html). No target script/resource argument is declared. |
| Shipped table-return consumer | `base/content/gui.zip`, `gui/construction/construction_react_util.tl:1531-1537` calls company.lockPermits and inspects a returned table. `game_mechanics/company/company.script.tl:507-552` matches the event name and returns either a table of errorMessages or an empty table. Its GUI handler ignores component ID; this does not justify ignoring RNA's own namespaced ID. |
| Routing | The UI sends component ID oz_railway_network_architect.plan and names ending .status, .refresh, .plan. The owner checks that exact ID and prefix/action. These literals agree. The native implementation of event broadcast/result aggregation is not present in the inspected Lua/Teal definitions; no ordering or winner rule can be established. |
| Subscriptions | GameScriptState declares subscription methods. The shipped examples inspected subscribe engine state for simulation events; they do not establish that our GUI event requires an added subscription. None was invented. |
| Centering | `base/tealdef/scripts/builtin.d.tl:1186-1203` declares initialX/initialY and movable. In gui.zip, `gui/menu/mod_manager_react_util.tl:3671-3683` creates UninstallDialogWindow with initialX=0.5 and initialY=0.5. Its dialog CSS at `gui/main/popover_react_util.css.lua:10-12` only changes background color. [Official Builtin definitions](https://wiki.transportfever3.com/script-doc/content/scripts/builtin.html). |

### Changes and relevant diff

Only these six files change relative to the preceding runtime fix:

```text
AGENTS.md
README.md
docs/phase_4b2_user_planning.md
oz_railway_network_architect/content/live_plan.script.lua
oz_railway_network_architect/content/live_plan_ui.script.lua
tests/live_plan_test.lua
```

The descriptor, stylesheet, request module, data module, sampling, limits, inventories,
A* and metadata remain unchanged. The owner changes only diagnostic markers/counter
and an additive response correlation field; its routing and planning logic are intact.

```diff
+-- UI request: additive diagnostic envelope, not the Plan replay token
+request._rnaTrace = trace
+traceEvent("GUI_DISPATCH ...")
 local value = api.gui.fireGuiScriptEvent(eventId, eventId .. "." .. name, request)
+traceEvent("GUI_RESULT type=... towns_type=... epoch=... response_trace=...")
+-- Validate the fields consumed by rendering before applying the snapshot.

+-- Owner: entry, explicit route decision, and response creation markers
+local value = response(state, accepted, reason)
+value._rnaTraceId = traceId
+traceEvent("HANDLER_RESPONSE ...")
-return response(state, accepted, reason)
+return value

 closable = true, movable = true, pinnable = false,
+initialX = 0.5, initialY = 0.5,
```

This excerpt abbreviates diagnostic strings; the actual code reports types, route
rejection reasons, epoch, status, town count and correlation echo. It never dumps
the town list, grid or waypoints. IDs such as w1:e1 are unique within a launcher
lifetime, with a new sequence value on every dispatched event and a window-generation
prefix. They deliberately do not replace the Game Script's requestId/epoch/world
validation. They are not globally unique across application restarts; UI_INIT marks
the new diagnostic scope.

The UI traces its first eight dispatches per launcher lifetime. The owner caps tracing
at eight relevant events per GUI session, including namespaced events whose diagnostic
payload is missing. Such entries show trace=unavailable and the actual parameter type.
Each traced exchange has at most five boundary markers. Normal polling then continues
without trace logs. A transport/shape failure still pauses polling and emits one
UI_ERROR with the trace ID. Each explicit retry may report another failure. No
per-frame diagnostics or background retries were added.

Nil and malformed responses now identify the failed field. Status/request/catalog
fields and bounded dense town arrays are checked before they can reach render logic.
An invalid response leaves the previous snapshot intact, reports a visible interface
error and disables Plan; it never creates a successful town list. The same documented
synchronous return transport and main-thread enqueueJoin remain in use.

Initial centering uses only the native normalized placement fields. No pixel position,
repeated repositioning, viewport query, stylesheet size change or dragging restriction
is added. Close still removes the native singleton; reopen instantiates a window with
the same initial centering parameters. Native position retention by ID and actual
scaled placement after dragging/reopening remain runtime acceptance checks.

### Tests and limits of the mock

**87 tests pass: 20 rail + 22 A* + 45 live/UI**, including all preceding 81 tests.
The six added groups cover descriptor-based resolution, original event ID/name/param
forwarding, shared owner state, successful town data, wrong routes, nil handler result,
a deliberately discarded return, malformed response shapes, recovery, bounded traces,
unique per-launcher correlation, stale/busy/replayed requests, and initial centering
on open/reopen. Existing explicit Plan/Refresh and no-auto-plan tests still pass.

The mock now resolves the actual .gs.lua exports rather than assuming their registration,
and passes original arguments directly in the documented seven-argument order. It models
one handler's documented return contract; it does NOT model unknown native broadcasting,
aggregation or marshalling. Fault injection demonstrates observability of those boundaries,
not their actual cause in TF3. Lua syntax (32 files), JSON, UTF-8, imports, resources,
identity/revision and scope checks pass.

### Minimal staging update after review

Do not run this step until the code is reviewed. No deployment was performed.
Close TF3, back up the following installed files outside the mod, then replace only:

```text
content/live_plan.script.lua
content/live_plan_ui.script.lua
```

Source root: `D:\code\transport-fever-3\railway-architect\oz_railway_network_architect`.
Existing target root:
`C:\Program Files (x86)\Steam\userdata\175442176\3493540\local\staging_area\oz_railway_network_architect`.
Verify target modId/revision, preserve relative paths and compare SHA-256 hashes after
copying. The stylesheet and descriptor already match the intended versions and need
no replacement for this change. Do not copy tests/docs or touch saves/game archives.

### Exact runtime evidence and acceptance criteria

Start a new test session to reset diagnostic budgets. Capture logs from UI_INIT through
the first status exchange and one explicit Refresh. Expect this sequence on successful
native delivery (values are examples, not manufactured runtime results):

```text
[RNA:PLAN:4B2] COMM GUI_DISPATCH id=oz_railway_network_architect.plan name=oz_railway_network_architect.plan.status trace=w1:e1
[RNA:PLAN:4B2] COMM HANDLER_ENTRY src=<native source> id=oz_railway_network_architect.plan name=oz_railway_network_architect.plan.status param_type=table trace=w1:e1
[RNA:PLAN:4B2] COMM HANDLER_ROUTE accepted=true action=status trace=w1:e1
[RNA:PLAN:4B2] COMM HANDLER_RESPONSE type=table epoch=<epoch> status=idle towns=<count> accepted=false reason=nil trace=w1:e1
[RNA:PLAN:4B2] COMM GUI_RESULT type=table towns_type=table epoch=<same epoch> response_trace=w1:e1 trace=w1:e1
```

Status accepted=false means it is a read query, not an accepted planning action.
Waiting/loading is legitimate before readiness. Once the owner reports idle, the UI
must display the matching real town count and names/IDs without an interface error.

| Observed boundary | Next conclusion supported by the trace |
| --- | --- |
| GUI_DISPATCH then GUI_RESULT nil, no HANDLER_ENTRY | Target handler entry has not been observed. Check both trace-v1 startup markers and registration/delivery; do not yet declare a native routing cause. Missing or transformed parameters may appear as a separate trace=unavailable entry. |
| HANDLER_ENTRY then HANDLER_ROUTE accepted=false | Exact rejected ID/prefix/action is logged. Compare the untouched outbound and inbound values. |
| HANDLER_RESPONSE table with towns, then GUI_RESULT nil/wrong shape | A valid Lua response was constructed but did not arrive intact at this UI call; investigate native propagation/aggregation with this evidence. |
| HANDLER_ENTRY without HANDLER_RESPONSE | Inspect intervening native errors and routing markers; the callback did not reach response creation. |
| Matching valid response, waiting/zero towns | Communication works; compare actual owner readiness/catalog state, not the former UI placeholder. |

Acceptance after communication is understood and corrected requires:

1. No restricted-API or malformed-response errors; a real town list matches owner data.
2. Refresh reloads the catalog; Plan occurs only on a click, once per accepted request.
   Same-town, stale-session, replay and busy protections remain intact.
3. No auto planning on load/open/poll. Failure stops automatic polling; one explicit
   Refresh produces one new exchange, with no recurring errors.
4. The bounded window initially centers on both axes at the actual resolution/UI scale,
   can be dragged, stays where dragged while open, and starts centered after close/reopen.
   Title-bar close/Back/focus and preserved form selection still work.
5. Reload resets session selection/results without stale requests or detached updates.

Until those observations exist, real town delivery, native return marshalling and
centered reopen behavior remain unresolved. Stop for review before installation.


## Latest component-ID routing investigation (no runtime changes)

The latest supplied log, also confirmed in the installed stdout.txt, has two
nil results and no handler-entry markers. Centering is now accepted by the user.
**The custom component ID is a plausible suspect, not a source-proven cause.**
The user's instruction for an unestablished cause applies: design one bounded
verification, without changing production transport or installing anything.

### What is verified

- The staged live_plan.gs.lua, live_plan.script.lua and live_plan_ui.script.lua
  match the workspace, normalizing line endings. The descriptor references
  `oz_railway_network_architect::/live_plan.script@guiHandleEvent`.
- The 2026-11-03 log at 10:50:10Z creates the live_plan.gs GameScript entity;
  trace-v1 startup markers appear, the owner reaches idle with ten towns, and
  requests w1:e1 (status) and w1:e2 (refresh) return nil. No relevant descriptor,
  callback-resource or startup error was found in that log.
- HANDLER_ENTRY is emitted before lifecycle and ID/name/action filtering. It is
  conditional on the trace/relevance flag and an eight-event owner budget; it is
  not an unconditional callback-entry print. These first two UI requests enable
  traces, and no earlier related handler markers are present. No filter rejection
  can explain the missing entry marker if the documented arguments arrive intact
  and the logging preamble runs successfully. Native pre-entry/preamble failure
  and argument transformation are not ruled out solely by missing logs.
- The UI's explicit native Window ID is `oz_railway_network_architect.plan.window`.
  The component argument `oz_railway_network_architect.plan` is our logical namespace,
  not an ID registered by this UI. That mismatch alone does not prove delivery behavior.

### Native source comparison

Installed root: `D:\SteamLibrary\steamapps\common\Transport Fever 3`.

| Question | Verified evidence and limit |
| --- | --- |
| First argument | `api/tealdef/api/gui.d.tl:50-57` calls it component id and documents a handler result. [Official GUI API](https://wiki.transportfever3.com/script-doc/api/gui.html). It does not specify whether missing components are rejected, forwarded or ignored. |
| Empty-ID request with return | gui.zip `gui/construction/construction_react_util.tl:1531-1537` sends `fireGuiScriptEvent("", "company.lockPermits", ...)` and examines the table result. This is a verified native usage pattern, not a demonstration of the invalid-ID resolver. |
| Matching handler | game_mechanics.zip `game_mechanics/company/company.script.tl:507-552` uses the same seven-argument signature as RNA, ignores `_id`, matches `name == "company.lockPermits"`, and returns tables. RNA matches both logical ID and namespaced name. |
| Registration | `company/company.gs.lua:12-14` registers guiHandleEventScript just like RNA. `api/tealdef/api/type.d.tl:1361-1371` declares the callback-reference fields; no extra GUI-registration switch is documented there. No additional requirement was established from the inspected sources. |
| State ownership | `base/tealdef/scripts/gamescript.d.tl:61-68` supplies the script's GUI state to update and event callbacks. No changes to ownership or shared global state are justified. |
| Registration lookup | `api/tealdef/api/engine/system.d.tl:318-323` declares getEntityForGameScript(name), returning the entity holding the script state. gui.zip `gui/debug_panel/make_entity_debug_panel.tl:461-462` uses a .gs resource name. This lookup would confirm an entity already evidenced by logs; it does not prove event-handler subscription/delivery. It was not added as a second probe. |
| Native routing/aggregation implementation | The inspected sources expose the binding declaration and callers/handlers, not the native component lookup or result aggregation implementation. We cannot establish that an arbitrary non-empty ID blocks delivery, nor claim empty ID repairs this mod until observed. |

Simply changing the sender to empty ID would still fail our current explicit
`id ~= eventId` filter if native delivery succeeded. Both sides would need a
consistent change. That fact is tested, but no runtime filter was loosened now.

### One bounded runtime verification design (not implemented)

Use one paired A/B **status-only** experiment in the existing mounted UI's verified
main-thread join, after the owner has logged idle. Replace the initial normal status
request with exactly two consecutive protected calls in that experiment:

```lua
api.gui.fireGuiScriptEvent("oz_railway_network_architect.plan",
    "oz_railway_network_architect.plan.status", customProbeParams)
api.gui.fireGuiScriptEvent("",
    "oz_railway_network_architect.plan.status", emptyProbeParams)
```

Both carry only the same diagnostic probe marker and separate correlation IDs,
`route-probe:custom` and `route-probe:empty`. They do not carry Plan parameters.
A temporary handler exception must accept empty ID **only** for this marked status
probe; it must not accept empty-ID Plan, Refresh or other names. Keep the normal
handler validation unchanged for everything else.

Guard the pair with a launcher-local one-shot flag, set before either call. Never
re-run it on polling, Refresh, reopen, or request failure during that launcher
lifetime. Check mount/container lifetime before each call. Neither result is applied
to the form or used as a fallback route. Stop polling after the experiment, show an
explicit diagnostic-complete/error message, retain full bounded boundary markers,
and make no plan. This is two read-only calls in **one** controlled verification;
no additional registration lookup, alternate transport or automatic retry is proposed.

Expected markers (proposed; not claims of observed output):

```text
[RNA:PLAN:4B2] ROUTE_PROBE_BEGIN calls=2 action=status
[RNA:PLAN:4B2] COMM GUI_DISPATCH id="oz_railway_network_architect.plan" trace=route-probe:custom
... corresponding entry/route/response/result, if delivered ...
[RNA:PLAN:4B2] COMM GUI_DISPATCH id="" trace=route-probe:empty
... corresponding entry/route/response/result, if delivered ...
[RNA:PLAN:4B2] ROUTE_PROBE_COMPLETE custom_type=<type> empty_type=<type> polling=paused
```

Keep event names in the full dispatch logs as in existing tracing. Each result must
include type, epoch, town count and echoed correlation ID. Expected success for the
ID hypothesis: custom returns nil without entry, while empty produces matching
HANDLER_ENTRY, accepted status routing, HANDLER_RESPONSE towns=10 and GUI_RESULT
with the same response and trace. The count is ten only for the supplied unchanged map.
That would support a subsequent sender/handler correction using empty component ID
and namespaced event names, while preserving request validation.

If both return nil without entry, reject the claim that an empty ID alone fixes
routing; investigate handler activation with the new evidence. If both enter but
returns disappear, investigate propagation. If either route enters and is rejected,
compare the received ID/name/probe arguments. Do not declare success from a mock.

### Tests and exact changed files

Three additional groups bring the suite to **90 passing tests** (20 rail, 22 planner,
48 live/UI). They cover:

1. Ten synthetic engine-fixture towns through the actual descriptor-resolved owner;
   status returns all ten sorted records. Refresh returns accepted/loading with zero
   towns while collection is pending; the following completed status returns all ten,
   including a changed fixture name. The initial Refresh response is not fabricated.
2. An explicitly injected pre-handler delivery gate reproduces nil/no-entry with ten
   backend towns. The UI shows the error, does not populate fake towns, pauses polling,
   and makes only one additional call on explicit Refresh.
3. In the injected empty-ID-allowed model, the unchanged owner logs entry then rejects
   empty ID. This prevents a sender-only fix from being mistaken for working routing.

The gate is a fault model, **not verified TF3 internals**. Other tests still use the
explicit single-handler contract shim. No unit test is presented as proof of actual
native callback dispatch or response marshalling. All existing click/replay/session,
no-auto-plan, centering and core tests remain intact.

Changed files in this investigation only:

```text
tests/live_plan_test.lua
README.md
docs/phase_4b2_user_planning.md
```

Relevant test-harness diff:

```diff
-local function newSession(overrides)
+local function newSession(overrides, deliveryGate)
 ...
+if deliveryGate and not deliveryGate(id, name) then return nil end
 return callbacks.guiHandleEvent(nil, nil, gui, "test", id, name, param)
```

Static checks: 32 Lua files, JSON, UTF-8 without BOM, resource references, callback
exports and unchanged mod identity/revision. All deployable files remain byte-for-byte
unchanged from the start of this investigation, including the accepted centering.

**Files to replace in staging now: none.** The verification design is not installed
or implemented. If approved later, its temporary runtime patch would involve only
live_plan_ui.script.lua and live_plan.script.lua, reviewed as a separate diff. Stop
for review; no commit, push, revision change or staging update was performed.


## Implemented one-shot routing A/B probe

This section supersedes the preceding design-only staging guidance. No research was
repeated. The approved diagnostic is implemented, not yet verified in native TF3.

**Trigger:** after the owner logs idle, open the centered RNA window and click the
existing **Refresh towns** button once. The first explicit Refresh per launcher
lifetime queues the pair in the existing main-thread enqueueJoin. Mount and timers
never trigger it. The one-shot flag is set before queueing and survives close/reopen.
If closed/expired before execution, zero calls run; if closed during A, B is skipped.
The flag remains consumed in both cases. A new game UI/launcher lifetime re-arms it.

Call A uses component ID `oz_railway_network_architect.plan`; B uses `""`. Both use
`oz_railway_network_architect.plan.status`. Each receives exactly these two fields:

```lua
{
    _rnaRoutingProbe = "oz_railway_network_architect.route_ab_status.v1",
    _rnaTrace = {id = "<shared token>:A or :B", enabled = true},
}
```

Only the correlation token differs between the two payloads. Each call has its own
pcall: A throwing does not skip B unless the window expires. Neither response is
applied to the view, selections or retained form. No catalog refresh, planning,
terrain query or mutation is requested. Probe completion is not routing success.
The UI shows the two result types and keeps polling paused. Later explicit Refresh
clicks retain normal routing and cannot repeat the pair. An accepted planning request
continues independently. No persistent flag, save write or global state is added.

The owner admits empty ID only when the event name is the exact status name, the
marker matches, a bounded string trace ID with enabled=true is present, and there
are no other top-level request fields. Empty-ID Plan, Refresh, unmarked status and
payloads containing planning fields are still rejected. Normal routing/validation
is unchanged. Qualified probe entry/route/response logs bypass the ordinary trace
budget, without consuming it.

### Exact changed files

```text
oz_railway_network_architect/content/live_plan_ui.script.lua
oz_railway_network_architect/content/live_plan.script.lua
tests/live_plan_test.lua
README.md
AGENTS.md
docs/phase_4b2_user_planning.md
```

The stylesheet, centering fields, descriptor, planner, sampling/request modules,
four inventories, identity and revision remain unchanged.

Minimal relevant diff (probe body abbreviated):

```diff
 -- Refresh click
+if runRoutingProbe() then return end
 send("refresh", {})

+-- Launcher-local, consumed before queueing; passed to its window.
+local routingProbe = react.useRef({used = false})
+-- Within one protected-lifetime join: exactly A then B, each independently protected.
+api.gui.fireGuiScriptEvent(componentId, eventId .. ".status", markedStatusOnlyParams)
+-- Log only; never apply either response; leave polling paused.

-if id ~= eventId then ... return end
+if id ~= eventId and not (id == "" and routingProbe) then ... return end
+-- routingProbe here means the strictly validated status-only marker above.
```

### Validation

**96 tests pass: 20 railway, 22 planning, 54 live/UI.** All preceding 90 scenarios
remain covered; their Refresh tests now account for the temporary first-click probe
before exercising subsequent normal Refresh behavior. Six added groups verify:

- Explicit-only trigger, equivalent status payloads, A/B IDs, distinct tokens,
  queued duplicate protection, ten backend fixture towns, no fallback and no replay
  after reopen.
- Entry/routing/response logs despite exhausted GUI/owner trace budgets.
- Narrow empty-ID exception rejecting other actions and planning fields.
- Both-undelivered and returned-but-lost fault models, paused polling and no fake data.
- Independent pcall handling when A throws and B returns normally.
- Teardown before the join or during A, expired-state safety and consumed one-shot flag.

32 Lua files pass syntax checks. JSON, UTF-8, local/native resource references,
callback exports, identity/revision and diff checks pass. Mock routing outcomes are
fault models, not claims about TF3 internals. Native A/B results remain unknown.

### Safe staging update and exact log command

No staging update was performed. After review, close TF3 and back up these two files
outside the mod, then replace only these relative paths:

```text
content/live_plan_ui.script.lua
content/live_plan.script.lua
```

Source: `D:\code\transport-fever-3\railway-architect\oz_railway_network_architect`.
Target: `C:\Program Files (x86)\Steam\userdata\175442176\3493540\local\staging_area\oz_railway_network_architect`.
Verify modId/revision and compare copied SHA-256 hashes. Leave all other staged files
alone. Tests/docs are not deployment files.

Load the same test map, briefly unpause, wait for TOWNS available=10 and STATE idle,
then open RNA and click Refresh towns once. Do not click it repeatedly while collecting
the result. The normal initial status request may still show its existing nil error;
that is not the A/B probe. The probe begins only at ROUTE_PROBE_BEGIN.

Read the exact log with PowerShell (read-only):

```powershell
Select-String -LiteralPath 'C:\Program Files (x86)\Steam\userdata\175442176\3493540\local\crash_dump\stdout.txt' -SimpleMatch '[RNA:PLAN:4B2]'
```

Retain the output before another launch replaces stdout. Expected markers for the
component-ID hypothesis (tokens/count depend on the current session/map):

```text
[RNA:PLAN:4B2] ROUTE_PROBE_BEGIN calls=2 action=status token=w1:e2
[RNA:PLAN:4B2] COMM GUI_DISPATCH probe=route_ab_status call=A id="oz_railway_network_architect.plan" name=oz_railway_network_architect.plan.status trace=w1:e2:A
[RNA:PLAN:4B2] COMM GUI_RESULT probe=route_ab_status call=A id="oz_railway_network_architect.plan" name=oz_railway_network_architect.plan.status trace=w1:e2:A type=nil towns=unavailable response_trace=unavailable
[RNA:PLAN:4B2] COMM GUI_DISPATCH probe=route_ab_status call=B id="" name=oz_railway_network_architect.plan.status trace=w1:e2:B
[RNA:PLAN:4B2] COMM HANDLER_ENTRY src=<native source> id="" name=oz_railway_network_architect.plan.status param_type=table trace=w1:e2:B
[RNA:PLAN:4B2] COMM HANDLER_ROUTE accepted=true action=status trace=w1:e2:B
[RNA:PLAN:4B2] COMM HANDLER_RESPONSE type=table epoch=<epoch> status=idle towns=10 accepted=false reason=nil trace=w1:e2:B
[RNA:PLAN:4B2] COMM GUI_RESULT probe=route_ab_status call=B id="" name=oz_railway_network_architect.plan.status trace=w1:e2:B type=table towns=10 response_trace=w1:e2:B
[RNA:PLAN:4B2] ROUTE_PROBE_COMPLETE status=finished calls=2 A_type=nil B_type=table polling=paused
```

These are expected diagnostic shapes, not observed results. A handler reaching the
GUI for A produces the same entry/route/response markers with A's trace. An exception
reports type=error and its bounded detail. Closing during execution reports
status=aborted and calls=0 or 1. No automatic retry follows.

Interpretation:

- A nil/no entry, B matching entry and valid town response: component ID is supported
  as the routing cause; recommend a later consistent sender/receiver correction.
- Both nil/no entry: component ID alone is insufficient; investigate native handler
  activation/delivery next.
- Handler response exists but matching GUI result is nil: investigate return propagation.
- Route rejection or mismatched correlation: inspect received arguments; do not call
  it success. A table alone is not proof that the expected owner result arrived.

No permanent routing correction is made by this probe. Stop for review after the
single experiment; do not advance the project or construct anything.


## Handler activation correction

### Decision and limits of the evidence

Choose **A: keep the authoritative Game Script and register its event interests**.
No React-owned replacement pipeline is introduced. Its conditional evaluation is
unnecessary now that shipped source establishes a missing registration step.

The previous report overlooked `company.script.tl:384-389`: the comment explicitly
says `-- gui events`, followed by subscriptions for `company.lockPermits`,
`company.unlockPermits` and builder events. These are registered on the **engine**
GameScriptState, and handled by the company's **guiHandleEvent**. Calling these
subscriptions engine-only was incorrect. This is specific installed evidence for
using engine-state subscriptions for GUI delivery, not an assumption that all
engine subscriptions belong in GUI state.

Proven code defect: RNA registered its GUI callback references but never registered
any event interests. Source-backed explanation: the GUI update can run while events
are not opted in. Native confirmation that this omission fully explains the observed
nil results is still required. The installed sources inspected expose declarations
and Lua/Teal consumers, but no C++ GameScript dispatcher implementation; no internal
broadcast, filtering order or return aggregation behavior is claimed.

The supplied A/B result rules out a component-ID-only correction. The actual local
stdout at 2026-11-03 11:22:20Z records creation of
`oz_railway_network_architect::/live_plan.gs`; at 11:22:35Z it records UI_SESSION_READY,
and both 11:22:51Z probe calls return nil. The script entity is active by this
runtime evidence and the functioning town collector. This does not prove activation
of every callback.

### Installed-source evidence

Paths below are relative to `D:\SteamLibrary\steamapps\common\Transport Fever 3`.
ZIP members were read in place; installed files were not modified.

| Contract | Evidence |
| --- | --- |
| GUI event subscriptions | `base/content/game_mechanics.zip`, `game_mechanics/company/company.script.tl:370-390`: engine handleEvent initialization registers exact GUI event names under `-- gui events`. Lines 507-552 receive company.lockPermits in guiHandleEvent and return a table. |
| Guarded update initialization | Same archive, `game_mechanics/achievements/achievements.script.tl:180-196`: update checks state:hasEventSubscriptions(), then state:subscribeToEvent(name), before normal work. The new registration-only update follows this pattern, including when dt is zero. |
| Callback registration | `company/company.gs.lua:3-14` registers updateScript and guiHandleEventScript using script@export references. `api/tealdef/api/type.d.tl:1361-1371` declares those descriptor fields. RNA retains the two GUI references and adds updateScript to a separate minimal resource. |
| State and callback signatures | `base/tealdef/scripts/gamescript.d.tl:40-68`: subscription methods on GameScriptState, update(userParams, state, dt), guiUpdate with read-only engine state, and seven-argument guiHandleEvent. No subscription is attempted on GUI read-only engine state. |
| Event and result | [Official api.gui documentation](https://wiki.transportfever3.com/script-doc/api/gui.html), `api/tealdef/api/gui.d.tl:50-57`; `base/content/gui.zip`, `gui/construction/construction_react_util.tl:1531-1537` dispatches company.lockPermits and reads its return. Component ID and request/response transport remain unchanged. |
| Script identity lookup | `api/tealdef/api/engine/system.d.tl:318-323` declares getEntityForGameScript(name). `gui/debug_panel/make_entity_debug_panel.tl:461-462` passes a .gs resource name, not .gs.lua or a callback reference. RNA's exact name is `oz_railway_network_architect::/live_plan.gs`, corroborated by the runtime creation log. |

The GUI owner now performs one protected
`api.engine.system.gameScriptSystem.getEntityForGameScript("oz_railway_network_architect::/live_plan.gs")`
lookup per GUI session. REGISTRATION_LOOKUP logs the returned entity or precise
failure. This is diagnostic only: it neither reads nor treats the engine component
as the GUI session and cannot fabricate a town list or suppress planning on failure.
The lookup has not yet been executed in native TF3 with this patch.

### Exact changed files for this correction

Existing uncommitted Phase 4B.2 work was preserved. This list describes this turn's
changes, not every difference from the older accepted Git commit.

- `oz_railway_network_architect/content/live_plan.gs.lua`: add updateScript reference.
- `oz_railway_network_architect/content/live_plan_events.script.lua`: new registration-only update.
- `oz_railway_network_architect/content/live_plan.script.lua`: one protected registration lookup; remove temporary empty-ID probe exception and trace-budget bypass.
- `oz_railway_network_architect/content/live_plan_ui.script.lua`: remove A/B action/ref; first Refresh again performs one normal refresh.
- `tests/live_plan_test.lua`: resolve/run registered engine update, gate transport by subscribed event name, replace six obsolete probe tests with activation regressions, add two lookup tests, restore normal Refresh assertions.
- `tests/run_lua_tests.py`: validate updateScript references/exports as well as GUI callbacks.
- `AGENTS.md`, `README.md`, this report: current registration evidence, scope and acceptance instructions.

Relevant additive diff:

```diff
--- content/live_plan.gs.lua
+++ content/live_plan.gs.lua
@@
     return {
+        updateScript = {
+            fileName = "oz_railway_network_architect::/live_plan_events.script@update",
+        },
         guiUpdateScript = {
```

The entire new registration resource is:

```lua
-- Registration only: no simulation data writes, planning, or saved session state.
-- company.script.tl:380-389 subscribes engine state to names handled by its
-- guiHandleEvent. achievements.script.tl:180-196 initializes subscriptions in update.
function data()
    return {
        update = function(_params, state, _dt)
            if state:hasEventSubscriptions() then return end
            state:subscribeToEvent("oz_railway_network_architect.plan.status")
            state:subscribeToEvent("oz_railway_network_architect.plan.refresh")
            state:subscribeToEvent("oz_railway_network_architect.plan.plan")
            state:subscribeToEvent("reactPostInit")
            debugPrint("[RNA:PLAN:4B2] EVENT_SUBSCRIPTIONS_READY count=4")
        end,
    }
end
```

No engine-state get/set, engine command or custom saved payload is added. Native
subscription metadata is managed by the game. Planning data, selections and results
remain in their existing transient GUI owners. The normal ID/name filter,
request/session/replay validation, enqueueJoin, centered window, four inventories,
canonical A*, sampling and search limits are unchanged. Removal of the completed
probe restores the ordinary strict component-ID filter; it does not choose a new ID.

### Regression and static validation

Run:

```powershell
uv run --no-project --offline --with lupa==2.8 python tests/run_lua_tests.py
```

Result: 98 tests (20 railway, 22 planning, 56 live/UI), 33 Lua syntax checks,
UTF-8/no BOM, JSON, local imports/resources, metadata and all descriptor callback
exports pass. Six retired A/B tests were replaced with six activation/normal-Refresh
tests; two lookup tests were added. Existing functional tests were rerun.

The key regression deliberately disables the registered update callback while
allowing guiUpdate to collect ten fixture towns. Transport refuses unsubscribed
names, producing nil with no handler entry and paused UI polling. Restoring the
update subscribes the exact names; an explicit Refresh then reaches the actual
registered handler, and subsequent status displays the ten fixture towns. The fixture
is synthetic and confined to tests. This demonstrates the correction under the
source-backed subscription model, not independent proof of native dispatch.

Additional tests cover exact four subscriptions, repeated zero-dt updates, no
registration data reads/writes, unrecognized event names, subscribed reactPostInit,
new-state initialization, one Refresh per click, exact lookup resource and bounded
lookup failure. Existing tests cover restricted React contexts, teardown, response
loss, malformed results, busy/replay/stale requests, explicit planning and centering.

### Staging patch after review only

No staging files were changed. After review, close TF3 completely. For the already
installed development copy containing the previous UI fix, copy these four files
only (new dependency first; descriptor last). Preserve a backup outside staging if
needed. Do not copy tests or repository documentation.

```powershell
$rnaSource = 'D:\code\transport-fever-3\railway-architect\oz_railway_network_architect\content'
$rnaTarget = 'C:\Program Files (x86)\Steam\userdata\175442176\3493540\local\staging_area\oz_railway_network_architect\content'
foreach ($rnaFile in @('live_plan_events.script.lua', 'live_plan.script.lua', 'live_plan_ui.script.lua', 'live_plan.gs.lua')) {
    Copy-Item -LiteralPath (Join-Path $rnaSource $rnaFile) -Destination (Join-Path $rnaTarget $rnaFile)
    if ((Get-FileHash -LiteralPath (Join-Path $rnaSource $rnaFile)).Hash -ne
        (Get-FileHash -LiteralPath (Join-Path $rnaTarget $rnaFile)).Hash) {
        throw "RNA copy mismatch: $rnaFile"
    }
}
```

No identity/revision change is needed. This is not a general package installation
procedure for an older staging copy missing Phase 4B.2 dependencies.

### Native acceptance procedure and expected markers

1. Reload the same ten-town map with the mod enabled; briefly unpause so the engine
   registration update and existing readiness gate can run. Do not save solely for
   this test. Expect one EVENT_SUBSCRIPTIONS_READY marker for the script state.
2. Confirm REGISTRATION_LOOKUP resolves the exact .gs resource to an entity, and
   TOWNS available=10 / STATE status=idle still appear. Lookup resolution alone is
   not delivery success; unavailable lookup must show its error.
3. Open the launcher. If an initial pre-activation dispatch already paused polling,
   click Refresh once after registration. Expect correlated dispatch, handler entry,
   accepted route, table response and GUI table result. Status requests must show
   ten actual towns once collection finishes. Refresh first returns loading/zero
   while recollection is pending; that is the existing asynchronous collection contract.
4. Both dropdowns must show the actual town names with entity IDs, and no route
   should run until Plan is clicked. Check no ROUTE_PROBE markers remain.
5. Choose two different towns, click Plan once, and confirm exactly one REQUEST_START
   and a real terminal status. Busy/replayed requests must not restart work. Request
   another plan after completion; close/reopen must preserve normal behavior and centering.
6. Load another map in the same process. Confirm fresh list/session invalidation and
   no automatic plan or stale selection. Observe subscription initialization on the
   new script state; do not assume engine callback ordering or persistence semantics
   from the mock.

Typical status exchange (trace/entity values vary):

```text
[RNA:PLAN:4B2] EVENT_SUBSCRIPTIONS_READY count=4
[RNA:PLAN:4B2] REGISTRATION_LOOKUP name=oz_railway_network_architect::/live_plan.gs status=resolved entity=<id>
[RNA:PLAN:4B2] TOWNS available=10 rejected=0 read_errors=0
[RNA:PLAN:4B2] COMM GUI_DISPATCH id=oz_railway_network_architect.plan name=oz_railway_network_architect.plan.status trace=w1:e1
[RNA:PLAN:4B2] COMM HANDLER_ENTRY src=<native source> id="oz_railway_network_architect.plan" name=oz_railway_network_architect.plan.status param_type=table trace=w1:e1
[RNA:PLAN:4B2] COMM HANDLER_ROUTE accepted=true action=status trace=w1:e1
[RNA:PLAN:4B2] COMM HANDLER_RESPONSE type=table epoch=<epoch> status=idle towns=10 accepted=false reason=nil trace=w1:e1
[RNA:PLAN:4B2] COMM GUI_RESULT type=table towns_type=table epoch=<epoch> response_trace=w1:e1 trace=w1:e1
```

Status is read-only, so accepted=false with no reason is normal. Handler/GUI trace
logging remains capped at eight exchanges; inspect the first exchange after launch.
The subscription and lookup messages are independently bounded.

```powershell
Select-String -LiteralPath 'C:\Program Files (x86)\Steam\userdata\175442176\3493540\local\crash_dump\stdout.txt' -Pattern '\[RNA:PLAN:4B2\]'
```

Failure interpretation: no EVENT_SUBSCRIPTIONS_READY after unpausing means the new
update resource/lifecycle needs inspection. Subscriptions ready but no handler entry
leaves native delivery unresolved. Handler table response followed by GUI nil leaves
native propagation unresolved. Neither case authorizes another ID experiment or a
claim of success. Native reload behavior and unchanged timing-resolution limitations
also remain to be verified. Stop for review before installing or advancing phases.


## Window alignment, padding and status UX

### Runtime baseline and scope

The user has verified EVENT_SUBSCRIPTIONS_READY, registration lookup, ten real towns,
correlated handler/table responses, and an explicit Plan request in TF3. Preserve
that working communication architecture. This patch changes only presentation:
initial window positioning/style, content padding/control alignment and the completed
unsupported request message. No native visual success is claimed for this patch.

### Verified installed layout evidence

All sources below are in the installed TF3 directory
`D:\SteamLibrary\steamapps\common\Transport Fever 3`; GUI members are read from
`base/content/gui.zip` without extracting or modifying installed files.

| Evidence | Implication for this correction |
| --- | --- |
| `base/tealdef/scripts/builtin.d.tl:1186-1208` declares initialX/initialY, movable, closable, content and compact. `gui/menu/mod_manager_react_util.tl:3671-3683` uses 0.5/0.5 for a centered native dialog. | Retain normalized initial coordinates, movement, closing and focus. No screen-pixel offsets. |
| `gui/main/builtin.lua:423-429` forwards dynamic child params.initialX/initialY to WindowContainerChild. | Supply the same 0.5/0.5 to addSingletonWindow parameters as well as the inner Window. The prior wrapper parameters omitted them. |
| `gui/main/builtin.css.lua:1946-1949` defaults Window anchorPoint and gravity to 0/0. `gui/menu/mod_browser.css.lua:15-22` and `gui/main/internal.css.lua:760-763` set both to 0.5/0.5 for native centered windows. | Add the centered anchor/gravity only to Window!rna-planner-window. Native movement remains responsible for the dragged position; no timer or position-reset calls are added. |
| `gui/main/builtin.lua:159-166` exposes native content and header children and states C++ modifies the wrapper. `gui/main/builtin.css.lua:2000-2051` separately styles TitleLayout, Title and the close button; lines 1962-1968 define the window shadow. | Anchor the whole Window, not the scroll form. Keep title, close-button and shadow geometry native. Do not compensate for chrome with guessed pixel offsets. The internal placement arithmetic is native, so exact rendered bounds require visual validation. |
| `gui/main/popover_react_util.css.lua:24-25`, `gui/map_editor/map_editor.css.lua:18-19`, and `gui/main/debug.css.lua:18-19` apply padding to Window::Content. | Move the inset from BoxLayout to the native content component. Use symmetric 20 logical pixels, without modifying the title bar. |
| `gui/main/builtin.css.lua:1628-1636` stretches ScrollArea content horizontally and sets vertical scrollbar width 8; `gui/menu/mod_browser.css.lua:449-450` uses horizontal-fill gravity for ComboBox. | Retain vertical scrolling and the 520-wide bounded window; remove the dropdown's mandatory 440 minimum, retain its 440 maximum and allow horizontal fill/shrink. Text remains capped at 440 with textAutoWrap. |

At the stylesheet level, 520 - 20 - 20 - 8 = 472 logical pixels remain after
horizontal padding and the native scrollbar. The 440-wide text/dropdown caps fit
with 32 pixels of allowance. This is a capacity check, not a reconstruction of
native border, font, dropdown-arrow or DPI layout. Labels/status and buttons share
the form's left edge; only form action buttons receive the left/top gravity rule.
The window's native close button is outside that selector.

### Unsupported message and provenance

The actual stdout records source (-804, -624), destination (3676, -1268), distance
4526.050817, and reason `pair_exceeds_grid_resolution_or_boundary_margin`.
The X separation is 4480, exceeding the existing maximum axis span of
(32 - 1) * 128 = 3968. This makes distance-specific wording justified for this case:

> The selected towns are too far apart for the current prototype's sampling resolution.
> No route was calculated. Try towns closer together.

This is presentation-only reasoning from the accepted grid limits. It does not run
another search, change constraints or label a connection physically impossible.
For the same combined reason without a provably excessive axis span, the message
mentions the sampling resolution or map-boundary margin and suggests closer towns
away from the map edge. Other unsupported reasons retain their existing messages.
The request's precise reason and COMPLETE diagnostic remain unchanged.

### Exact changed files and relevant diff

Relative to the start of this targeted task (earlier uncommitted changes preserved):

```text
AGENTS.md
README.md
docs/phase_4b2_user_planning.md
oz_railway_network_architect/content/live_plan_ui.css.lua
oz_railway_network_architect/content/live_plan_ui.script.lua
oz_railway_network_architect/content/live_plan.script.lua
tests/live_plan_test.lua
```

```diff
--- content/live_plan_ui.css.lua
+++ content/live_plan_ui.css.lua
@@
     add("Window!rna-planner-window", {
+        anchorPoint = {0.5, 0.5},
+        gravity = {0.5, 0.5},
@@
+    add("Window!rna-planner-window Window::Content", {
+        padding = {20, 20, 20, 20},
+    })
@@
-        padding = {12, 12, 12, 12},
@@
+    add("BoxLayout!rna-planner-form > Button", {gravity = {0, 0}})
@@
-        minSize = {440, 32},
+        minSize = {-1, 32},
         maxSize = {440, -1},
+        gravity = {-1, 0},
--- content/live_plan_ui.script.lua
+++ content/live_plan_ui.script.lua
@@
                     container:get():getApi().addSingletonWindow(PlannerWindow, {
+                        -- WindowContainer forwards these to WindowContainerChild.
+                        initialX = 0.5, initialY = 0.5,
                         form = form,
```

The only owner-script change is immediately after construction of the completed
request's existing status message:

```lua
if r.status == "unsupported" and r.reason == "pair_exceeds_grid_resolution_or_boundary_margin" then
    state.message = "The selected towns exceed the current prototype's sampling resolution or map-boundary margin. "
        .. "No route was calculated. Try towns closer together and away from the map edge."
    if r.pair and (math.abs(r.pair.start.x - r.pair.destination.x) > (config.gridLimit - 1) * 128
        or math.abs(r.pair.start.y - r.pair.destination.y) > (config.gridLimit - 1) * 128) then
        state.message = "The selected towns are too far apart for the current prototype's sampling resolution. "
            .. "No route was calculated. Try towns closer together."
    end
end
```

Subscriptions, routing, response fields, owner lifecycle, inventories, canonical A*,
request pipeline, grid/search configuration, identity and revision are unchanged.

### Validation

The complete existing suite plus three new scenarios passes: **101 tests** (20 rail,
22 core, 59 live/UI). Lua 5.4 syntax passes for **33 files**. Resource targets/imports,
callback exports, JSON, UTF-8 without BOM, identity and revision checks pass.

Existing style and close/reopen tests now assert centered anchor/gravity, initial
coordinates at both native placement layers, padding on the correct native content
selector, no extra BoxLayout padding, aligned action buttons, dropdown shrinkability
and the stylesheet width budget. Existing selections, focus, subscription-gated
communication and request-protection tests remain in the full suite.

New tests run the real pipeline and event handler against the recorded town
coordinates (fixture-only IDs), check the exact unsupported message in the UI and
on reopen, retain the exact diagnostic reason, and verify zero terrain reads and no
candidate result. A boundary-margin fixture prevents incorrectly saying every
unsupported pair is distant. A long transport-error test checks the wrapped text
class, bounded diagnostic length, scroll structure and paused polling.

Static/mocked tests cannot establish actual pixel centering, glyph wrapping,
scrollbar geometry, close-button extents or visual clipping in native TF3.

### Minimal staging update after review

No staging deployment was performed. Close TF3 fully before copying these three
files into the already working Phase 4B.2 development mod. Other runtime files,
including live_plan_events.script.lua and live_plan.gs.lua, need no replacement.

```powershell
$rnaSource = 'D:\code\transport-fever-3\railway-architect\oz_railway_network_architect\content'
$rnaTarget = 'C:\Program Files (x86)\Steam\userdata\175442176\3493540\local\staging_area\oz_railway_network_architect\content'
foreach ($rnaFile in @('live_plan_ui.css.lua', 'live_plan_ui.script.lua', 'live_plan.script.lua')) {
    Copy-Item -LiteralPath (Join-Path $rnaSource $rnaFile) -Destination (Join-Path $rnaTarget $rnaFile)
    if ((Get-FileHash -LiteralPath (Join-Path $rnaSource $rnaFile)).Hash -ne
        (Get-FileHash -LiteralPath (Join-Path $rnaTarget $rnaFile)).Hash) {
        throw "RNA copy mismatch: $rnaFile"
    }
}
```

### Native visual acceptance checklist

- Load the same map, allow readiness, open the launcher. Confirm real town data and
  the existing successful communication markers; no automatic Plan request.
- At two supported display resolutions and UI scale settings, compare the complete
  visible window's outer bounds, including title/close chrome, against viewport
  center. No fixed pixel correction is expected. Extreme scales with a logical
  viewport narrower than the existing 520-wide window remain outside verified sizing.
- Drag the window away from center and wait through status polling: it must stay
  where dragged. Close by title bar and Back, reopen through launcher; each newly
  created window should start centered. Verify focus and town selections survive.
- Check equal native content insets at left/right, aligned labels/actions/status,
  readable dropdowns and full arrow/control visibility. Open both dropdowns and
  inspect the longest available town names. Title/close behavior must be unchanged.
- At increased scale or reduced height, verify vertical scrolling reaches the final
  status/help text without overlap or clipping. Check long visible error/status text
  wraps within the content area. No spacers or horizontal scroll were introduced.
- Select Morley to Winterton on the reported map: see the exact distance message and
  no route; stdout still reports the original precise unsupported reason. Select a
  previously supported pair afterward and confirm normal explicit planning still works.

Stop for review. Native rendering after these changes is unverified; do not infer
pixel-perfect results from mocked layout checks. No commits, pushes, revision changes
or changes to installed game/staging files were made.
