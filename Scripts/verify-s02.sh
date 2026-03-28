#!/usr/bin/env bash
set -euo pipefail

PROJECT="DefaultBrowserSwitcher.xcodeproj"
SCHEME="DefaultBrowserSwitcher"
DERIVED_DATA="${DERIVED_DATA:-.build/verify-s02}"
APP_BINARY="$DERIVED_DATA/Build/Products/Debug/DefaultBrowserSwitcher.app/Contents/MacOS/DefaultBrowserSwitcher"
ORIGINAL_PROBE_JSON="$DERIVED_DATA/browser-discovery-original.json"
SWITCHED_PROBE_JSON="$DERIVED_DATA/browser-discovery-switched.json"
RESTORED_PROBE_JSON="$DERIVED_DATA/browser-discovery-restored.json"
APP_REPORT_JSON="$DERIVED_DATA/browser-discovery-switch-report.json"
SELECTION_JSON="$DERIVED_DATA/browser-discovery-selection.json"
APP_LOG="$DERIVED_DATA/browser-discovery-switch.log"
SHOULD_RESTORE=0
APP_PID=""

mkdir -p "$DERIVED_DATA"
rm -f "$ORIGINAL_PROBE_JSON" "$SWITCHED_PROBE_JSON" "$RESTORED_PROBE_JSON" "$APP_REPORT_JSON" "$SELECTION_JSON" "$APP_LOG"

print_artifacts() {
  echo "Artifacts:" >&2
  echo "  original probe: $ORIGINAL_PROBE_JSON" >&2
  echo "  switched probe: $SWITCHED_PROBE_JSON" >&2
  echo "  restored probe: $RESTORED_PROBE_JSON" >&2
  echo "  app report:     $APP_REPORT_JSON" >&2
  echo "  selection:      $SELECTION_JSON" >&2
  echo "  app log:        $APP_LOG" >&2
}

stop_app() {
  if [[ -n "$APP_PID" ]]; then
    kill "$APP_PID" 2>/dev/null || true
    wait "$APP_PID" 2>/dev/null || true
    APP_PID=""
  fi
}

set_default_handler() {
  local application_path="$1"
  local scheme="$2"

  swift - "$application_path" "$scheme" <<'SWIFT'
import AppKit
import Foundation

private final class CallbackResolver: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Error?, Never>?
    private var didResolve = false

    init(continuation: CheckedContinuation<Error?, Never>) {
        self.continuation = continuation
    }

    func resolve(_ error: Error?) {
        lock.lock()
        guard !didResolve, let continuation else {
            lock.unlock()
            return
        }

        didResolve = true
        self.continuation = nil
        lock.unlock()

        continuation.resume(returning: error)
    }
}

let applicationPath = CommandLine.arguments[1]
let scheme = CommandLine.arguments[2]
let targetURL = URL(fileURLWithPath: applicationPath).standardizedFileURL
let workspace = NSWorkspace.shared
let timeout: TimeInterval = 10
let deadline = Date().addingTimeInterval(timeout)
let sampleURL = URL(string: "\(scheme)://example.com")!

Task {
    let callbackError = await withCheckedContinuation { continuation in
        let resolver = CallbackResolver(continuation: continuation)

        workspace.setDefaultApplication(at: targetURL, toOpenURLsWithScheme: scheme) { error in
            resolver.resolve(error)
        }

        Task {
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            resolver.resolve(nil)
        }
    }

    var observedURL = workspace.urlForApplication(toOpen: sampleURL)?.standardizedFileURL
    while observedURL?.path != targetURL.path, Date() < deadline {
        try? await Task.sleep(nanoseconds: 250_000_000)
        observedURL = workspace.urlForApplication(toOpen: sampleURL)?.standardizedFileURL
    }

    if observedURL?.path == targetURL.path {
        exit(0)
    }

    if let callbackError {
        fputs("Failed restoring \(scheme) to \(applicationPath): \(callbackError.localizedDescription)\n", stderr)
    } else {
        fputs("Timed out restoring \(scheme) to \(applicationPath)\n", stderr)
    }

    if let observedURL {
        fputs("Last observed \(scheme) handler: \(observedURL.path)\n", stderr)
    }

    exit(1)
}

RunLoop.main.run()
SWIFT
}

restore_original_handlers() {
  local original_http original_https attempt restore_error=0
  original_http="$(python3 - "$SELECTION_JSON" <<'PY'
import json, sys
with open(sys.argv[1]) as handle:
    selection = json.load(handle)
print(selection["originalHTTPPath"])
PY
)"
  original_https="$(python3 - "$SELECTION_JSON" <<'PY'
