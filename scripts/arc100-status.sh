#!/usr/bin/env bash
# 설치·실행 상태 요약
set -uo pipefail
APP_ROOT=/opt/arc100
echo "=== ARC-100 HMI 상태 ==="
echo "기기        : $(tr -d '\0' < /proc/device-tree/model 2>/dev/null || uname -m)"
echo "현재 버전   : $(readlink -f "$APP_ROOT/current" 2>/dev/null | xargs -r basename || echo '(없음)')"
echo "이전 버전   : $(cat "$APP_ROOT/previous" 2>/dev/null || echo '(없음)')"
echo "설치된 버전 : $(ls "$APP_ROOT/releases" 2>/dev/null | tr '\n' ' ')"
echo "릴리스 저장소: $(grep ARC100_REPO "$APP_ROOT/repo.env" 2>/dev/null | cut -d= -f2)"
echo "설정 파일   : $( [[ -f /etc/arc100/site.json ]] && echo /etc/arc100/site.json || echo '(없음)')"
if [[ -f "$APP_ROOT/health/boot_ok" ]]; then
  echo "헬스 마커   : $(cat "$APP_ROOT/health/boot_ok") ($(stat -c %y "$APP_ROOT/health/boot_ok" | cut -d. -f1))"
else
  echo "헬스 마커   : 없음"
fi
echo
echo "--- 서비스 ---"
systemctl --user status arc100-hmi.service --no-pager 2>/dev/null | head -n 5 || echo "(사용자 세션에서 실행하세요)"
systemctl --user list-timers arc100-healthcheck.timer --no-pager 2>/dev/null | head -n 3 || true
echo
echo "--- RS-485 포트 ---"
ls -l /dev/rs485-* 2>/dev/null || echo "(/dev/rs485-* 없음 — arc100-list-serial 로 규칙 작성)"
echo
echo "--- 디스플레이 ---"
echo "WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-} DISPLAY=${DISPLAY:-} XDG_SESSION_TYPE=${XDG_SESSION_TYPE:-}"
