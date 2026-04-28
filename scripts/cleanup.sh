#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$SCRIPT_DIR/.."
[ -f "$REPO/.env" ] && source "$REPO/.env"
WORKDIR="${WORKDIR:-$REPO}"

echo "cleanup: starting ($(date '+%Y-%m-%d %H:%M'))"

python3 - "$WORKDIR" <<'PYEOF'
import os, sys, glob, datetime, json

repo = sys.argv[1]

def trim_file(path, keep_lines):
    if not os.path.exists(path):
        return
    with open(path) as f:
        lines = f.readlines()
    if len(lines) <= keep_lines:
        print(f"cleanup: {os.path.basename(path)} - {len(lines)} lines, no trim needed")
        return
    removed = len(lines) - keep_lines
    with open(path + '.tmp', 'w') as f:
        f.writelines(lines[-keep_lines:])
    os.replace(path + '.tmp', path)
    print(f"cleanup: {os.path.basename(path)} - trimmed {removed} lines, kept {keep_lines}")

def delete_old(pattern, days, label):
    cutoff = datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(days=days)
    paths = glob.glob(pattern)
    deleted = 0
    for path in paths:
        mtime = datetime.datetime.fromtimestamp(os.path.getmtime(path), tz=datetime.timezone.utc)
        if mtime < cutoff:
            os.remove(path)
            deleted += 1
    print(f"cleanup: {label} - deleted {deleted} of {len(paths)} files older than {days}d")

trim_file(os.path.join(repo, 'rawr-events.log'), 500)
trim_file(os.path.join(repo, 'memory', 'progress.txt'), 200)

delete_old(os.path.join(repo, 'memory', '????-??-??.md'), 14, 'daily memory files')
delete_old(os.path.join(repo, 'plans', 'approved', '*.md'), 30, 'approved plans')
delete_old(os.path.join(repo, 'plans', 'cancelled', '*.md'), 30, 'cancelled plans')
delete_old(os.path.join(repo, 'logs', '*.jsonl'), 14, 'agent run logs')
delete_old(os.path.join(repo, 'logs', '*.prompt.txt'), 14, 'agent run prompts')

# Log completion event
entry = {
    'ts': datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'),
    'agent': 'cleanup',
    'event': 'success',
    'detail': 'log rotation complete'
}
events_path = os.path.join(repo, 'rawr-events.log')
with open(events_path, 'a') as f:
    f.write(json.dumps(entry) + '\n')
PYEOF

echo "cleanup: done"
