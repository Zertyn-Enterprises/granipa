#!/usr/bin/env python3
"""Regression tests for the signing behavior of Scripts/bundle.sh.

Runs the REAL bundle.sh (byte-identical copy) inside an isolated temp fixture:
stub `security`/`swift`/`codesign`/`install_name_tool` on PATH, a fake nested
Sparkle hierarchy emitted by the swift stub, and a marker inside a pre-existing
build/Grañipa.app to prove that identity failures never build or delete the
old bundle. The stub `security` prints realistic `find-identity` output with
quoted identity names, injected via an exported variable. bundle.sh passes
targets as repo-root-relative paths; stubs and assertions normalize them to
the absolute paths the fixture compares against.

Stdlib only. Run: python3 Tests/Shell/test_bundle_signing.py [-v]
"""

import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent.parent
BUNDLE_SH = REPO / "Scripts" / "bundle.sh"

TEAM = "R4V252C833"
DR_HASH = "A1B2C3D4E5F60718293A4B5C6D7E8F9012345678"
DR_NAME = f"Developer ID Application: ZERTYN ENTERPRISES ({TEAM})"
DEV_HASH = "0123456789ABCDEF0123456789ABCDEF01234567"
DEV_NAME = f"Apple Development: zertyn@zertyn.com ({TEAM})"
OTHER_HASH = "FFEEDDCCBBAA99887766554433221100FFEE0011"
OTHER_DR_NAME = "Developer ID Application: SOMEBODY ELSE (AAAAAAAAAA)"


def identity_listing(*identities):
    """Render lines the way `security find-identity -v -p codesigning` does."""
    text = "".join(
        f'  {i}) {hash_} "{name}"\n' for i, (hash_, name) in enumerate(identities, 1)
    )
    return text + f"    {len(identities)} valid identities found\n"


FULL_LISTING = identity_listing(
    (DEV_HASH, DEV_NAME),
    (DR_HASH, DR_NAME),
    (OTHER_HASH, OTHER_DR_NAME),
)
NO_DR_LISTING = identity_listing((DEV_HASH, DEV_NAME))
WRONG_TEAM_LISTING = identity_listing((DEV_HASH, DEV_NAME), (OTHER_HASH, OTHER_DR_NAME))

SECURITY_STUB = """\
#!/bin/bash
# Prints a realistic `security find-identity -v -p codesigning` listing.
printf '%s\\n' "$STUB_SECURITY_OUT"
exit 0
"""

SWIFT_STUB = """\
#!/bin/bash
{ IFS=$'\\t'; printf '%s\\n' "$*"; } >> "$STUB_HOME/swift.log"
for arg in "$@"; do
  [ "$arg" = "--show-bin-path" ] && { echo "$STUB_HOME/.build/$3"; exit 0; }
done
# swift build -c <config>: emit binaries plus a fake nested Sparkle hierarchy.
bin_dir="$STUB_HOME/.build/$3"
mkdir -p "$bin_dir"
: > "$bin_dir/Granipa"
: > "$bin_dir/GranipaBatteryHelper"
fw="$STUB_HOME/.build/macos/$3/Sparkle.framework"
mkdir -p "$fw/XPCServices/org.sparkle-project.SparkleUpdater.xpc" \\
  "$fw/Resources" "$fw/Versions/A/Updater.app/Contents/MacOS"
: > "$fw/Resources/Autoupdate"
exit 0
"""

CODESIGN_STUB = """\
#!/bin/bash
{ IFS=$'\\t'; printf '%s\\n' "$*"; } >> "$STUB_HOME/codesign.log"
target="${@: -1}"
# bundle.sh passes targets relative to the repo root; STUB_CODESIGN_FAIL_TARGET
# is absolute, so compare in absolute form.
case "$target" in /*) ;; *) target="$PWD/$target" ;; esac
# Fail only the FIRST attempt on the designated target, so a fallback that
# retries the same target (e.g. an ad-hoc second pass) would succeed.
if [ -n "${STUB_CODESIGN_FAIL_TARGET:-}" ] && [ "$target" = "$STUB_CODESIGN_FAIL_TARGET" ] \\
   && [ ! -f "$STUB_HOME/codesign-failed-once" ]; then
  : > "$STUB_HOME/codesign-failed-once"
  echo "stub codesign: refusing to sign $target" >&2
  exit 1
fi
exit 0
"""

