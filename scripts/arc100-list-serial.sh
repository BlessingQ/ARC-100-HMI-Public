#!/usr/bin/env bash
# 연결된 USB-RS485 포트의 시리얼 번호·인터페이스 번호·USB 포트 경로를 출력한다.
# 출력값으로 /etc/udev/rules.d/99-arc100-rs485.rules 의 자리표시자를 채운다.
set -uo pipefail
shopt -s nullglob
found=0
for dev in /dev/ttyUSB* /dev/ttyACM*; do
  found=1
  info="$(udevadm info -q property -n "$dev" 2>/dev/null)"
  vid="$(grep -m1 '^ID_VENDOR_ID=' <<<"$info" | cut -d= -f2)"
  pid="$(grep -m1 '^ID_MODEL_ID=' <<<"$info" | cut -d= -f2)"
  ser="$(grep -m1 '^ID_SERIAL_SHORT=' <<<"$info" | cut -d= -f2)"
  ifn="$(grep -m1 '^ID_USB_INTERFACE_NUM=' <<<"$info" | cut -d= -f2)"
  path="$(grep -m1 '^ID_PATH=' <<<"$info" | cut -d= -f2)"
  model="$(grep -m1 '^ID_MODEL=' <<<"$info" | cut -d= -f2)"
  links="$(grep -m1 '^DEVLINKS=' <<<"$info" | cut -d= -f2)"
  printf '%-14s VID:PID=%s:%s  serial=%-12s  if=%-3s  model=%s\n' "$dev" "${vid:-?}" "${pid:-?}" "${ser:-(없음)}" "${ifn:-?}" "${model:-?}"
  printf '               ID_PATH=%s\n' "${path:-?}"
  [[ -n "$links" ]] && printf '               links=%s\n' "$links"
done
[[ $found -eq 1 ]] || echo "USB 시리얼 장치가 없습니다."
echo
echo "규칙 작성 예 (FTDI 4채널, 시리얼 있음):"
echo '  SUBSYSTEM=="tty", ATTRS{idVendor}=="0403", ATTRS{serial}=="<serial>", ENV{ID_USB_INTERFACE_NUM}=="00", SYMLINK+="rs485-modbus"'
echo "규칙 작성 예 (CH340 등 시리얼 없음 → USB 포트 경로로 고정):"
echo '  SUBSYSTEM=="tty", ENV{ID_PATH}=="<ID_PATH>", SYMLINK+="rs485-modbus"'
echo "적용:  sudo udevadm control --reload-rules && sudo udevadm trigger && ls -l /dev/rs485-*"
