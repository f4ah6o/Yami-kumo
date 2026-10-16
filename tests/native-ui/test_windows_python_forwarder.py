"""Verify the Windows native_ui runner's python3 forwarder contract."""

import json
import os
import subprocess
import sys


def main() -> int:
    interpreter = os.path.abspath(sys.executable)
    selected_interpreter = os.environ.get("YAMI_SELECTED_PYTHON_PATH")
    forwarder = os.environ.get("YAMI_PYTHON_FORWARDER_PATH")
    if not selected_interpreter:
        raise RuntimeError(
            "YAMI_SELECTED_PYTHON_PATH must name the interpreter running this test"
        )
    if os.path.normcase(os.path.abspath(selected_interpreter)) != os.path.normcase(
        interpreter
    ):
        raise RuntimeError(
            "YAMI_SELECTED_PYTHON_PATH must name the interpreter running this test"
        )
    if not forwarder or not os.path.isfile(forwarder):
        raise RuntimeError("YAMI_PYTHON_FORWARDER_PATH must name the compiled python3 forwarder")

    arguments = [
        "plain",
        "space value",
        'quote"inside',
        "trailing\\",
        'slash\\\\"quote',
        "",
        "unicode 日本",
    ]
    program = (
        "import json,sys; print(json.dumps(sys.argv[1:])); "
        "sys.stderr.write('forwarder stderr sentinel\\n'); sys.exit(37)"
    )
    child_arguments = ["-c", program, *arguments]
    environment = os.environ.copy()
    expected = subprocess.run(
        [interpreter, *child_arguments], capture_output=True, env=environment, check=False
    )
    actual = subprocess.run(
        [forwarder, *child_arguments], capture_output=True, env=environment, check=False
    )

    observed_arguments = json.loads(expected.stdout.decode("utf-8"))
    if expected.returncode != 37 or observed_arguments != arguments:
        raise RuntimeError(
            "direct interpreter control failed: "
            f"exit={expected.returncode}, args={observed_arguments!r}"
        )
    if (actual.returncode, actual.stdout, actual.stderr) != (
        expected.returncode,
        expected.stdout,
        expected.stderr,
    ):
        raise RuntimeError(
            "forwarder did not preserve child arguments, stdout, stderr, and exit status"
        )

    print(
        "Windows Python forwarder passed: venv interpreter, argument boundaries, "
        f"stdout, stderr, and exit status {actual.returncode}."
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:
        print(f"Windows Python forwarder test failed: {error}", file=sys.stderr)
        raise SystemExit(1)
