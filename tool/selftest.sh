#!/bin/sh
# Runs the plugin's own tests against the example app.
#   sh tool/selftest.sh              unit and widget tests
#   sh tool/selftest.sh <device>     the same, then a live session on <device>
set -e
cd "$(dirname "$0")/../example"
pilot() { dart ../skills/driving-flutter-apps/scripts/pilot.dart "$@"; }

flutter pub get
flutter test --exclude-tags golden

[ -n "$1" ] || exit 0

trap 'pilot stop' EXIT
pilot start -d "$1" --timeout 900
QA_DEMO_PASSWORD=secret pilot run pilot/checkout.flow
# This flow makes the app throw, so pilot must report it as failed.
if pilot run pilot/app_error.flow; then
  echo "app_error.flow passed, but it has to fail" >&2
  exit 1
fi
pilot stop
trap - EXIT
flutter test integration_test -d "$1" --dart-define=QA_DEMO_PASSWORD=secret
echo "Live self-test passed on $1."
