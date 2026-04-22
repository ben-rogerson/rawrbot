# Sourceable helper: run_claude <prompt_file> [<capture_file>]
#
# Wraps the `claude` CLI with a bash-native watchdog so a hung invocation
# self-recovers instead of blocking the launchd agent (which would otherwise
# sit on its PID for days and skip every scheduled fire).
#
# Output is captured to a file and replayed to stdout when claude exits or is
# killed, so partial output is always preserved in rawr.log.
#
# Configure via CLAUDE_TIMEOUT (seconds, default 7200 = 2 hours).
# Returns claude's exit code, or 124 if the watchdog killed it.

run_claude() {
  local prompt_file="$1"
  local capture_file="${2:-}"
  local timeout_sec="${CLAUDE_TIMEOUT:-7200}"
  local poll_sec=5
  local own_capture=0

  if [ -z "$capture_file" ]; then
    capture_file=$(mktemp)
    own_capture=1
  fi
  : > "$capture_file"

  local timeout_flag
  timeout_flag=$(mktemp)
  rm -f "$timeout_flag"

  claude --dangerously-skip-permissions -p "$(cat "$prompt_file")" \
    > "$capture_file" 2>&1 &
  local claude_pid=$!

  # Watchdog polls claude's liveness. When claude exits naturally, the
  # watchdog exits naturally too (no killing needed, no job-control noise).
  # If the timeout is reached while claude is still alive, it escalates TERM
  # then KILL and signals the caller via the timeout_flag file.
  (
    local elapsed=0
    while [ "$elapsed" -lt "$timeout_sec" ]; do
      kill -0 "$claude_pid" 2>/dev/null || exit 0
      sleep "$poll_sec"
      elapsed=$((elapsed + poll_sec))
    done
    kill -0 "$claude_pid" 2>/dev/null || exit 0
    touch "$timeout_flag"
    echo "claude-run: exceeded ${timeout_sec}s timeout, killing pid $claude_pid" >&2
    pkill -TERM -P "$claude_pid" 2>/dev/null
    kill -TERM "$claude_pid" 2>/dev/null
    for _ in 1 2 3 4 5; do
      kill -0 "$claude_pid" 2>/dev/null || exit 0
      sleep 2
    done
    pkill -KILL -P "$claude_pid" 2>/dev/null
    kill -KILL "$claude_pid" 2>/dev/null
  ) &
  local watchdog_pid=$!

  local rc=0
  wait "$claude_pid" 2>/dev/null || rc=$?
  wait "$watchdog_pid" 2>/dev/null || true

  cat "$capture_file"
  [ "$own_capture" = "1" ] && rm -f "$capture_file"

  if [ -f "$timeout_flag" ]; then
    rm -f "$timeout_flag"
    return 124
  fi
  return $rc
}
