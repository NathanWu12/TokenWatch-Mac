# TokenWatch Mac

**가볍고 낮은 자원 사용량으로 상시 실행에 적합한 macOS 네이티브 AI 사용량 / 쿼터 허브입니다.** Codex, Claude Code, Antigravity, OpenCode의 표준 로컬 데이터를 읽기 전용으로 자동 탐지하고 오늘 / 7일 / 30일 / 누적 사용량, 모델·프로젝트 추세, 쿼터를 한곳에 표시합니다.

[English](README.md) · [简体中文](README.zh-CN.md) · [繁體中文](README.zh-TW.md) · [日本語](README.ja.md) · **한국어** · [Français](README.fr.md) · [Español](README.es.md)

## 상시 실행을 위한 설계

Codex 영구 증분 인덱스는 새로 추가된 바이트만 읽고 FSEvents가 허용된 Provider 디렉터리 변경을 감지합니다. 동시 수집 수를 제한하고 의미 없는 디스크 / LAN / CloudKit 쓰기를 건너뛰며, 원격 동기화는 latest-wins 방식으로 오래된 스냅샷 대기열을 만들지 않습니다. Swift / SwiftUI 네이티브 구현으로 내장 브라우저 런타임이나 상시 로컬 웹 서버가 필요하지 않습니다.

### 참고 성능

약 **810 MB의 Codex 기록**을 사용한 참고 측정: 콜드 수집 **3.23초 / 약 127 MiB**, 인덱스가 있는 증분 수집 **0.86초 / 약 34 MiB**, 변경 없음 **0.82초 / 약 34 MiB**. 이는 수집 / 내보내기 경로의 피크이며 앱의 상시 RSS와 동일하지 않습니다.

## 작은 크기와 낮은 오버헤드는 구조에서 나옵니다

TokenWatch Mac은 **네이티브 Swift / SwiftUI / AppKit**으로 개발되며 macOS 시스템 Framework를 직접 사용합니다. 현재 Universal Release에는 **임베디드 Frameworks, Chromium, Electron, Node.js runtime이 없습니다**.

2026-09-05 실측: Universal DMG **5.3 MB**, 설치된 `.app` **약 11 MB**. 약 1.5시간 실행 후 유휴 상태에서 `top` MEM **약 45 MB**, 1초 간격 6회 연속 샘플에서 **CPU 0.0% / POWER 0.0**이었습니다. `ps` RSS는 공유 매핑을 포함해 **약 121 MiB**입니다. `POWER`는 `top`의 상대 지표이며 와트 측정값이 아닙니다.

현재 Apple M6 Mac mini 구성기(2026-09-05)에서 인접한 8 GB 통합 메모리 단계와 256→512 GB SSD 단계는 각각 **$200** 차이입니다. 단순 용량 등가로 보면 45 MB는 24 GB의 **약 0.19% / 약 $1.1 상당**, 11 MB 앱은 256 GB의 **약 0.004% / 약 $0.01 상당**입니다. 실제 하드웨어 원가를 의미하지 않습니다.

Electron v44.0.0 macOS arm64 runtime ZIP은 **약 123.7 MiB**입니다. TokenWatch의 5.3 MB Universal DMG는 Apple Silicon과 Intel 바이너리를 모두 포함하면서도 그 압축 runtime 자체보다 **약 23배 작습니다**. 이는 프레임워크 기준 비교이며 모든 비-Swift 앱이나 경쟁 앱이 무겁다는 뜻은 아닙니다.

Sources: [Apple M6 Mac mini](https://www.apple.com/newsroom/2026/08/apple-unveils-a-more-powerful-mac-mini-featuring-the-all-new-m6-and-m5-pro/) · [Apple configurator](https://www.apple.com/shop/buy-mac/mac-mini/m6-chip-12-core-cpu-12-core-gpu-24gb-memory-256gb-storage) · [Electron v44.0.0](https://github.com/electron/electron/releases/tag/v44.0.0) · [Electron process model](https://www.electronjs.org/docs/latest/tutorial/process-model)

## 스크린샷

<p align="center">
  <img src="docs/images/dashboard.webp" width="900" alt="TokenWatch Mac 대시보드">
</p>
<p align="center"><sub>사용량 요약, 프로젝트별 내역, 모델 분포 및 사용량 추세.</sub></p>

<p align="center">
  <img src="docs/images/menu-bar.webp" width="560" alt="TokenWatch Mac 메뉴 막대 팝오버">
</p>
<p align="center"><sub>기간별 사용량과 쿼터 창을 보여 주는 메뉴 막대 팝오버.</sub></p>

## 개인정보 보호

TokenWatch 스냅샷에는 프롬프트, 응답, 도구 인수, 전체 프로젝트 경로 또는 공급자 자격 증명을 저장하지 않습니다. CloudKit에는 사용자의 private database에 최신 종단 간 암호화 봉투만 저장합니다. 파일 탐색은 알려진 Provider 디렉터리로 제한됩니다.

## 설치

GitHub Releases에서 최신 DMG를 다운로드합니다.

현재 DMG는 Universal 빌드이며 ad-hoc 서명 상태로 notarization되지 않았습니다. macOS에서 Gatekeeper 경고가 표시될 수 있습니다. CloudKit 원격 동기화는 필요한 entitlement가 포함된 빌드에서만 사용할 수 있습니다.

## 빌드

요구 사항: macOS 14+, Xcode, Swift 6.1 toolchain.

```sh
Scripts/bootstrap
Scripts/verify
Scripts/build-mac-dmg
```

## 소스 코드

소스 코드는 투명성과 검토를 위해 공개되어 있습니다. 저장소의 라이선스 파일에 명시되지 않은 경우 오픈 소스 라이선스가 부여되지 않습니다.
