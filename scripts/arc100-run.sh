#!/usr/bin/env bash
# systemd 사용자 서비스가 호출하는 실행 래퍼.
# 디스플레이(Wayland/X11)가 준비될 때까지 기다린 뒤 /opt/arc100/current/arc100_hmi 를 전체화면으로 실행한다.
set -uo pipefail
APP_ROOT=/opt/arc100
BIN="$APP_ROOT/current/arc100_hmi"
[[ -x "$BIN" ]] || { echo "[run] 앱이 설치되어 있지 않습니다: $BIN" >&2; sleep 30; exit 1; }

export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export ARC100_CONFIG="${ARC100_CONFIG:-/etc/arc100/site.json}"
export ARC100_DATA_DIR="${ARC100_DATA_DIR:-/var/lib/arc100}"
export ARC100_HEALTH_DIR="${ARC100_HEALTH_DIR:-$APP_ROOT/health}"
export GDK_BACKEND="wayland,x11"
export LANG="${LANG:-ko_KR.UTF-8}"

# 디스플레이 대기 (Wayland 소켓 또는 X11 소켓). 최대 120초, 이후엔 그냥 시도.
for _ in $(seq 1 60); do
  if [[ -S "$XDG_RUNTIME_DIR/${WAYLAND_DISPLAY:-wayland-0}" ]]; then
    export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}"
    break
  fi
  if [[ -S /tmp/.X11-unix/X0 ]]; then
    export DISPLAY="${DISPLAY:-:0}"
    break
  fi
  sleep 2
done

cd "$APP_ROOT/current"
exec "$BIN" --fullscreen "$@"
