# Docker 기반 이메일 서버 취약점 실험 및 분석

>  이론 학습 참고<br> https://publish.obsidian.md/imyesung/smtp-dns-vuln-lab/index

## 프로젝트 개요
- Docker 환경을 기반으로 실험용 이메일 서버(Postfix, DNSMasq 등)를 구축한다.
- 이메일 서버 작동 원리를 SMTP, POP3, IMAP 수준까지 기초부터 정확히 이해한다.
- 구조적 취약점을 직접 실험하고, 공격 시나리오를 구성하며, 대응 방법까지 탐구한다.
- 실험 과정과 결과를 종합하여 '이메일 서버 취약점 분석 보고서'를 작성하는 것을 최종 목표로 한다.

### 기본 전제

- 이메일 서버 시스템에 대한 이해가 없는 초보자 관점에서 실험을 진행한다.
- 실험은 로컬 Docker 네트워크 내에서만 이루어진다.
- 외부 인터넷과 격리된 환경에서 모든 테스트를 수행한다.

### 현재 실험 환경
- **mail-postfix**: 메일 서버
- **dns-dnsmasq**: DNS 서버
- **mua-debian**: 클라이언트 테스트용

**데모 흐름 최적화**:
  - mail-postfix 컨테이너에서 취약 설정 → 패치 → 재검증 흐름 구현
  - mua-debian 컨테이너에서 공격 시뮬레이션
  - 결과 비교 및 HTML 리포트 자동 생성

## Core Tasks

### 1단계: 실험 환경 및 기본 흐름 준비

| 번호 | 항목 | 상태 | 근거 | 커밋/목적 |
|------|------|------|------|------------|
| 1 | 실험 목표 및 자동화 흐름 정의 | 완료 | README.md, lab-notebook.md | 1461927: docs: 실험 방향 리디자인 |
| 2 | 격리된 Docker 네트워크 구성 | 완료 | docker-compose.yml, 3개 네트워크 | e723f45: feat: 이메일 서버 네트워크 분리 |
| 3 | 기본 메일 전송 스크립트 작성 | 완료 | sendmail.sh, fetchmail.sh | b02a912: feat: 기본 메일 전송 스크립트 |
| 4 | 데모 자동화 구조 설계 | 완료 | Makefile, Mermaid.js 포함 | 1461927: docs: 실험 방향 리디자인 |
| 5 | HTML 리포트 생성 스크립트 초안 | 완료 | gen_report_html.sh 초안 | d4e7f29: feat: 리포트 생성 초안 |
| 6 | Docker 네트워크 3분할 구성 | 완료 | CIDR 기반 분리 확인 | e723f45: 네트워크 분할 |
| 7 | attack_openrelay.sh 작성 및 실행 | 완료 | swaks로 인증 없는 메일 전송 | 98a71b2: feat: 오픈릴레이 공격 스크립트 |

---

### 2단계: 패킷 기반 증명 및 자동화

| 번호 | 항목 | 상태 | 작업 내용 | 실험 벡터 |
|------|------|------|-----------|------------|
| 7-1 | SMTP 패킷 캡처 스크립트 작성 | 진행 중 | `capture_smtp.sh` 작성 (tcpdump 포트 25, 465, 587) | SMTP 프로토콜 분석 |
| 7-2 | 공격 전/후 자동 패킷 수집 | 진행 중 | 관리 서버→클라이언트 실행 구조 | 자동화 파이프라인 |
| 7-3 | SMTP 패킷 분석 스크립트 | 진행 중 | `analyze_pcap.sh` (SMTP 명령어 추출) | 프로토콜 취약점 분석 |

---

### 3단계: 보안 강화 및 검증

