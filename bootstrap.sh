#!/usr/bin/env bash
# ARC-100 HMI 원클릭 설치 부트스트랩 (Raspberry Pi 5 / Raspberry Pi OS 64-bit Desktop)
#
#   curl -fsSL https://raw.githubusercontent.com/BlessingQ/ARC-100-HMI-Public/master/bootstrap.sh | bash
#
# git 을 설치하고 저장소를 ~/ARC-100-HMI-Public 에 클론(또는 갱신)한 뒤 install.sh 를 sudo 로 실행한다.
set -euo pipefail
REPO_URL="${ARC100_REPO_URL:-https://github.com/BlessingQ/ARC-100-HMI-Public.git}"
DEST="${ARC100_INSTALLER_DIR:-$HOME/ARC-100-HMI-Public}"

if ! command -v git >/dev/null; then
  echo "[bootstrap] git 설치"
  sudo apt-get update -qq && sudo apt-get install -y -qq git
fi
if [[ -d "$DEST/.git" ]]; then
  echo "[bootstrap] 설치 스크립트 갱신: $DEST"
  git -C "$DEST" pull --ff-only
else
  echo "[bootstrap] 설치 스크립트 클론: $REPO_URL -> $DEST"
  git clone --depth 1 "$REPO_URL" "$DEST"
fi
chmod +x "$DEST"/install.sh "$DEST"/uninstall.sh "$DEST"/scripts/*.sh
echo "[bootstrap] install.sh 실행 (sudo 비밀번호를 물을 수 있습니다)"
sudo "$DEST/install.sh" --user "$USER" "$@"
