#!/usr/bin/env bash
# ARC-100 원격 지원 · 화상 키보드 설정 (2026-10-08)
#
#   1. 데스크톱을 X11(Openbox, rpd-x) 로 전환 — TeamViewer 는 Raspberry Pi 의 Wayland(labwc) 에서
#      접속이 "연결 중" 에 멈추는 경우가 있어 TeamViewer 가 X11 을 권장한다. (재부팅 후 적용)
#   2. 화상 키보드 onboard — X11 용. (squeekboard 는 Wayland 전용이라 X11 에서는 뜨지 않는다)
#      화면 오른쪽 아래 작은 키보드 아이콘을 누르면 열리고, 글자 입력 칸을 누르면 자동으로도 뜬다.
#   3. TeamViewer Host (무인 접속용, 부팅하면 항상 대기) + 라이선스 동의 + 데몬 자동 시작.
#      회사 계정에 붙이려면 --tv-token <할당 토큰> (TeamViewer 관리 콘솔 → 설계·배포 → 할당 구성).
#      ※ TeamViewer 는 회사 용도면 유료 라이선스가 필요하다 (무료 = 개인용).
#
# 사용법 (install.sh 가 자동으로 부른다. 이미 설치된 기기는 이것만 따로 실행해도 된다):
#   sudo arc100-remote-setup                      # 전부
#   sudo arc100-remote-setup --tv-token XXXX      # + TeamViewer 회사 계정에 할당
#   sudo arc100-remote-setup --no-teamviewer      # 키보드 · X11 만
#   sudo arc100-remote-setup --wayland            # X11 전환 취소 (Wayland + squeekboard 로 되돌림, TeamViewer 는 남김)
set -euo pipefail

APP_USER="${SUDO_USER:-}"
DO_X11=1
DO_KEYBOARD=1
DO_TEAMVIEWER=1
TV_TOKEN="${ARC100_TV_TOKEN:-}"
BACK_TO_WAYLAND=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --user) APP_USER="$2"; shift 2 ;;
    --tv-token) TV_TOKEN="$2"; shift 2 ;;
    --no-teamviewer) DO_TEAMVIEWER=0; shift ;;
    --no-keyboard) DO_KEYBOARD=0; shift ;;
    --no-x11) DO_X11=0; shift ;;
    --wayland) BACK_TO_WAYLAND=1; shift ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "알 수 없는 옵션: $1" >&2; exit 1 ;;
  esac
done

