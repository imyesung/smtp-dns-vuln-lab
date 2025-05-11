# SMTP & DNS Vulnerability Lab – Progress Notebook
*Last updated: 2025-05-12*

<https://publish.obsidian.md/imyesung/smtp-dns-vuln-lab/index>

## 1. Project Objective
이메일 전송 인프라(`Postfix` + `DNSMasq`)를 **로컬 Docker** 환경에 재현하고, SMTP 오픈 릴레이 등 구조적 취약점을 실험·분석·대응한다.  
최종 산출물은 자동화된 **실험 파이프라인**과 **보안 강화 보고서**이다.

## 2. Scope & Assumptions
* 모든 실험은 로컬 Docker 네트워크에 한정한다.  
* SMTP·POP3·IMAP 중 **SMTP** 시나리오를 우선한다.  
* 외부 메일 서버나 실제 도메인 서비스와 연결하지 않는다.  
* 이메일 서버 시스템에 대한 이해가 없는 초보자 관점에서 실험을 진행한다.  

## 3. Current Lab Topology
| Container      | Role                                          |
| -------------- | --------------------------------------------- |
| `mail-postfix` | vulnerable SMTP server                        |
| `dns-dnsmasq`  | stub DNS server (future SPF tests)            |
| `mua-debian`   | client / attacker node                        |
| `controller`   | automation, packet capture (`NET_ADMIN`, `NET_RAW`)

## 4. Automated Demo Pipeline
```
[controller]
├─ attack_openrelay.sh ─▶ swaks ─▶ [mail-postfix]
│
├─ capture_smtp.sh ─▶ tcpdump ─▶ before.pcap / after.pcap
│
├─ analyze_pcap.sh ─▶ tshark  ─▶ smtp_summary.json
│
├─ harden_postfix.sh ─▶ postconf │ (backup ⇆ restore)
│
└─ gen_report_html.sh ─▶ report.html (before vs after)
```
## 5. Progress Tracker  

### Stage 1 ― 환경 구축 & 기준선 설정 (완료)
| # | Task                   | Status | Evidence/Notes                     |
|---|-----------------------|--------|------------------------------------|
| 1 | 목표·흐름 정의            | ✓      | `README.md`, `lab-notebook.md`     |
| 2 | Docker 네트워크 3분할      | ✓      | `docker-compose.yml`               |
| 3 | 기본 메일 송·수신 스크립트   | ✓      | `sendmail.sh`, `fetchmail.sh`      |
| 4 | 자동화 Makefile 골격      | ✓      | Makefile `demo-*` targets          |

### Stage 2 ― 패킷 증거 수집 & 자동화 (완료)
| # | Task                    | Status | Evidence/Notes                      |
|---|------------------------|--------|-------------------------------------|
| 5 | `capture_smtp.sh` 작성   | ✓      | 포트 25/465/587, tcpdump             |
| 6 | 자동 패킷 수집 흐름 완성     | ✓      | `run_experiment.sh` (BEFORE/AFTER)   |
| 7 | `analyze_pcap.sh` 작성   | ✓      | tshark 기반 SMTP 명령 추출            |

### Stage 3 ― 하드닝 & 재테스트 (진행중)
| #  | Task                         | Status | Evidence/Notes                     |
|----|-----------------------------|--------|-------------------------------------|
| 8  | `harden_postfix.sh` 작성     | ✓      | `smtpd_relay_restrictions` 등       |
| 9  | 설정 백업 메커니즘 **[A1]**    | ▷      | `main.cf.bak-YYYYMMDD` (높음, 1h)    |
| 10 | 재공격 테스트 & 비교           | ✓      | 로그·pcap diff 검증                  |
| 11 | 타임스탬프 기반 로그 백업 **[A2]** | ▷    | 덮어쓰기 방지 메커니즘 (높음, 2h)       |
| 12 | 스크립트 에러 핸들링 강화 **[B4]** | □    | `trap` 메커니즘 도입 (높음, 4h)        |

#### A1. 설정 백업 메커니즘 세부 구현 계획
1. 컨테이너 `mail-postfix` 내 `/etc/postfix/main.cf` 접근  
2. ISO 8601 형식 타임스탬프 생성 함수 구현  
3. rsync/scp 활용 백업 메커니즘 작성  
4. 백업 전·후 무결성 검증 및 로깅  
5. `harden_postfix.sh`에 백업 기능 통합  

#### A2. 타임스탬프 기반 로그 백업 함수 세부 구현 계획
1. 공통 유틸 스크립트에 타임스탬프 생성 함수 추가  
2. 로그 디렉터리에 덮어쓰기 방지 로직 삽입  
3. NDJSON 로깅 형식과 연동  

