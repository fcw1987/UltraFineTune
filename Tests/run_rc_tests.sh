#!/bin/bash
# Reproducible safe RC validation. All audio content is generated in memory.
# Never installs an app, starts capture/playback, or mutates devices/preferences.
set -euo pipefail

UF_RC_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
UF_RC_RESULTS="${UF_RC_RESULTS_DIR:-$UF_RC_ROOT/Tests/results/$(date -u +%Y%m%dT%H%M%SZ)}"
UF_RC_BUILD="$(mktemp -d "${TMPDIR:-/tmp}/uf-rc-tests.XXXXXX")"
trap 'rm -rf "$UF_RC_BUILD"' EXIT
mkdir -p "$UF_RC_RESULTS"
UF_RC_FAILED=0

run_phase() {
    local phase="$1"
    shift
    printf '\nRunning %s\n' "$phase"
    if "$@" >"$UF_RC_RESULTS/$phase.log" 2>&1; then
        cat "$UF_RC_RESULTS/$phase.log"
        printf 'PASS %s\n' "$phase" | tee -a "$UF_RC_RESULTS/summary.txt"
    else
        local result=$?
        cat "$UF_RC_RESULTS/$phase.log"
        printf 'FAIL %s (exit %d)\n' "$phase" "$result" | tee -a "$UF_RC_RESULTS/summary.txt"
        UF_RC_FAILED=1
    fi
}

{
    date -u
    uname -sm
    git -C "$UF_RC_ROOT" rev-parse HEAD
    git -C "$UF_RC_ROOT" status --short
    for UF_RC_SOURCE in UFEQ.c UFRing.c UFAudioEngine.m; do
        shasum -a 256 "$UF_RC_ROOT/Sources/$UF_RC_SOURCE"
    done
    if [[ -n "${UF_RC_APP_BINARY:-}" ]]; then
        shasum -a 256 "$UF_RC_APP_BINARY"
    fi
    "${CC:-cc}" --version
    python3 --version
    if [[ "$(uname -s)" == Darwin ]]; then
        sw_vers
        xcrun --sdk macosx --show-sdk-version
    fi
} > "$UF_RC_RESULTS/environment.txt" 2>&1
: > "$UF_RC_RESULTS/summary.txt"

run_phase portable-normal env UFEQ_SANITIZE= "$UF_RC_ROOT/Tests/run_tests.sh"
run_phase portable-asan-ubsan env ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}" UFEQ_SANITIZE=address "$UF_RC_ROOT/Tests/run_tests.sh"
run_phase portable-tsan env UFEQ_SANITIZE=thread "$UF_RC_ROOT/Tests/run_tests.sh"
run_phase callbacks-normal python3 "$UF_RC_ROOT/Tests/check_callbacks.py"
run_phase callbacks-asan-ubsan python3 "$UF_RC_ROOT/Tests/check_callbacks.py" --sanitize
run_phase callbacks-tsan python3 "$UF_RC_ROOT/Tests/check_callbacks.py" --thread-sanitize

if [[ "$(uname -s)" == Darwin ]]; then
    run_phase lifecycle-normal python3 "$UF_RC_ROOT/Tests/check_lifecycle.py"
    run_phase lifecycle-asan-ubsan python3 "$UF_RC_ROOT/Tests/check_lifecycle.py" --sanitize
else
    printf 'SKIP lifecycle: macOS Foundation runtime required\n' | tee -a "$UF_RC_RESULTS/summary.txt"
fi

run_phase benchmark-build "${CC:-cc}" -std=c11 -O2 -g -Wall -Wextra -Wpedantic -Werror -fno-fast-math \
    -I"$UF_RC_ROOT/Sources" "$UF_RC_ROOT/Tests/benchmark_dsp.c" \
    "$UF_RC_ROOT/Sources/UFEQ.c" "$UF_RC_ROOT/Sources/UFRing.c" -lm -o "$UF_RC_BUILD/benchmark"
if [[ -x "$UF_RC_BUILD/benchmark" ]]; then
    run_phase benchmark "$UF_RC_BUILD/benchmark"
fi

# A caller may explicitly supply the native binary after a successful build.
# These CLI modes must remain read-only/off-state as documented by the app.
if [[ -n "${UF_RC_APP_BINARY:-}" ]]; then
    run_phase native-self-test "$UF_RC_APP_BINARY" --self-test
    run_phase native-diagnostics "$UF_RC_APP_BINARY" --diagnostics
fi
printf '\nEvidence: %s\n' "$UF_RC_RESULTS"
exit "$UF_RC_FAILED"
