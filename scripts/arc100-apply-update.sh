#!/usr/bin/env bash
# 설치된 릴리스를 활성화한다: current 링크 교체 -> 앱 재시작 -> 헬스체크 대기.
#   arc100-apply-update v1.2.0
# 기동 60초 안에 health/boot_ok 가 갱신되지 않으면 이전 버전으로 되돌린다.
set -euo pipefail
APP_ROOT=/opt/arc100
VER="${1:-}"
[[ -n "$VER" ]] || { echo "사용법: arc100-apply-update <버전>" >&2; exit 1; }
[[ "$VER" == v* ]] || VER="v$VER"
NEW="$APP_ROOT/releases/$VER"
[[ -x "$NEW/arc100_hmi" ]] || { echo "설치되지 않은 버전: $VER" >&2; exit 1; }

log() { printf '[update] %s\n' "$*"; }

CUR="$(readlink -f "$APP_ROOT/current" 2>/dev/null || true)"
if [[ -n "$CUR" && "$CUR" != "$NEW" ]]; then
  basename "$CUR" > "$APP_ROOT/previous"
fi

# 원자적 링크 교체
ln -sfn "$NEW" "$APP_ROOT/current.tmp"
mv -Tf "$APP_ROOT/current.tmp" "$APP_ROOT/current"
sync   # 전원 급차단 대비 — 링크 교체를 SD 카드에 확정
rm -f "$APP_ROOT/health/boot_ok" "$APP_ROOT/health/fail_count"
log "current -> $VER"

if systemctl --user is-enabled arc100-hmi.service >/dev/null 2>&1; then
  systemctl --user restart arc100-hmi.service
  log "앱 재시작. 헬스체크 대기(최대 90초)..."
  for _ in $(seq 1 18); do
    sleep 5
    if [[ -f "$APP_ROOT/health/boot_ok" ]]; then
      log "정상 기동 확인: $(cat "$APP_ROOT/health/boot_ok")"
      exit 0
    fi
  done
  log "헬스 마커가 없습니다. 이전 버전으로 롤백합니다."
  exec "$APP_ROOT/bin/arc100-rollback"
else
  log "서비스가 등록되어 있지 않습니다. 앱은 다음 부팅/수동 실행 시 $VER 로 시작합니다."
fi
