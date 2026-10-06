#!/bin/sh
set -eu

UF_TEST_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
UF_TEST_BUILD=$(mktemp -d "${TMPDIR:-/tmp}/ufeq-tests.XXXXXX")
trap 'rm -rf "$UF_TEST_BUILD"' EXIT HUP INT TERM
UF_TEST_CC=${CC:-cc}
UF_SANITIZER_FLAGS=

case "${UFEQ_SANITIZE:-}" in
    "") ;;
    address) UF_SANITIZER_FLAGS="-fsanitize=address,undefined -fno-omit-frame-pointer" ;;
    thread) UF_SANITIZER_FLAGS="-fsanitize=thread -fno-omit-frame-pointer" ;;
    *) echo "UFEQ_SANITIZE must be empty, address, or thread" >&2; exit 2 ;;
esac

for UF_TEST_SUITE in eq ring presets; do
    case "$UF_TEST_SUITE" in
        eq) UF_TEST_SOURCE=UFEQ ;;
        ring) UF_TEST_SOURCE=UFRing ;;
        presets) UF_TEST_SOURCE=UFEQ ;;
    esac
    # Intentional word splitting expands the fixed optional compiler flags above.
    # shellcheck disable=SC2086
    "$UF_TEST_CC" -std=c11 -Wall -Wextra -Wpedantic -Werror -O2 -g -fno-fast-math \
        $UF_SANITIZER_FLAGS \
        -I"$UF_TEST_ROOT/Sources" \
        "$UF_TEST_ROOT/Sources/$UF_TEST_SOURCE.c" \
        "$UF_TEST_ROOT/Tests/test_$UF_TEST_SUITE.c" \
        -lm -pthread -o "$UF_TEST_BUILD/test_$UF_TEST_SUITE"

    "$UF_TEST_BUILD/test_$UF_TEST_SUITE"
done
