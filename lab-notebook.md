# Docker 기반 이메일 서버 취약점 실험 및 분석

## 프로젝트 개요

### 전체 목표

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
- **mua-alpine**: 클라이언트 테스트용

**데모 흐름 최적화**:
  - mail-postfix 컨테이너에서 취약 설정 → 패치 → 재검증 흐름 구현
  - mua-alpine 컨테이너에서 공격 시뮬레이션
  - 결과 비교 및 HTML 리포트 자동 생성


## Part 1: Docker 기초 압축

### 1. Docker 기초 개념

**Docker는 왜 필요한가? 컨테이너와 VM의 핵심 차이는 무엇인가?**

- [x] Docker 기본 아키텍처 스터디

### 2. Docker 명령어 실습

**Docker에서 컨테이너를 생성하고 관리하는 기본 명령어는 무엇인가?**

- [x] `docker ps, run, stop, rm, images` 명령어 실습

### 3. Docker Compose 기본 구조

**여러 컨테이너를 관리할 때 Docker Compose는 어떻게 동작하는가?**

- [x] 간단한 docker-compose.yml 구조 파악
- [x] `docker-compose up`, `docker-compose down` 명령어 실습

## Part 2: 이메일 서버 기초 심화

### 4. 이메일 시스템 기본 구조

**MTA, MDA, MUA는 각각 무엇이며, 어떤 역할을 하는가?**

- [x] 송신, 수신, 사용자 에이전트 흐름을 개념도와 함께 정리

### 5. SMTP 프로토콜 기초

**SMTP는 어떤 구조로 메일을 전송하는가? 주요 명령어는 무엇인가?**

- [ ] SMTP 명령어(HELO, MAIL FROM, RCPT TO, DATA) 학습
- [ ] telnet을 이용한 SMTP 명령어 실습

### 6. POP3와 IMAP 프로토콜 비교

**POP3와 IMAP은 어떤 차이가 있으며, 각각의 장단점은 무엇인가?**

- [ ] 두 프로토콜의 특징 비교
- [ ] 사용 포트(110, 143) 정리
- [ ] 각 프로토콜의 사용 흐름 정리

### 7. 이메일 서버 포트 번호 체계

**SMTP, SMTPS, Submission, POP3, IMAPS 등 각 프로토콜은 어떤 포트를 사용하는가?**

- [ ] 포트 번호 정리 (25, 465, 587, 110, 995, 143, 993)
- [ ] 각 포트별 용도와 보안 특성 표로 정리

### 8. 이메일 서버 통신 흐름 전체 요약

**메일이 송신되고 수신되기까지 전체 과정은 어떻게 흐르는가?**

- [x] 송신자 → SMTP 서버 → 수신자 메일 서버 → POP3/IMAP 사용자 흐름 요약

### 9. Postfix 기본 개념 심화

**Postfix는 SMTP 서버로서 어떤 내부 구조를 가지는가?**

- [ ] Postfix 프로세스(Postfix master, smtpd, pickup, qmgr 등) 흐름 정리

### 10. Postfix 주요 설정 파일(main.cf) 구조

**main.cf 파일에서 가장 중요한 설정 항목은 무엇인가?**
- [ ] `myhostname` 항목 분석
- [ ] `mydomain` 항목 분석
- [ ] `myorigin` 항목 분석
- [ ] `mydestination` 항목 분석
- [ ] `relayhost` 항목 분석
- [ ] `smtpd_recipient_restrictions` 항목 분석

### 11. DNSMasq 기본 개념 및 이메일 서버와의 관계

**DNSMasq는 왜 필요하며, 이메일 서버와 어떤 관계가 있는가?**

- [ ] DNSMasq의 DNS 재귀 질의 기능 학습
- [ ] SPF 레코드 질의와의 연관성 정리

## Part 3: 실험 환경 구축

### 12. 현재 컨테이너 구성 파악 및 최적화

**기존 컨테이너 환경을 효율적으로 활용하는 방법은?**

- [x] 현재 docker-compose.yml 분석
- [ ] 각 컨테이너 역할 명확화
  - mail-postfix: SMTP 서버 (취약점 테스트 대상)
  - dns-dnsmasq: DNS 서버 (SPF 레코드 및 재귀 질의 테스트)
  - mua-alpine: 클라이언트 (공격 스크립트 실행 환경)

### 13. 자동화 스크립트 개발

**취약점 공격 및 패치 프로세스를 자동화하는 방법은?**

- [ ] `attack_openrelay.sh` 스크립트 작성 (mua-alpine 컨테이너 내 실행)
  - swaks 설치 및 설정
  - 인증 없는 메일 전송
  - 로그 자동 수집 (artifacts/before.log)

- [ ] `harden_postfix.sh` 스크립트 작성 (mail-postfix 컨테이너 내 실행)
  - postconf로 설정 변경
  - Postfix 재로드 명령

- [ ] `gen_report_html.sh` 스크립트 작성 (호스트 시스템에서 실행)
  - 순수 HTML 형식의 보고서 생성
  - diff를 통한 로그 비교 자동화

### 14. 통합 데모 흐름 구성

**30초 안에 전체 공격→패치→검증 흐름을 실행하는 Makefile 구성 방법은?**

