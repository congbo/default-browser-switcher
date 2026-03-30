#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <installed-app-path>" >&2
  exit 1
fi

APP_PATH="$1"

if [[ ! -d "${APP_PATH}" ]]; then
  echo "App not found: ${APP_PATH}" >&2
  exit 1
fi

codesign --verify --deep --strict --verbose=2 "${APP_PATH}"
spctl -a -vv --type execute "${APP_PATH}"
open -na "${APP_PATH}"
sleep 3

if ! pgrep -x DefaultBrowserSwitcher >/dev/null; then
  echo "DefaultBrowserSwitcher did not appear to launch." >&2
  exit 1
fi

cat <<'EOF'
Installed app verification passed.

Next manual checks:
1. Open the installed menu bar app outside Xcode.
2. Confirm the browser list loads and one browser switch updates the system default browser.
3. Confirm Refresh works and the browser list stays usable afterward.
4. If you can reproduce a failed or stale switch state, confirm Retry becomes available and helps recover.
EOF
