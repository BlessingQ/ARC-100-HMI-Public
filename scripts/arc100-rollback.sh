#!/usr/bin/env bash
# 직전 버전(/opt/arc100/previous)으로 되돌리고 앱을 재시작한다.
set -euo pipefail
APP_ROOT=/opt/arc100
[[ -f "$APP_ROOT/previous" ]] || { echo "[rollback] 이전 버전 기록이 없습니다" >&2; exit 1; }
PREV="$(cat "$APP_ROOT/previous")"
[[ -x "$APP_ROOT/releases/$PREV/arc100_hmi" ]] || { echo "[rollback] 이전 버전이 없습니다: $PREV" >&2; exit 1; }
CUR="$(basename "$(readlink -f "$APP_ROOT/current")")"
ln -sfn "$APP_ROOT/releases/$PREV" "$APP_ROOT/current.tmp"
mv -Tf "$APP_ROOT/current.tmp" "$APP_ROOT/current"
echo "$CUR" > "$APP_ROOT/previous"
rm -f "$APP_ROOT/health/boot_ok" "$APP_ROOT/health/fail_count"
echo "[rollback] current -> $PREV (되돌리기 전: $CUR)"
date -Is >> "$APP_ROOT/health/rollback.log"
if systemctl --user is-enabled arc100-hmi.service >/dev/null 2>&1; then
  systemctl --user restart arc100-hmi.service
fi