#### B4. 스크립트 에러 핸들링 강화 세부 구현 계획
1. `trap` 메커니즘으로 스크립트 종료 코드 표준화  
2. 의존성 및 환경 사전 검증 함수 추가  
3. 실행 로그 형식 통일 및 강화  
4. 컨테이너 연결성(네트워크) 검증 로직 삽입  
5. 타임아웃 및 실패 조건 세분화  

### Stage 4 ― 보고서 작성 & 메트릭 (진행중)
| #  | Task                                 | Status | Evidence/Notes                   |
|----|-------------------------------------|--------|----------------------------------|
| 13 | `gen_report_html.sh` 확장             | ✓      | Bulma CSS 기반                   |
| 14 | CVSS 자동 산정 **[A5]**              | ▷      | `calc_cvss.py` 초안 (중간, 3h)    |
| 15 | 개선 효과 계량화                       | ▷      | 성공률·응답코드 통계               |
| 16 | SMTP 응답 코드별 카테고리화 **[A4]**    | □      | 응답 코드별 의미 분류 (중간, 2h)    |
| 17 | Bulma 리포트 템플릿 개선 **[B5]**      | □      | 시각적 명료성 강화 (중간, 4h)      |

#### A4. SMTP 응답 코드별 카테고리화 세부 구현 계획
1. `analyze_pcap.sh` 결과 기반 응답 코드 추출 스크립트 작성  
2. 응답 코드별 의미 및 분류 테이블 생성  
3. CSV/JSON 데이터 파일로 저장  

#### A5. CVSS 자동 산정 세부 구현 계획
1. CVSS 3.1 벡터 상수 정의  
2. SMTP 오픈 릴레이 특성 자동 매핑 로직 구현  
3. 벡터→점수 변환 및 JSON 출력 기능 구현  
4. 리포트 생성기 연동 인터페이스 작성  
5. 단위 테스트 케이스 작성  

#### B5. Bulma 리포트 템플릿 개선 세부 구현 계획
1. 현재 템플릿 분석 및 개선점 식별
2. 데이터 시각화 컴포넌트 추가
3. 테이블 및 카드 디자인 최적화
4. 반응형 디자인 구현
5. 테마 색상 일관성 확보

### Stage 5 ― 패키징 & 향후 작업 (계획)
| #  | Task                        | Status | Evidence/Notes                          |
|----|----------------------------|--------|------------------------------------------|
| 18 | artifacts 백업 구조           | ✓      | ISO-8601 타임스탬프 기록                  |
| 19 | `Makefile` 타깃 세분화 **[A3]** | □     | `demo-before`/`demo-after`/`report` (중간, 1h) |
| 20 | 위협 모델 (Mermaid) **[B3]**   | □     | ATT&CK view 예정 (중간, 3h)              |
| 21 | `main.cf` diff 리포트 **[B1]** | □     | side-by-side HTML (중간, 4h, 선행: A1)   |
| 22 | SMTP 시퀀스 다이어그램 **[B2]**  | □     | Mermaid sequence (낮음, 3h)              |
| 23 | DNS 재귀 질의 기본 설정 **[B6]** | □     | `dnsmasq.conf` 최적화 (낮음, 3h)         |

#### A3. Makefile 타깃 세분화 세부 구현 계획
1. Makefile에 `demo-before`, `demo-after` 섹션 분리  
2. 각 섹션 실행 흐름 검증 및 문서화  

#### B1. `main.cf` diff 리포트 세부 구현 계획
1. 설정 백업 완료 후 시작 가능
2. HTML 형식 diff 시각화 구현
3. 색상 코딩 적용 (추가/삭제/변경)
4. 주석 및 설명 기능 추가

#### B2. SMTP 시퀀스 다이어그램 세부 구현 계획
1. 정상 흐름 및 오픈 릴레이 케이스 식별
2. Mermaid 구문으로 다이어그램 작성
3. 리포트 통합

#### B3. 위협 모델 다이어그램 세부 구현 계획
1. ATT&CK 프레임워크 매핑
2. 위협 엑터, 벡터, 완화조치 식별
3. Mermaid 형식 다이어그램 작성

#### B6. DNS 재귀 질의 설정 세부 구현 계획
1. dnsmasq 설정 파일 분석
2. 최적 설정 파라미터 연구
3. 테스트 및 검증

## 향후 작업: SMTP Fuzzer

