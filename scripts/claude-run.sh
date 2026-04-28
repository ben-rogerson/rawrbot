# Sourceable helper: run_claude <prompt_file> <log_file>
#
# Wraps the `claude` CLI in stream-json mode with a bash-native watchdog so a
# hung invocation self-recovers instead of blocking the launchd agent.
#
# Output is written as JSONL to <log_file>. The prompt is copied to
# <log_file%.jsonl>.prompt.txt for full reproducibility.
#
# Configure via CLAUDE_TIMEOUT (seconds, default 7200 = 2 hours).
# Returns claude's exit code, or 124 if the watchdog killed it.

run_claude() {
  local prompt_file="$1"
  local log_file="$2"
  local timeout_sec="${CLAUDE_TIMEOUT:-7200}"
  local poll_sec=5

  if [ -z "$log_file" ]; then
    echo "run_claude: log_file argument is required" >&2
    return 2
  fi
  mkdir -p "$(dirname "$log_file")"
  : > "$log_file"
  cp "$prompt_file" "${log_file%.jsonl}.prompt.txt"

  local timeout_flag
  timeout_flag=$(mktemp)
  rm -f "$timeout_flag"

  claude --dangerously-skip-permissions \
    --output-format stream-json --verbose --include-partial-messages \
    -p "$(cat "$prompt_file")" \
    > "$log_file" 2>&1 &
  local claude_pid=$!

  # Watchdog polls claude's liveness. When claude exits naturally, the
  # watchdog exits naturally too. If the timeout is reached while claude is
  # still alive, escalate TERM then KILL and signal the caller via timeout_flag.
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

  if [ -f "$timeout_flag" ]; then
    rm -f "$timeout_flag"
    return 124
  fi
  return $rc
}
