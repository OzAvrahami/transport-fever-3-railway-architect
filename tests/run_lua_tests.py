"""Development-only Lua 5.4 syntax, railway and planning tests; no TF3 or saves."""
from pathlib import Path
import json
import re

from lupa.lua54 import LuaRuntime

root = Path(__file__).resolve().parents[1]
package = root / "oz_railway_network_architect"
lua = LuaRuntime(unpack_returned_tuples=True)
compile_lua = lua.eval("function(source, name) local f, err = load(source, name); assert(f, err) end")
files = sorted(package.rglob("*.lua")) + sorted((root / "tests").glob("*.lua"))
for path in files:
    source = path.read_text(encoding="utf-8")
    assert not source.startswith("\ufeff"), f"BOM: {path}"
    compile_lua(source, str(path))
    if package in path.parents:
        assert not re.search(r"api\.cmd\.(?:sendCommand|makeWorldBuildProposalCmd)\s*\(", source), path
        assert "track_test.lua" not in source, path
    for ref in re.findall(r'oz_railway_network_architect::/([^"\s]+)', source):
        resource = ref.split("@")[0]
        if "@" in ref:
            resource += ".lua"
        assert (package / "content" / resource).is_file(), f"Missing reference: {ref}"
print(f"PASS Lua 5.4 syntax: {len(files)} files; local resource/import targets exist")
for path in [root / "AGENTS.md", root / "README.md", *(root / "docs").glob("*.md"), *package.rglob("*"), *files]:
    if path.is_file():
        text = path.read_bytes().decode("utf-8", errors="strict")
        assert not text.startswith("\ufeff"), f"BOM: {path}"
for path in package.rglob("*.json"):
    json.loads(path.read_text(encoding="utf-8"), parse_constant=lambda value: (_ for _ in ()).throw(ValueError(value)))
print("PASS UTF-8 without BOM and JSON syntax")
manifest = json.loads((package / "mod.json").read_text(encoding="utf-8"))
metadata = json.loads((package / "_metadata/modinfo.json").read_text(encoding="utf-8"))
assert manifest["modId"] == "oz_railway_network_architect" and manifest["revision"] == 1
assert manifest["cosmetic"] is True, "The active mod is read-only again"
assert metadata["name"] == "Railway Network Architect"
read_descriptor = lua.eval("""function(source)
    local env = {}
    assert(load(source, 'descriptor', 't', env))()
    return env.data()
end""")
references = [manifest["runScript"]["fileName"]]
for path in (package / "content").glob("*.gs.lua"):
    descriptor = read_descriptor(path.read_text(encoding="utf-8"))
    for field in ("updateScript", "guiUpdateScript", "guiHandleEventScript"):
        if descriptor[field]:
            references.append(descriptor[field]["fileName"])
for reference in references:
    resource, callback = reference.split("::/")[1].split("@")
    source = (package / "content" / (resource + ".lua")).read_text(encoding="utf-8")
    assert re.search(rf"\b{re.escape(callback)}\s*=\s*function\b", source), reference
print("PASS mod identity/revision and all descriptor/manifest callback exports")
lua.globals().ROOT = root.as_posix()
lua.execute((root / "tests" / "rail_inventory_test.lua").read_text(encoding="utf-8"))
# Separate runtime: the planner cannot accidentally depend on the rail tests' API mocks.
planning_lua = LuaRuntime(unpack_returned_tuples=True)
planning_lua.globals().MODULE_PATH = (package / "content").as_posix() + "/?.lua;" + root.as_posix() + "/?.lua"
planning_lua.execute('''
package.path = MODULE_PATH
ug_require = function(resource)
    local relative = assert(resource:match("^oz_railway_network_architect::/(.+)%.lua$"), resource)
    return require((relative:gsub("/", ".")))
end
''')
planning_lua.execute((root / "tests" / "corridor_planner_test.lua").read_text(encoding="utf-8"))
planning_lua.execute((root / "tests" / "hierarchical_planner_test.lua").read_text(encoding="utf-8"))
planning_lua.execute((root / "tests" / "preview_test.lua").read_text(encoding="utf-8"))
planning_lua.execute((root / "tests" / "network_planner_test.lua").read_text(encoding="utf-8"))
planning_lua.execute((root / "tests" / "network_worklist_test.lua").read_text(encoding="utf-8"))
planning_lua.execute((root / "tests" / "rail_geometry_test.lua").read_text(encoding="utf-8"))
planning_lua.execute((root / "tests" / "track_geometry_dto_test.lua").read_text(encoding="utf-8"))
planning_lua.execute((root / "tests" / "track_proposal_assembly_test.lua").read_text(encoding="utf-8"))
planning_lua.execute((root / "tests" / "station_sites_test.lua").read_text(encoding="utf-8"))
planning_lua.globals().CONTENT = (package / "content").as_posix()
planning_lua.execute((root / "tests" / "live_plan_test.lua").read_text(encoding="utf-8"))
