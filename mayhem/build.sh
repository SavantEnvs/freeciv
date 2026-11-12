#!/usr/bin/env bash
#
# mayhem/build.sh — freeciv: sanitized server libraries + four fuzz harnesses (and -standalone
# reproducers), then an independent normal-flags build of freeciv-server/freeciv-ruleup for test.sh.
set -euo pipefail

[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS COVERAGE_FLAGS

cd "$SRC"

SAN="$SRC/mayhem/build/san"
TST="$SRC/mayhem/build/test"
mkdir -p "$SAN" "$TST"

# freeciv's genhash/registry callbacks go through function pointers of a different type on
# every input, which floods -fsanitize=function; that one UBSan check is relaxed, everything else halts.
SAN_C="$SANITIZER_FLAGS -fno-sanitize=function $DEBUG_FLAGS"

# Server-only build: no clients, no modpack installer, no audio/NLS; ruleup is the one tool built.
MESON_OPTS=(-Dclients= -Dfcmp= -Dtools=ruleup -Dnls=false -Daudio=none -Ddefault_library=static)

# LSan off at build time (also needed by the build-time generators the sanitized meson tree runs).
$CXX $SANITIZER_FLAGS $DEBUG_FLAGS -c mayhem/lsan_off.cc -o "$SAN/lsan_off.o"

# 1) The project itself, instrumented for ASan/UBSan and SanCov.
setup() { # <builddir> <buildtype>
  meson setup --reconfigure "$1" "$SRC" --buildtype="$2" "${MESON_OPTS[@]}"
}
CFLAGS="$SAN_C -fsanitize=fuzzer-no-link" \
LDFLAGS="$SAN/lsan_off.o $SAN_C -fsanitize=fuzzer-no-link" \
  setup "$SAN" debugoptimized
ninja -C "$SAN" -j"$MAYHEM_JOBS" libfc_server.a libfreeciv.a libfc_ai.a

# 2) Harnesses: fuzzer binary + standalone reproducer.
INC=(-I"$SAN" -I"$SRC" -I"$SRC/dependencies/lua-5.5/src" -I"$SRC/dependencies/tinycthread"
     -I"$SRC/dependencies/tolua-5.2/include" -I"$SRC/dependencies/cvercmp"
     -I"$SRC/utility" -I"$SRC/common" -I"$SRC/common/networking" -I"$SRC/common/scriptcore"
     -I"$SRC/common/aicore" -I"$SRC/server" -I"$SRC/server/advisors" -I"$SRC/server/scripting"
     -I"$SRC/server/generator" -I"$SRC/server/ruleset" -I"$SRC/server/savegame"
     -I"$SRC/ai" -I"$SRC/ai/classic")
LIBS=(-Wl,--start-group "$SAN/libfc_server.a" "$SAN/libfreeciv.a" "$SAN/libfc_ai.a"
      -lm -lreadline -lsqlite3 -lz -lcurl -licuuc -licudata -lbz2 -llzma -lzstd -Wl,--end-group -pthread)

$CC $SAN_C -c "$STANDALONE_FUZZ_MAIN" -o "$SAN/standalone_main.o"
harness() { # <binary> <source> [extra compile flags]
  local h="$1" src="$2"; shift 2
  $CC $SAN_C -DHAVE_CONFIG_H -D_FILE_OFFSET_BITS=64 "$@" "${INC[@]}" $LIB_FUZZING_ENGINE \
      "$SAN/lsan_off.o" "$SRC/mayhem/$src.c" "${LIBS[@]}" -o "/mayhem/$h"
  $CC $SAN_C -DHAVE_CONFIG_H -D_FILE_OFFSET_BITS=64 "$@" "${INC[@]}" \
      "$SAN/standalone_main.o" "$SAN/lsan_off.o" "$SRC/mayhem/$src.c" "${LIBS[@]}" -o "/mayhem/$h-standalone"
}
harness fuzz_secfile fuzz_secfile
harness fuzz_packets fuzz_packets
harness fuzz_packets_server fuzz_packets -DFUZZ_PACKETS_SERVER
harness fuzz_savegame fuzz_savegame

# 3) Test build: the project's normal flags, independent of the sanitized tree.
CFLAGS="$COVERAGE_FLAGS" LDFLAGS="$COVERAGE_FLAGS" setup "$TST" debugoptimized
ninja -C "$TST" -j"$MAYHEM_JOBS" freeciv-server freeciv-ruleup
