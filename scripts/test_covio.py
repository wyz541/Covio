import os
import pathlib
import re
import shlex
import subprocess
import tempfile
import unittest


SCRIPT = pathlib.Path(__file__).with_name("covio")


def function_body(name: str) -> str:
    source = SCRIPT.read_text(encoding="utf-8")
    match = re.search(
        rf"^{re.escape(name)}\(\) \{{\n(.*?)^\}}",
        source,
        flags=re.MULTILINE | re.DOTALL,
    )
    if match is None:
        raise AssertionError(f"missing shell function: {name}")
    return match.group(1)


class CovioLocalInstallTests(unittest.TestCase):
    def test_script_is_syntactically_valid(self):
        subprocess.run(["bash", "-n", str(SCRIPT)], check=True)

    def test_local_always_uses_the_transactional_package(self):
        command = function_body("cmd_local")
        self.assertIn("local_pkg\n", command)
        self.assertNotIn("local_app", SCRIPT.read_text(encoding="utf-8"))

    def test_packaging_never_uses_terminal_sudo(self):
        source = SCRIPT.read_text(encoding="utf-8")
        self.assertIsNone(re.search(r"\bsudo\b", source))

    def test_package_install_uses_one_graphical_authorization(self):
        installer = function_body("run_installer_with_administrator")
        authorization = function_body("run_with_administrator")
        self.assertIn("run_with_administrator", installer)
        self.assertEqual(installer.count("run_with_administrator"), 1)
        self.assertIn("with administrator privileges", authorization)
        self.assertEqual(authorization.count("do shell script"), 1)

    def test_installer_wrapper_builds_a_quoted_installer_command(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            osascript = root / "osascript"
            installer = root / "installer"
            args_file = root / "args.txt"
            script_file = root / "root-script.sh"
            package = root / "Covio test.pkg"

            osascript.write_text(
                "#!/bin/bash\n"
                "set -euo pipefail\n"
                "printf '%s\\n' \"$*\" > \"$COVIO_TEST_ARGS\"\n"
                "cat \"$2\" > \"$COVIO_TEST_ROOT_SCRIPT\"\n",
                encoding="utf-8",
            )
            installer.write_text("#!/bin/bash\nexit 0\n", encoding="utf-8")
            osascript.chmod(0o700)
            installer.chmod(0o700)
            package.write_bytes(b"pkg")

            environment = os.environ | {
                "COVIO_OSASCRIPT_BINARY": str(osascript),
                "COVIO_INSTALLER_BINARY": str(installer),
                "COVIO_TEST_ARGS": str(args_file),
                "COVIO_TEST_ROOT_SCRIPT": str(script_file),
            }
            subprocess.run(
                [
                    "bash",
                    "-c",
                    'source "$1"; run_installer_with_administrator "$2"',
                    "covio-test",
                    str(SCRIPT),
                    str(package),
                ],
                check=True,
                env=environment,
            )

            self.assertEqual(len(args_file.read_text(encoding="utf-8").splitlines()), 1)
            root_script = script_file.read_text(encoding="utf-8")
            command = shlex.split(root_script.splitlines()[-1])
            self.assertEqual(
                command,
                [str(installer), "-pkg", str(package), "-target", "/"],
            )


if __name__ == "__main__":
    unittest.main()