| 번호 | 항목 | 상태 | 작업 내용 | 실험 벡터 |
|------|------|------|-----------|------------|
| 8 | Postfix 설정 강화 스크립트 | 진행 중 | `harden_postfix.sh` (postconf 명령어) | 보안 강화 자동화 |
| 8-1 | smtpd_relay_restrictions 설정 | 계획됨 | 릴레이 제한 설정 | 릴레이 제한 |
| 8-2 | mynetworks 제한 설정 | 계획됨 | CIDR 기반 제한 설정 | 네트워크 접근 제어 |
| 8-3 | smtpd_recipient_restrictions 설정 | 계획됨 | 수신자 기반 제한 설정 | 수신자 검증 강화 |
| 8-4 | smtpd_helo_restrictions 설정 | 계획됨 | HELO 명령어 검증 설정 | HELO 스푸핑 방지 |
| 8-5 | 보안 설정 백업 메커니즘 | 계획됨 | 설정 파일 자동 백업 | 설정 버전 관리 |
| 9 | 보안 강화 후 재공격 테스트 | 진행 중 | before/after 로그 비교 | 대응 효과 검증 |

---

### 4단계: 리포트 및 정량화

| 번호 | 항목 | 상태 | 작업 내용 | 실험 벡터 |
|------|------|------|-----------|------------|
| 10 | 리포트 자동화 확장 | 진행 중 | `gen_report_html.sh` 확장 | 결과 시각화 자동화 |
| 10-1 | CVSS 점수 산정 로직 추가 | 계획됨 | 취약점 심각도 평가 | 위험도 평가 |
| 10-2 | 보안 개선 효과 계량화 | 계획됨 | 공격 성공률 계량화 | 개선 효과 측정 |

---

### 5단계: 정리 및 확장 계획

| 번호 | 항목 | 상태 | 작업 내용 | 실험 벡터 |
|------|------|------|-----------|------------|
| 11 | artifacts 폴더 정리 및 결과 백업 | 진행 중 | 로그/pcap/리포트 백업 구조 | 결과물 관리 |
| 12 | 타임스탬프 기반 로그 백업 | 계획됨 | 덮어쓰기 방지 메커니즘 | 결과 추적성 확보 |
| 13 | Makefile 타깃 세분화 | 계획됨 | demo-before/after/report 구조 | 실행 흐름 자동화 |
| 14 | 위협모델 기반 종합 정리 | 계획됨 | Mermaid.js 위협 구조도 | 보안 모델링 |
| 19 | main.cf 설정 변경 diff 리포트 | 계획됨 | diff 기반 설정 변경 시각화 | 구성 변경 추적 |
| 20 | SMTP 상호작용 시각화 | 계획됨 | 프로토콜 시퀀스 다이어그램 | 취약점 시각화 |
| 21 | 공격 실패 메시지 유형 분류 | 계획됨 | 응답 코드별 카테고리화 | 보안 효과 분석 |

---

### 6단계: 후순위 실험 계획

| 번호 | 항목 | 상태 | 필요 작업 | 실험 벡터 |
|------|------|------|-----------|------------|
| 15 | DNS 재귀 질의 실험 | 향후 계획 | dnsmasq.conf 설정 필요 | DNS 취약점 |
| 16 | SPF 위조 실험 | 향후 계획 | DNS TXT 레코드 조작 필요 | 이메일 스푸핑 |
| 17 | STARTTLS 캡처 실험 | 향후 계획 | openssl/tcpdump 활용 예정 | 암호화 분석 |
| 18 | SMTP 로그 기반 탐지 흐름 | 향후 계획 | mail.log 패턴 추출 및 탐지 | 이상 행위 탐지 |
| 22 | 메일 헤더 위조 실험 항목 추가 | 향후 계획 | From 헤더 위변조 검증 | 기밀성 우회 실험 |
| 23 | 테스트 메일 로그 수신 여부 확인 | 향후 계획 | MTA 로그 기반 검증 | 전송 완료성 검증 |

## 부록: 개선된 데모 흐름

