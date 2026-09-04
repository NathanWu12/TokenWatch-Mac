# TokenWatch Mac

**가볍고 낮은 자원 사용량으로 상시 실행에 적합한 macOS 네이티브 AI 사용량 / 쿼터 허브입니다.** Codex, Claude Code, Antigravity, OpenCode의 표준 로컬 데이터를 읽기 전용으로 자동 탐지하고 오늘 / 7일 / 30일 / 누적 사용량, 모델·프로젝트 추세, 쿼터를 한곳에 표시합니다.

[English](README.md) · [简体中文](README.zh-CN.md) · [繁體中文](README.zh-TW.md) · [日本語](README.ja.md) · **한국어** · [Français](README.fr.md) · [Español](README.es.md)

## 상시 실행을 위한 설계

Codex 영구 증분 인덱스는 새로 추가된 바이트만 읽고 FSEvents가 허용된 Provider 디렉터리 변경을 감지합니다. 동시 수집 수를 제한하고 의미 없는 디스크 / LAN / CloudKit 쓰기를 건너뛰며, 원격 동기화는 latest-wins 방식으로 오래된 스냅샷 대기열을 만들지 않습니다. Swift / SwiftUI 네이티브 구현으로 내장 브라우저 런타임이나 상시 로컬 웹 서버가 필요하지 않습니다.

### 참고 성능

약 **810 MB의 Codex 기록**을 사용한 참고 측정: 콜드 수집 **3.23초 / 약 127 MiB**, 인덱스가 있는 증분 수집 **0.86초 / 약 34 MiB**, 변경 없음 **0.82초 / 약 34 MiB**. 이는 수집 / 내보내기 경로의 피크이며 앱의 상시 RSS와 동일하지 않습니다.

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
