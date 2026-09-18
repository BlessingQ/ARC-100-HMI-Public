#!/usr/bin/env bash
# 자동 시작 보호 (root, 부팅마다 사용자 세션이 열리기 전에 실행 — arc100-guard.service)
#
# 현장에서 전원이 갑자기 끊기면 SD 카드(ext4)에 막 쓰인 파일이 0바이트로 남을 수 있고, systemd 는
# 비어 있는 유닛 파일을 "masked" 로 취급해 앱을 영영 띄우지 않는다. 그래서 설치 때 보관해 둔 원본
# (/opt/arc100/units/)과 사용자 유닛(~/.config/systemd/user/)을 비교해 없거나 비었거나 /dev/null 로
# 가리키면 복구하고, 자동 시작 링크(default.target.wants 등)와 linger 도 다시 잡는다.
#
#   sudo arc100-guard            # 수동 점검·복구
set -uo pipefail
APP_ROOT=/opt/arc100
[[ $EUID -eq 0 ]] || { echo "sudo로 실행하세요" >&2; exit 1; }
[[ -f "$APP_ROOT/app.env" ]] || { echo "[guard] $APP_ROOT/app.env 없음 — install.sh 를 다시 실행하세요" >&2; exit 1; }
# shellcheck disable=SC1091
source "$APP_ROOT/app.env"          # APP_USER, APP_UID, APP_HOME
UNIT_DIR="$APP_HOME/.config/systemd/user"
SRC_DIR="$APP_ROOT/units"
log() { printf '[guard] %s\n' "$*"; logger -t arc100-guard -- "$*" 2>/dev/null || true; }

repaired=0
install -d -o "$APP_USER" -g "$APP_USER" "$APP_HOME/.config" "$APP_HOME/.config/systemd" "$UNIT_DIR" \
  "$UNIT_DIR/default.target.wants" "$UNIT_DIR/timers.target.wants"

for u in arc100-hmi.service arc100-healthcheck.service arc100-healthcheck.timer; do
  src="$SRC_DIR/$u"; dst="$UNIT_DIR/$u"
  [[ -s "$src" ]] || { log "원본이 비어 있음: $src (install.sh 재실행 필요)"; continue; }
  # -L: /dev/null 심볼릭 링크(mask) 도 복구 대상
  if [[ -L "$dst" || ! -s "$dst" ]]; then
    log "유닛 복구: $dst ($( [[ -e "$dst" || -L "$dst" ]] && echo '비어 있거나 mask 됨' || echo '없음'))"
    rm -f "$dst"
    install -m 0644 -o "$APP_USER" -g "$APP_USER" "$src" "$dst"
    repaired=1
  fi
done

# 자동 시작(enable) 링크 — systemctl 없이도 부팅 시 default.target 이 끌어오도록 직접 보장
want() {
  local link="$1" target="$2"
  if [[ "$(readlink "$link" 2>/dev/null)" != "$target" ]]; then
    ln -sfn "$target" "$link"; chown -h "$APP_USER":"$APP_USER" "$link"
    log "자동 시작 링크 복구: $link"; repaired=1
  fi
}
want "$UNIT_DIR/default.target.wants/arc100-hmi.service"        "$UNIT_DIR/arc100-hmi.service"
want "$UNIT_DIR/timers.target.wants/arc100-healthcheck.timer"   "$UNIT_DIR/arc100-healthcheck.timer"

# 사용자 매니저가 로그인 없이도 뜨도록 (업데이트 적용·헬스체크가 SSH 세션과 무관하게 동작)
if [[ ! -e "/var/lib/systemd/linger/$APP_USER" ]]; then
  loginctl enable-linger "$APP_USER" && log "linger 복구: $APP_USER"
fi

if [[ $repaired -eq 1 ]]; then
  sync
  # 사용자 매니저가 이미 떠 있으면(수동 실행 시) 바로 반영
  if [[ -S "/run/user/$APP_UID/bus" ]]; then
    sudo -u "$APP_USER" XDG_RUNTIME_DIR="/run/user/$APP_UID" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$APP_UID/bus" \
      systemctl --user daemon-reload || true
    sudo -u "$APP_USER" XDG_RUNTIME_DIR="/run/user/$APP_UID" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$APP_UID/bus" \
      systemctl --user unmask arc100-hmi.service arc100-healthcheck.timer 2>/dev/null || true
    sudo -u "$APP_USER" XDG_RUNTIME_DIR="/run/user/$APP_UID" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$APP_UID/bus" \
      systemctl --user enable --now arc100-hmi.service arc100-healthcheck.timer || true
  fi
  log "복구 완료"
else
  echo "[guard] 이상 없음"
fi
