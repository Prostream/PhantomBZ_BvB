"""Run Lua 5.4 tests with an isolated local lupa wheel (pip --target .dev-python lupa)."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / '.dev-python'))
from lupa.lua54 import LuaRuntime

runtime = LuaRuntime(unpack_returned_tuples=True)
runtime.globals().arg = runtime.table_from({i: x for i, x in enumerate(sys.argv[1:])})
runtime.execute("assert(loadfile(arg[0]))()")
