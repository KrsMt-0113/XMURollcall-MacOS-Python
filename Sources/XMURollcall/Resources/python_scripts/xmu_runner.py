"""
Subprocess entrypoint for Swift bridge.
Executes one module function call and prints the returned JSON string.
"""

import importlib
import json
import sys
import traceback


def main():
    if len(sys.argv) != 4:
        print(json.dumps({"success": False, "error": "Usage: xmu_runner.py <module> <function> <args_json>"}))
        return 2

    module_name = sys.argv[1]
    function_name = sys.argv[2]
    args_json = sys.argv[3]

    try:
        args = json.loads(args_json)
        if not isinstance(args, list):
            raise ValueError("args_json must decode to a list")

        module = importlib.import_module(module_name)
        func = getattr(module, function_name)
        result = func(*args)

        if isinstance(result, str):
            print(result)
        else:
            print(json.dumps(result, ensure_ascii=False))
        return 0
    except Exception as exc:
        # Return machine-readable failure and keep traceback in stderr for diagnostics.
        print(json.dumps({"success": False, "error": str(exc)}))
        traceback.print_exc(file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())