- [ ] `make demo` 명령 구현
  ```
  make demo
  └─ ① docker compose에서 이미 실행 중인 컨테이너 활용
  └─ ② docker exec mua-alpine bash /scripts/attack_openrelay.sh
     ├─ Alpine 컨테이너에서 swaks로 인증 없는 메일 전송
     └─ 로그 → artifacts/before.log
  └─ ③ docker exec mail-postfix bash /scripts/harden_postfix.sh
     ├─ postconf -e 'smtpd_recipient_restrictions = reject_unauth_destination'
     └─ postfix reload
  └─ ④ docker exec mua-alpine bash /scripts/attack_openrelay.sh  # 재검증
     └─ 로그 → artifacts/after.log
  └─ ⑤ bash scripts/gen_report_html.sh   # HTML 리포트 생성·열람
  ```

### 15. SMTP 서버 초기 설정 확인

**취약점 테스트를 위한 Postfix 초기 설정은 어떻게 해야 하는가?**

- [x] mail-postfix 컨테이너 로그 점검
- [ ] SMTP 포트 개방 상태 확인
- [ ] 오픈 릴레이 초기 상태 검증

### 16. DNS 서버 설정

**이메일 취약점 테스트를 위한 DNSMasq 구성 방법은?**

- [ ] SPF 레코드 설정 (약한 SPF 설정 ~all)
- [ ] 재귀 질의 허용 설정
- [ ] 도메인 설정 (mail.local → mail-postfix 컨테이너)

### 17. 클라이언트 테스트 환경 구성

**mua-alpine 컨테이너에서 공격 테스트를 수행하기 위한 설정은?**

- [ ] swaks 설치
- [ ] 테스트 스크립트 복사
- [ ] 결과 저장 디렉토리 설정

## Part 4: 우선순위 실험 및 분석

### 18. 오픈 릴레이 취약 구성 및 이해

**오픈 릴레이는 어떻게 구성되고, SMTP relay control 구조는 무엇인가?**

- [ ] `smtpd_recipient_restrictions` 설정을 `permit_mynetworks`로 구성
- [ ] 오픈 릴레이 상태 자동 검증

### 19. 오픈 릴레이 악용 가능성 실험

**인증 없이 메일 릴레이가 가능한지 어떻게 실험하는가?**

- [ ] mua-alpine에서 swaks로 인증 없는 외부 도메인 메일 전송
- [ ] 릴레이 성공 여부 확인
- [ ] 자동화된 결과 기록

### 20. 오픈 릴레이 보안 강화 및 검증

**smtpd_recipient_restrictions를 안전하게 구성하려면 어떻게 해야 하는가?**

- [ ] `reject_unauth_destination` 설정 적용
- [ ] postfix reload로 설정 적용
- [ ] 동일 공격 재시도 및 차단 확인

### 21. SPF 레코드 약화 설정 및 실험 (2순위)

**약한 SPF(~all) 레코드는 어떤 식으로 스푸핑 공격을 가능하게 하는가?**

- [ ] dns-dnsmasq에서 약한 SPF 레코드 설정
- [ ] 외부 도메인 스푸핑 테스트
- [ ] 수신 측 SPF 검증 과정 분석

### 22. STARTTLS 미지원 환경 구성 및 실험 (2순위)

**STARTTLS 없이 SMTP 인증을 시도하면 어떤 위험이 발생하는가?**

- [ ] mail-postfix에서 STARTTLS 미사용 설정
- [ ] 평문 인증 패킷 확인
- [ ] tcpdump로 패킷 캡처 분석

### 23. DNS 재귀 질의 취약 구성 및 이해 (3순위)

**DNS 재귀 허용이 공격 벡터로 작동하는 구조는 무엇인가?**

- [ ] dns-dnsmasq에서 재귀 질의 허용 설정 적용
- [ ] 재귀 질의 테스트
- [ ] 증폭 공격 가능성 분석

## Part 5: 보고서 생성 및 최종 정리

### 24. HTML 리포트 파이프라인 구현

**경량 HTML 보고서 자동 생성 방법은?**

- [ ] `gen_report_html.sh` 스크립트 완성
  - 환경 정보 자동 수집
  - 로그 diff 자동 생성
  - 스타일이 적용된 HTML 보고서 생성
  - 브라우저 자동 열기

### 25. CI/CD 최적화 전략

**GitHub Actions 등 CI 환경에서 실험을 효율적으로 실행하는 방법은?**

- [ ] docker-compose 최적화
  ```yaml
  # docker-compose.ci.yml 예시
  version: "3.9"
  services:
    mail-postfix:
      image: boky/postfix:alpine
    # 나머지 설정...
  ```
- [ ] 이미지 캐싱 전략 (`docker pull` 선행)
- [ ] 아티팩트 최소화 (`artifacts/*.html`만 업로드)
- [ ] timeout 최적화 (15분 → 5분)

### 26. 종합 취약점 리스크 매핑

**발견된 취약점들을 위협모델링 관점에서 어떻게 정리할 수 있는가?**

- [ ] 취약점별 공격 시나리오 정리
- [ ] 각 취약점의 영향 분석
- [ ] 취약점별 대응 방안 표로 구성

### 27. 최종 정리 및 개인 메모 작성

**이번 실험을 통해 얻은 가장 중요한 교훈은 무엇인가?**

- [ ] 개인 메모로 실험 소회 정리
- [ ] 향후 개선 방향 제안
- [ ] 학습 자료 및 참고 문헌 정리

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