import json, sys
with open(sys.argv[1]) as handle:
    selection = json.load(handle)
print(selection["originalHTTPSPath"])
PY
)"

  echo "==> Restoring original handlers"

  for attempt in 1 2 3; do
    restore_error=0

    if ! set_default_handler "$original_http" http; then
      restore_error=1
    fi

    if ! set_default_handler "$original_https" https; then
      restore_error=1
    fi

    sleep 1
    swift Scripts/browser-discovery-probe.swift > "$RESTORED_PROBE_JSON"

    if python3 - "$SELECTION_JSON" "$RESTORED_PROBE_JSON" <<'PY'
import json, sys
selection_path, probe_path = sys.argv[1:3]
with open(selection_path) as handle:
    selection = json.load(handle)
with open(probe_path) as handle:
    probe = json.load(handle)

http_path = probe.get("currentHTTPHandler", {}).get("applicationURL")
https_path = probe.get("currentHTTPSHandler", {}).get("applicationURL")
if http_path != selection["originalHTTPURL"]:
    raise SystemExit(f"HTTP restore mismatch: expected {selection['originalHTTPURL']!r}, got {http_path!r}")
if https_path != selection["originalHTTPSURL"]:
    raise SystemExit(f"HTTPS restore mismatch: expected {selection['originalHTTPSURL']!r}, got {https_path!r}")
PY
    then
      return 0
    fi

    if [[ "$attempt" -lt 3 ]]; then
      echo "Restore attempt $attempt did not settle yet. Retrying..." >&2
      sleep 2
    fi
  done

  return 1
}

cleanup() {
  local exit_code=$?
  trap - EXIT
  stop_app

  if [[ "$SHOULD_RESTORE" == "1" ]]; then
    if ! restore_original_handlers; then
      echo "Restore verification failed." >&2
      print_artifacts
      exit_code=1
    fi
  fi

  exit "$exit_code"
}
trap cleanup EXIT

echo "==> Running focused BrowserDiscovery verification tests"
xcodebuild test \
  -quiet \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA" \
  -only-testing:BrowserDiscoveryTests/AppShellSmokeTests \
  -only-testing:BrowserDiscoveryTests/BrowserDiscoveryStoreTests \
  -only-testing:BrowserDiscoveryTests/SystemBrowserDiscoveryServiceTests

echo "==> Capturing original live browser state"
swift Scripts/browser-discovery-probe.swift > "$ORIGINAL_PROBE_JSON"
python3 - "$ORIGINAL_PROBE_JSON" "$SELECTION_JSON" <<'PY'
import json, sys
from urllib.parse import unquote, urlparse
probe_path, selection_path = sys.argv[1:3]
with open(probe_path) as handle:
    probe = json.load(handle)

original_http = probe.get("currentHTTPHandler")
original_https = probe.get("currentHTTPSHandler")
if not original_http or not original_https:
    raise SystemExit("Original live state is missing an HTTP or HTTPS handler, so restore-safe verification cannot proceed.")

original_http_url = original_http.get("applicationURL")
original_https_url = original_https.get("applicationURL")
if not original_http_url or not original_https_url:
    raise SystemExit("Original live state is missing handler URLs, so restore-safe verification cannot proceed.")

candidates = probe.get("candidates", [])
eligible = [
    candidate for candidate in candidates
    if set(candidate.get("supportedSchemes", [])) == {"http", "https"}
    and candidate.get("bundleIdentifier")
    and candidate.get("applicationURL") not in {original_http_url, original_https_url}
]

if not eligible:
    raise SystemExit("No alternate dual-scheme browser candidate with a bundle identifier is available for live switch verification.")

eligible.sort(key=lambda candidate: ((candidate.get("displayName") or "").lower(), candidate.get("applicationURL") or ""))
target = eligible[0]

def file_url_to_path(value: str) -> str:
    parsed = urlparse(value)
    return unquote(parsed.path)

selection = {
    "targetDisplayName": target.get("displayName") or target.get("applicationURL"),
    "targetPath": file_url_to_path(target["applicationURL"]),
    "targetURL": target["applicationURL"],
    "originalHTTPPath": file_url_to_path(original_http_url),
    "originalHTTPSPath": file_url_to_path(original_https_url),
    "originalHTTPURL": original_http_url,
    "originalHTTPSURL": original_https_url,
}

with open(selection_path, "w") as handle:
    json.dump(selection, handle, indent=2, sort_keys=True)
PY
SHOULD_RESTORE=1
TARGET_PATH="$(python3 - "$SELECTION_JSON" <<'PY'
import json, sys
with open(sys.argv[1]) as handle:
    selection = json.load(handle)
