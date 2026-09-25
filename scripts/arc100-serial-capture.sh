#!/usr/bin/env bash
# 시리얼 원문 캡처 — 프로토콜이 확정되지 않은 장비(기상대 WatchDog 3250DR 등)의 수신 바이트를 그대로 저장한다.
# 추가 패키지 없음 (stty · timeout · od). 결과는 ~/Documents/serial_capture/ 에 .bin(원본) + .txt(HEX·ASCII) 로 남는다.
#
#   arc100-serial-capture                                  # /dev/rs232-weather, 9600, 60 s
#   arc100-serial-capture --baud scan                      # 1200~115200 을 차례로 10 s 씩 들어보고 가장 그럴듯한 속도를 추천
#   arc100-serial-capture --baud 19200 --secs 300          # 5 분
#   arc100-serial-capture --send 'D\r' --secs 10           # 질의형 장비: 문자열을 보내고 응답을 듣는다 (\r \n 이스케이프)
#   arc100-serial-capture --port /dev/ttyUSB3 --stop-app   # 앱이 포트를 쥐고 있으면 잠시 멈추고, 끝나면 다시 켠다
#
# 주의: 앱(arc100-hmi)이 같은 포트를 열고 있으면 바이트가 나뉘어 빠진다 → --stop-app 을 쓰거나,
#       앱 설정 → 통신 모니터 → ch4 에서 TXT 줄로 보고 USB 저장(comm_log.txt)으로 받는다.
set -euo pipefail

PORT=/dev/rs232-weather
BAUD=9600
SECS=60
SEND=""
STOP_APP=0
FRAME="cs8 -parenb -cstopb"   # 8N1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --port) PORT="$2"; shift 2 ;;
    --baud) BAUD="$2"; shift 2 ;;
    --secs) SECS="$2"; shift 2 ;;
    --send) SEND="$2"; shift 2 ;;
    --frame) case "$2" in
               8N1) FRAME="cs8 -parenb -cstopb" ;;
               8N2) FRAME="cs8 -parenb cstopb" ;;
               8E1) FRAME="cs8 parenb -parodd -cstopb" ;;
               7E1) FRAME="cs7 parenb -parodd -cstopb" ;;
               *) echo "알 수 없는 프레임: $2 (8N1|8N2|8E1|7E1)"; exit 2 ;;
             esac; shift 2 ;;
    --stop-app) STOP_APP=1; shift ;;
    -h|--help) sed -n '2,13p' "$0"; exit 0 ;;
    *) echo "알 수 없는 옵션: $1"; exit 2 ;;
  esac
done

[[ -e "$PORT" ]] || { echo "포트 없음: $PORT  (arc100-list-serial 로 확인)"; exit 1; }
OUT_DIR="${HOME}/Documents/serial_capture"
mkdir -p "$OUT_DIR"
TS="$(date +%Y%m%d_%H%M%S)"

restart_app() {
  if [[ $STOP_APP -eq 1 ]]; then
    systemctl --user start arc100-hmi.service 2>/dev/null && echo "앱 다시 시작" || true
  fi
}
if [[ $STOP_APP -eq 1 ]]; then
  systemctl --user stop arc100-hmi.service 2>/dev/null && echo "앱 잠시 정지 (캡처 끝나면 다시 시작)" || true
  trap restart_app EXIT
  sleep 1
fi

setup() { stty -F "$PORT" "$1" $FRAME raw -echo -ixon -ixoff -crtscts clocal cread min 0 time 1; }

# 수신 바이트 중 인쇄 가능(0x20~0x7E, CR, LF, TAB) 비율 %
printable_pct() {
  local f="$1" n
  n=$(stat -c %s "$f")
  [[ $n -eq 0 ]] && { echo 0; return; }
  local p
  p=$(LC_ALL=C tr -cd '\11\12\15\40-\176' < "$f" | wc -c)
  echo $(( p * 100 / n ))
}

dump_txt() {
  local bin="$1" txt="$2"
  {
    echo "# 포트 $PORT · ${BAUD} · ${FRAME} · $(stat -c %s "$bin") B · $(date -Is)"
    [[ -n "$SEND" ]] && echo "# 송신: $SEND"
    echo "# 인쇄 가능 비율: $(printable_pct "$bin") %"
    echo
    echo "## ASCII (CR=\\r LF=\\n, 그 외 제어문자=.)"
    LC_ALL=C sed -e 's/\r/\\r/g' "$bin" | LC_ALL=C tr -c '\11\12\40-\176' '.' || true
    echo
    echo
    echo "## HEX"
    od -An -tx1 -v -w16 "$bin"
  } > "$txt"
}

capture() {  # capture <baud> <secs> <bin>
  setup "$1"
  : > "$3"
  if [[ -n "$SEND" ]]; then
    ( sleep 0.3; printf '%b' "$SEND" > "$PORT" ) &
  fi
  timeout "$2" cat "$PORT" > "$3" 2>/dev/null || true
}

if [[ "$BAUD" == "scan" ]]; then
  echo "보레이트 탐색 — 각 10 s (장비가 자발 송신 주기가 길면 --secs 로 늘리세요)"
  best=""; best_score=-1
  for b in 1200 2400 4800 9600 19200 38400 57600 115200; do
    f="$OUT_DIR/scan_${TS}_${b}.bin"
    capture "$b" 10 "$f"
    n=$(stat -c %s "$f"); pp=$(printable_pct "$f")
    score=$(( n > 0 ? pp : -1 ))
    printf '  %6s bps : %5d B · 인쇄 가능 %3d %%\n' "$b" "$n" "$pp"
    if [[ $score -gt $best_score ]]; then best_score=$score; best=$b; fi
  done
  if [[ $best_score -lt 0 ]]; then
    echo "→ 어떤 속도에서도 수신 없음: 배선(TX/RX 교차·GND), 장비 전원, 자발 송신 여부(질의형이면 --send) 확인"
  else
    echo "→ 추천 속도: $best bps (인쇄 가능 $best_score %). 이진 프로토콜이면 비율이 낮아도 정상일 수 있음"
    BAUD=$best
  fi
  echo "각 속도 원본: $OUT_DIR/scan_${TS}_*.bin"
  exit 0
fi

BIN="$OUT_DIR/capture_${TS}_${BAUD}.bin"
TXT="$OUT_DIR/capture_${TS}_${BAUD}.txt"
echo "캡처: $PORT ${BAUD} bps ${SECS} s …"
capture "$BAUD" "$SECS" "$BIN"
dump_txt "$BIN" "$TXT"
echo "수신 $(stat -c %s "$BIN") B · 인쇄 가능 $(printable_pct "$BIN") %"
echo "저장: $BIN"
echo "      $TXT   ← 이 파일을 개발자에게 보내 주세요 (앱 설정 → 시스템 → USB 저장 으로도 옮길 수 있음)"
head -n 12 "$TXT" | tail -n +5
