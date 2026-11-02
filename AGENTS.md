# Railway Network Architect

## Current milestone

Phase 3C only: add a read-only railway topology inventory. City, industry and
terrain inventories are accepted in-game; the baseline is b262240 on main.
Preserve all accepted scanners, mod identity, revision, metadata and bootstrap.
Do not commit, tag, push or publish. Results stay in GUI-session memory, never
saves or exports. Stop for review before network planning, UI or construction.

Future planning must consider road alternatives, demand, distance, existing
infrastructure and cost. A city or industry does not automatically need rail.
Those decisions and economic calculations are outside Phase 3C.

## Development conventions

- The deployable mod is `oz_railway_network_architect/`; repository documentation
  and development tools stay outside it.
- Keep `modId` as `oz_railway_network_architect`, the display name as
  `Railway Network Architect`, and the current revision as `1`.
- Use plain Lua. Do not add a compiler, package manager or
  other dependency without a demonstrated need.
- Use four spaces in Lua and two spaces in JSON. Encode text as UTF-8 without BOM.
- Use lowercase file and directory names inside the deployable mod.
- Follow verified TF3 resource references and lifecycle contracts. Never assume
  TF2 compatibility. Keep documentation links and local evidence in README.md.
- A resource-loading diagnostic does not prove live-world readiness. Never put
  city queries into the bootstrap hook. Use the verified Game Script callback.
- Keep engine API integration separate from pure data normalization. Sort records
  by entity ID. Distinguish missing data from zero and avoid repeated scans/logs.
- Railway adjacency describes shared BASE_NODE endpoints only. Degree >= 3 is a
  junction candidate, not operational switch connectivity or route availability.
  Empty railway networks must succeed. Never classify all STATION entities as rail.
- Keep synthetic graph tests outside the mod package. An isolated development
  Lua runtime is permitted for tests; add no game dependency or project manifest.
- Documented TF3 bindings may report Lua type "table". Check presence and use
  documented direct calls inside pcall; never require type(value) == "function".
- Terrain sampling is capped at 24x24 cell centers. Validate coordinates before
  height/water queries; clamped out-of-bounds heights are not valid samples.
  Use bounded batches, retain explicit partial/completed status and log summaries
  plus capped error examples, never every sample.
- Keep the once-only flag out of engine state and GUI SaveData. Reload behavior
  of callback GUI state must pass real-game verification, including same-process reload.
- Do not introduce globals except the documented resource entry point `data`.
- Validate JSON, metadata, script references and encoding after relevant edits.
  Use an existing Lua checker if available; do not claim static checks prove a
  successful TF3 load. Record checks that were unavailable or not run.

## Safety and scope

- Treat installed game files, shipped examples and API definitions as read-only.
- Do not invoke world-changing commands or change simulation configuration.
- Do not persist mod state or modify user saves in this milestone.
- Do not install or overwrite a local mod copy without a user request to do so.
  Document installation steps for the user instead.
- Do not publish, upload, commit or push without explicit user authorization.
- Reassess `cosmetic`, `severityAdd` and `severityRemove` when behavior changes;
  the current values apply only to diagnostics and read-only inventory.
- Keep changes small and report verified behavior separately from assumptions.

<!-- OCTOCODE-GLOBAL-START -->
## Octocode MCP — Codebase Research

Prefer Octocode for unfamiliar or complex codebases, architecture and dependency
analysis, locating implementations and callers, cross-file changes, regressions,
and relevant external repositories or npm packages. Do not invoke it for simple
localized edits or questions already answered by verified evidence.

1. Start focused discovery with localSearch.
2. Read relevant source with localGetFileContent.
3. Use localAnalyzeGraph when dependencies matter.
4. Use lspGetSemantics when symbol-level verification is needed.
5. Verify conclusions against source and distinguish evidence from assumptions.

Prefer narrow searches and reuse findings. Graphs are structural evidence, not
runtime proof. Do not modify files merely to investigate. Never expose credentials,
tokens or private repository contents. Preserve repository-specific instructions
and do not change Git, release, testing or deployment workflows. If Octocode is
unavailable for a path, report the limitation and use appropriate read-only tools.
<!-- OCTOCODE-GLOBAL-END -->
