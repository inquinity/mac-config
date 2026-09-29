#!/usr/bin/env bash
# Fixture test for move-claude-folder.sh against a fake HOME.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"; WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT; cd "$WORK"; mkdir fx
T="$PWD/fx"; H="$T/home"; S="$SCRIPT_DIR/move-claude-folder.sh"
export HOME=$H CLAUDE_MOVE_SKIP_RUNNING_CHECK=1
M="$H/Library/Application Support/Claude/claude-code-sessions/a/b"
mkdir -p "$H/.claude/projects" "$M" "$T/oss/proj/sub" "$T/oss/proj/.claude/worktrees/w1" "$T/oss/proj-2" "$T/dst"
git -C "$T/oss/proj" init -q
enc(){ printf '%s' "$1" | sed 's/[^A-Za-z0-9]/-/g'; }
mk(){ d="$H/.claude/projects/$(enc "$1")"; mkdir -p "$d/memory" "$d/s1"; echo "{\"cwd\":\"$1\"}" > "$d/$2.jsonl"; echo m > "$d/memory/$3.md"; }
mk "$T/oss/proj" aaa m1; mk "$T/oss/proj/sub" bbb m2; mk "$T/oss/proj/.claude/worktrees/w1" www m4; mk "$T/oss/proj-2" ccc m3
echo "{\"cwd\":\"$T/oss/proj\"}" > "$M/local_1.json"; echo "{\"cwd\":\"$T/oss/proj-2\"}" > "$M/local_2.json"
echo "{\"n\":1,\"projects\":{\"$T/oss/proj\":{\"allowedTools\":[\"A\"]},\"$T/oss/proj-2\":{}}}" > "$H/.claude.json"
echo "{\"project\":\"$T/oss/proj\"}" > "$H/.claude/history.jsonl"
tree_state(){ (cd "$H" && find . -path './claude-folder-move-backups' -prune -o -type f -print | sed 's|.*fx-||' | sort); }
tree_state > "$T/state0"; jq -S . "$H/.claude.json" > "$T/cj0"
fail=0
step(){ echo "== $1"; shift; "$S" --apply "$@" 2>&1 | grep -E "FAIL|Done|Error" | sed "s|$T|T|g" | cut -c1-140; }
step "hop 1: oss/proj -> dst/proj" "$T/oss/proj" "$T/dst/proj"
echo "projects after hop 1:"; ls "$H/.claude/projects" | sed 's/.*scratchpad-fx-//' | tr '\n' ' '; echo
echo "worktree dir:"; ls "$T/dst/proj/.claude/worktrees"; (cd "$T/dst/proj" && git worktree list | wc -l)
step "hop 2 (transcript cwd is stale): dst/proj -> dst/moved" "$T/dst/proj" "$T/dst/moved"
echo "projects after hop 2:"; ls "$H/.claude/projects" | sed 's/.*scratchpad-fx-//' | tr '\n' ' '; echo
step "rollback: dst/moved -> oss/proj" "$T/dst/moved" "$T/oss/proj"
tree_state | diff - "$T/state0" >/dev/null && echo "IDENTICAL file tree" || { echo "TREE DIFFERS"; fail=1; }
jq -S . "$H/.claude.json" | diff - "$T/cj0" >/dev/null && echo "IDENTICAL .claude.json" || { echo "CLAUDE.JSON DIFFERS"; fail=1; }
grep -q "$T/oss/proj\"" "$H/.claude/history.jsonl" && grep -q "$T/oss/proj\"" "$M/local_1.json" && grep -q "proj-2" "$M/local_2.json" && echo "metadata/history restored, proj-2 untouched"
echo "== backup management"
"$S" --list-backups | sed "s|$T|T|" | cut -f1,2
"$S" --remove-backup ../x; echo "traversal rc=$?"
"$S" --apply --remove-backup "$("$S" --list-backups | head -1 | cut -f1)"; "$S" --list-backups | wc -l
exit $fail