print(selection["targetPath"])
PY
)"

echo "==> Building app bundle for live switch verification"
xcodebuild build \
  -quiet \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA"

if [[ ! -x "$APP_BINARY" ]]; then
  echo "Expected app binary at $APP_BINARY" >&2
  print_artifacts
  exit 1
fi

echo "==> Launching app to request a verified browser switch"
DEFAULT_BROWSER_SWITCHER_SNAPSHOT_PATH="$APP_REPORT_JSON" \
DEFAULT_BROWSER_SWITCHER_SWITCH_TARGET_PATH="$TARGET_PATH" \
"$APP_BINARY" > "$APP_LOG" 2>&1 &
APP_PID=$!

report_ready=0
for _ in {1..120}; do
  if [[ -f "$APP_REPORT_JSON" ]]; then
    if python3 - "$APP_REPORT_JSON" "$TARGET_PATH" <<'PY'
import json, sys
from urllib.parse import unquote, urlparse
report_path, target_path = sys.argv[1:3]
with open(report_path) as handle:
    report = json.load(handle)
result = report.get("lastSwitchResult") or {}
requested = result.get("requestedTarget") or {}
outcomes = result.get("schemeOutcomes") or []
requested_path = unquote(urlparse(requested.get("applicationURL", "")).path)
ready = (
    requested_path == target_path
    and {outcome.get("scheme") for outcome in outcomes} == {"http", "https"}
    and result.get("verifiedSnapshot") is not None
)
raise SystemExit(0 if ready else 1)
PY
    then
      report_ready=1
      break
    fi
  fi

  if ! kill -0 "$APP_PID" 2>/dev/null; then
    break
  fi

  sleep 0.25
done

if [[ "$report_ready" != "1" ]]; then
  echo "The app did not produce a completed switch report within the timeout." >&2
  tail -n 200 "$APP_LOG" >&2 || true
  print_artifacts
  exit 1
fi

stop_app

echo "==> Capturing post-switch live browser state"
swift Scripts/browser-discovery-probe.swift > "$SWITCHED_PROBE_JSON"

python3 - "$APP_REPORT_JSON" "$SWITCHED_PROBE_JSON" "$SELECTION_JSON" <<'PY'
import json, sys
report_path, probe_path, selection_path = sys.argv[1:4]
with open(report_path) as handle:
    report = json.load(handle)
with open(probe_path) as handle:
    probe = json.load(handle)
with open(selection_path) as handle:
    selection = json.load(handle)

if report.get("phase") != "loaded":
    raise SystemExit(f"Expected loaded app phase, got {report.get('phase')!r}")

result = report.get("lastSwitchResult")
if not result:
    raise SystemExit("App report is missing lastSwitchResult after the requested launch switch.")
if result.get("classification") != "success":
    raise SystemExit(f"Expected a verified success classification, got {result.get('classification')!r}")

requested = result.get("requestedTarget") or {}
if requested.get("applicationURL") != selection["targetURL"]:
    raise SystemExit(f"Requested target mismatch: expected {selection['targetURL']!r}, got {requested.get('applicationURL')!r}")

outcomes = result.get("schemeOutcomes") or []
if {outcome.get("scheme") for outcome in outcomes} != {"http", "https"}:
    raise SystemExit("Per-scheme outcomes are incomplete in the app report.")

verified_snapshot = result.get("verifiedSnapshot")
if not verified_snapshot:
    raise SystemExit("App report is missing the verified snapshot payload after switching.")

app_snapshot = report.get("snapshot")
if not app_snapshot:
    raise SystemExit("App report is missing the top-level snapshot payload.")

def normalize(snapshot):
    def normalized_app(app):
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
        "currentHTTPHandler": normalized_app(snapshot.get("currentHTTPHandler")),
        "currentHTTPSHandler": normalized_app(snapshot.get("currentHTTPSHandler")),
        "candidates": candidates,
    }

if normalize(app_snapshot) != normalize(verified_snapshot):
    raise SystemExit("Top-level snapshot does not match the verified switch snapshot.")
if normalize(verified_snapshot) != normalize(probe):
    raise SystemExit("Verified switch snapshot does not match the independent live probe after switching.")

http_target = (verified_snapshot.get("currentHTTPHandler") or {}).get("applicationURL")
https_target = (verified_snapshot.get("currentHTTPSHandler") or {}).get("applicationURL")
if http_target != selection["targetURL"] or https_target != selection["targetURL"]:
    raise SystemExit("The verified live state did not move both HTTP and HTTPS to the requested target.")
PY

echo "S02 verification passed."
