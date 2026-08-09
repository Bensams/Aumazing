#!/usr/bin/env bash
# Keep generating until the library is complete, surviving crashes and
# upstream outages. Safe to run unattended.
#
# Each pass skips files that already exist, so a restart resumes rather than
# redoing work. The stall guard is the important part for an overnight run:
# if a pass finishes without producing a single new file, the API is down or
# rejecting us, and looping would burn credits and hammer KIE for hours. Three
# consecutive stalls and it stops.
#
#   KIE_API_KEY=... ./run_until_done.sh
#
# Progress: tools/voice_gen/supervisor.log (per-clip lines) and the === pass
# markers on stdout.
set -u

cd "$(dirname "$0")" || exit 1

MAX_PASSES="${MAX_PASSES:-60}"
MAX_STALLS="${MAX_STALLS:-3}"
BACKOFF="${BACKOFF:-60}"
PY=./.venv/Scripts/python.exe
LOG=supervisor.log

if [ -z "${KIE_API_KEY:-}" ]; then
  echo "KIE_API_KEY is not set; refusing to start." >&2
  exit 1
fi

count() { find out/kie -name '*.wav' 2>/dev/null | wc -l | tr -d ' '; }

# Derive the target from the tool itself rather than hardcoding it: the roster
# changes, and a stale TARGET either stops early or spins until the stall guard
# trips. --dry-run costs nothing and needs no API key.
if [ -z "${TARGET:-}" ]; then
  plan=$("$PY" -u generate_kie.py --lang all --dry-run 2>/dev/null |
         grep 'To render:')
  todo=$(echo "$plan" | sed -n 's/.*To render: *\([0-9]*\).*/\1/p')
  done_already=$(echo "$plan" | sed -n 's/.*(\([0-9]*\) already present.*/\1/p')
  TARGET=$(( ${todo:-0} + ${done_already:-0} ))
fi
if [ "${TARGET:-0}" -le 0 ]; then
  echo "Could not determine a target; set TARGET=<clips> explicitly." >&2
  exit 1
fi

stalls=0
start_total=$(count)
echo "=== supervisor start: $start_total/$TARGET at $(date '+%F %T') ==="

for pass in $(seq 1 "$MAX_PASSES"); do
  before=$(count)
  if [ "$before" -ge "$TARGET" ]; then
    echo "=== COMPLETE: $before/$TARGET ==="
    exit 0
  fi

  echo "=== pass $pass starting at $before/$TARGET $(date '+%T') ==="
  "$PY" -u generate_kie.py --lang all --workers 32 --yes >>"$LOG" 2>&1
  rc=$?
  after=$(count)
  echo "=== pass $pass done: $before -> $after/$TARGET (exit $rc) $(date '+%T') ==="

  if [ "$after" -ge "$TARGET" ]; then
    echo "=== COMPLETE: $after/$TARGET ==="
    exit 0
  fi

  if [ "$after" -le "$before" ]; then
    stalls=$((stalls + 1))
    echo "=== no progress (stall $stalls/$MAX_STALLS) ==="
    if [ "$stalls" -ge "$MAX_STALLS" ]; then
      echo "=== STOPPING: $MAX_STALLS passes with no new files. Upstream is" \
           "probably down. Nothing lost -- rerun to resume. ==="
      exit 1
    fi
    # Back off harder each time rather than retrying straight into an outage.
    sleep $((BACKOFF * stalls * stalls))
  else
    stalls=0
    sleep 10
  fi
done

echo "=== gave up after $MAX_PASSES passes: $(count)/$TARGET ==="
exit 1
