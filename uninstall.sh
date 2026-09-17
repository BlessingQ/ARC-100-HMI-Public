#!/usr/bin/env bash
# ARC-100 HMI 제거. 설정(/etc/arc100)과 로그 DB(/var/lib/arc100)는 --purge 를 줄 때만 지운다.
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "sudo로 실행하세요" >&2; exit 1; }
APP_USER="${SUDO_USER:-pi}"
PURGE=0
[[ "${1:-}" == "--purge" ]] && PURGE=1
APP_UID="$(id -u "$APP_USER")"
APP_HOME="$(getent passwd "$APP_USER" | cut -d: -f6)"
U="$APP_HOME/.config/systemd/user"

sudo -u "$APP_USER" XDG_RUNTIME_DIR="/run/user/$APP_UID" systemctl --user disable --now arc100-hmi.service arc100-healthcheck.timer 2>/dev/null || true
rm -f "$U/arc100-hmi.service" "$U/arc100-healthcheck.service" "$U/arc100-healthcheck.timer" \
      "$U/default.target.wants/arc100-hmi.service" "$U/timers.target.wants/arc100-healthcheck.timer"
rm -f /usr/local/bin/arc100-status /usr/local/bin/arc100-fetch-release /usr/local/bin/arc100-apply-update \
      /usr/local/bin/arc100-rollback /usr/local/bin/arc100-list-serial
rm -rf /opt/arc100
rm -f /usr/local/sbin/arc100-timesync /etc/sudoers.d/arc100-timesync
rm -f /etc/udev/rules.d/99-arc100-rs485.rules
udevadm control --reload-rules || true

if [[ $PURGE -eq 1 ]]; then
  rm -rf /etc/arc100 /var/lib/arc100
  echo "설정·로그까지 삭제했습니다."
else
  echo "설정(/etc/arc100)·로그(/var/lib/arc100)는 남겨두었습니다 (--purge 로 삭제)."
fi
echo "제거 완료. 자동 로그인 설정은 raspi-config 에서 필요 시 되돌리세요."
