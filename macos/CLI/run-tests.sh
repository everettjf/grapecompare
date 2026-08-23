#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

TMP_ROOT="$(mktemp -d -t grapecompare-cli-tests)"
trap 'rm -rf "$TMP_ROOT"' EXIT
BIN="$TMP_ROOT/grapecompare"
bash build.sh "$BIN"

printf 'one\ntwo\nthree\n' > "$TMP_ROOT/base.txt"
printf 'ONE\ntwo\nthree\n' > "$TMP_ROOT/ours.txt"
printf 'one\ntwo\nTHREE\n' > "$TMP_ROOT/theirs.txt"

if "$BIN" diff "$TMP_ROOT/base.txt" "$TMP_ROOT/base.txt" | grep -q '^identical$'; then
    echo 'PASS: CLI diff returns identical'
else
    echo 'FAIL: CLI diff returns identical'
    exit 1
fi

set +e
PATCH_OUTPUT="$($BIN diff "$TMP_ROOT/base.txt" "$TMP_ROOT/ours.txt" --patch)"
DIFF_STATUS=$?
set -e
if [[ $DIFF_STATUS -eq 1 && "$PATCH_OUTPUT" == *'@@ '* && "$PATCH_OUTPUT" == *'+ONE'* ]]; then
    echo 'PASS: CLI diff emits patch and difference status'
else
    echo 'FAIL: CLI diff emits patch and difference status'
    exit 1
fi

set +e
DIFF_JSON="$($BIN diff "$TMP_ROOT/base.txt" "$TMP_ROOT/ours.txt" --format json)"
DIFF_JSON_STATUS=$?
set -e
if [[ $DIFF_JSON_STATUS -eq 1 ]] && ruby -rjson -e '
  value = JSON.parse(ARGV.fetch(0))
  abort unless value["command"] == "diff" && value["identical"] == false && value["hunkCount"] == 1
' "$DIFF_JSON"; then
    echo 'PASS: CLI diff emits stable machine-readable JSON'
else
    echo 'FAIL: CLI diff emits stable machine-readable JSON'
    exit 1
fi

printf '%s\n' "$PATCH_OUTPUT" \
    | sed -e 's@a/base.txt@a/apply.txt@g' -e 's@b/ours.txt@b/apply.txt@g' \
    > "$TMP_ROOT/apply.patch"
cp "$TMP_ROOT/base.txt" "$TMP_ROOT/apply.txt"
git -C "$TMP_ROOT" apply --check "$TMP_ROOT/apply.patch"
patch -s "$TMP_ROOT/apply.txt" < "$TMP_ROOT/apply.patch"
if cmp -s "$TMP_ROOT/apply.txt" "$TMP_ROOT/ours.txt"; then
    echo 'PASS: exported patch is accepted by git apply and reconstructs the target'
else
    echo 'FAIL: exported patch is accepted by git apply and reconstructs the target'
    exit 1
fi

"$BIN" merge "$TMP_ROOT/base.txt" "$TMP_ROOT/ours.txt" "$TMP_ROOT/theirs.txt" "$TMP_ROOT/merged.txt"
if [[ "$(cat "$TMP_ROOT/merged.txt")" == $'ONE\ntwo\nTHREE' ]]; then
    echo 'PASS: CLI merge writes independent changes'
else
    echo 'FAIL: CLI merge writes independent changes'
    exit 1
fi
MERGE_JSON="$($BIN merge "$TMP_ROOT/base.txt" "$TMP_ROOT/ours.txt" "$TMP_ROOT/theirs.txt" "$TMP_ROOT/merged-json.txt" --format json)"
if ruby -rjson -e '
  value = JSON.parse(ARGV.fetch(0))
  abort unless value["command"] == "merge" && value["resolved"] == true && value["conflictCount"] == 0
' "$MERGE_JSON"; then
    echo 'PASS: CLI merge emits stable machine-readable JSON'
else
    echo 'FAIL: CLI merge emits stable machine-readable JSON'
    exit 1
fi

printf 'one\nOURS\nthree\n' > "$TMP_ROOT/conflict-ours.txt"
printf 'one\nTHEIRS\nthree\n' > "$TMP_ROOT/conflict-theirs.txt"
set +e
"$BIN" merge "$TMP_ROOT/base.txt" "$TMP_ROOT/conflict-ours.txt" \
    "$TMP_ROOT/conflict-theirs.txt" "$TMP_ROOT/conflicted.txt" >/dev/null
MERGE_STATUS=$?
set -e
if [[ $MERGE_STATUS -eq 1 ]] && grep -q '^<<<<<<< ours$' "$TMP_ROOT/conflicted.txt"; then
    echo 'PASS: CLI merge writes conflict markers and conflict status'
else
    echo 'FAIL: CLI merge writes conflict markers and conflict status'
    exit 1
fi

printf '{"a":1,"b":2}' > "$TMP_ROOT/left.json"
printf '{"b":2,"a":1}' > "$TMP_ROOT/right.json"
STRUCTURED_OUTPUT="$($BIN structured json "$TMP_ROOT/left.json" "$TMP_ROOT/right.json")"
if [[ -z "$STRUCTURED_OUTPUT" ]]; then
    echo 'PASS: CLI structured comparison ignores JSON key order'
