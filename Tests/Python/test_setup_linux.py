#!/usr/bin/env python3
"""Vertragstests für den plattformneutralen Python-Bootstrap."""

import contextlib
import importlib.util
import io
import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock


REPO_ROOT = Path(__file__).resolve().parents[2]
SETUP_PATH = REPO_ROOT / "Tools" / "setup.py"
SPEC = importlib.util.spec_from_file_location("apply_foundry_setup_linux", SETUP_PATH)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("setup.py konnte nicht geladen werden")
setup = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = setup
SPEC.loader.exec_module(setup)


def detections(**overrides):
    result = {
        "coreRuntime": setup.Detection(True, "3.11.9", "/usr/bin/python3"),
        "browser": setup.Detection(True, "151.0.0.0", "/usr/bin/chromium"),
        "fonts": setup.Detection(True, None, "/usr/share/fonts/LiberationSans-Regular.ttf"),
        "shellcheck": setup.Detection(True, "0.10.0", "/usr/bin/shellcheck"),
    }
    result.update(overrides)
    return result


def options(**overrides):
    values = {
        "runtime": False,
        "browser": False,
        "fonts": False,
        "shellcheck": False,
        "dry_run": True,
        "assume_yes": False,
        "output_format": "json",
    }
    values.update(overrides)
    return setup.Options(**values)


class FakeRunner:
    def __init__(self):
        self.commands = []

    def run(self, args):
        self.commands.append(list(args))


class FakePrivilege:
    def __init__(self):
        self.commands = []

    def run(self, args):
        self.commands.append(list(args))


class NonInteractive:
    def isatty(self):
        return False


class InteractiveAnswer:
    def __init__(self, answer):
        self.answer = answer

    def isatty(self):
        return True

    def readline(self):
        return self.answer + "\n"


class SetupLinuxTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.catalog = setup.load_catalog()

    def context(self, manager="apt", distro="debian"):
        executable = self.catalog["packageManagers"][manager]["executable"]
        return setup.PlatformContext(distro, "13", "x86_64", manager, "/usr/bin/" + executable)

    def test_manifest_is_versioned_and_contains_only_declared_components(self):
        self.assertEqual(2, self.catalog["schemaVersion"])
        self.assertEqual("3.11", self.catalog["minimumPythonVersion"])
        self.assertEqual(
            {"apt", "dnf", "yum", "pacman", "zypper"},
            set(self.catalog["packageManagers"]),
        )
        for manager in self.catalog["packageManagers"].values():
            self.assertEqual(set(setup.COMPONENT_NAMES), set(manager["components"]))
        serialized = json.dumps(self.catalog).lower()
        self.assertNotIn("pypi", serialized)
        self.assertNotIn("aur", serialized)
        self.assertNotIn("snap", serialized)

    def test_manifest_rejects_unsafe_package_names(self):
        altered = json.loads(json.dumps(self.catalog))
        altered["packageManagers"]["apt"]["components"]["browser"]["packages"] = ["chromium;id"]
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "invalid.json"
            path.write_text(json.dumps(altered), encoding="utf-8")
            with self.assertRaises(setup.SetupError) as caught:
                setup.load_catalog(path)
        self.assertEqual(setup.EXIT_USAGE_OR_PLATFORM, caught.exception.exit_code)

    def test_parser_supports_all_and_gnu_long_options(self):
        _, parsed = setup.parse_args(
            ["--all", "--browser=chromium", "--dry-run", "--yes", "--format=json"]
        )
        self.assertTrue(all(parsed.selected.values()))
        self.assertTrue(parsed.dry_run)
        self.assertTrue(parsed.assume_yes)
        self.assertEqual("json", parsed.output_format)

    def test_parser_rejects_unknown_browser_with_exit_two(self):
        with contextlib.redirect_stderr(io.StringIO()):
            with self.assertRaises(SystemExit) as caught:
                setup.parse_args(["--browser", "firefox"])
        self.assertEqual(2, caught.exception.code)

    def test_manager_detection_uses_declared_precedence(self):
        with tempfile.TemporaryDirectory() as temp:
            os_release = Path(temp) / "os-release"
            os_release.write_text('ID="fedora"\nVERSION_ID="43"\n', encoding="utf-8")

            def fake_which(name):
                return "/fake/" + name if name in ("dnf", "yum") else None

            context = setup.build_context(
                self.catalog,
                which=fake_which,
                machine="amd64",
                os_release_path=os_release,
                trust_executable=lambda path: path,
            )
        self.assertEqual("dnf", context.manager)
        self.assertEqual("x86_64", context.architecture)
        self.assertEqual("fedora", context.distro_id)

    def test_unknown_manager_and_wrong_architecture_are_exit_two(self):
        with tempfile.TemporaryDirectory() as temp:
            os_release = Path(temp) / "os-release"
            os_release.write_text("ID=unknown\nVERSION_ID=1\n", encoding="utf-8")
            with self.assertRaises(setup.SetupError) as manager_error:
                setup.build_context(
                    self.catalog,
                    which=lambda _name: None,
                    machine="x86_64",
                    os_release_path=os_release,
                    trust_executable=lambda path: path,
                )
            with self.assertRaises(setup.SetupError) as architecture_error:
                setup.build_context(
                    self.catalog,
                    which=lambda _name: "/bin/tool",
                    machine="aarch64",
                    os_release_path=os_release,
                    trust_executable=lambda path: path,
                )
        self.assertEqual(2, manager_error.exception.exit_code)
        self.assertIn("Manuell benötigt", str(manager_error.exception))
        self.assertEqual(2, architecture_error.exception.exit_code)
        self.assertIn("ausschließlich x64", str(architecture_error.exception))

    def test_untrusted_package_manager_path_is_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            os_release = Path(temp) / "os-release"
            executable = Path(temp) / "apt-get"
            os_release.write_text("ID=debian\nVERSION_ID=13\n", encoding="utf-8")
            executable.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
            executable.chmod(0o755)
            with self.assertRaises(setup.SetupError) as caught:
                setup.build_context(
                    self.catalog,
                    which=lambda name: str(executable) if name == "apt-get" else None,
                    machine="x86_64",
                    os_release_path=os_release,
                )
        self.assertEqual(2, caught.exception.exit_code)

    def test_schema_three_exposes_python_core_runtime_and_install_plan(self):
        report = setup.build_report(
            options(runtime=True, shellcheck=True),
            self.context(),
            self.catalog,
            detections(shellcheck=setup.Detection(False)),
        )
        self.assertEqual(3, report["schemaVersion"])
        self.assertEqual("linux", report["coreRuntime"]["platform"])
        self.assertEqual("python", report["coreRuntime"]["language"])
        self.assertEqual("3.11", report["coreRuntime"]["minimumVersion"])
        self.assertEqual("python3 Tools/setup.py --runtime --dry-run --format json", report["coreRuntime"]["setupCommand"])
        self.assertEqual("install", report["dependencies"]["shellcheck"]["plannedAction"])
        self.assertEqual(["shellcheck"], report["plannedChanges"][0]["packages"])
        self.assertIn("--shellcheck", report["applyCommand"])

    def test_windows_and_macos_use_only_the_declared_package_routes(self):
        missing = detections(
            coreRuntime=setup.Detection(False), browser=setup.Detection(False),
            fonts=setup.Detection(False), shellcheck=setup.Detection(False),
        )
        windows = setup.build_report(options(runtime=True, browser=True, shellcheck=True), setup.PlatformContext("windows", "11", "x86_64", "winget", "C:/Windows/System32/winget.exe", "windows"), self.catalog, missing)
        self.assertEqual("winget", windows["packageManager"])
        self.assertEqual("Python.Python.3.13", windows["plannedChanges"][0]["packages"][0])
        self.assertNotIn("powershell", json.dumps(windows).lower())
        macos = setup.build_report(options(runtime=True, browser=True, fonts=True, shellcheck=True), setup.PlatformContext("macos", "15", "x86_64", "brew", "/usr/local/bin/brew", "macos"), self.catalog, missing)
        self.assertEqual("brew", macos["packageManager"])
        self.assertEqual({"python@3.13", "google-chrome", "font-liberation", "shellcheck"}, {package for change in macos["plannedChanges"] for package in change["packages"]})

    def test_font_detection_falls_back_to_actual_system_font_without_fc_match(self):
        with tempfile.TemporaryDirectory() as temp:
            font = Path(temp) / "nested/LiberationSans-Regular.ttf"
            font.parent.mkdir()
            font.write_bytes(b"\x00\x01\x00\x00" + b"synthetic-font-data" * 80)
            detected = setup.detect_fonts(
                which=lambda _name: None,
                trust_executable=lambda path: path,
                font_roots=(Path(temp),),
            )
        self.assertTrue(detected.present)
        self.assertEqual(str(font), detected.path)

    def test_font_file_fallback_rejects_name_only_and_symlinks(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            fake = root / "LiberationSans-Regular.ttf"
            fake.write_bytes(b"not-a-font" * 200)
            self.assertFalse(setup.detect_fonts(which=lambda _name: None, font_roots=(root,)).present)
            fake.unlink()
            outside = root.parent / (root.name + "-font.ttf")
            outside.write_bytes(b"\x00\x01\x00\x00" + b"synthetic-font-data" * 80)
            self.addCleanup(lambda: outside.unlink(missing_ok=True))
            fake.symlink_to(outside)
            self.assertFalse(setup.detect_fonts(which=lambda _name: None, font_roots=(root,)).present)

    def test_ubuntu_missing_chromium_is_manual_snap_block(self):
        report = setup.build_report(
            options(browser=True),
            self.context(distro="ubuntu"),
            self.catalog,
            detections(browser=setup.Detection(False)),
        )
        browser = report["dependencies"]["browser"]
        self.assertTrue(browser["blocked"])
        self.assertFalse(browser["installable"])
        self.assertEqual("manual", browser["plannedAction"])
        self.assertEqual([], report["plannedChanges"])
        self.assertTrue(report["manualActionRequired"])
        self.assertNotIn("snap", json.dumps(report["plannedChanges"]))

    def test_rocky_base_repositories_defer_browser_and_shellcheck(self):
        rocky = setup.PlatformContext("rocky", "9", "x86_64", "dnf", "/usr/bin/dnf")
        report = setup.build_report(
            options(browser=True, shellcheck=True),
            rocky,
            self.catalog,
            detections(
                browser=setup.Detection(False),
                shellcheck=setup.Detection(False),
            ),
        )
        self.assertEqual([], report["plannedChanges"])
        self.assertEqual({"browser", "shellcheck"}, {item["component"] for item in report["manualActions"]})
        for component in ("browser", "shellcheck"):
            detail = report["dependencies"][component]
            self.assertTrue(detail["blocked"])
            self.assertFalse(detail["installable"])
            self.assertEqual("manual", detail["plannedAction"])
            self.assertIn("Communityquellen", detail["reason"])

    def test_snap_executable_is_never_accepted_as_chromium(self):
        detected = setup.detect_browser(
            which=lambda name: "/snap/bin/chromium" if name == "chromium" else None
        )
        self.assertFalse(detected.present)

    def test_snap_transition_wrapper_is_rejected_before_execution(self):
        with tempfile.TemporaryDirectory() as temp:
            wrapper = Path(temp) / "chromium-browser"
            wrapper.write_text("#!/bin/sh\nexec snap run chromium \"$@\"\n", encoding="utf-8")
            wrapper.chmod(0o755)
            with mock.patch.object(setup, "capture_command") as capture:
                detected = setup.detect_browser(
                    which=lambda name: str(wrapper) if name == "chromium-browser" else None,
                    trust_executable=lambda path: path,
                )
        self.assertFalse(detected.present)
        capture.assert_not_called()

    def test_existing_chrome_or_edge_satisfies_chromium_browser_capability(self):
        cases = (
            ("google-chrome", "Google Chrome", "Google Chrome 151.0.7922.173"),
            ("microsoft-edge", "Microsoft Edge", "Microsoft Edge 151.0.100.1"),
        )
        with tempfile.TemporaryDirectory() as temp:
            executable = Path(temp) / "browser"
            executable.write_text("#!/bin/sh\n", encoding="utf-8")
            executable.chmod(0o755)
            for command_name, provider, version_output in cases:
                with self.subTest(command=command_name):
                    completed = setup.subprocess.CompletedProcess(
                        [str(executable), "--version"], 0, stdout=version_output, stderr=""
                    )
                    with mock.patch.object(setup, "capture_command", return_value=completed):
                        detected = setup.detect_browser(
                            which=lambda name, selected=command_name: str(executable)
                            if name == selected
                            else None,
                            trust_executable=lambda path: path,
                        )
                    self.assertTrue(detected.present)
                    self.assertEqual("151.0.7922.173" if command_name == "google-chrome" else "151.0.100.1", detected.version)
                    self.assertEqual(provider, detected.provider)

    def test_existing_chrome_avoids_ubuntu_snap_block(self):
        report = setup.build_report(
            options(browser=True),
            self.context(distro="ubuntu"),
            self.catalog,
            detections(
                browser=setup.Detection(
                    True,
                    "151.0.7922.173",
                    "/opt/google/chrome/google-chrome",
                    "Google Chrome",
                )
            ),
        )
        browser = report["dependencies"]["browser"]
        self.assertFalse(browser["blocked"])
        self.assertEqual("present", browser["status"])
        self.assertEqual("Google Chrome", browser["detectedAs"])
        self.assertEqual([], report["manualActions"])

    def test_ubuntu_snap_block_exits_two_without_package_command(self):
        selected = options(browser=True, dry_run=False, assume_yes=True)
        missing_browser = detections(browser=setup.Detection(False))
        stdout = io.StringIO()
        with mock.patch.object(setup, "collect_detections", return_value=missing_browser):
            with mock.patch.object(setup, "PackageInstaller") as installer:
                with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(io.StringIO()):
                    code = setup.run_setup(selected, self.context(distro="ubuntu"), self.catalog)
        self.assertEqual(2, code)
        self.assertEqual("blocked", json.loads(stdout.getvalue())["status"])
        installer.assert_not_called()

    def test_apt_update_and_install_both_use_sudo_and_update_runs_once(self):
        runner = FakeRunner()
        privilege = setup.PrivilegeExecutor(
            runner,
            effective_uid=1000,
            which=lambda name: "/usr/bin/sudo" if name == "sudo" else None,
            trust_executable=lambda path: path,
        )
        installer = setup.PackageInstaller(self.context(), privilege)
        installer.install(["python3"])
        installer.install(["shellcheck"])
        self.assertEqual(
            [
                ["/usr/bin/sudo", "--", "/usr/bin/apt-get", "update"],
                [
                    "/usr/bin/sudo",
                    "--",
                    "/usr/bin/apt-get",
                    "install",
                    "--yes",
                    "--no-install-recommends",
                    "python3",
                ],
                [
                    "/usr/bin/sudo",
                    "--",
                    "/usr/bin/apt-get",
                    "install",
                    "--yes",
                    "--no-install-recommends",
                    "shellcheck",
                ],
            ],
            runner.commands,
        )

    def test_missing_privilege_is_runtime_error(self):
        privilege = setup.PrivilegeExecutor(
            FakeRunner(),
            effective_uid=1000,
            which=lambda _name: None,
            trust_executable=lambda path: path,
        )
        with self.assertRaises(setup.SetupError) as caught:
            privilege.run(["/usr/bin/apt-get", "update"])
        self.assertEqual(1, caught.exception.exit_code)

    def test_distribution_commands_use_argument_lists(self):
        expected = {
            "dnf": ["/usr/bin/dnf", "install", "-y", "chromium"],
            "yum": ["/usr/bin/yum", "install", "-y", "chromium"],
            "zypper": [
                "/usr/bin/zypper",
                "--non-interactive",
                "install",
                "--no-recommends",
                "chromium",
            ],
        }
        for manager, command in expected.items():
            with self.subTest(manager=manager):
                privilege = FakePrivilege()
                setup.PackageInstaller(self.context(manager=manager), privilege).install(["chromium"])
                self.assertEqual([command], privilege.commands)
        privilege = FakePrivilege()
        pacman = setup.PackageInstaller(self.context(manager="pacman"), privilege)
        pacman.install(["chromium"])
        pacman.install(["shellcheck"])
        self.assertEqual("-Syu", privilege.commands[0][1])
        self.assertEqual("-S", privilege.commands[1][1])

    def test_pacman_plan_discloses_full_system_upgrade(self):
        report = setup.build_report(
            options(runtime=True), self.context(manager="pacman"), self.catalog,
            detections(coreRuntime=setup.Detection(False)),
        )
        self.assertTrue(report["packageManagerOperation"]["fullSystemUpgrade"])
        self.assertTrue(report["plannedChanges"][0]["includesFullSystemUpgrade"])
        self.assertIn("-Syu", report["packageManagerOperation"]["detail"])

    def test_noninteractive_confirmation_is_exit_two(self):
        with self.assertRaises(setup.SetupError) as caught:
            setup.confirm_installation(stdin=NonInteractive(), stdout=io.StringIO())
        self.assertEqual(2, caught.exception.exit_code)

    def test_interactive_rejection_is_not_confirmation(self):
        self.assertFalse(
            setup.confirm_installation(stdin=InteractiveAnswer("n"), stdout=io.StringIO())
        )

    def test_noninteractive_json_run_still_returns_safe_plan(self):
        selected = options(shellcheck=True, dry_run=False, assume_yes=False)
        stdout = io.StringIO()
        with mock.patch.object(
            setup,
            "collect_detections",
            return_value=detections(shellcheck=setup.Detection(False)),
        ):
            with mock.patch.object(
                setup,
                "confirm_installation",
                side_effect=setup.SetupError("Bestätigung fehlt", 2),
            ):
                with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(io.StringIO()):
                    code = setup.run_setup(selected, self.context(), self.catalog)
        report = json.loads(stdout.getvalue())
        self.assertEqual(2, code)
        self.assertEqual("confirmation_required", report["status"])
        self.assertEqual(["shellcheck"], report["plannedChanges"][0]["packages"])

    def test_old_or_virtualenv_python_is_rejected(self):
        old = setup.subprocess.CompletedProcess(
            ["old"],
            0,
            stdout=json.dumps(
                {
                    "version": [3, 8, 20],
                    "executable": sys.executable,
                    "prefix": "/usr",
                    "base_prefix": "/usr",
                }
            ),
            stderr="",
        )
        virtual = setup.subprocess.CompletedProcess(
            ["venv"],
            0,
            stdout=json.dumps(
                {
                    "version": [3, 12, 1],
                    "executable": sys.executable,
                    "prefix": "/tmp/venv",
                    "base_prefix": "/usr",
                }
            ),
            stderr="",
        )
        with mock.patch.object(setup, "python_candidates", return_value=["old", "venv"]):
            with mock.patch.object(setup, "capture_command", side_effect=[old, virtual]):
                detected = setup.detect_python((3, 9))
        self.assertFalse(detected.present)

    def test_idempotent_run_does_not_create_installer(self):
        selected = options(runtime=True, browser=True, fonts=True, shellcheck=True, dry_run=False, assume_yes=True)
        with mock.patch.object(setup, "collect_detections", return_value=detections()):
            with mock.patch.object(setup, "PackageInstaller") as installer:
                stdout = io.StringIO()
                with contextlib.redirect_stdout(stdout):
                    code = setup.run_setup(selected, self.context(), self.catalog)
        self.assertEqual(0, code)
        installer.assert_not_called()
        self.assertEqual("ready", json.loads(stdout.getvalue())["status"])

    def test_failed_installation_reports_reached_partial_state(self):
        missing = detections(shellcheck=setup.Detection(False))
        selected = options(shellcheck=True, dry_run=False, assume_yes=True)
        fake_installer = mock.Mock()
        fake_installer.install.side_effect = setup.CommandError("synthetischer Paketfehler")
        stdout = io.StringIO()
        stderr = io.StringIO()
        with mock.patch.object(setup, "collect_detections", return_value=missing):
            with mock.patch.object(setup, "PackageInstaller", return_value=fake_installer):
                with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
                    code = setup.run_setup(selected, self.context(), self.catalog)
        report = json.loads(stdout.getvalue())
        self.assertEqual(1, code)
        self.assertEqual("failed", report["status"])
        self.assertEqual("shellcheck", report["failedComponent"])
        self.assertEqual([], report["appliedChanges"])
        self.assertIn("synthetischer Paketfehler", stderr.getvalue())

    def test_failure_after_one_component_lists_applied_partial_state(self):
        initial = detections(
            fonts=setup.Detection(False),
            shellcheck=setup.Detection(False),
        )
        after_fonts = detections(shellcheck=setup.Detection(False))
        selected = options(fonts=True, shellcheck=True, dry_run=False, assume_yes=True)
        fake_installer = mock.Mock()
        fake_installer.install.side_effect = [None, setup.CommandError("zweiter Paketfehler")]
        stdout = io.StringIO()
        with mock.patch.object(
            setup,
            "collect_detections",
            side_effect=[initial, after_fonts, after_fonts],
        ):
            with mock.patch.object(setup, "PackageInstaller", return_value=fake_installer):
                with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(io.StringIO()):
                    code = setup.run_setup(selected, self.context(), self.catalog)
        report = json.loads(stdout.getvalue())
        self.assertEqual(1, code)
        self.assertEqual("shellcheck", report["failedComponent"])
        self.assertEqual("fonts", report["appliedChanges"][0]["component"])
        self.assertEqual("present", report["dependencies"]["fonts"]["status"])


if __name__ == "__main__":
    unittest.main()