| #  | Task                               | Status | Evidence/Notes                         |
|----|-----------------------------------|--------|---------------------------------------|
| F1 | 퍼저 아키텍처 기본 골격 설정         | □      | Python `asyncio` 기반 (중간, 2h)       |
| F2 | 변이 전략 모듈 구현                 | □      | 명령어, 헤더, 인코딩 퍼징 (중간, 4h)     |
| F3 | 모니터링 및 로깅 통합               | □      | 응답코드 추적, 크래시 감지 (중간, 3h)    |
| F4 | 자동 분류 및 실패 클러스터링         | □      | 고유 실패 그룹화 (중간, 3h)             |
| F5 | 퍼징 보고서 출력 생성기              | □      | HTML 리포트 + 재현 스크립트 (중간, 2h)   |

## 6. 실행 순서 및 로드맵

### 단기 실행 계획 `High Priorty`
1. **[A1]** 설정 백업 메커니즘 (1h)
2. **[A2]** 타임스탬프 기반 로그 백업 함수 (2h)
3. **[B4]** 스크립트 에러 핸들링 강화 (4h)

### 중기 실행 계획 `Mid Priorty`
4. **[A3]** Makefile 타깃 세분화 (1h)
5. **[A4]** SMTP 응답 코드별 카테고리화 (2h)
6. **[A5]** CVSS 자동 산정 (3h)
7. **[B1]** `main.cf` diff 리포트 (4h, 선행: A1)
8. **[B5]** Bulma 리포트 템플릿 개선 (4h)
9. **[B3]** 위협 모델 다이어그램 (3h)

### 후기 실행 계획 `Low Priorty`
10. **[B2]** SMTP 시퀀스 다이어그램 (3h)
11. **[B6]** DNS 재귀 질의 설정 (3h)

### 개발 흐름 최적화
1. A1 → A2 → A3 → A4 → A5  
2. B4 → B1 → B5  
3. B2 → B3  
4. B6  
5. F1 → F2 → F3 → F4 → F5

## 7. Post-Report: SMTP Fuzzer Tasks
- [ ] **F1:** 퍼저 아키텍처 기본 골격 설정 (2h, 중간)  
- [ ] **F2:** 변이 전략 모듈 구현 (4h, 중간)  
- [ ] **F3:** 모니터링 및 로깅 통합 (3h, 중간)  
- [ ] **F4:** 자동 분류 및 실패 클러스터링 기능 구현 (3h, 중간)  
- [ ] **F5:** 퍼징 보고서 출력 생성기 개발 (2h, 중간)   

## 8. 완료된 마일스톤 (2025-04 ~ 2025-05)
### 주요 커밋
| Hash      | Tag      | Message                             |
|-----------|----------|-------------------------------------|
| `1461927` | docs     | 실험 방향 리디자인                  |
| `e723f45` | feat     | 네트워크 분리 & CIDR 설정            |
| `98a71b2` | feat     | SMTP 오픈 릴레이 공격 스크립트        |
| `d4e7f29` | feat     | HTML 리포트 생성 초안               |
| `d0e4b5e` | refactor | tcpdump→`any` 인터페이스 개선       |
| `b02a912` | feat     | 기본 메일 전송 스크립트               |

* 컨테이너 인프라 구축 완료 (`mail-postfix`, `dns-dnsmasq`, `mua-debian`, `controller`)  
* 엔드투엔드 자동화 (`run_experiment.sh`): 공격 → 캡처 → 하드닝 → 재테스트 → 리포트  
* NDJSON + RFC 3339 구조화 로깅, Attack ID 상관관계  
* 자동화된 공격 흐름: `attack_openrelay.sh` + swaks  
* 패킷 캡처·분석: `capture_smtp.sh` + `analyze_pcap.sh`

## 9. Final Deliverables
* `report-${YYYYMMDD}.html` (비교·그래프 포함)  
* `artifacts/` 디렉터리: PCAP, 로그, 분석 JSON, diff  
* Makefile 단일 명령 `make demo-full` 완료 기록

## 10. Revision History (key commits)
| Hash      | Tag      | Message                             |
|-----------|----------|-------------------------------------|
| `1461927` | docs     | 실험 방향 리디자인                  |
| `e723f45` | feat     | 네트워크 분리 & CIDR 설정            |
| `98a71b2` | feat     | SMTP 오픈 릴레이 공격 스크립트        |
| `d4e7f29` | feat     | HTML 리포트 생성 초안               |
| `d0e4b5e` | refactor | tcpdump→`any` 인터페이스 개선       |
| `b02a912` | feat     | 기본 메일 전송 스크립트               |
