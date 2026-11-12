#!/usr/bin/env bash
#
# mayhem/test.sh — freeciv known-answer oracle: drives the normal-flags freeciv-server and freeciv-ruleup
# (built by mayhem/build.sh) on known rulesets/scenarios and asserts the values they print and write.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${MAYHEM_JOBS:=$(nproc)}"   # build parallelism; env-overridable, falls back to nproc (use -j"$MAYHEM_JOBS")
cd "$SRC"

# emit_ctrf <tool> <passed> <failed> [skipped] [pending] [other]
# Writes a CTRF report (file + stdout `CTRF {...}` marker) and returns non-zero iff failed>0.
emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}


TST="$SRC/mayhem/build/test"
SERVER="$TST/freeciv-server"
RULEUP="$TST/freeciv-ruleup"
export FREECIV_DATA_PATH="$SRC/data"
for b in "$SERVER" "$RULEUP"; do
  [ -x "$b" ] || { echo "missing $b — mayhem/build.sh should have built it" >&2; exit 2; }
done

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cd "$WORK"

PASSED=0
FAILED=0
# expect <name> <file> <fixed string that must appear on one line of the file>
expect() {
  if grep -qxF -- "$3" "$2"; then
    PASSED=$((PASSED + 1)); echo "PASS $1"
  else
    FAILED=$((FAILED + 1)); echo "FAIL $1: expected line [$3] in $2" >&2
  fi
}
# expect_re <name> <file> <extended regex>
expect_re() {
  if grep -qE -- "$3" "$2"; then
    PASSED=$((PASSED + 1)); echo "PASS $1"
  else
    FAILED=$((FAILED + 1)); echo "FAIL $1: expected /$3/ in $2" >&2
  fi
}
# unit_field <ruleset-file> <unit name> <key>: value of <key> in the section whose name=_("<unit name>")
section_field() {
  awk -v want="name=_(\"$2\")" -v key="$3" '
    /^\[/ { insec = 0 }
    $0 == want { insec = 1; next }
    insec && index($0, key "=") == 1 { print substr($0, length(key) + 2); exit }' "$1"
}
expect_val() { # <name> <got> <want>
  if [ "$2" = "$3" ]; then
    PASSED=$((PASSED + 1)); echo "PASS $1"
  else
    FAILED=$((FAILED + 1)); echo "FAIL $1: got [$2] want [$3]" >&2
  fi
}

# 1) ruleup parses the classic ruleset and writes it back from its in-memory model.
timeout 300 "$RULEUP" -r classic -o "$WORK/ru" > ruleup.log 2>&1
expect_re "ruleup reports the save"    ruleup.log '^3: Saved '
expect_val "classic Warriors build_cost" "$(section_field ru/units.ruleset Warriors build_cost)" 10
expect_val "classic Warriors attack"     "$(section_field ru/units.ruleset Warriors attack)" 1
expect_val "classic Warriors defense"    "$(section_field ru/units.ruleset Warriors defense)" 1
expect_val "classic Warriors hitpoints"  "$(section_field ru/units.ruleset Warriors hitpoints)" 10
expect_val "classic Warriors obsolete_by" "$(section_field ru/units.ruleset Warriors obsolete_by)" '"Pikemen"'
expect_val "classic Phalanx defense"     "$(section_field ru/units.ruleset Phalanx defense)" 2
expect_val "classic Catapult attack"     "$(section_field ru/units.ruleset Catapult attack)" 6
expect "classic terrain Grassland"      ru/terrain.ruleset 'name=_("Grassland")'
expect "classic tech Bronze Working"    ru/techs.ruleset   'name=_("Bronze Working")'
expect "classic building Barracks"      ru/buildings.ruleset 'name=_("Barracks")'

# 2) The server loads the tutorial scenario and answers `list players`, then saves it back out.
mkdir saves
printf 'set compresstype plain\nlist players\nsave kat\nquit\n' > kat.serv
timeout 300 "$SERVER" -f "$SRC/data/scenarios/tutorial.sav" -r kat.serv -s "$WORK/saves" \
  -p $((20000 + $$ % 20000)) -A none < /dev/null > server.log 2>&1
expect "server runs the scenario script" server.log 'Loading tutorial events.'
expect "server lists first player"       server.log 'AI*1 [#ff0000]: Team 1, user Unassigned'
expect "server lists second player"      server.log 'AI*2 [#ffff00]: Team 2, user Unassigned'
expect "server player ai level"          server.log '  AI, classic, difficulty level Easy'
expect "server says goodbye"             server.log 'Goodbye.'
expect "saved game rulesetdir"           saves/kat.sav 'rulesetdir="civ2civ3"'
expect "saved game year"                 saves/kat.sav 'year=-4000'
expect "saved game compresstype setting" saves/kat.sav '"compresstype","PLAIN","ZSTD","Internal"'
expect "saved game aifill setting"       saves/kat.sav '"aifill",2,2,"Changed"'
expect "saved game topology setting"     saves/kat.sav '"topology","ISO|HEX","ISO|HEX","Changed"'
expect "saved game server state"         saves/kat.sav 'server_state="S_S_INITIAL"'

# 3) The saved game loads again and lists the same players.
printf 'list players\nquit\n' > again.serv
timeout 300 "$SERVER" -f "$WORK/saves/kat.sav" -r again.serv -s "$WORK/saves" \
  -p $((20000 + $$ % 20000)) -A none < /dev/null > again.log 2>&1
expect "reloaded save lists first player"  again.log 'AI*1 [#ff0000]: Team 1, user Unassigned'
expect "reloaded save lists second player" again.log 'AI*2 [#ffff00]: Team 2, user Unassigned'

emit_ctrf "freeciv-kat" "$PASSED" "$FAILED" 0
