#!/usr/bin/env bash
# ARC-100 HMI 설치 스크립트 — Raspberry Pi 5 / Raspberry Pi OS (64-bit, Desktop, Bookworm 이상)
#
# 하는 일:
#   1. 필수 패키지 설치, 앱 사용자를 dialout 그룹에 추가
#   2. /opt/arc100 디렉터리 구성 (releases/, current -> 심볼릭 링크, health/)
#   3. GitHub Releases에서 최신 앱 패키지 다운로드 + sha256 검증 + 설치 (--local <tar.gz> 로 대체 가능)
#   4. /etc/arc100/site.json 설정 파일 배치 (기존 파일은 유지)
#   5. RS-485 udev 규칙 설치 (/dev/rs485-* 고정 이름)
#   6. 키오스크: 데스크톱 자동 로그인, 화면 꺼짐 방지
#   7. systemd 사용자 서비스 등록 -> 부팅 시 앱 자동 시작, 죽으면 자동 재시작
#   8. 헬스체크 타이머 등록 -> 업데이트 후 기동 실패 3회 시 자동 롤백
#
# 사용법:
#   sudo ./install.sh                     # 최신 릴리스 설치
#   sudo ./install.sh --local app.tar.gz  # 직접 빌드한 패키지 설치
#   sudo ./install.sh --user pi           # 앱을 실행할 데스크톱 사용자 지정 (기본: sudo를 호출한 사용자)
#   sudo ./install.sh --no-kiosk          # 자동 로그인/화면 설정은 건드리지 않음
set -euo pipefail

REPO="${ARC100_REPO:-BlessingQ/ARC-100-HMI-Public}"
APP_ROOT=/opt/arc100
CONF_DIR=/etc/arc100
DATA_DIR=/var/lib/arc100
SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

LOCAL_PKG=""
APP_USER="${SUDO_USER:-}"
KIOSK=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --local) LOCAL_PKG="$2"; shift 2 ;;
    --user) APP_USER="$2"; shift 2 ;;
    --no-kiosk) KIOSK=0; shift ;;
    -h|--help) sed -n '2,22p' "$0"; exit 0 ;;
    *) echo "알 수 없는 옵션: $1" >&2; exit 1 ;;
  esac
done

