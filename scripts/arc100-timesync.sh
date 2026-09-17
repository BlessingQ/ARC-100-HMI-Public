#!/usr/bin/env bash
# arc100-timesync — 시각 소스 전환(네트워크 NTP ↔ RTC/수동), 수동 시각 설정, RTC 기록. root 로 실행한다.
# install.sh 가 /usr/local/sbin/arc100-timesync (root 소유) 로 설치하고 앱 사용자에게 sudoers NOPASSWD 를 준다.
# 앱(설정 > 시스템 > 시간·RTC)이 `sudo -n arc100-timesync <cmd>` 로 호출한다.
#
#   arc100-timesync status                       # JSON 한 줄
#   arc100-timesync ntp on|off                   # 네트워크 자동 동기화 켜기/끄기 (끄면 RTC/수동 모드)
#   arc100-timesync set "2026-09-17 14:32:00"    # 수동 시각 → 시스템 시각 + RTC 기록 (NTP 자동 해제)
#   arc100-timesync from-rtc                     # RTC 시각을 시스템에 적용
#   arc100-timesync charge on                    # Pi 5 RTC 배터리(ML2020) 세류 충전 켜기 (config.txt, 재부팅 필요)
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "root 로 실행하세요 (sudo)" >&2; exit 1; }

CONFIG_TXT=/boot/firmware/config.txt
[[ -f "$CONFIG_TXT" ]] || CONFIG_TXT=/boot/config.txt

json_escape() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

status() {
  local ntp synced tz rtc rtctime now charge
  ntp=$(timedatectl show -p NTP --value 2>/dev/null || echo no)
  synced=$(timedatectl show -p NTPSynchronized --value 2>/dev/null || echo no)
  tz=$(timedatectl show -p Timezone --value 2>/dev/null || echo "")
  if [[ -e /dev/rtc0 ]]; then rtc=yes; rtctime=$(hwclock -r 2>/dev/null | cut -d. -f1 || echo ""); else rtc=no; rtctime=""; fi
  now=$(date '+%Y-%m-%d %H:%M:%S')
  if grep -qE '^dtparam=rtc_bbat_vchg=' "$CONFIG_TXT" 2>/dev/null; then charge=yes; else charge=no; fi
  printf '{"ntp":%s,"synced":%s,"timezone":"%s","rtc":%s,"rtc_time":"%s","system_time":"%s","battery_charge":%s}\n' \
    "$([[ $ntp == yes ]] && echo true || echo false)" \
    "$([[ $synced == yes ]] && echo true || echo false)" \
    "$(json_escape "$tz")" \
    "$([[ $rtc == yes ]] && echo true || echo false)" \
    "$(json_escape "$rtctime")" "$now" \
    "$([[ $charge == yes ]] && echo true || echo false)"
}

case "${1:-status}" in
  status) status ;;
  ntp)
    case "${2:-}" in
      on)  timedatectl set-ntp true;  sleep 2; hwclock -w 2>/dev/null || true; echo "NTP on" ;;
      off) timedatectl set-ntp false; echo "NTP off (RTC/수동)" ;;
      *) echo "ntp on|off" >&2; exit 1 ;;
    esac ;;
  set)
    [[ "${2:-}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2}(:[0-9]{2})?$ ]] || { echo "형식: \"YYYY-MM-DD HH:MM[:SS]\"" >&2; exit 1; }
    timedatectl set-ntp false
    timedatectl set-time "$2"
    hwclock -w 2>/dev/null || echo "경고: RTC 기록 실패 (/dev/rtc0 없음?)" >&2
    echo "시각 설정: $2 (RTC 기록)" ;;
  from-rtc)
    [[ -e /dev/rtc0 ]] || { echo "RTC 없음" >&2; exit 1; }
    timedatectl set-ntp false
    hwclock -s
    echo "RTC → 시스템 적용: $(date '+%Y-%m-%d %H:%M:%S')" ;;
  charge)
    [[ "${2:-}" == on ]] || { echo "charge on" >&2; exit 1; }
    if ! grep -qE '^dtparam=rtc_bbat_vchg=' "$CONFIG_TXT"; then
      printf '\n# ARC-100: RTC 배터리(ML2020) 세류 충전\ndtparam=rtc_bbat_vchg=3000000\n' >> "$CONFIG_TXT"
    fi
    echo "RTC 배터리 충전 설정됨 — 재부팅 후 적용" ;;
  *) sed -n '2,11p' "$0"; exit 1 ;;
esac
