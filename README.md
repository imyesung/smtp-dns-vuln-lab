# SMTP & DNS Vulnerability Lab

> **[주의] 본 프로젝트는 보안 연구 및 교육 목적에 한하여 사용해야 합니다.**  
> 외부 네트워크나 실제 운영 환경에서 실험을 수행하지 마십시오.  
> 모든 컨테이너는 로컬 Docker 네트워크 안에 격리되어야 하며,  
> 작성자는 코드 오·남용에 따른 책임을 지지 않습니다.

_*이 레포지토리는 보안 실험 환경 자체를 설계하고 자동화하는 데 중점을 둡니다. 공격 코드보다 실험 흐름과 재현 가능한 구조에 집중하며, 현재도 계속 작업 중입니다._

## !WORK IN PROGRESS!
**구현 완료**
- Docker 기반 Postfix + DNSMasq + MUA 인프라 자동 구성
- 오픈 릴레이 실험 자동화 및 보안 강화 적용
- 실험 전후 결과 비교 리포트(HTML) 자동 생성
- 컨테이너 상태 체크, 스크립트 실행 흐름 자동화(Makefile)

**예정 작업**
- SPF 스푸핑, DNS 재귀 질의 실험 스크립트 완성
- STARTTLS 캡슐화 우회 실험 고도화

## Objectives
- Docker(Debian base) 환경으로 이메일 스택(Postfix + DNSMasq)을 구성한다.  
- SMTP → 전송 → 수신 → 열람까지 전 과정을 패킷 레벨로 관찰한다.  
- 오픈 릴레이‧SPF 스푸핑‧DNS 재귀 질의 등 대표 취약점을 실험한다.  
- **취약점 공격 → 패치 적용 → 재공격 → 결과 분석** 과정을 자동화한다.  
- 자동 생성된 HTML(추후 PDF) 리포트로 문서화한다.

## Assumptions
- 이메일 시스템 배경지식이 없어도 따라 할 수 있도록 설계.  
- 실험은 반드시 **로컬 Docker 네트워크**에서만 진행한다.  
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

## Quick Demo
```
make demo
├─ mua-debian  : 인증 없는 메일 전송(공격)
├─ mail-postfix: 설정 변경(보안 강화)
└─ mua-debian  : 동일 공격 재시도 & 결과 캡처
     ↳ before / after 비교 → HTML 리포트
```

## 주요 명령어
```bash
# 경량(기본) 실험
make demo          # 전체 흐름 1-클릭 실행
make report        # 보고서만 재생성

# Postfix 하드닝/복구 수동 실행
make postfix-harden    # main.cf에 보안 옵션 적용 및 postfix reload
make postfix-restore   # main.cf 원본 복구 및 postfix reload

# 심화 환경(포트 매핑 포함)
make full          # docker-compose.full.yml 사용

# 세부 단계 직접 실행
make test-vulnerabilities   # 공격만
make secure-and-verify      # 패치 + 재공격
```

## Network Topology

| 네트워크 | 목적                           | CIDR          |
|----------|------------------------------|---------------|
| smtp-net | Postfix 서버 & MUA 컨테이너   | 172.30.0.0/24 |
| dns-net  | DNSMasq(SPF, 재귀 질의 실험)  | 172.30.1.0/24 |

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
- PDF 변환은 TinyTeX 기반 기능으로 예정

## 보안 및 공개 가이드라인
- **로컬 Docker** 이외 환경에서 실행 금지.  
- 공격 스크립트는 **방어 효과 검증** 용도이며, 실무 시스템 대상 사용 금지.  
- 본 프로젝트로 발생한 법적·윤리적 문제는 전적으로 사용자 책임.
