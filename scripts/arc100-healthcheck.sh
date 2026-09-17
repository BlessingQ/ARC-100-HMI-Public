#!/usr/bin/env bash
# 2분마다 타이머로 실행. 앱이 기동 후 60초 안에 health/boot_ok 를 쓰지 못한 채
# 재시작을 반복하면(3회) 이전 버전으로 자동 롤백한다.
set -euo pipefail
APP_ROOT=/opt/arc100
H="$APP_ROOT/health"
mkdir -p "$H"

# 서비스가 없거나 앱이 없으면 할 일 없음
systemctl --user is-active arc100-hmi.service >/dev/null 2>&1 || exit 0
[[ -e "$APP_ROOT/current/arc100_hmi" ]] || exit 0

# 정상 마커가 있고 5분 이내면 OK
if [[ -f "$H/boot_ok" ]]; then
  age=$(( $(date +%s) - $(stat -c %Y "$H/boot_ok") ))
  # 앱이 살아 있으면 마커를 주기적으로 갱신한다(앱 책임). 오래됐어도 프로세스가 살아 있으면 통과.
  echo 0 > "$H/fail_count"
  exit 0
fi

# 마커가 없다 = 기동 중이거나 기동 실패 반복
started="$(systemctl --user show arc100-hmi.service -p ExecMainStartTimestampMonotonic --value 2>/dev/null || echo 0)"
restarts="$(systemctl --user show arc100-hmi.service -p NRestarts --value 2>/dev/null || echo 0)"
if [[ "${restarts:-0}" -ge 3 ]]; then
  echo "[healthcheck] 기동 실패 반복(NRestarts=$restarts) → 롤백" | systemd-cat -t arc100-healthcheck -p warning
  "$APP_ROOT/bin/arc100-rollback" || true
  systemctl --user reset-failed arc100-hmi.service || true
fi
exit 0