INSTALL_NAME_TOOL_STUB = "#!/bin/bash\nexit 0\n"


class BundleSigningTests(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="granipa-bundle-tests-"))
        scripts = self.tmp / "Scripts"
        scripts.mkdir()
        shutil.copyfile(BUNDLE_SH, scripts / "bundle.sh")
        (scripts / "bundle.sh").chmod(0o755)
        resources = self.tmp / "Resources"
        resources.mkdir()
        for name in (
            "Info.plist",
            "AppIcon.icns",
            "com.zertyn.granipa.batteryhelper.plist",
            "Granipa.entitlements",
        ):
            (resources / name).write_text("stub\n", encoding="utf-8")
        bin_dir = self.tmp / "bin"
        bin_dir.mkdir()
        for name, body in (
            ("security", SECURITY_STUB),
            ("swift", SWIFT_STUB),
            ("codesign", CODESIGN_STUB),
            ("install_name_tool", INSTALL_NAME_TOOL_STUB),
        ):
            stub = bin_dir / name
            stub.write_text(body, encoding="utf-8")
            stub.chmod(0o755)
        self.identities = FULL_LISTING
        self.codesign_id = None
        self.codesign_fail_target = None

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    # -- fixture helpers ---------------------------------------------------

    def app(self):
        return self.tmp / "build" / "Grañipa.app"

    def abs_target(self, path):
        """Recorded targets are repo-root-relative; compare in absolute form."""
        return path if path.startswith("/") else str(self.tmp / path)

    def run_bundle(self, config="debug"):
        env = dict(os.environ)
        env["PATH"] = f"{self.tmp / 'bin'}:{env['PATH']}"
        env["STUB_HOME"] = str(self.tmp)
        env["STUB_SECURITY_OUT"] = self.identities
        env.pop("CODESIGN_ID", None)
        if self.codesign_id is not None:
            env["CODESIGN_ID"] = self.codesign_id
        if self.codesign_fail_target is not None:
            env["STUB_CODESIGN_FAIL_TARGET"] = str(self.codesign_fail_target)
        return subprocess.run(
            ["bash", str(self.tmp / "Scripts" / "bundle.sh"), config],
            capture_output=True,
            text=True,
            env=env,
        )

    def log_calls(self, name):
        path = self.tmp / name
        if not path.exists():
            return []
        text = path.read_text(encoding="utf-8")
        # Stubs join args with single tabs ("$*" with IFS=<tab>); a trailing
        # empty field is a real empty argument, so split without stripping.
        return [line.split("\t") for line in text.splitlines() if line.strip()]

    def codesign_signs(self):
        """[(--sign value, target)] for each signing call (verify excluded)."""
        return [
            (call[call.index("--sign") + 1], self.abs_target(call[-1]))
            for call in self.log_calls("codesign.log")
            if "--sign" in call
        ]

    def plant_old_bundle(self):
        marker = self.app() / "Contents" / "marker"
        marker.parent.mkdir(parents=True)
        marker.write_text("previous build\n", encoding="utf-8")
        return marker

    def nested_targets(self):
        fw = self.app() / "Contents" / "Frameworks" / "Sparkle.framework"
        return {
            "xpc": fw / "XPCServices" / "org.sparkle-project.SparkleUpdater.xpc",
            "autoupdate": fw / "Resources" / "Autoupdate",
            "updater": fw / "Versions" / "A" / "Updater.app",
            "framework": fw,
            "helper": self.app() / "Contents" / "MacOS" / "GranipaBatteryHelper",
            "app": self.app(),
        }

    def assert_hard_failure(self, proc, marker):
        """Identity rejection: no build, no signing, old bundle untouched."""
        self.assertNotEqual(proc.returncode, 0, proc.stdout)
        self.assertNotIn("Built", proc.stdout)
        self.assertEqual(self.log_calls("swift.log"), [])
        self.assertEqual(self.codesign_signs(), [])
        self.assertTrue(marker.exists())

    # -- default identity selection ---------------------------------------

    def test_default_picks_team_developer_id_over_development(self):
        proc = self.run_bundle()
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertIn("Built", proc.stdout)
        signs = self.codesign_signs()
        # 3 Sparkle nested targets + framework + helper + app
        self.assertEqual(len(signs), 6)
        for sign_id, _ in signs:
            self.assertEqual(sign_id, DR_NAME)

    def test_release_config_also_uses_team_developer_id(self):
        proc = self.run_bundle(config="release")
        self.assertEqual(proc.returncode, 0, proc.stderr)
        for sign_id, _ in self.codesign_signs():
            self.assertEqual(sign_id, DR_NAME)

    # -- missing / wrong-team identity ------------------------------------

    def test_missing_identity_fails_before_build_and_keeps_old_bundle(self):
        self.identities = NO_DR_LISTING
        marker = self.plant_old_bundle()
        self.assert_hard_failure(self.run_bundle(), marker)

    def test_wrong_team_only_fails_before_build_and_keeps_old_bundle(self):
        self.identities = WRONG_TEAM_LISTING
        marker = self.plant_old_bundle()
        self.assert_hard_failure(self.run_bundle(), marker)

    # -- explicit CODESIGN_ID validation ----------------------------------

    def test_explicit_exact_name_accepted(self):
        self.codesign_id = DR_NAME
        proc = self.run_bundle()
        self.assertEqual(proc.returncode, 0, proc.stderr)
        for sign_id, _ in self.codesign_signs():
            self.assertEqual(sign_id, DR_NAME)

    def test_explicit_hash_accepted(self):
        self.codesign_id = DR_HASH
        proc = self.run_bundle()
        self.assertEqual(proc.returncode, 0, proc.stderr)
        for sign_id, _ in self.codesign_signs():
            self.assertEqual(sign_id, DR_HASH)

    def test_explicit_development_identity_rejected(self):
        self.codesign_id = DEV_NAME
        marker = self.plant_old_bundle()
        self.assert_hard_failure(self.run_bundle(), marker)

    def test_explicit_adhoc_dash_rejected(self):
        self.codesign_id = "-"
        marker = self.plant_old_bundle()
        self.assert_hard_failure(self.run_bundle(), marker)

    def test_explicit_unknown_identity_rejected(self):
        self.codesign_id = f"Developer ID Application: NOT PRESENT ({TEAM})"
        marker = self.plant_old_bundle()
        self.assert_hard_failure(self.run_bundle(), marker)

    # -- signing failures abort at the first failing nested target ---------

    def assert_sign_failure_aborts(self, key):
        target = self.nested_targets()[key]
        self.codesign_fail_target = target
        proc = self.run_bundle()
        self.assertNotEqual(proc.returncode, 0, proc.stdout)
        self.assertNotIn("Built", proc.stdout)
        signs = self.codesign_signs()
        self.assertTrue(signs)
        for sign_id, _ in signs:  # never falls back to ad-hoc
            self.assertNotEqual(sign_id, "-")
        self.assertEqual(signs[-1][1], str(target))  # stops right there

    def test_xpc_sign_failure_aborts(self):
        self.assert_sign_failure_aborts("xpc")

    def test_autoupdate_sign_failure_aborts(self):
        self.assert_sign_failure_aborts("autoupdate")

    def test_updater_app_sign_failure_aborts(self):
        self.assert_sign_failure_aborts("updater")

    def test_framework_sign_failure_aborts(self):
        self.assert_sign_failure_aborts("framework")

    def test_helper_sign_failure_aborts(self):
        self.assert_sign_failure_aborts("helper")

    def test_app_sign_failure_aborts(self):
        self.assert_sign_failure_aborts("app")

    # -- Developer ID options are never customized -------------------------

    def test_app_gets_runtime_entitlements_and_timestamp(self):
        proc = self.run_bundle()
        self.assertEqual(proc.returncode, 0, proc.stderr)
        calls = self.log_calls("codesign.log")
        app_calls = [
            c
            for c in calls
            if self.abs_target(c[-1]) == str(self.app()) and "--sign" in c
        ]
        self.assertEqual(len(app_calls), 1)
        for token in (
            "--options",
            "runtime",
            "--entitlements",
            "Resources/Granipa.entitlements",
            "--timestamp",
        ):
            self.assertIn(token, app_calls[0])
        helper_calls = [c for c in calls if c[-1].endswith("GranipaBatteryHelper")]
        self.assertEqual(len(helper_calls), 1)
        self.assertIn("--identifier", helper_calls[0])


if __name__ == "__main__":
    unittest.main(verbosity=2)
