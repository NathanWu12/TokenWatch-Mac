# TokenWatch Mac

**가볍고 낮은 자원 사용량으로 상시 실행에 적합한 macOS 네이티브 AI 사용량 / 쿼터 허브입니다.** Codex, Claude Code, Antigravity, OpenCode의 표준 로컬 데이터를 읽기 전용으로 자동 탐지하며 오늘 / 7일 / 30일 / 누적 사용량, 모델·프로젝트 추세, 쿼터를 한곳에 표시합니다.

[English](README.md) · [简体中文](README.zh-CN.md) · [日本語](README.ja.md) · **한국어** · [Français](README.fr.md) · [Español](README.es.md)

## 항상 켜두기 위한 성능 설계

Codex 영구 증분 인덱스는 새로 추가된 바이트만 읽고, FSEvents가 허용된 공급자 경로 변경을 감지합니다. 동시 수집 수를 제한하고, 의미 없는 디스크/LAN/CloudKit 쓰기를 건너뛰며, 원격 동기화는 latest-wins 방식으로 오래된 스냅샷 대기열을 만들지 않습니다.

약 810 MB Codex 기록 기준 실측(2026-09-04): 콜드 수집 **3.23초 / 약 127 MiB**, 인덱스가 있는 증분 수집 **0.86초 / 약 34 MiB**, 변경 없음 **0.82초 / 약 34 MiB**. 이는 수집 경로의 피크이며 앱의 상시 RSS와 동일하지 않습니다.

## 개인정보 보호

prompt, response, 도구 인자, 전체 프로젝트 경로, 공급자 자격 증명을 TokenWatch 스냅샷에 저장하지 않습니다. CloudKit에는 사용자 private database의 최신 E2E 암호화 봉투만 저장합니다.

## 설치

GitHub Releases의 DMG를 사용하세요. 현재 Preview DMG는 ad-hoc 서명 및 미공증 상태이며 local-only entitlement를 사용하므로 CloudKit 원격 동기화는 비활성화됩니다. 안정 공개판은 Developer ID 서명과 notarization이 필요합니다.

```sh
Scripts/bootstrap
Scripts/verify
Scripts/build-mac-dmg
```

실제 대시보드 스크린샷은 stable release 전에 추가합니다. 명시적인 LICENSE가 없는 한 오픈소스 라이선스는 부여되지 않습니다.