else
    echo 'FAIL: CLI structured comparison ignores JSON key order'
    exit 1
fi
STRUCTURED_JSON="$($BIN structured json "$TMP_ROOT/left.json" "$TMP_ROOT/right.json" --format json)"
if ruby -rjson -e '
  value = JSON.parse(ARGV.fetch(0))
  abort unless value["command"] == "structured" && value["identical"] == true && value["differences"] == []
' "$STRUCTURED_JSON"; then
    echo 'PASS: CLI structured comparison emits stable machine-readable JSON'
else
    echo 'FAIL: CLI structured comparison emits stable machine-readable JSON'
    exit 1
fi

printf '<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>a</key><integer>1</integer></dict></plist>' > "$TMP_ROOT/left.plist"
cp "$TMP_ROOT/left.plist" "$TMP_ROOT/right.plist"
if [[ -z "$("$BIN" structured plist "$TMP_ROOT/left.plist" "$TMP_ROOT/right.plist")" ]]; then
    echo 'PASS: CLI compares property lists semantically'
else
    echo 'FAIL: CLI compares property lists semantically'
    exit 1
fi

mkdir "$TMP_ROOT/repo"
git -C "$TMP_ROOT/repo" init -b main >/dev/null
git -C "$TMP_ROOT/repo" config user.email tests@grapecompare.local
git -C "$TMP_ROOT/repo" config user.name 'GrapeCompare Tests'
printf 'base\n' > "$TMP_ROOT/repo/file.txt"
git -C "$TMP_ROOT/repo" add file.txt
git -C "$TMP_ROOT/repo" commit -m base >/dev/null
printf 'working\n' > "$TMP_ROOT/repo/file.txt"
set +e
GIT_OUTPUT="$($BIN git "$TMP_ROOT/repo" HEAD WORKTREE)"
GIT_STATUS=$?
set -e
if [[ $GIT_STATUS -eq 1 && "$GIT_OUTPUT" == $'modified\tfile.txt' ]]; then
    echo 'PASS: CLI Git comparison reports working-tree changes'
else
    echo 'FAIL: CLI Git comparison reports working-tree changes'
    exit 1
fi

set +e
GIT_JSON="$($BIN git "$TMP_ROOT/repo" HEAD WORKTREE --format json)"
GIT_JSON_STATUS=$?
set -e
if [[ $GIT_JSON_STATUS -eq 1 ]] && ruby -rjson -e '
  value = JSON.parse(ARGV.fetch(0))
  change = value.fetch("changes").fetch(0)
  abort unless value["command"] == "git" && change["kind"] == "modified" && change["path"] == "file.txt"
' "$GIT_JSON"; then
    echo 'PASS: CLI Git comparison emits stable machine-readable JSON'
else
    echo 'FAIL: CLI Git comparison emits stable machine-readable JSON'
    exit 1
fi

GIT_CONFIG_OUTPUT="$("$BIN" git-config)"
if [[ "$GIT_CONFIG_OUTPUT" == *'test $code -le 1'* ]] && \
   [[ "$GIT_CONFIG_OUTPUT" == *'open -W -n -a GrapeCompare --args --merge'* ]] && \
   [[ "$GIT_CONFIG_OUTPUT" == *'test -f "$sentinel"'* ]] && \
   [[ "$GIT_CONFIG_OUTPUT" == *'trustExitCode = true'* ]]; then
    echo 'PASS: CLI emits Git difftool and mergetool configuration'
else
    echo 'FAIL: CLI emits Git difftool and mergetool configuration'
    exit 1
fi
printf '%s\n' "$GIT_CONFIG_OUTPUT" > "$TMP_ROOT/grapecompare.gitconfig"
if git -C "$TMP_ROOT/repo" -c include.path="$TMP_ROOT/grapecompare.gitconfig" \
    difftool --no-prompt HEAD -- file.txt >/dev/null; then
    echo 'PASS: emitted configuration runs as a Git difftool for differing files'
else
    echo 'FAIL: emitted configuration runs as a Git difftool for differing files'
    exit 1
fi

mkdir "$TMP_ROOT/sync-left" "$TMP_ROOT/sync-right"
printf 'left\n' > "$TMP_ROOT/sync-left/new.txt"
set +e
SYNC_OUTPUT="$($BIN folder-sync "$TMP_ROOT/sync-left" "$TMP_ROOT/sync-right" mirror --dry-run)"
SYNC_STATUS=$?
set -e
if [[ $SYNC_STATUS -eq 1 && "$SYNC_OUTPUT" == *'"dryRun" : true'* && \
      "$SYNC_OUTPUT" == *'"relativePath" : "new.txt"'* ]] && \
      [[ ! -e "$TMP_ROOT/sync-right/new.txt" ]]; then
    echo 'PASS: CLI folder sync dry-run emits a plan without mutating either root'
else
    echo 'FAIL: CLI folder sync dry-run emits a plan without mutating either root'
    exit 1
fi

echo 'ALL CLI TESTS PASSED'