log()  { printf '\033[1;36m[ARC-100]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[ARC-100] 경고:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[ARC-100] 오류:\033[0m %s\n' "$*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "sudo로 실행하세요:  sudo ./install.sh"
[[ -n "$APP_USER" && "$APP_USER" != "root" ]] || die "앱을 실행할 데스크톱 사용자를 --user 로 지정하세요 (예: --user pi)"
id "$APP_USER" >/dev/null 2>&1 || die "사용자 '$APP_USER' 가 없습니다"
APP_HOME="$(getent passwd "$APP_USER" | cut -d: -f6)"
APP_UID="$(id -u "$APP_USER")"

ARCH="$(uname -m)"
[[ "$ARCH" == "aarch64" ]] || warn "aarch64 가 아닙니다 ($ARCH). Raspberry Pi OS 64-bit 를 권장합니다."
if grep -q "Raspberry Pi 5" /proc/device-tree/model 2>/dev/null; then
  log "기기: $(tr -d '\0' < /proc/device-tree/model)"
else
  warn "Raspberry Pi 5 가 아닌 것으로 보입니다: $(tr -d '\0' < /proc/device-tree/model 2>/dev/null || echo unknown)"
fi

# ── 1. 패키지 ────────────────────────────────────────────────────────────────
log "패키지 설치"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq curl jq git ca-certificates libgtk-3-0 liblzma5 libstdc++6 libblkid1 fonts-noto-cjk >/dev/null
usermod -aG dialout "$APP_USER"

# ── 2. 디렉터리 ──────────────────────────────────────────────────────────────
log "디렉터리 구성: $APP_ROOT"
install -d -o "$APP_USER" -g "$APP_USER" "$APP_ROOT" "$APP_ROOT/releases" "$APP_ROOT/health" "$APP_ROOT/bin" "$APP_ROOT/downloads"
install -d -o "$APP_USER" -g "$APP_USER" "$DATA_DIR"
install -d "$CONF_DIR"

install -m 0755 -o "$APP_USER" -g "$APP_USER" "$SRC_DIR/scripts/arc100-fetch-release.sh"  "$APP_ROOT/bin/arc100-fetch-release"
install -m 0755 -o "$APP_USER" -g "$APP_USER" "$SRC_DIR/scripts/arc100-apply-update.sh"   "$APP_ROOT/bin/arc100-apply-update"
install -m 0755 -o "$APP_USER" -g "$APP_USER" "$SRC_DIR/scripts/arc100-rollback.sh"       "$APP_ROOT/bin/arc100-rollback"
install -m 0755 -o "$APP_USER" -g "$APP_USER" "$SRC_DIR/scripts/arc100-healthcheck.sh"    "$APP_ROOT/bin/arc100-healthcheck"
install -m 0755 -o "$APP_USER" -g "$APP_USER" "$SRC_DIR/scripts/arc100-run.sh"            "$APP_ROOT/bin/arc100-run"
install -m 0755 -o "$APP_USER" -g "$APP_USER" "$SRC_DIR/scripts/arc100-list-serial.sh"    "$APP_ROOT/bin/arc100-list-serial"
install -m 0755 -o "$APP_USER" -g "$APP_USER" "$SRC_DIR/scripts/arc100-status.sh"         "$APP_ROOT/bin/arc100-status"
ln -sfn "$APP_ROOT/bin/arc100-status"        /usr/local/bin/arc100-status
ln -sfn "$APP_ROOT/bin/arc100-fetch-release" /usr/local/bin/arc100-fetch-release
ln -sfn "$APP_ROOT/bin/arc100-apply-update"  /usr/local/bin/arc100-apply-update
ln -sfn "$APP_ROOT/bin/arc100-rollback"      /usr/local/bin/arc100-rollback
ln -sfn "$APP_ROOT/bin/arc100-list-serial"   /usr/local/bin/arc100-list-serial
printf 'ARC100_REPO=%s\n' "$REPO" > "$APP_ROOT/repo.env"

# ── 3. 앱 패키지 ─────────────────────────────────────────────────────────────
if [[ -n "$LOCAL_PKG" ]]; then
  log "로컬 패키지 설치: $LOCAL_PKG"
  sudo -u "$APP_USER" ARC100_REPO="$REPO" "$APP_ROOT/bin/arc100-fetch-release" --local "$LOCAL_PKG" --activate
else
  log "GitHub Releases 에서 최신 패키지 확인: $REPO"
  if ! sudo -u "$APP_USER" ARC100_REPO="$REPO" "$APP_ROOT/bin/arc100-fetch-release" --activate; then
    warn "릴리스를 가져오지 못했습니다. 나중에 'arc100-fetch-release --activate' 를 다시 실행하거나 --local 로 설치하세요."
  fi
fi

# ── 4. 설정 파일 ─────────────────────────────────────────────────────────────
if [[ ! -f "$CONF_DIR/site.json" ]]; then
  log "설정 파일 생성: $CONF_DIR/site.json (site.example.json 복사)"
  install -m 0644 "$SRC_DIR/config/site.example.json" "$CONF_DIR/site.json"
else
  log "설정 파일 유지: $CONF_DIR/site.json"
fi
chown "$APP_USER":"$APP_USER" "$CONF_DIR/site.json"

# ── 5. udev ──────────────────────────────────────────────────────────────────
if [[ ! -f /etc/udev/rules.d/99-arc100-rs485.rules ]]; then
  log "udev 규칙 설치 (템플릿) — 실제 컨버터 시리얼은 'arc100-list-serial' 로 확인 후 수정"
  install -m 0644 "$SRC_DIR/config/99-arc100-rs485.rules" /etc/udev/rules.d/99-arc100-rs485.rules
else
  log "udev 규칙 유지: /etc/udev/rules.d/99-arc100-rs485.rules"
fi
udevadm control --reload-rules && udevadm trigger || true

# ── 6. 키오스크 ──────────────────────────────────────────────────────────────
if [[ $KIOSK -eq 1 ]] && command -v raspi-config >/dev/null; then
  log "키오스크: 데스크톱 자동 로그인($APP_USER), 화면 꺼짐 방지"
  raspi-config nonint do_boot_behaviour B4 || warn "자동 로그인 설정 실패 (raspi-config)"
  raspi-config nonint do_blanking 1 || warn "화면 꺼짐 방지 설정 실패 (raspi-config)"
fi

# ── 7. systemd 사용자 서비스 (부팅 시 자동 시작) ─────────────────────────────
log "systemd 사용자 서비스 등록: arc100-hmi.service"
USER_UNIT_DIR="$APP_HOME/.config/systemd/user"
install -d -o "$APP_USER" -g "$APP_USER" "$APP_HOME/.config" "$APP_HOME/.config/systemd" "$USER_UNIT_DIR"
install -m 0644 -o "$APP_USER" -g "$APP_USER" "$SRC_DIR/config/arc100-hmi.service"         "$USER_UNIT_DIR/arc100-hmi.service"
install -m 0644 -o "$APP_USER" -g "$APP_USER" "$SRC_DIR/config/arc100-healthcheck.service" "$USER_UNIT_DIR/arc100-healthcheck.service"
install -m 0644 -o "$APP_USER" -g "$APP_USER" "$SRC_DIR/config/arc100-healthcheck.timer"   "$USER_UNIT_DIR/arc100-healthcheck.timer"
loginctl enable-linger "$APP_USER" || true

run_user_systemctl() {
  sudo -u "$APP_USER" XDG_RUNTIME_DIR="/run/user/$APP_UID" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$APP_UID/bus" systemctl --user "$@"
}
if [[ -d "/run/user/$APP_UID" ]]; then
  run_user_systemctl daemon-reload
  run_user_systemctl enable arc100-hmi.service arc100-healthcheck.timer
  if [[ -e "$APP_ROOT/current/arc100_hmi" ]]; then
    run_user_systemctl restart arc100-hmi.service || warn "서비스 시작 실패 — 'arc100-status' 로 확인"
    run_user_systemctl start arc100-healthcheck.timer || true
  fi
else
  warn "사용자 세션이 아직 없어 서비스 활성화를 건너뜁니다. 재부팅 후 자동 로그인되면 활성화됩니다."
  # 재부팅 후 첫 로그인에 enable 되도록 wants 링크를 직접 만든다
  install -d -o "$APP_USER" -g "$APP_USER" "$USER_UNIT_DIR/default.target.wants" "$USER_UNIT_DIR/timers.target.wants"
  ln -sfn "$USER_UNIT_DIR/arc100-hmi.service" "$USER_UNIT_DIR/default.target.wants/arc100-hmi.service"
  ln -sfn "$USER_UNIT_DIR/arc100-healthcheck.timer" "$USER_UNIT_DIR/timers.target.wants/arc100-healthcheck.timer"
  chown -h "$APP_USER":"$APP_USER" "$USER_UNIT_DIR/default.target.wants/arc100-hmi.service" "$USER_UNIT_DIR/timers.target.wants/arc100-healthcheck.timer"
fi

# ── 완료 ─────────────────────────────────────────────────────────────────────
echo
log "설치 완료."
echo "  앱 경로      : $APP_ROOT/current  ->  $(readlink -f "$APP_ROOT/current" 2>/dev/null || echo '(릴리스 없음)')"
echo "  설정         : $CONF_DIR/site.json"
echo "  로그         : journalctl --user -u arc100-hmi -f   (사용자 $APP_USER 로 실행)"
echo "  상태         : arc100-status"
echo "  시리얼 확인  : arc100-list-serial   ->  /etc/udev/rules.d/99-arc100-rs485.rules 수정"
echo "  업데이트     : arc100-fetch-release --activate   /  롤백: arc100-rollback"
echo
echo "  재부팅하면 자동 로그인 후 앱이 전체화면으로 시작됩니다:  sudo reboot"
