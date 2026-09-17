#!/usr/bin/env bash
# 최신 앱 패키지를 GitHub Releases 에서 받아 /opt/arc100/releases/<버전> 에 설치한다.
#
#   arc100-fetch-release                  # 최신 stable 릴리스 다운로드·검증만 (활성화 안 함)
#   arc100-fetch-release --activate       # 다운로드 후 current 링크 교체 + 앱 재시작
#   arc100-fetch-release --tag v1.2.0     # 특정 버전
#   arc100-fetch-release --beta           # prerelease 포함
#   arc100-fetch-release --local pkg.tar.gz [--activate]   # 직접 빌드한 패키지 설치
#
# 패키지 규격: arc100-hmi-linux-arm64-vX.Y.Z.tar.gz  (+ 같은 이름 .sha256)
#   tar 안에는 bundle/arc100_hmi (실행 파일), bundle/lib, bundle/data, manifest.json 이 있다.
set -euo pipefail

APP_ROOT=/opt/arc100
[[ -f "$APP_ROOT/repo.env" ]] && source "$APP_ROOT/repo.env"
REPO="${ARC100_REPO:-BlessingQ/ARC-100-HMI-Public}"
API="https://api.github.com/repos/$REPO/releases"

TAG=""; ACTIVATE=0; BETA=0; LOCAL=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --tag) TAG="$2"; shift 2 ;;
    --activate) ACTIVATE=1; shift ;;
    --beta) BETA=1; shift ;;
    --local) LOCAL="$2"; shift 2 ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) echo "알 수 없는 옵션: $1" >&2; exit 1 ;;
  esac
done

log() { printf '[fetch] %s\n' "$*"; }
die() { printf '[fetch] 오류: %s\n' "$*" >&2; exit 1; }

install_pkg() {  # $1 = tar.gz 경로
  local pkg="$1" tmp ver dest
  tmp="$(mktemp -d)"
  tar -xzf "$pkg" -C "$tmp"
  [[ -f "$tmp/manifest.json" ]] || die "패키지에 manifest.json 이 없습니다"
  ver="$(jq -r .version "$tmp/manifest.json")"
  [[ "$ver" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+ ]] || die "manifest.version 이 잘못됨: $ver"
  [[ "$ver" == v* ]] || ver="v$ver"
  [[ -x "$tmp/bundle/arc100_hmi" ]] || die "bundle/arc100_hmi 실행 파일이 없습니다"
  dest="$APP_ROOT/releases/$ver"
  rm -rf "$dest"
  mkdir -p "$dest"
  cp -a "$tmp/bundle/." "$dest/"
  cp "$tmp/manifest.json" "$dest/manifest.json"
  rm -rf "$tmp"
  log "설치됨: $dest"
  echo "$ver"
}

if [[ -n "$LOCAL" ]]; then
  [[ -f "$LOCAL" ]] || die "파일 없음: $LOCAL"
  if [[ -f "$LOCAL.sha256" ]]; then
    (cd "$(dirname "$LOCAL")" && sha256sum -c "$(basename "$LOCAL").sha256" --quiet) || die "sha256 불일치"
  fi
  VER="$(install_pkg "$LOCAL" | tail -n1)"
else
  command -v jq >/dev/null || die "jq 가 필요합니다 (sudo apt install jq)"
  if [[ -n "$TAG" ]]; then
    REL_JSON="$(curl -fsSL "$API/tags/$TAG")" || die "릴리스 $TAG 를 찾을 수 없습니다"
  elif [[ $BETA -eq 1 ]]; then
    REL_JSON="$(curl -fsSL "$API?per_page=1" | jq '.[0]')" || die "릴리스 목록 조회 실패"
  else
    REL_JSON="$(curl -fsSL "$API/latest")" || die "최신 릴리스 조회 실패 (릴리스가 아직 없거나 네트워크 문제)"
  fi
  TAG="$(echo "$REL_JSON" | jq -r .tag_name)"
  [[ -n "$TAG" && "$TAG" != "null" ]] || die "릴리스가 없습니다"
  PKG_URL="$(echo "$REL_JSON" | jq -r '.assets[] | select(.name | test("^arc100-hmi-linux-arm64-.*\\.tar\\.gz$")) | .browser_download_url' | head -n1)"
  SUM_URL="$(echo "$REL_JSON" | jq -r '.assets[] | select(.name | test("^arc100-hmi-linux-arm64-.*\\.tar\\.gz\\.sha256$")) | .browser_download_url' | head -n1)"
  [[ -n "$PKG_URL" ]] || die "릴리스 $TAG 에 arc100-hmi-linux-arm64-*.tar.gz 자산이 없습니다"

  if [[ -d "$APP_ROOT/releases/$TAG" && $ACTIVATE -eq 0 ]]; then
    log "이미 설치된 버전: $TAG"; exit 0
  fi
  mkdir -p "$APP_ROOT/downloads"
  PKG="$APP_ROOT/downloads/$(basename "$PKG_URL")"
  log "다운로드: $PKG_URL"
  curl -fL --progress-bar -o "$PKG" "$PKG_URL"
  if [[ -n "$SUM_URL" ]]; then
    curl -fsSL -o "$PKG.sha256" "$SUM_URL"
    (cd "$APP_ROOT/downloads" && sha256sum -c "$(basename "$PKG").sha256" --quiet) || die "sha256 불일치 — 다운로드 파일 폐기"
    log "sha256 확인 완료"
  else
    log "경고: .sha256 자산이 없어 무결성 검증을 건너뜁니다"
  fi
  VER="$(install_pkg "$PKG" | tail -n1)"
fi

if [[ $ACTIVATE -eq 1 ]]; then
  exec "$APP_ROOT/bin/arc100-apply-update" "$VER"
else
  log "활성화하려면:  arc100-apply-update $VER"
fi
