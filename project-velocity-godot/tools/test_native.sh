#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
engine="${GODOT_BIN:-godot}"
"$engine" --headless --editor --path . --import

test_home="$(mktemp -d)"
trap 'rm -rf -- "$test_home"' EXIT
for suite in world_test population_test powers_test progress_rewind_test combat_integration hud_spec traversal_test campaign_flow_test neon4_regression_test sol62_controls_test sol62_animation_test midnight_test; do
  mkdir -p "$test_home/$suite"
  XDG_DATA_HOME="$test_home/$suite" "$engine" --headless --path . --fixed-fps 60 --script "res://tests/$suite.gd"
done
