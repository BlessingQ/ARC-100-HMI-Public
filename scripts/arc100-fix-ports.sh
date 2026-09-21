#!/usr/bin/env bash
# 회선 → USB 시리얼 포트 배정을 재부팅해도 안 바뀌게 고정한다 (2026-09-21).
#
# 문제: /dev/ttyUSB0·1·2 번호는 부팅 때마다 USB 열거 순서에 따라 바뀐다. site.json 에 ttyUSBn 을 직접 적어 두면
#       재부팅 뒤 회선이 뒤바뀌어 TX 는 나가는데 RX 가 안 오는 것처럼 보인다.
# 해결: 지금 site.json 에 배정된 포트(앱 화면 "통신 포트" 에서 맞춰 둔 상태)를 읽어, 각 어댑터의 고유 serial(FTDI 등) 또는
#       USB 물리 포트 경로(ID_PATH, CH340 처럼 serial 없는 칩)로 udev 규칙을 만들고 /dev/rs485-* 고정 이름을 붙인 뒤
#       site.json 도 그 이름으로 바꾼다. 한 번만 실행하면 된다.
#
#   sudo arc100-fix-ports            # 현재 배정 기준으로 규칙 생성 + site.json 갱신
#   sudo arc100-fix-ports --dry-run  # 규칙만 화면에 출력 (파일 변경 없음)
set -euo pipefail
CONF="${ARC100_CONFIG:-/etc/arc100/site.json}"
RULES=/etc/udev/rules.d/99-arc100-rs485.rules
DRY=0
[[ "${1:-}" == "--dry-run" ]] && DRY=1
[[ $EUID -eq 0 || $DRY -eq 1 ]] || { echo "sudo 로 실행하세요:  sudo arc100-fix-ports" >&2; exit 1; }
command -v jq >/dev/null || { echo "jq 가 필요합니다 (sudo apt install jq)" >&2; exit 1; }
[[ -f "$CONF" ]] || { echo "설정 파일이 없습니다: $CONF" >&2; exit 1; }

declare -A LINK=([modbus]=rs485-modbus [ioc]=rs485-ioc [inverter]=rs485-inverter [weather]=rs232-weather)
declare -A LABEL=([modbus]="ch1 센서·HM-100 #1" [ioc]="ch2 IOC-100" [inverter]="ch3 인버터·HM-100 #2" [weather]="ch4 기상대 RS-232")
rules=()
jqset=()
seen_keys=()
warn=0