```
make demo
└─ ① 기존 컨테이너 활용 (mail-postfix, dns-dnsmasq, mua-alpine)
└─ ② 필요한 도구 설치 (swaks, tcpdump 등)
   └─ docker exec mua-alpine apk add --no-cache swaks
   └─ docker exec mail-postfix apk add --no-cache tcpdump
└─ ③ 공격 스크립트 복사 및 실행
   └─ docker cp scripts/attack_openrelay.sh mua-alpine:/tmp/
   └─ docker exec mua-alpine bash /tmp/attack_openrelay.sh /tmp/before.log
└─ ④ 보안 강화 스크립트 실행
   └─ docker cp scripts/harden_postfix.sh mail-postfix:/tmp/
   └─ docker exec mail-postfix bash /tmp/harden_postfix.sh
└─ ⑤ 공격 재시도 및 결과 검증
   └─ docker exec mua-alpine bash /tmp/attack_openrelay.sh /tmp/after.log
└─ ⑥ 결과 파일 호스트로 복사
   └─ docker cp mua-alpine:/tmp/before.log artifacts/
   └─ docker cp mua-alpine:/tmp/after.log artifacts/
└─ ⑦ HTML 리포트 생성
   └─ bash scripts/gen_report_html.sh
```

## 실험 우선순위 정리

| 우선순위 | 실험 항목 | 설명 |
|---------|----------|------|
| 1순위 | 오픈 릴레이 ▶ 패치 흐름 완성 | 기본 데모의 핵심, 30초 실행 목표 |
| 2순위 | SPF 약화·스푸핑 데모 | 이메일 공격의 대표적 사례 |
| 2순위 | STARTTLS 평문 인증 캡처 | 암호화 부재의 위험성 시각화 |
| 3순위 | DNS 재귀·증폭 실험 | DNS 계층 취약점 이해 |
| 3순위 | CI 배지·상태 대시보드 | 지속적 통합 최적화 |

## 핵심 스크립트 예시

### HTML 리포트 생성 스크립트

```bash
#!/usr/bin/env bash
# scripts/gen_report_html.sh
ts=$(date -u +%Y%m%d-%H%M%S)
report=artifacts/demo-$ts.html

# 디렉토리 생성
mkdir -p artifacts

cat > "$report" <<EOF
<!DOCTYPE html>
<html lang="en"><meta charset="utf-8">
<title>SMTP-DNS Lab Report $ts</title>
<style>
body{font-family:monospace;background:#fafafa;margin:2rem;}
h1{font-size:1.4rem;border-bottom:1px solid #555;}
pre{background:#eee;padding:1rem;border-radius:5px;}
</style>
<h1>Environment</h1>
<pre>$(docker compose ps --format table)</pre>

<h1>Log diff</h1>
<pre>$(diff -u artifacts/before.log artifacts/after.log)</pre>

<h1>Verdict</h1>
<p><b>Fix ✔</b></p>
</html>
EOF

xdg-open "$report" 2>/dev/null || open "$report"
```

### Makefile 예시

```makefile
# Makefile
.PHONY: demo clean setup

demo: setup attack-before patch attack-after report

setup:
	@echo "=== Setting up test environment ==="
	docker exec mua-alpine apk add --no-cache swaks
	mkdir -p artifacts

attack-before:
	@echo "=== Running attack before hardening ==="
	docker cp scripts/attack_openrelay.sh mua-alpine:/tmp/
	docker exec mua-alpine bash /tmp/attack_openrelay.sh /tmp/before.log
	docker cp mua-alpine:/tmp/before.log artifacts/

patch:
	@echo "=== Applying security patch ==="
	docker cp scripts/harden_postfix.sh mail-postfix:/tmp/
	docker exec mail-postfix bash /tmp/harden_postfix.sh

attack-after:
	@echo "=== Running attack after hardening ==="
	docker exec mua-alpine bash /tmp/attack_openrelay.sh /tmp/after.log
	docker cp mua-alpine:/tmp/after.log artifacts/

report:
	@echo "=== Generating HTML report ==="
	bash scripts/gen_report_html.sh

clean:
	@echo "=== Cleaning up ==="
	rm -rf artifacts/*.log artifacts/*.html
```