#!/usr/bin/env python3
"""Run Lua regressions in isolated mod copies using Lua 5.1 and LuaJIT.

Requires the optional developer dependency `lupa`; no game files are read.
Mocks test contracts and failure paths, not REDengine rendering or collision.
"""
from __future__ import annotations

import argparse
import importlib
import json
import os
from pathlib import Path
import shutil
import tempfile

ROOT = Path(__file__).resolve().parents[1]
MOD = ROOT / "bin/x64/plugins/cyber_engine_tweaks/mods/LocationStudio"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runtime", choices=("lua51", "luajit21"), default="luajit21")
    parser.add_argument("tests", nargs="*")
    args = parser.parse_args()
    runtime_class = importlib.import_module("lupa." + args.runtime).LuaRuntime
    syntax_runtime = runtime_class(unpack_returned_tuples=True)
    syntax_runtime.execute('function check_syntax(path) local fn,err=loadfile(path);assert(fn,err) end')
    lua_files = sorted(MOD.rglob('*.lua'))
    for path in lua_files:
        syntax_runtime.globals().check_syntax(str(path))
    print(f'PASS {args.runtime} syntax ({len(lua_files)} mod files)')
    tests = [ROOT / "tests" / name for name in args.tests] if args.tests else sorted((ROOT / "tests").glob("*_test.lua"))
    failed = 0
    for test in tests:
        with tempfile.TemporaryDirectory(prefix="locationstudio-test-") as directory:
            mod = Path(directory) / "LocationStudio"
            shutil.copytree(MOD, mod, ignore=shutil.ignore_patterns("__pycache__", "*.pyc"))
            for folder in ("data", "logs", "bridge", "exports", "thumbnails"):
                (mod / folder).mkdir(exist_ok=True)
            old = Path.cwd()
            try:
                os.chdir(mod)
                lua = runtime_class(unpack_returned_tuples=True)
                lua.globals().arg = lua.table_from([str(mod), str(ROOT / 'tests')])
                def to_python(value):
                    if not hasattr(value, 'items'):
                        return value
                    entries = dict(value.items())
                    if entries and set(entries) == set(range(1, len(entries) + 1)):
                        return [to_python(entries[index]) for index in range(1, len(entries) + 1)]
                    return {str(key): to_python(item) for key, item in entries.items()}
                lua.globals().test_json_encode = lambda value: json.dumps(to_python(value), allow_nan=False)
                lua.globals().test_json_decode = lambda value: lua.table_from(json.loads(value), recursive=True)
                # Keep test output short without muting exceptions/assertions.
                lua.globals().print = lambda *values: None
                lua.globals()._test_file = str(test)
                lua.execute("dofile(_test_file)")
                print(f"PASS {args.runtime} {test.name}")
            except Exception as error:
                failed += 1
                print(f"FAIL {args.runtime} {test.name}\n{error}")
            finally:
                os.chdir(old)
    print(f"{len(tests) - failed}/{len(tests)} tests passed ({args.runtime}).")
    return int(failed > 0)


if __name__ == "__main__":
    raise SystemExit(main())
