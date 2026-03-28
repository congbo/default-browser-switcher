#!/usr/bin/env bash
set -euo pipefail

PROJECT="DefaultBrowserSwitcher.xcodeproj"
SCHEME="DefaultBrowserSwitcher"
DERIVED_DATA="${DERIVED_DATA:-.build/verify-s01}"
APP_BINARY="$DERIVED_DATA/Build/Products/Debug/DefaultBrowserSwitcher.app/Contents/MacOS/DefaultBrowserSwitcher"
PROBE_JSON="$DERIVED_DATA/browser-discovery-probe.json"
APP_JSON="$DERIVED_DATA/browser-discovery-app.json"
FAILURE_JSON="$DERIVED_DATA/browser-discovery-failure.json"
APP_LOG="$DERIVED_DATA/browser-discovery-app.log"

mkdir -p "$DERIVED_DATA"
rm -f "$PROBE_JSON" "$APP_JSON" "$FAILURE_JSON" "$APP_LOG"

cleanup() {
  if [[ -n "${APP_PID:-}" ]]; then
    kill "$APP_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT

echo "==> Running BrowserDiscovery test suite"
xcodebuild test \
  -quiet \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA"

echo "==> Capturing live system discovery probe"
swift Scripts/browser-discovery-probe.swift > "$PROBE_JSON"
python3 - "$PROBE_JSON" <<'PY'
import json, sys
with open(sys.argv[1]) as handle:
    json.load(handle)
PY

echo "==> Building app bundle for launch verification"
xcodebuild build \
  -quiet \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA"

if [[ ! -x "$APP_BINARY" ]]; then
  echo "Expected app binary at $APP_BINARY" >&2
  exit 1
fi

echo "==> Launching app and exporting discovery report"
DEFAULT_BROWSER_SWITCHER_SNAPSHOT_PATH="$APP_JSON" \
DEFAULT_BROWSER_SWITCHER_EXIT_AFTER_SNAPSHOT=1 \
"$APP_BINARY" > "$APP_LOG" 2>&1 &
APP_PID=$!

for _ in {1..50}; do
  if [[ -f "$APP_JSON" ]]; then
    break
  fi
  if ! kill -0 "$APP_PID" 2>/dev/null; then
    break
  fi
  sleep 0.2
done
wait "$APP_PID" || true
unset APP_PID

if [[ ! -f "$APP_JSON" ]]; then
  echo "The app did not export a discovery report. Log follows:" >&2
  cat "$APP_LOG" >&2
  exit 1
fi

python3 - "$PROBE_JSON" "$APP_JSON" <<'PY'
import json, sys
probe_path, app_path = sys.argv[1:3]
with open(probe_path) as handle:
    probe = json.load(handle)
with open(app_path) as handle:
    app_report = json.load(handle)

if app_report.get("phase") != "loaded":
    raise SystemExit(f"Expected loaded app phase, got {app_report.get('phase')!r}")
if app_report.get("lastErrorMessage"):
    raise SystemExit(f"Expected no app error, got {app_report.get('lastErrorMessage')!r}")

app_snapshot = app_report.get("snapshot")
if not app_snapshot:
    raise SystemExit("App report is missing its snapshot payload")

def normalize(snapshot):
    def app_key(app):
        if app is None:
            return None
        return {
            "bundleIdentifier": app.get("bundleIdentifier"),
            "displayName": app.get("displayName"),
            "applicationURL": app.get("applicationURL"),
        }

    candidates = sorted(
        (
            {
                "bundleIdentifier": candidate.get("bundleIdentifier"),
                "displayName": candidate.get("displayName"),
                "applicationURL": candidate.get("applicationURL"),
                "supportedSchemes": sorted(candidate.get("supportedSchemes", [])),
            }
            for candidate in snapshot.get("candidates", [])
        ),
        key=lambda candidate: (
            candidate.get("displayName") or "",
            candidate.get("bundleIdentifier") or candidate.get("applicationURL") or "",
        ),
    )
    return {
        "currentHTTPHandler": app_key(snapshot.get("currentHTTPHandler")),
        "currentHTTPSHandler": app_key(snapshot.get("currentHTTPSHandler")),
        "candidates": candidates,
    }

if normalize(probe) != normalize(app_snapshot):
    raise SystemExit("App discovery report does not match the standalone system probe")
PY

echo "==> Verifying failure-state observability"
DEFAULT_BROWSER_SWITCHER_FORCE_DISCOVERY_ERROR="verify forced discovery failure" \
DEFAULT_BROWSER_SWITCHER_SNAPSHOT_PATH="$FAILURE_JSON" \
DEFAULT_BROWSER_SWITCHER_EXIT_AFTER_SNAPSHOT=1 \
"$APP_BINARY" > "$APP_LOG" 2>&1 &
APP_PID=$!

for _ in {1..50}; do
  if [[ -f "$FAILURE_JSON" ]]; then
    break
  fi
  if ! kill -0 "$APP_PID" 2>/dev/null; then
    break
  fi
  sleep 0.2
done
wait "$APP_PID" || true
unset APP_PID

if [[ ! -f "$FAILURE_JSON" ]]; then
  echo "The app did not export the forced-failure report. Log follows:" >&2
  cat "$APP_LOG" >&2
  exit 1
fi

python3 - "$FAILURE_JSON" <<'PY'
import json, sys
with open(sys.argv[1]) as handle:
    report = json.load(handle)
if report.get("phase") != "failed":
    raise SystemExit(f"Expected failed phase for forced error, got {report.get('phase')!r}")
error = report.get("lastErrorMessage")
if not error or "verify forced discovery failure" not in error:
    raise SystemExit(f"Expected forced failure message, got {error!r}")
PY

echo "S01 verification passed."