for bus in modbus ioc inverter weather; do
  port="$(jq -r ".buses.${bus}.port // empty" "$CONF")"
  link="${LINK[$bus]}"
  if [[ -z "$port" || "$port" == sim://* ]]; then
    echo "[$bus] ${LABEL[$bus]}: 포트 미지정/시뮬 — 건너뜀"
    continue
  fi
  if [[ ! -e "$port" ]]; then
    echo "[$bus] ${LABEL[$bus]}: $port 가 지금 없습니다 — 어댑터가 꽂혀 있는지 확인 (건너뜀)" >&2
    warn=1
    continue
  fi
  dev="$(readlink -f "$port")"          # /dev/rs485-* 심볼릭 링크면 실제 ttyUSBn 으로
  info="$(udevadm info -q property -n "$dev" 2>/dev/null || true)"
  vid="$(grep -m1 '^ID_VENDOR_ID=' <<<"$info" | cut -d= -f2)"
  ser="$(grep -m1 '^ID_SERIAL_SHORT=' <<<"$info" | cut -d= -f2)"
  ifn="$(grep -m1 '^ID_USB_INTERFACE_NUM=' <<<"$info" | cut -d= -f2)"
  path="$(grep -m1 '^ID_PATH=' <<<"$info" | cut -d= -f2)"
  model="$(grep -m1 '^ID_MODEL=' <<<"$info" | cut -d= -f2)"
  if [[ -z "$path" && -z "$ser" ]]; then
    echo "[$bus] $dev: udev 속성을 읽지 못했습니다 (USB 시리얼이 아닌가요?) — 건너뜀" >&2
    warn=1
    continue
  fi
  key="${ser:-}|${ifn:-}"
  how=""
  # serial 이 있고 다른 회선과 겹치지 않으면 serial+인터페이스 번호(꽂는 자리 바꿔도 유지). 아니면 물리 포트 경로.
  if [[ -n "$ser" && "$ser" != "0" && ! " ${seen_keys[*]:-} " =~ " $key " ]]; then
    seen_keys+=("$key")
    rule="SUBSYSTEM==\"tty\", ATTRS{idVendor}==\"$vid\", ATTRS{serial}==\"$ser\""
    [[ -n "$ifn" ]] && rule+=", ENV{ID_USB_INTERFACE_NUM}==\"$ifn\""
    how="serial=$ser if=${ifn:-?} (USB 자리를 바꿔도 유지)"
  else
    [[ -n "$ser" ]] && echo "[$bus] serial '$ser' 이 다른 회선과 같습니다(복제 칩) → USB 포트 경로로 고정" >&2
    rule="SUBSYSTEM==\"tty\", ENV{ID_PATH}==\"$path\""
    how="ID_PATH=$path (같은 USB 구멍에 꽂혀 있어야 유지)"
  fi
  rule+=", SYMLINK+=\"$link\", MODE=\"0660\", GROUP=\"dialout\""
  rules+=("# ${LABEL[$bus]} — $dev ${model:+($model)} : $how" "$rule")
  jqset+=(".buses.${bus}.port = \"/dev/${link}\"")
  echo "[$bus] ${LABEL[$bus]}: $dev → /dev/$link   [$how]"
done

if [[ ${#rules[@]} -eq 0 ]]; then
  echo "고정할 포트가 없습니다. 먼저 앱 설정 → 통신 포트에서 회선마다 ttyUSBn 을 배정하세요." >&2
  exit 1
fi

{
  echo "# ARC-100 시리얼 고정 이름 — arc100-fix-ports 가 $(date -Is) 에 생성. 다시 만들려면: sudo arc100-fix-ports"
  echo "# 확인: ls -l /dev/rs485-* /dev/rs232-*   ·   장치 속성: arc100-list-serial"
  printf '%s\n' "${rules[@]}"
} > /tmp/arc100-rules.$$

if [[ $DRY -eq 1 ]]; then
  echo; echo "----- 생성될 규칙 ($RULES) -----"; cat /tmp/arc100-rules.$$; rm -f /tmp/arc100-rules.$$
  echo; echo "(dry-run: 파일을 바꾸지 않았습니다)"; exit 0
fi

install -m 0644 /tmp/arc100-rules.$$ "$RULES"; rm -f /tmp/arc100-rules.$$
udevadm control --reload-rules
udevadm trigger --subsystem-match=tty
udevadm settle || true
sleep 1

ok=1
for bus in modbus ioc inverter weather; do
  link="${LINK[$bus]}"
  for s in "${jqset[@]}"; do
    [[ "$s" == *"/dev/$link"* ]] || continue
    if [[ -e "/dev/$link" ]]; then
      echo "확인: /dev/$link -> $(readlink -f "/dev/$link")"
    else
      echo "실패: /dev/$link 가 생기지 않았습니다 — arc100-list-serial 출력과 $RULES 를 대조하세요" >&2
      ok=0
    fi
  done
done
[[ $ok -eq 1 ]] || exit 1

cp -a "$CONF" "$CONF.bak"
filter="$(IFS='|'; echo "${jqset[*]}")"
jq "$filter" "$CONF" > "$CONF.tmp" && mv -f "$CONF.tmp" "$CONF"
owner="$(stat -c %U "$CONF.bak")"; chown "$owner":"$owner" "$CONF" 2>/dev/null || true
sync
echo
echo "site.json 갱신 완료 (백업: $CONF.bak). 앱을 재시작하면 고정 이름으로 접속합니다:"
echo "  systemctl --user restart arc100-hmi     (앱 사용자 터미널에서)  또는  sudo reboot"
[[ $warn -eq 0 ]] || echo "경고가 있었습니다 — 위 메시지를 확인하세요."