log()  { printf '\033[1;36m[원격·키보드]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[원격·키보드] 경고:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[원격·키보드] 오류:\033[0m %s\n' "$*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "sudo 로 실행하세요:  sudo arc100-remote-setup"
command -v raspi-config >/dev/null || die "raspi-config 가 없습니다 (Raspberry Pi OS 가 아님)"

# ── 되돌리기: Wayland(labwc) + squeekboard ───────────────────────────────────
if [[ $BACK_TO_WAYLAND -eq 1 ]]; then
  log "데스크톱을 Wayland(labwc) 로 되돌림 + squeekboard(터치 화면이면 자동)"
  raspi-config nonint do_wayland W2
  raspi-config nonint do_squeekboard S2 || true
  rm -f /etc/xdg/autostart/arc100-onboard.desktop
  log "완료 — 재부팅하면 적용됩니다:  sudo reboot"
  exit 0
fi

export DEBIAN_FRONTEND=noninteractive
NEED_REBOOT=0

# ── 1. X11 전환 ──────────────────────────────────────────────────────────────
if [[ $DO_X11 -eq 1 ]]; then
  cur="$(grep -E '^user-session=' /etc/lightdm/lightdm.conf 2>/dev/null | cut -d= -f2 || true)"
  if [[ "$cur" == "rpd-x" ]]; then
    log "데스크톱: 이미 X11 (rpd-x)"
  else
    log "데스크톱을 X11(Openbox) 로 전환 (지금: ${cur:-알 수 없음}) — 재부팅 후 적용"
    raspi-config nonint do_wayland W1
    NEED_REBOOT=1
  fi
fi

# ── 2. 화상 키보드 onboard ───────────────────────────────────────────────────
if [[ $DO_KEYBOARD -eq 1 ]]; then
  log "화상 키보드 onboard 설치"
  apt-get install -y -qq onboard at-spi2-core >/dev/null
  # 기본값: 작게 시작 · 떠 있는 아이콘으로 열기 · 입력 칸을 누르면 자동 표시 · 화면 아래에 붙임
  cat > /usr/share/glib-2.0/schemas/90_arc100-onboard.gschema.override <<'EOF'
[org.onboard]
start-minimized=true

[org.onboard.auto-show]
enabled=true

[org.onboard.icon-palette]
in-use=true

[org.onboard.window]
docking-enabled=true
EOF
  # 입력 칸 자동 표시는 접근성(AT-SPI) 신호로 동작한다
  if [[ -f /usr/share/glib-2.0/schemas/org.gnome.desktop.interface.gschema.xml ]]; then
    printf '[org.gnome.desktop.interface]
toolkit-accessibility=true
' > /usr/share/glib-2.0/schemas/91_arc100-a11y.gschema.override
  fi
  glib-compile-schemas /usr/share/glib-2.0/schemas/ || warn "gschema 컴파일 실패 — onboard 기본값이 적용되지 않을 수 있음"
  # X11 세션에서 로그인하면 자동 시작 (onboard 패키지의 자동 시작은 GNOME 계열 조건이 있어 따로 둔다)
  cat > /etc/xdg/autostart/arc100-onboard.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=ARC-100 화상 키보드 (onboard)
Exec=onboard
NoDisplay=true
X-GNOME-Autostart-enabled=true
EOF
  # Wayland 로 되돌릴 때를 위해 squeekboard 는 "터치 화면이면 자동" 으로 둔다 (X11 에서는 뜨지 않음)
  raspi-config nonint do_squeekboard S2 >/dev/null 2>&1 || true
fi

# ── 3. TeamViewer Host ───────────────────────────────────────────────────────
if [[ $DO_TEAMVIEWER -eq 1 ]]; then
  if command -v teamviewer >/dev/null; then
    log "TeamViewer: 이미 설치됨 ($(teamviewer --version 2>/dev/null | grep -oE '[0-9]+\.[0-9.]+' | head -1))"
  else
    case "$(dpkg --print-architecture)" in
      arm64) deb_arch=arm64 ;;
      armhf) deb_arch=armhf ;;
      amd64) deb_arch=amd64 ;;
      *) die "지원하지 않는 아키텍처: $(dpkg --print-architecture)" ;;
    esac
    url="https://download.teamviewer.com/download/linux/teamviewer-host_${deb_arch}.deb"
    log "TeamViewer Host 내려받기: $url"
    tmp="$(mktemp -d)"
    curl -fL --retry 3 -o "$tmp/teamviewer-host.deb" "$url" || die "TeamViewer 내려받기 실패 (인터넷 확인)"
    log "TeamViewer Host 설치 (의존 패키지 포함)"
    apt-get install -y -qq "$tmp/teamviewer-host.deb" >/dev/null || die "TeamViewer 설치 실패"
    rm -rf "$tmp"
  fi
  teamviewer license accept >/dev/null 2>&1 || true
  teamviewer daemon enable >/dev/null 2>&1 || true
  teamviewer daemon start >/dev/null 2>&1 || true
  if [[ -n "$TV_TOKEN" ]]; then
    log "TeamViewer 를 회사 계정에 할당 (무인 접속)"
    teamviewer assignment --token "$TV_TOKEN" || warn "할당 실패 — 토큰을 확인하세요 (TeamViewer 관리 콘솔)"
  fi
  sleep 3
  TV_ID="$(teamviewer info 2>/dev/null | grep -oE 'TeamViewer ID:[^0-9]*[0-9]+' | grep -oE '[0-9]+$' || true)"
  [[ -n "$TV_ID" ]] && log "TeamViewer ID: $TV_ID" || warn "TeamViewer ID 를 아직 못 읽었습니다 — 재부팅 후 'teamviewer info'"
fi

sync
echo
log "완료."
[[ $DO_KEYBOARD -eq 1 ]] && echo "  화상 키보드 : 화면 구석의 키보드 아이콘을 누르거나, 글자 입력 칸을 누르면 뜹니다"
[[ $DO_TEAMVIEWER -eq 1 ]] && echo "  TeamViewer  : ID 확인 'teamviewer info' · 무인 접속 비밀번호 'sudo teamviewer passwd <비밀번호>' (또는 --tv-token 으로 회사 계정 할당)"
[[ $NEED_REBOOT -eq 1 ]] && echo "  재부팅해야 X11 화면으로 바뀝니다:  sudo reboot"
echo "  되돌리기    : sudo arc100-remote-setup --wayland   (Wayland + squeekboard)"
