#!/bin/sh
# Backup = commit + push to GitHub (github.com/0x6432/zbe).
# Token is read from /data/.gh_token (never committed, never stored in .git/config).
set -e
cd /data/qbe-zig
H=HANDOFF.md
if [ $(( $(date +%s) - $(stat -c %Y $H) )) -gt 1200 ]; then
  echo "REFUSING: $H older than 20 min; update it first" >&2; exit 1; fi
N=$(( $(git log --oneline | grep -c 'wip: periodic backup') + 1 ))
TS=$(date -u +%Y%m%d-%H%M%S)
sed -i "s/^Updated: .*/Updated: $TS UTC (backup $N)/" $H
cp $H /data/HANDOFF.md
cp /data/backup.sh tools/backup.sh
git add -A
git commit -qm "wip: periodic backup $N $TS" || true
TOK=$(cat /data/.gh_token)
git push -q "https://0x6432:$TOK@github.com/0x6432/zbe.git" HEAD:main --tags 2>&1 | sed "s/$TOK/***/g"
git push -q "https://0x6432:$TOK@github.com/0x6432/zbe.git" HEAD:main 2>&1 | sed "s/$TOK/***/g"
echo "pushed backup $N $TS -> github.com/0x6432/zbe ($(git rev-parse --short HEAD))"
