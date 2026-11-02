# Railway Network Architect

**Phase 2B: read-only city inventory.** Plain Lua; no UI, construction, terrain or
economy changes, dependencies, or export files. Identity and revision remain
`oz_railway_network_architect`, `Railway Network Architect`, **1**.

Phase 2A was accepted by the user: staging discovery, activation, bootstrap output,
`Game is ready`, and normal shutdown were verified. Its resource-loading marker
appeared on multiple workers. The first Phase 2B runtime test reached the GUI
callback, then aborted in the capability check before enumeration. A successful
scan has **not** been verified in TF3.

## Documented API invocation correction

Runtime diagnostics reported all five required engine bindings as Lua tables.
The scanner incorrectly required `type(value) == "function"`. The documented
call signatures do not establish that runtime representation requirement.
The correction checks presence and invokes the documented calls inside `pcall`;
it makes no claim about internal binding representation and does not inspect or
modify metatables. Successful scanning still requires a new runtime test.

- [Official engine signatures and state access](https://wiki.transportfever3.com/script-doc/api/engine.html):
  `getEntitiesWithComponent(componentType, filters?)` returns entity IDs;
  `forEachEntityWithComponent(callback, componentType)` iterates entities;
  `getComponent(entity, componentType)` returns a component or nil;
  `entityExists(entity)` returns a boolean. These use dot calls, without `self`.
  Engine reads are documented for both GUI and Engine states.
- [Official engine utilities](https://wiki.transportfever3.com/script-doc/api/engine/util.html):
  `api.engine.util.getWorld()` returns the world entity and
  `api.engine.util.getEntityName(entity)` returns a name or nil.
- Installed `gui.zip/gui/statistics/statistic_towns.tl:468` uses the same
  `getEntitiesWithComponent(api.type.ComponentType.TOWN)` call. Installed
  `gui/entity_window/view_manager.tl` uses `api.engine.entityExists` and
  `town_util.tl:1562` delegates names to `api.engine.util.getEntityName`.

Read failures retain their API path and original runtime error. Town name and
position failures also identify the shipped helper and its underlying engine read.
The optional timer uses the same protected direct-call pattern; a timer exception
leaves duration unavailable and adds an `error` field to the existing `DURATION`
line. Returned data validation, lifecycle and the terminal guard are unchanged.

For this patch, close TF3 and copy `content/city_inventory_api.lua` and
`content/city_inventory.script.lua` from
the workspace package into the same relative path in the existing staging package
(full paths below). Compare source/destination hashes with `Get-FileHash` if
desired. Keep metadata and all other staged files unchanged; README is not deployed.
Restart TF3 and load the test game, since the failed session was marked finished.

If a readiness read throws, expect `WAIT_WORLD` followed by a diagnostic such as:

```text
[RNA:CITY:2B] SCAN_ABORTED <API path>: <original runtime error>
```

The placeholders are illustrative. Enumeration errors use `SCAN_ERROR`; per-town
errors remain on the affected `TOWN` record. Capture the complete line and build.
If reads succeed, the unchanged readiness gate and normal scan output below apply.

## Files

```text
railway-architect/
  .gitignore
  AGENTS.md
  README.md
  oz_railway_network_architect/
    mod.json
    _metadata/modinfo.json
    content/
      mod.script.lua
      city_inventory.gs.lua
      city_inventory.script.lua
      city_inventory_api.lua
      city_inventory_data.lua
```

The manifest and bootstrap are unchanged. The new descriptor registers the live
callback; `city_inventory.script.lua` handles readiness, deduplication and logging;
`city_inventory_api.lua` contains game integration; `city_inventory_data.lua`
contains pure normalization and formatting. Metadata now describes Phase 2B.
`cosmetic=true` and add/remove severity `None` reflect the read-only design, not a
completed Phase 2B runtime/removal test.

## Lifecycle and source evidence

Official TF3 references:

- [Resource types](https://wiki.transportfever3.com/doku.php?id=modding:general:resourcetypes): `.gs.lua`, `.script.lua`, namespaces and UTF-8 without BOM.
- [GameScriptDesc and vector types](https://wiki.transportfever3.com/script-doc/api/type.html).
- [Game Script types](https://wiki.transportfever3.com/script-doc/content/scripts/gamescript.html): this page returned HTTP 429; installed definitions supplied the callback evidence.
- [Engine API](https://wiki.transportfever3.com/script-doc/api/engine.html): read-only engine access is available from GUI and Engine states.
- [Town utilities](https://wiki.transportfever3.com/script-doc/content/game_mechanics/towns/town_util.html).
- [Mod scripts](https://wiki.transportfever3.com/doku.php?id=modding:general:modscripts): resource hooks remain separate from live-game callbacks.
- [Staging directory](https://wiki.transportfever3.com/doku.php?id=modding:general:publishing): use local staging without uploading.

Read-only evidence from `D:\SteamLibrary\steamapps\common\Transport Fever 3`:

| Source | Verified evidence |
| --- | --- |
| `api/tealdef/api/type.d.tl`, `GameScriptDesc` | `guiUpdateScript` is a script reference. |
| `base/tealdef/scripts/gamescript.d.tl`, `GameScriptWithGui` | Callback arguments are user/capture parameters, read-only engine state, and GUI state. |
| `base/content/game_mechanics.zip`: `game_mechanics/celebrations/celebrations.gs.lua` | Descriptor links `.script@guiUpdate`. |
| Same archive: `celebrations.script.tl` and `achievements/achievements.script.tl` | GUI callbacks read engine data and initialize state using `guiState:get()` / `guiState:set()`. |
| `base/content/gui.zip`: `gui/hud/happy_change_display.script.tl` | GUI callback state deduplicates handling; persistent GUI SaveData is a separate interface. |
| `api/tealdef/api/engine.d.tl` and `api/engine/util.d.tl` | Town enumeration, entity checks, world lookup, game-time and name reads. |
| `api/tealdef/api/util.d.tl` | `api.util.getApplicationTime()` returns seconds since application start; GUI thread only. |

Octocode's previously verified path restriction excludes the installed game.
PowerShell/ripgrep and Python's ZIP reader inspected these files without extracting
or modifying game content. No TF2 contracts are assumed.

The integration is:

1. TF3 discovers `content/city_inventory.gs.lua` as a Game Script resource.
2. `guiUpdateScript.fileName` references
   `oz_railway_network_architect::/city_inventory.script@guiUpdate`.
3. The first GUI callback logs `WAIT_WORLD` and checks required read APIs.
4. It requires an existing world entity and `GAME_TIME.tickCount`, records a
   baseline, then waits for a later callback to observe an increased tick.
5. It marks the GUI callback state finished before attempting one scan. Further
   callbacks return immediately without world reads. No engine update hook is added.

Using a GUI callback does not add UI. No town queries run during script evaluation
or from `runScript`. Readiness checks occur on the first callback and every 30
callbacks thereafter. Sixty consecutive checks without a usable world abort once.
A valid paused world waits indefinitely without repeated messages: **briefly
unpause to scan**. Missing required APIs or thrown readiness errors abort safely.

The guard uses only Game Script **GUI callback state**, following shipped
initialization/deduplication patterns. The code never writes engine state, calls
`setGuiSaveData`, saves userdata or writes files. Public definitions do not
explicitly guarantee GUI-state reset on every load path: same-process save reload
is a mandatory acceptance test. There is no persistent engine-state completion
flag. If that test fails, resolve session semantics before accepting Phase 2B.
Tick advancement is an additional readiness condition, not a verified callback
for the textual `Game is ready` log line; confirm actual timing in-game.

The accepted bootstrap remains unchanged and may still repeat across workers.
Its messages are not city scans. No unverified cross-worker suppression was added.

## Town data

The adapter uses
`api.engine.getEntitiesWithComponent(api.type.ComponentType.TOWN)` and rechecks
each entity's existence and TOWN component. It imports:

```text
::/game_mechanics/towns/town_util.tl
::/scripts/entity_util.tl
```

Imports use `ug_require`, with `::` selecting base-game content. Installed Lua files
`economy.zip/economy/placementparamsutil.lua` and `gui.zip/gui/main/builtin.lua`
demonstrate importing `.tl` modules this way; no Teal compiler is needed here.
The shipped town utility's `getTownName` delegates to `getEntityName`, and its
`getTownsToPositions` calls `entity_util.getPosition`. The adapter uses that position
helper per entity to isolate failures. In `scripts.zip/scripts/entity_util.tl`, it
returns the bounding-volume midpoint, or nil when that component is missing.
Thus X/Y/Z mean **town bounding-volume center**, not station position or terrain
height. `Vec3f.x/y/z` are declared in the installed API types.

Records are sorted numerically by ID. Zero remains zero; missing/empty names and
missing/nonfinite coordinates become `unavailable`. Invalidated entities retain a
record with `read_error`; any recovered fields remain available. Malformed or
duplicate IDs are rejected and counted. Control characters in names/errors are
removed before logging. No population or ongoing monitoring is implemented.

## Safe update of the installed development copy

Close TF3. Only copy package files from:

```text
D:\code\transport-fever-3\railway-architect\oz_railway_network_architect
```

into the already installed folder:

```text
C:\Program Files (x86)\Steam\userdata\175442176\3493540\local\staging_area\oz_railway_network_architect
```

Keep `mod.json` directly inside that folder. Back up the old copy outside staging
if desired; do not create another active copy with the same ID. Do not copy README,
AGENTS or `.gitignore`. Do not modify the original game install or subscribed mods.
The following command checks identity and copies seven explicit files without
recursive deletion or changes to saves. Existing `_metadata` and `content`
directories must remain in place.

```powershell
$rnaSource = 'D:\code\transport-fever-3\railway-architect\oz_railway_network_architect'
$rnaTarget = 'C:\Program Files (x86)\Steam\userdata\175442176\3493540\local\staging_area\oz_railway_network_architect'
if (Get-Process -Name TransportFever3 -ErrorAction SilentlyContinue) {
    throw 'Close TF3 before updating staging.'
}
$rnaSource = (Resolve-Path -LiteralPath $rnaSource -ErrorAction Stop).Path
$rnaTarget = (Resolve-Path -LiteralPath $rnaTarget -ErrorAction Stop).Path
foreach ($rnaRoot in @($rnaSource, $rnaTarget)) {
    $rnaManifest = Get-Content -LiteralPath (Join-Path $rnaRoot 'mod.json') -Raw | ConvertFrom-Json
    if ($rnaManifest.modId -ne 'oz_railway_network_architect') {
        throw "Unexpected mod identity in $rnaRoot"
    }
}
$rnaFiles = @(
    'mod.json', '_metadata\modinfo.json', 'content\mod.script.lua',
    'content\city_inventory.gs.lua', 'content\city_inventory.script.lua',
    'content\city_inventory_api.lua', 'content\city_inventory_data.lua'
)
foreach ($rnaFile in $rnaFiles) {
    if (-not (Test-Path -LiteralPath (Join-Path $rnaSource $rnaFile) -PathType Leaf)) {
        throw "Missing source file: $rnaFile"
    }
}
foreach ($rnaFile in $rnaFiles) {
    Copy-Item -LiteralPath (Join-Path $rnaSource $rnaFile) -Destination (Join-Path $rnaTarget $rnaFile) -Force -ErrorAction Stop
    if ((Get-FileHash -LiteralPath (Join-Path $rnaSource $rnaFile)).Hash -ne
        (Get-FileHash -LiteralPath (Join-Path $rnaTarget $rnaFile)).Hash) {
        throw "Copy verification failed: $rnaFile"
    }
}
```

If copying is interrupted, rerun with TF3 closed before testing. Do not click Mod
Hub Upload/Update: those publish remotely. On another account/machine, obtain its
TF3 userdata path rather than reuse this account number. The agent has not updated
staging or launched TF3.

## Manual verification

1. Update staging, launch TF3 and confirm the mod is enabled as revision 1. Use a
   disposable test game and disable unrelated optional mods.
2. Wait for loading to finish, then briefly unpause if necessary. Allow several
   seconds for polling. No custom UI is expected.
3. Find one `SCAN_START`, town records in ascending numeric ID order, total count,
   duration and `SCAN_COMPLETE status=ok`. Compare names/count with the game's town
   list. Duplicate names must remain separate IDs.
4. Let the simulation run, pause and resume. There must be no additional scan.
5. **Essential:** using the game's normal UI and a disposable test save, reload in
   the same TF3 process. Expect one new scan for that load. Also test returning to
   the menu and loading a different test game, then a fresh application launch.
   The agent does not access or edit saves; the user controls these manual tests.
6. If an existing zero-town test map is available, load it and unpause. Expect
   `TOTAL count=0 incomplete=0 rejected=0` and `SCAN_COMPLETE status=ok`. Do not
   delete towns from a valued save just to test this.
7. Exit normally and retain the relevant log excerpt before another launch can
   replace it. Do not proceed to Phase 3 until real-game review accepts Phase 2B.

```powershell
$rnaLog = 'C:\Program Files (x86)\Steam\userdata\175442176\3493540\local\crash_dump\stdout.txt'
Select-String -LiteralPath $rnaLog -SimpleMatch '[RNA:CITY:2B]'
```

Illustrative output; IDs, names, coordinates and time will vary:

```text
[RNA:CITY:2B] WAIT_WORLD waiting_for_valid_world_and_tick_advance; unpause_to_scan
[RNA:CITY:2B] SCAN_START
[RNA:CITY:2B] TOWN id=101 name="Example Town" x=0.000000 y=-300.000000 z=12.000000 status=ok
[RNA:CITY:2B] TOTAL count=1 incomplete=0 rejected=0
[RNA:CITY:2B] DURATION seconds=0.001000 clock=application_time includes_record_logging=true
[RNA:CITY:2B] SCAN_COMPLETE status=ok
```

Missing fields print `unavailable`, not `0`. Partial records yield completion
status `partial`. Enumeration/import failure yields `SCAN_ERROR`, an unavailable
count and completion status `error`. Readiness/API failure yields `SCAN_ABORTED`
without a successful completion marker. Attempts are not retried automatically.
Duration is an application-time difference including imports, normalization and
record logging; it may be zero at timer resolution, or unavailable if the timer
cannot be read. It is not CPU profiling.

| Symptom | Action |
| --- | --- |
| Bootstrap only, no Phase 2B marker | Check new files, references, activation and resource errors. Discovery alone is not execution. |
| `WAIT_WORLD` only | Unpause. If still stuck while time advances, capture the build and log errors. |
| `SCAN_ABORTED` or `SCAN_ERROR` | Capture the error, resolve it, then reload to retest. |
| Repeated scans in one load, or no scan on same-process reload | Session-state lifecycle failed acceptance; stop and report it. |
| `status=partial` | Inspect missing fields/errors and compare against the town list. |
| Zero count on a populated map | Treat as a failure; inspect enumeration and lifecycle timing. |
| Repeated Phase 2A worker messages | Known bootstrap behavior; only count `[RNA:CITY:2B]` scans. |

## Validation and unresolved risks

Static checks passed for strict JSON parsing, metadata, UTF-8 without BOM, local
resource/import references, callback exports, installed API symbol evidence and
byte-identical manifest/bootstrap versus the accepted staging copy. Both
PowerShell examples passed PowerShell parser validation without execution.
Manual review covers empty maps, nil fields, zero
coordinates, invalid entities, duplicates, sorting, readiness and terminal guards.

No Lua interpreter/compiler or Lua parser was found in the checked local tooling.
Lua syntax is manually reviewed, not compiler-validated. No dependencies were
installed. TF3 integration, GUI-state lifetime on reload, and precise scan timing
remain untested; the manual acceptance tests above are required. The public
references do not expose a guaranteed `Game is ready` callback or explicit
GUI-state reset contract for all load paths.

The scan runs synchronously in the GUI callback and logs every town once. Very
large maps may briefly stall. This is a snapshot; it does not track later town
changes. No files in the original installation or saves were modified, and nothing
was published, committed or pushed. Stop after Phase 2B for review.
