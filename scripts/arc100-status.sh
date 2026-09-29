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
UNIT="$HOME/.config/systemd/user/arc100-hmi.service"
if [[ -L "$UNIT" ]]; then unit_desc="mask 됨 ($(readlink "$UNIT"))"
elif [[ ! -e "$UNIT" ]]; then unit_desc="없음"
elif [[ ! -s "$UNIT" ]]; then unit_desc="0바이트 (비어 있음 → systemd 가 masked 로 취급)"
else unit_desc="정상 ($(stat -c %s "$UNIT") bytes)"; fi
echo "유닛 파일   : $UNIT — $unit_desc"
if systemctl --user show arc100-hmi.service -p LoadState --value >/dev/null 2>&1; then
  echo "자동 시작   : $(systemctl --user is-enabled arc100-hmi.service 2>&1 | head -n 1) / 현재: $(systemctl --user is-active arc100-hmi.service 2>&1 | head -n 1)"
  systemctl --user status arc100-hmi.service --no-pager 2>/dev/null | head -n 5
  systemctl --user list-timers arc100-healthcheck.timer --no-pager 2>/dev/null | head -n 3 || true
else
  echo "(사용자 systemd 에 연결 불가 — 앱 사용자로 로그인한 터미널에서 실행하세요)"
fi
case "$unit_desc" in 정상*) ;; *) echo "→ 복구: sudo arc100-guard   (또는 cd ~/ARC-100-HMI-Public && git pull && sudo ./install.sh)";; esac
echo "보호 서비스 : $(systemctl is-enabled arc100-guard.service 2>&1 | head -n 1)"
[[ -f "$APP_ROOT/health/hang_restarts.log" ]] && echo "하트비트 재시작: $(wc -l < "$APP_ROOT/health/hang_restarts.log")회 (마지막 $(tail -n 1 "$APP_ROOT/health/hang_restarts.log"))"
echo
echo "--- 회선 포트 (site.json → 지금 실제 장치) ---"
# ttyUSB 번호는 재부팅마다 바뀐다 → 앱 v0.1.36+ 는 /dev/serial/by-id(칩 시리얼) 고유 경로를 저장한다.
if command -v jq >/dev/null && [[ -f /etc/arc100/site.json ]]; then
  while IFS=$'\t' read -r bus port; do
    real="$(readlink -f "$port" 2>/dev/null)"
    if [[ "$port" == sim://* ]]; then note="시뮬"
    elif [[ ! -e "$port" ]]; then note="없음 ✗"
    elif [[ "$port" =~ ^/dev/tty(USB|ACM)[0-9]+$ ]]; then note="번호 경로 ⚠ 재부팅 시 바뀔 수 있음 (앱 재시작 시 고유 경로로 자동 고정)"
    else note="→ $real"; fi
    printf '  %-9s %s  %s\n' "$bus" "$port" "$note"
  done < <(jq -r '.buses | to_entries[] | "\(.key)\t\(.value.port)"' /etc/arc100/site.json)
fi
ls -l /dev/rs485-* /dev/rs232-* 2>/dev/null
echo "  고유 경로: $(ls /dev/serial/by-id 2>/dev/null | tr '\n' ' ')"
echo
echo "--- 디스플레이 ---"
echo "WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-} DISPLAY=${DISPLAY:-} XDG_SESSION_TYPE=${XDG_SESSION_TYPE:-}"
