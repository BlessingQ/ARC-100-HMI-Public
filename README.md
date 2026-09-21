# ARC-100 HMI — 설치 안내서

㈜아이온텍 **ARC-100 공기재순환 제어기**의 터치 HMI/제어 앱을 **Raspberry Pi 5**에 설치·자동 시작·자동 업데이트하는 저장소입니다.

> 이 저장소에는 **설치 스크립트와 빌드된 앱 패키지(Releases)만** 있습니다. 앱 소스 코드는 포함하지 않습니다.

## 1. 대상 환경

| 항목 | 요구 사항 |
|---|---|
| 보드 | Raspberry Pi 5 (4 GB 이상 권장) |
| OS | Raspberry Pi OS **64-bit, Desktop** (Bookworm 이상). Lite 불가 — 화면이 필요합니다 |
| 화면 | 10.1" 1920×1080 정전식 터치 (HDMI + USB 터치) |
| 통신 | 절연형 USB-RS485 3채널 (ch1 센서/HM-100 #1, ch2 IOC-100 ×1, ch3 인버터 ×3 + HM-100 #2) + USB-RS232 1채널 (ch4 외부 기상대 WatchDog 3250DR, 옵션 — 자발 송신 장치라 단독 회선) |
| 네트워크 | 설치·업데이트 시에만 인터넷 필요. 운전 중에는 불필요 |

## 2. 설치 (한 줄)

Raspberry Pi 5의 터미널에서:

```bash
curl -fsSL https://raw.githubusercontent.com/BlessingQ/ARC-100-HMI-Public/master/bootstrap.sh | bash
```

이 명령이 하는 일:

1. `git` 설치 → 이 저장소를 `~/ARC-100-HMI-Public`에 클론
2. `install.sh`를 `sudo`로 실행
   - 필수 패키지 설치, 사용자를 `dialout` 그룹에 추가
   - `/opt/arc100/` 구성 (`releases/`, `current` 링크, `bin/`, `health/`)
   - GitHub **Releases의 최신 패키지**를 내려받아 **sha256 검증** 후 설치
   - `/etc/arc100/site.json` 설정 파일 생성 (이미 있으면 유지)
   - RS-485 udev 규칙 템플릿 설치 (`/dev/rs485-*` 고정 이름)
   - 데스크톱 **자동 로그인**, **화면 꺼짐 방지** (`raspi-config`)
   - **systemd 사용자 서비스** 등록 → **부팅 시 앱 자동 시작**, 죽으면 5초 후 재시작
   - 헬스체크 타이머 등록 → 업데이트 후 기동 실패가 반복되면 **자동 롤백**
3. 완료 후 `sudo reboot` 하면 자동 로그인 → 앱이 전체화면으로 시작됩니다.

수동 설치도 같습니다:

```bash
git clone https://github.com/BlessingQ/ARC-100-HMI-Public.git ~/ARC-100-HMI-Public
cd ~/ARC-100-HMI-Public
sudo ./install.sh --user $USER
```

옵션:

| 옵션 | 설명 |
|---|---|
| `--local app.tar.gz` | GitHub 대신 직접 빌드한 패키지를 설치 (Pi 5 빌드 머신에서 스모크 테스트용) |
| `--user pi` | 앱을 실행할 데스크톱 사용자 (기본: sudo를 호출한 사용자) |
| `--no-kiosk` | 자동 로그인·화면 꺼짐 설정을 건드리지 않음 |

## 3. 설치 후 반드시 할 일 — RS-485 포트 고정

`/dev/ttyUSB0~3` 번호는 **재부팅 때마다 바뀔 수 있습니다** (USB 열거 순서). site.json 에 ttyUSBn 을 그대로 두면 재부팅 뒤 회선이 뒤바뀌어 "TX 는 나가는데 RX 가 없는" 증상이 됩니다. 반드시 고정 이름으로 바꿉니다 — 한 줄이면 됩니다:

```bash
# 1) 앱 화면 설정 → 통신 포트 에서 회선마다 지금 맞는 ttyUSBn 을 배정·저장 (통신 모니터로 응답 확인)
# 2) 그 배정을 그대로 고정:
sudo arc100-fix-ports                    # 어댑터 serial(또는 USB 구멍 위치)로 udev 규칙 생성 + site.json 을 /dev/rs485-* 로 갱신
ls -l /dev/rs485-* /dev/rs232-*          # rs485-modbus, rs485-ioc, rs485-inverter (+ rs232-weather)
```

- FTDI 처럼 칩 고유 serial 이 있는 어댑터는 **USB 구멍을 바꿔 꽂아도** 유지됩니다.
- CH340 같은 serial 없는 어댑터는 **USB 물리 포트 위치**로 고정되므로 꽂는 자리를 바꾸면 다시 `sudo arc100-fix-ports` 를 실행합니다.
- 미리 보기만: `sudo arc100-fix-ports --dry-run`. 수동으로 하려면 `arc100-list-serial` 로 값을 보고 `/etc/udev/rules.d/99-arc100-rs485.rules` 를 편집.

| 장치명 | 채널 | 연결 장치 |
|---|---|---|
| `/dev/rs485-modbus` | ch1 | 아이온텍 SensorNode ×13 (ID 2~14) + HM-100 #1 (ID 1) |
| `/dev/rs485-ioc` | ch2 | IOC-100 #1 (ID 1) |
| `/dev/rs485-inverter` | ch3 | LSLV-G100 인버터 국번 21 / 22 / 23 **+ HM-100 #2 (ID 1)** — 9600 8N1 공유. HM-100 은 ID 1 에만 응답하고 그 외 ID 프레임에는 침묵하므로 충돌 없음 |
| `/dev/rs232-weather` | ch4 | 외부 기상대 스펙트럼 WatchDog 3250DR (AUX RS-232 9600) — 없으면 복도 센서로 대체 |

RS-485 3개 링크가 모두 없으면 앱은 **출력 쓰기를 잠근 채** 기동합니다 (표시만 함).

## 4. 설정 파일 `/etc/arc100/site.json`

`config/site.example.json`이 초기값으로 복사됩니다. 현장에 맞게 고칠 항목:

- `control.tset_c`, `rh_low/high`, `nh3_high_ppm`, `co2_high_ppm`, `head_count`, `cmh_per_head` — 제어 인자 (앱 설정 화면에서도 변경 가능)
- `dampers[].stroke_s` — 댐퍼 전개~전폐 소요 시간 (시운전 실측)
- `inverters[].rated_cmh_60hz` — 팬 정격 풍량 (환기량 표시용)
- `update.repo` — 릴리스 저장소 (기본 `BlessingQ/ARC-100-HMI-Public`)
- `update.auto` — `false`(기본, 수동) / `true`(자동: `check_interval_h` 시간마다 확인→다운로드→적용). 앱 **설정 > 시스템 > 업데이트** 화면에서도 전환 가능
- `admin_pin` — 관리자 PIN (기본 `1234`). 설정 저장·통신 포트 변경·트립 리셋·세척 모드·업데이트 방식(수동/자동) 변경에 필요. 업데이트 확인·다운로드·적용은 PIN 없이 확인 대화상자만
- `buses.*.port` — 회선별 포트. 앱의 **설정 > 통신 포트** 화면에서 터치로 고를 수 있으며(발견된 `/dev/rs485-*`·`/dev/ttyUSB*` 목록), 저장하면 즉시 재연결됩니다

업데이트를 해도 이 파일은 덮어쓰지 않습니다. 이벤트 로그 DB(`/var/lib/arc100/arc100.db`, 30일 보존)도 앱 폴더 밖에 있어 **업데이트·롤백 후에 그대로 보존**됩니다.

## 5. 운영 명령

| 명령 | 설명 |
|---|---|
| `arc100-status` | 버전·서비스·포트·헬스 상태 요약 |
| `sudo arc100-fix-ports` | 현재 회선→포트 배정을 udev 고정 이름(`/dev/rs485-*`)으로 굳히고 site.json 갱신 (재부팅 시 ttyUSB 번호 변경 대비) |
| 화면 **설정·시스템 → 통신 모니터** | 회선별 TX/RX 프레임(HEX)과 드라이버 해석을 실시간으로 봄 — 무응답·ID 불일치·길이 오류를 현장에서 바로 판별 |
| `journalctl --user -u arc100-hmi -f` | 앱 로그 실시간 보기 |
| `systemctl --user restart arc100-hmi` | 앱 재시작 |
| `arc100-fetch-release --activate` | 최신 릴리스 내려받아 적용 (앱 화면의 **업데이트 확인/적용** 버튼과 동일) |
| `arc100-fetch-release --tag v1.2.0 --activate` | 특정 버전 적용 |
| `arc100-rollback` | 직전 버전으로 되돌리기 |
| `sudo arc100-guard` | 자동 시작 유닛 점검·복구 (부팅마다 `arc100-guard.service` 가 자동 실행) |
| `sudo ~/ARC-100-HMI-Public/uninstall.sh [--purge]` | 제거 (`--purge`: 설정·로그까지) |

## 6. 업데이트 동작

**기본은 수동**입니다. 앱 **설정 > 시스템 > 업데이트** 화면에서 방식을 고릅니다 (관리자 PIN).

| 방식 | 동작 |
|---|---|
| **수동** (기본) | 운전자가 **업데이트 확인** → **다운로드** → **지금 적용** 을 차례로 누릅니다. 누르지 않으면 네트워크 접근도 하지 않습니다 |
| **자동** | 앱이 6시간마다(`update.check_interval_h`) 확인하고, 새 버전이 있으면 다운로드·검증 후 **바로 적용(재시작)** 합니다. 켤 때 확인 대화상자가 뜹니다 |

공통 절차:
1. `https://api.github.com/repos/BlessingQ/ARC-100-HMI-Public/releases/latest` 조회. 토큰 없음(공개 저장소).
2. `arc100-hmi-linux-arm64-vX.Y.Z.tar.gz`와 `.sha256`을 내려받아 검증하고 `/opt/arc100/releases/vX.Y.Z`에 풀어 둡니다.
3. `current` 링크를 바꾸고 앱을 재시작합니다 (약 20초). 재시작 중 인버터는 자체 지령 상실 보호(30 Hz)로 팬을 유지합니다.
4. 재시작 후 60초 안에 정상 기동 마커(`/opt/arc100/health/boot_ok`)가 없으면 이전 버전으로 자동 롤백합니다.

## 7. 릴리스 패키지 규격 (빌드 담당자용)

```
arc100-hmi-linux-arm64-v1.2.0.tar.gz
├── manifest.json        {"version":"1.2.0","min_from":"1.0.0","notes":"...","built":"2026-09-15T12:00:00+09:00"}
└── bundle/              flutter build linux --release 의 bundle 폴더 그대로
    ├── arc100_hmi       실행 파일
    ├── lib/             libflutter_linux_gtk.so, libserialport.so 등
    └── data/
arc100-hmi-linux-arm64-v1.2.0.tar.gz.sha256   (sha256sum 출력 형식)
```

Release 태그는 `vX.Y.Z`. 자산 이름 패턴 `arc100-hmi-linux-arm64-*.tar.gz`가 아니면 설치 스크립트가 찾지 못합니다.

## 8. 문제 해결

| 증상 | 확인 |
|---|---|
| 부팅 후 화면이 바탕화면만 보임 | `arc100-status` → `current` 링크가 있는지, `journalctl --user -u arc100-hmi -n 50` |
| `arc100-status` 에 서비스가 **masked** / 유닛 파일 0바이트 | 전원 급차단 뒤 SD 카드에 유닛 파일이 비어 남은 경우. `sudo arc100-guard` 로 복구(재부팅 시 자동). 앱 업데이트는 이 파일을 건드리지 않음 |
| 앱이 켜졌다 꺼졌다 반복 | 헬스체크가 3회 실패 후 롤백합니다. 로그로 원인 확인 후 `arc100-fetch-release --activate` 재시도 |
| 포트 열기 실패 (Permission denied) | 사용자가 `dialout` 그룹인지 (`groups`). 설치 후 **재로그인/재부팅** 필요 |
| `/dev/rs485-*`가 없음 | 3장의 udev 규칙. `arc100-list-serial`로 값 재확인 |
| HM-100 무응답 | 출고 보레이트가 19200인 개체가 있습니다. `site.json`의 `baud`를 19200으로 바꿔 시험 |
| IOC-100 무응답 | IOC 는 ID·GWID·체크섬이 하나라도 다르면 **침묵**합니다. 장치 방번호 **1-1** = GWID 1 · ID 1 → `site.json` `ioc[]` 는 `{ "id": 1, "gwid": 1 }`. 예전 `gwid: 0` 은 앱이 자동으로 1 로 고쳐 저장 (프로토콜 V2.0: 상태 150 B, 설정 31 B) |
| 인버터 지령이 반영되지 않음 | 인버터 `drv=3`, `Frq=6`(Int 485), `CM.01` 국번 21/22/23, `CM.03=3`(9600), `CM.04=0`(8N1) |
| 터치가 안 됨 / 전체화면이 안 됨 | Wayland(labwc) 문제일 수 있음. `sudo raspi-config` → Advanced Options → Wayland → **X11** 로 전환 후 재부팅 |

## 9. 저장소 구성

```
bootstrap.sh              curl 한 줄 설치 진입점
install.sh                본 설치 스크립트
uninstall.sh              제거
scripts/
  arc100-fetch-release.sh   Releases 다운로드·sha256 검증·설치
  arc100-apply-update.sh    current 링크 교체·재시작·헬스 대기·실패 시 롤백
  arc100-rollback.sh        직전 버전 복귀
  arc100-healthcheck.sh     2분 타이머, crash-loop 시 자동 롤백
  arc100-run.sh             디스플레이 준비 대기 후 앱 실행 (systemd ExecStart)
  arc100-list-serial.sh     USB-RS485 식별 정보 출력
  arc100-status.sh          상태 요약
config/
  arc100-hmi.service        systemd 사용자 서비스 (부팅 자동 시작)
  arc100-healthcheck.service / .timer
  99-arc100-rs485.rules     udev 템플릿
  site.example.json         설정 초기값
```

---
㈜아이온텍 (IONTEC Co., Ltd.) · ARC-100 Air Recycle Controller
