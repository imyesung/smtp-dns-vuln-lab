# SMTP & DNS Vulnerability Lab
**메일 취약점 실험 자동화**: 오픈 릴레이 `공격→하드닝→재검증` 사이클을 Docker로 완전 격리, `make demo` 한 번에 실행

> **[중요 주의사항]**  
> **본 프로젝트는 오직 보안 연구 및 교육 목적에 한하여 사용해야 합니다.**  
> 외부 네트워크나 실제 운영 환경에서 실험을 수행하지 마십시오.  
> 모든 컨테이너는 격리된 로컬 Docker 네트워크 내에서만 실행되어야 합니다.  
> 작성자는 코드 오용 또는 남용에 따른 어떠한 책임도 지지 않습니다.

---

_*이 레포지토리는 보안 실험 환경 자체를 설계하고 자동화하는 데 중점을 둡니다. 공격 코드보다 실험 흐름과 재현 가능한 구조에 집중하며, 현재도 계속 작업 중입니다._

**구현 완료된 주요 기능**
- **Docker 인프라**: Postfix + DNSMasq + MUA + Controller 컨테이너 환경
- **5개 보안 공격 스크립트**: STARTTLS 다운그레이드, 오픈 릴레이, DNS 재귀, DANE/MTA-STS, 인증 공격
- **패킷 캡처 & 분석**: tcpdump/tshark 기반 네트워크 트래픽 분석
- **자동화된 보안 강화**: Postfix 설정 자동화 및 백업/복원 메커니즘
- **종합 리포트 생성**: HTML 기반 before/after 비교 분석 보고서
- **완전 자동화**: `make comprehensive-test`로 전체 워크플로우 실행
- **구조화된 로깅**: NDJSON 형식 로그 및 상세 분석 데이터
- **CVSS 3.1 위험도 평가**: 자동화된 보안 점수 산정 시스템
- **SMTP 응답 분석**: 응답 코드별 상세 분류 및 보안 패턴 분석

**향후 개선 계획**
- 시각적 시퀀스 다이어그램 (Mermaid) 자동 생성
- 위협 모델링 다이어그램 및 ATT&CK 프레임워크 매핑
- SMTP Fuzzer 통합 (취약점 자동 발견)

## Objectives
- Docker(Debian base) 환경으로 이메일 스택(Postfix + DNSMasq)을 구성한다.  
- SMTP → 전송 → 수신 → 열람까지 전 과정을 패킷 레벨로 관찰한다.  
- 오픈 릴레이‧SPF 스푸핑‧DNS 재귀 질의 등 대표 취약점을 실험한다.  
- **취약점 공격 → 패치 적용 → 재공격 → 결과 분석** 과정을 자동화한다.  
- 자동 생성된 HTML(추후 PDF) 리포트로 문서화한다.

## Assumptions
- 이메일 시스템 배경지식이 없어도 따라 할 수 있도록 설계.  
- 실험은 반드시 **격리된 로컬 Docker 네트워크**에서만 진행한다.  
- 외부 인터넷과 단절된 환경으로 가정한다.  
- 사용되는 도메인·메일 주소·IP는 전부 가상 값이다.

## Directory Layout

| 경로 / 파일           | 설명                                           |
|-----------------------|-----------------------------------------------|
| `README.md`           | 개요 및 사용법                                 |
| `lab-notebook.md`     | 단계별 실험 로그/메모                          |
| `docker-compose.yml`  | **경량** 실험 환경 (3 컨테이너)                |
| `docker-compose.full.yml` | 포트 매핑 포함 **심화** 환경               |
| `Makefile`            | `make demo`, `make report` 등 자동화 진입점    |
| `scripts/`            | 공격·패치·리포트 자동화 스크립트              |
| `configs/`            | Postfix / DNSMasq 템플릿                       |
| `artifacts/`          | 로그·pcap·HTML 보고서 저장 (git-ignored)       |

## Quick Start
```bash
# Turn-Key 자동화 보안 평가 (권장)
make security-assessment
├─ 환경 검증 & 컨테이너 시작
├─ 5개 보안 공격 실행 (패킷 캡처)
├─ Postfix 보안 강화 적용
├─ 동일 공격 재실행 (효과 검증)
├─ CVSS 3.1 위험도 평가
├─ SMTP 응답 패턴 분석
└─ 종합 분석 리포트 생성 → artifacts/

# 개별 기능 실행
make status                  # 현재 상태 확인
make comprehensive-test      # 기본 종합 테스트
make cvss-analysis          # CVSS 위험도 평가
make smtp-response-analysis # SMTP 응답 분석
make attack-all             # 모든 공격 스크립트 실행
make harden                 # Postfix 보안 강화
```

## 주요 명령어
```bash
# 경량(기본) 실험
make demo          # 워크플로우 Turn-key 실행
make report        # 보고서 생성

# Postfix 하드닝/복구 수동 실행
make postfix-harden    # main.cf 보안 옵션 적용 및 postfix reload
make postfix-restore   # main.cf 원본 복구 및 postfix reload

# 심화 환경(포트 매핑 포함)
make full          # docker-compose.full.yml 사용

# 세부 단계 직접 실행
make test-vulnerabilities   # 공격
make secure-and-verify      # 패치 + 재공격
```

## Network Topology

| 네트워크 | 목적                           | 구성 방식            |
|----------|------------------------------|---------------------|
| smtp-net | Postfix 서버 & MUA 컨테이너   | 격리 Docker 네트워크 |
| dns-net  | DNSMasq(SPF, 재귀 질의 실험)  | 격리 Docker 네트워크 |

## 실험 항목

| 주제                    | 확인 내용                                             |
|-------------------------|-------------------------------------------------------|
| 오픈 릴레이             | 인증 없이 릴레이 가능한지 → `harden_postfix.sh`로 차단 |
| SPF 스푸핑              | 약한 SPF( ~all ) → 위조 메일 시도                     |
| STARTTLS 미지원         | 평문 인증 전송 노출 여부                              |
| DNS 재귀 질의           | 재귀 질의 허용 시 증폭 공격 가능성                    |

## 자동 보고서
- `scripts/gen_report_html.sh` → `artifacts/demo-<ts>.html` 저장  
- 템플릿: lightweight Bulma + highlight.js  
- PDF 변환은 TinyTeX 기반(예정)

## 보안 및 공개 가이드라인
- **로컬 Docker** 이외 환경에서 실행 금지
- 공격 스크립트는 **방어 효과 검증** 용도이며, 실무 시스템 대상 사용 금지
- 본 프로젝트로 발생한 법적·윤리적 문제는 전적으로 사용자 책임입니다.
