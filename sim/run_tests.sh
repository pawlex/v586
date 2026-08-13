#!/bin/sh
# Test runner for the v586 testbench ROM suite.
#
# Usage:  ./run_tests.sh [name ...]        (no args = run everything)
# Normally invoked as `make test` / `make test TEST=<name>` from sim/.
#
# Each test is a single self-describing rom/tests/<name>.asm: the program
# and the expectations about it live in one file, so there is no separate
# manifest to keep in sync. Directives are read from the leading comment
# block:
#
#   CLASS:          fetch | retire   (see below -- this distinction matters)
#   DESC:           one-line description
#   CYCLES:         how long to run
#   XFAIL:          yes  -> this test is expected to fail today
#   EXPECT-PC:      pc_out must reach this address   (repeatable)
#   EXPECT-NOT-PC:  pc_out must never reach it       (repeatable)
#   EXPECT-IO:      exact count of IO writes to the watched port
#   EXPECT-RAM:     exact count of RAM writes
#   EXPECT-WRITEIO: exact count of writeio_req pulses
#
# CLASS is documentation, not behaviour, but it is the most important
# field in the file. `fetch` tests assert where the fetch/PC pointer
# goes; `retire` tests assert that an instruction produced a real bus
# side effect. Those are NOT the same thing -- conflating them is the
# single most expensive mistake made in this investigation so far (see
# core_rtl/README.md). Keep the assertions in a test consistent with its
# class.
#
# Exit status: 0 if every test had its expected outcome. Non-zero on any
# unexpected FAIL *or* XPASS -- an XFAIL that starts passing means the
# retirement question just moved, which must not scroll by unnoticed.

set -u

BIN=${BIN:-./obj_dir/Vv586_tb_top}
TESTDIR=${TESTDIR:-rom/tests}

if [ ! -x "$BIN" ]; then
	echo "run_tests.sh: $BIN not built -- run 'make verilate' first" >&2
	exit 2
fi

# Pull every value of one directive out of a test's header comment block.
# Stops at the first non-comment line so directive-looking text further
# down the file can't leak in.
hdr_get() {
	awk -v key="$2" '
		/^[^;]/ && NF { exit }
		{
			line = $0
			sub(/^;[ \t]*/, "", line)
			if (match(line, "^" key ":")) {
				v = substr(line, RLENGTH + 1)
				gsub(/^[ \t]+|[ \t]+$/, "", v)
				if (v != "") print v
			}
		}
	' "$1"
}

if [ $# -gt 0 ]; then
	SELECTED=""
	for n in "$@"; do SELECTED="$SELECTED $TESTDIR/$n.asm"; done
else
	SELECTED=$(ls "$TESTDIR"/*.asm 2>/dev/null)
fi

[ -n "$SELECTED" ] || { echo "run_tests.sh: no tests found in $TESTDIR" >&2; exit 2; }

pass=0; fail=0; xfail=0; xpass=0
failed_names=""; xpassed_names=""

for asm in $SELECTED; do
	[ -f "$asm" ] || { echo "run_tests.sh: no such test: $asm" >&2; exit 2; }
	name=$(basename "$asm" .asm)
	hex="$TESTDIR/$name.hex"
	[ -f "$hex" ] || { echo "run_tests.sh: $hex missing -- run 'make -C rom'" >&2; exit 2; }

	class=$(hdr_get "$asm" CLASS);   class=${class:-fetch}
	desc=$(hdr_get "$asm" DESC)
	cycles=$(hdr_get "$asm" CYCLES); cycles=${cycles:-20000}
	xf=$(hdr_get "$asm" XFAIL)

	set -- --cycles="$cycles" --quiet
	for v in $(hdr_get "$asm" EXPECT-PC);      do set -- "$@" --expect-pc="$v";      done
	for v in $(hdr_get "$asm" EXPECT-NOT-PC);  do set -- "$@" --expect-not-pc="$v";  done
	for v in $(hdr_get "$asm" EXPECT-IO);      do set -- "$@" --expect-io="$v";      done
	for v in $(hdr_get "$asm" EXPECT-RAM);     do set -- "$@" --expect-ram="$v";     done
	for v in $(hdr_get "$asm" EXPECT-WRITEIO); do set -- "$@" --expect-writeio="$v"; done

	# Only --cycles and --quiet were added: the test asserts nothing, and
	# sim_main would exit 0 for it unconditionally. Treat that as a broken
	# test rather than letting a vacuous PASS into the summary.
	if [ $# -le 2 ]; then
		printf '%-6s %-22s [%s] %s\n' ERROR "$name" "$class" \
			"no EXPECT-* directives -- test asserts nothing"
		fail=$((fail + 1)); failed_names="$failed_names $name"
		continue
	fi

	out=$("$BIN" +rom="$hex" "$@" 2>&1); rc=$?

	case "$xf:$rc" in
		yes:0) status=XPASS; xpass=$((xpass+1)); xpassed_names="$xpassed_names $name" ;;
		yes:*) status=XFAIL; xfail=$((xfail+1)) ;;
		*:0)   status=PASS;  pass=$((pass+1)) ;;
		*)     status=FAIL;  fail=$((fail+1)); failed_names="$failed_names $name" ;;
	esac

	printf '%-6s %-22s [%s] %s\n' "$status" "$name" "$class" "$desc"

	# Show the per-assertion detail for anything that didn't go as
	# expected, so a failure is actionable without a re-run.
	if [ "$status" = FAIL ] || [ "$status" = XPASS ]; then
		echo "$out" | sed -n '/---- expectations ----/,$p' | sed 's/^/       | /'
	fi
done

echo
echo "---- suite summary ----"
echo "passed : $pass"
echo "failed : $fail$failed_names"
echo "xfail  : $xfail  (expected failures -- known-open behaviour)"
echo "xpass  : $xpass$xpassed_names"

if [ "$xpass" -gt 0 ]; then
	echo
	echo "*** An XFAIL test PASSED:$xpassed_names"
	echo "*** Something that never worked before now does. This is the signal the"
	echo "*** retirement investigation has been waiting for -- confirm it, then"
	echo "*** drop the XFAIL directive from the test and update core_rtl/README.md."
fi

[ "$fail" -eq 0 ] && [ "$xpass" -eq 0 ]
