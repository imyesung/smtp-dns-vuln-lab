# Makefile for SMTP & DNS Vulnerability Lab

SHELL := /bin/bash
COMPOSE := docker-compose
CONTROLLER_CONTAINER := controller
MUA_CONTAINER := mua-debian
MAIL_SERVER_CONTAINER := mail-postfix
SCRIPTS_DIR := /scripts
ARTIFACTS_DIR := /artifacts
HOST_ARTIFACTS_DIR := ./artifacts
HOST_SCRIPTS_DIR := ./scripts
ATTACK_ID_PREFIX := EXP
CURRENT_TIMESTAMP := $(shell LC_ALL=C date +%Y%m%d_%H%M%S)
DEMO_RUN_ID := $(ATTACK_ID_PREFIX)_$(CURRENT_TIMESTAMP)

# Container 상태 확인 및 보장 (utils.sh 함수와 통합)
define ensure_container_running
	@echo "INFO: Ensuring container $(1) is running and responsive..."
	@$(HOST_SCRIPTS_DIR)/common_functions.sh ensure_container_running "$(1)"
endef

# 파일 존재 대기 함수 (utils.sh 함수와 통합)
define wait_for_file
	@echo "INFO: Waiting for $(1) (timeout: $(2)s)..."
	@$(HOST_SCRIPTS_DIR)/common_functions.sh wait_for_file "$(1)" "$(2)"
endef

# 컨테이너에서 스크립트 실행 (에러 핸들링 포함)
# 사용법: $(call exec_in_container,컨테이너명,스크립트경로,추가인수...)
define exec_in_container
	@echo "INFO: Executing $(2) in container $(1)..."
	@if docker exec $(1) $(2) $(3); then \
		echo "INFO: $(2) completed successfully in $(1)"; \
	else \
		exit_code=$$?; \
		echo "ERROR: $(2) failed in $(1) with exit code $$exit_code"; \
		docker logs --tail 20 $(1) || true; \
		exit $$exit_code; \
	fi
endef

# 패킷 캡처 시작/중지 표준화
define start_packet_capture
	@echo "INFO: Starting packet capture for $(1)..."
	docker exec $(CONTROLLER_CONTAINER) bash -c "$(SCRIPTS_DIR)/capture_smtp.sh $(1) & echo \$$! > /tmp/capture_$(1).pid && touch $(ARTIFACTS_DIR)/capture_started_$(1)"
	$(call wait_for_file,$(HOST_ARTIFACTS_DIR)/capture_started_$(1),30)
	@echo "INFO: Packet capture started, waiting for stabilization..."
	sleep 5
endef

define stop_packet_capture
	@echo "INFO: Stopping packet capture for $(1)..."
	@echo "INFO: Attempting graceful tcpdump termination..."
	-docker exec mail-postfix bash -c "if [ -f /artifacts/tcpdump_$(1).pid ]; then TCPDUMP_PID=\$$(cat /artifacts/tcpdump_$(1).pid); echo \"Sending SIGTERM to tcpdump PID: \$$TCPDUMP_PID\"; kill -TERM \$$TCPDUMP_PID 2>/dev/null && sleep 3; if kill -0 \$$TCPDUMP_PID 2>/dev/null; then echo \"Sending SIGKILL to tcpdump PID: \$$TCPDUMP_PID\"; kill -KILL \$$TCPDUMP_PID 2>/dev/null; fi; rm -f /artifacts/tcpdump_$(1).pid; else echo \"No tcpdump PID file found for $(1)\"; fi"
	@echo "INFO: Stopping controller capture process..."
	-docker exec $(CONTROLLER_CONTAINER) bash -c "if [ -f /tmp/capture_$(1).pid ]; then kill \$$(cat /tmp/capture_$(1).pid) 2>/dev/null || true; rm /tmp/capture_$(1).pid; fi"
	@echo "INFO: Waiting for PCAP file to be written..."
	sleep 5
	$(call wait_for_file,$(HOST_ARTIFACTS_DIR)/smtp_$(1).pcap,90)
	@echo "INFO: Packet capture completed for $(1)"
endef

# 모든 보안 테스트 실행 (공통화)
define run_security_tests
	@echo "INFO: Running security tests for $(1)..."
	$(call exec_in_container,$(MUA_CONTAINER),$(SCRIPTS_DIR)/attack_starttls_downgrade.sh,$(1))
	$(call exec_in_container,$(MUA_CONTAINER),$(SCRIPTS_DIR)/attack_openrelay.sh,$(1))
	$(call exec_in_container,$(MUA_CONTAINER),$(SCRIPTS_DIR)/attack_dns_recursion.sh,$(1))
	$(call exec_in_container,$(MUA_CONTAINER),$(SCRIPTS_DIR)/attack_dane_mta-sts.sh,$(1))
	$(call exec_in_container,$(MUA_CONTAINER),$(SCRIPTS_DIR)/attack_auth_plaintext.sh,$(1))
	$(call exec_in_container,$(MUA_CONTAINER),$(SCRIPTS_DIR)/analyze_headers.sh,$(1))
endef

# 전체 데모 단계 실행 (패킷 캡처 + 공격 + 분석)
define run_demo_stage
	@echo "INFO: === Demo Stage: $(2) (ID: $(1)) ==="
	$(call ensure_container_running,$(MAIL_SERVER_CONTAINER))
	$(call ensure_container_running,$(MUA_CONTAINER))
	$(call ensure_container_running,$(CONTROLLER_CONTAINER))
	@$(HOST_SCRIPTS_DIR)/common_functions.sh wait_for_postfix
	$(call start_packet_capture,$(1))
	$(call run_security_tests,$(1))
	@echo "INFO: Waiting 10 seconds for traffic capture..."
	sleep 10
	$(call stop_packet_capture,$(1))
	@echo "INFO: Analyzing captured packets..."
	docker exec $(CONTROLLER_CONTAINER) $(SCRIPTS_DIR)/analyze_pcap.sh $(ARTIFACTS_DIR)/smtp_$(1).pcap $(ARTIFACTS_DIR)/analysis_$(1).txt
endef

# 단일 공격 실행 (간단한 테스트용)
define run_single_attack
	@echo "INFO: Running single attack: $(2) for $(1)..."
	$(call ensure_container_running,$(MAIL_SERVER_CONTAINER))
	$(call ensure_container_running,$(MUA_CONTAINER))
	@$(HOST_SCRIPTS_DIR)/common_functions.sh wait_for_postfix
	$(call exec_in_container,$(MUA_CONTAINER),$(SCRIPTS_DIR)/$(2),$(1))
endef

# Postfix 서비스 대기 함수
wait_for_postfix:
	@echo "INFO: Waiting for Postfix service..."
	@for i in $$(seq 1 60); do \
		if docker exec mail-postfix netstat -tuln | grep ':25 ' >/dev/null 2>&1; then \
			echo "INFO: Postfix ready after $$i seconds"; \
			sleep 2; \
			exit 0; \
		fi; \
		echo "INFO: Waiting for Postfix... ($$i/60)"; \
		sleep 1; \
	done; \
	echo "ERROR: Postfix not ready after 60 seconds"; \
	exit 1

.PHONY: up down logs ps build clean-artifacts demo demo-before demo-after analyze-all help exec postfix-restore postfix-harden generate-report run-checks check-starttls check-relay check-dns check-auth check-spfdkim comprehensive-test

up:
	@echo "INFO: Starting all Docker services..."
	$(COMPOSE) up -d --build --wait

down:
	@echo "INFO: Stopping and removing all Docker services..."
	$(COMPOSE) down -v

logs:
	$(COMPOSE) logs -f

ps:
	$(COMPOSE) ps

build:
	@echo "INFO: Building Docker images..."
	$(COMPOSE) build --no-cache

clean-artifacts:
	@echo "WARNING: This will remove all files in ./artifacts. Are you sure? (y/N)"
	@read -r response; \
	if [[ "$$response" =~ ^([yY][eE][sS]|[yY])$$ ]]; then \
		rm -rf ./artifacts/*; \
		mkdir -p ./artifacts; \
		echo "INFO: ./artifacts directory cleaned."; \
	else \
		echo "INFO: Cleanup cancelled."; \
	fi

demo: up demo-before postfix-harden demo-after analyze-all generate-report postfix-restore down
	@echo "INFO: Full demo sequence complete. Run ID: $(DEMO_RUN_ID)"

demo-before:
	$(call run_demo_stage,$(DEMO_RUN_ID)_BEFORE,Before Hardening)

postfix-harden:
	@echo "INFO: Applying Postfix security hardening..."
	$(call ensure_container_running,$(CONTROLLER_CONTAINER))
	docker exec $(CONTROLLER_CONTAINER) /scripts/harden_postfix.sh harden
	@echo "INFO: Reloading Postfix with new configuration..."
	docker exec $(MAIL_SERVER_CONTAINER) postfix reload
	@echo "INFO: Postfix hardening completed"

postfix-restore:
	@echo "INFO: Restoring vulnerable Postfix configuration..."
	$(call ensure_container_running,$(CONTROLLER_CONTAINER))
	docker exec $(CONTROLLER_CONTAINER) /scripts/harden_postfix.sh restore
	@echo "INFO: Reloading Postfix with vulnerable configuration..."
	docker exec $(MAIL_SERVER_CONTAINER) postfix reload
	@echo "INFO: Vulnerable configuration restored"

demo-after:
	$(call run_demo_stage,$(DEMO_RUN_ID)_AFTER,After Hardening)

analyze-all:
	@echo "INFO: Analyzing PCAPs..."
	$(call ensure_container_running,$(CONTROLLER_CONTAINER))
	docker exec $(CONTROLLER_CONTAINER) $(SCRIPTS_DIR)/analyze_pcap.sh $(ARTIFACTS_DIR)/smtp_$(DEMO_RUN_ID)_BEFORE.pcap $(ARTIFACTS_DIR)/analysis_$(DEMO_RUN_ID)_BEFORE.txt
	docker exec $(CONTROLLER_CONTAINER) $(SCRIPTS_DIR)/analyze_pcap.sh $(ARTIFACTS_DIR)/smtp_$(DEMO_RUN_ID)_AFTER.pcap $(ARTIFACTS_DIR)/analysis_$(DEMO_RUN_ID)_AFTER.txt

generate-report:
	@echo "INFO: Generating report for Run ID: $(DEMO_RUN_ID)..."
	$(HOST_SCRIPTS_DIR)/gen_report_html.sh "$(DEMO_RUN_ID)" "$(HOST_ARTIFACTS_DIR)/analysis_$(DEMO_RUN_ID)_BEFORE.txt" "$(HOST_ARTIFACTS_DIR)/analysis_$(DEMO_RUN_ID)_AFTER.txt" "$(HOST_ARTIFACTS_DIR)"

# 새로운 보안 테스트 명령어들
run-checks: up check-starttls check-relay check-dns check-auth check-spfdkim
	@echo "INFO: All security checks completed for Run ID: $(DEMO_RUN_ID)"

check-starttls:
	$(call run_single_attack,$(DEMO_RUN_ID),attack_starttls_downgrade.sh)

check-relay:
	$(call run_single_attack,$(DEMO_RUN_ID),attack_openrelay.sh)

check-dns:
	@echo "INFO: Running DNS recursion and DANE/MTA-STS attacks..."
	$(call ensure_container_running,$(MUA_CONTAINER))
	$(call exec_in_container,$(MUA_CONTAINER),$(SCRIPTS_DIR)/attack_dns_recursion.sh,$(DEMO_RUN_ID))
	$(call exec_in_container,$(MUA_CONTAINER),$(SCRIPTS_DIR)/attack_dane_mta-sts.sh,$(DEMO_RUN_ID))

check-auth:
	$(call run_single_attack,$(DEMO_RUN_ID),attack_auth_plaintext.sh)

check-spfdkim:
	$(call run_single_attack,$(DEMO_RUN_ID),analyze_headers.sh)

comprehensive-test: up comprehensive-before postfix-harden comprehensive-after analyze-comprehensive generate-comprehensive-report postfix-restore down
	@echo "INFO: ======================================================"
	@echo "INFO:        COMPREHENSIVE SECURITY TEST COMPLETED"
	@echo "INFO: ======================================================"
	@echo "INFO: Run ID: $(DEMO_RUN_ID)"
	@echo "INFO: "
	@echo "INFO: Generated Artifacts:"
	@echo "INFO: - BEFORE packet capture: smtp_$(DEMO_RUN_ID)_BEFORE.pcap"
	@echo "INFO: - AFTER packet capture: smtp_$(DEMO_RUN_ID)_AFTER.pcap"
	@echo "INFO: - BEFORE analysis: analysis_$(DEMO_RUN_ID)_BEFORE.txt"
	@echo "INFO: - AFTER analysis: analysis_$(DEMO_RUN_ID)_AFTER.txt"
	@echo "INFO: - Comprehensive reports: Check $(HOST_ARTIFACTS_DIR)/ for HTML/text reports"
	@echo "INFO: "
	@echo "INFO: Next Steps:"
	@echo "INFO: 1. Review HTML report: open $(HOST_ARTIFACTS_DIR)/report_$(DEMO_RUN_ID).html"
	@echo "INFO: 2. Analyze packet differences between BEFORE and AFTER"
	@echo "INFO: 3. Verify security improvements in the reports"
	@echo "INFO: ======================================================"

comprehensive-before:
	$(call run_demo_stage,$(DEMO_RUN_ID)_BEFORE,Comprehensive Test - Before Hardening)

comprehensive-after:
	$(call run_demo_stage,$(DEMO_RUN_ID)_AFTER,Comprehensive Test - After Hardening)

analyze-comprehensive:
	@echo "INFO: ===== COMPREHENSIVE PCAP ANALYSIS PHASE ====="
	@echo "INFO: This phase analyzes Before/After packet captures to identify security improvements"
	$(call ensure_container_running,$(CONTROLLER_CONTAINER))
	@echo "INFO: Step 1/4 - Validating PCAP files exist..."
	@if ! docker exec $(CONTROLLER_CONTAINER) test -f $(ARTIFACTS_DIR)/smtp_$(DEMO_RUN_ID)_BEFORE.pcap; then \
		echo "ERROR: BEFORE PCAP file missing: $(ARTIFACTS_DIR)/smtp_$(DEMO_RUN_ID)_BEFORE.pcap"; \
		echo "FATAL: Cannot perform comprehensive analysis without BEFORE packet capture"; \
		exit 1; \
	fi
	@if ! docker exec $(CONTROLLER_CONTAINER) test -f $(ARTIFACTS_DIR)/smtp_$(DEMO_RUN_ID)_AFTER.pcap; then \
		echo "ERROR: AFTER PCAP file missing: $(ARTIFACTS_DIR)/smtp_$(DEMO_RUN_ID)_AFTER.pcap"; \
		echo "FATAL: Cannot perform comprehensive analysis without AFTER packet capture"; \
		exit 1; \
	fi
	@echo "INFO: ✓ Both BEFORE and AFTER PCAP files found"
	@echo "INFO: Step 2/4 - Analyzing BEFORE hardening packet capture..."
	@if docker exec $(CONTROLLER_CONTAINER) $(SCRIPTS_DIR)/analyze_pcap.sh $(ARTIFACTS_DIR)/smtp_$(DEMO_RUN_ID)_BEFORE.pcap $(ARTIFACTS_DIR)/analysis_$(DEMO_RUN_ID)_BEFORE.txt; then \
		echo "INFO: ✓ BEFORE analysis completed successfully"; \
	else \
		echo "ERROR: BEFORE packet analysis failed - this will impact comprehensive report"; \
		exit 1; \
	fi
	@echo "INFO: Step 3/4 - Analyzing AFTER hardening packet capture..."
	@if docker exec $(CONTROLLER_CONTAINER) $(SCRIPTS_DIR)/analyze_pcap.sh $(ARTIFACTS_DIR)/smtp_$(DEMO_RUN_ID)_AFTER.pcap $(ARTIFACTS_DIR)/analysis_$(DEMO_RUN_ID)_AFTER.txt; then \
		echo "INFO: ✓ AFTER analysis completed successfully"; \
	else \
		echo "ERROR: AFTER packet analysis failed - this will impact comprehensive report"; \
		exit 1; \
	fi
	@echo "INFO: Step 4/4 - Validating analysis outputs..."
	@docker exec $(CONTROLLER_CONTAINER) sh -c "wc -l $(ARTIFACTS_DIR)/analysis_$(DEMO_RUN_ID)_BEFORE.txt $(ARTIFACTS_DIR)/analysis_$(DEMO_RUN_ID)_AFTER.txt" || true
	@echo "INFO: ===== COMPREHENSIVE PCAP ANALYSIS COMPLETED ====="

generate-comprehensive-report:
	@echo "INFO: ===== COMPREHENSIVE REPORT GENERATION PHASE ====="
	@echo "INFO: Generating multi-format security reports for Run ID: $(DEMO_RUN_ID)"
	@echo "INFO: Step 1/3 - Validating analysis files exist..."
	@if [ ! -f "$(HOST_ARTIFACTS_DIR)/analysis_$(DEMO_RUN_ID)_BEFORE.txt" ]; then \
		echo "ERROR: BEFORE analysis file missing: $(HOST_ARTIFACTS_DIR)/analysis_$(DEMO_RUN_ID)_BEFORE.txt"; \
		echo "FATAL: Cannot generate comprehensive report without BEFORE analysis"; \
		exit 1; \
	fi
	@if [ ! -f "$(HOST_ARTIFACTS_DIR)/analysis_$(DEMO_RUN_ID)_AFTER.txt" ]; then \
		echo "ERROR: AFTER analysis file missing: $(HOST_ARTIFACTS_DIR)/analysis_$(DEMO_RUN_ID)_AFTER.txt"; \
		echo "FATAL: Cannot generate comprehensive report without AFTER analysis"; \
		exit 1; \
	fi
	@echo "INFO: ✓ Both analysis files found, proceeding with report generation"
	@echo "INFO: Step 2/3 - Generating HTML comprehensive report..."
	@if $(HOST_SCRIPTS_DIR)/gen_report_html.sh "$(DEMO_RUN_ID)" "$(HOST_ARTIFACTS_DIR)/analysis_$(DEMO_RUN_ID)_BEFORE.txt" "$(HOST_ARTIFACTS_DIR)/analysis_$(DEMO_RUN_ID)_AFTER.txt" "$(HOST_ARTIFACTS_DIR)"; then \
		echo "INFO: ✓ HTML report generated successfully"; \
	else \
		echo "WARN: HTML report generation failed, continuing with text report"; \
	fi
	@echo "INFO: Step 3/3 - Generating text-based comprehensive report..."
	$(call ensure_container_running,$(CONTROLLER_CONTAINER))
	@if docker exec $(CONTROLLER_CONTAINER) $(SCRIPTS_DIR)/generate_comprehensive_report.sh $(DEMO_RUN_ID); then \
		echo "INFO: ✓ Text report generated successfully"; \
	else \
		echo "WARN: Text report generation failed"; \
	fi
	@echo "INFO: ===== REPORT GENERATION SUMMARY ====="
	@echo "INFO: Generated reports for Run ID: $(DEMO_RUN_ID)"
	@echo "INFO: Available report files:"
	@ls -la $(HOST_ARTIFACTS_DIR)/ | grep "$(DEMO_RUN_ID)" | grep -E "\.(html|txt|json)$$" | tail -10 || echo "WARN: No report files found matching Run ID pattern"
	@echo "INFO: ===== COMPREHENSIVE REPORT GENERATION COMPLETED ====="

exec:
ifndef SCRIPT
	$(error SCRIPT is not set. Usage: make exec SCRIPT=<script_name.sh> [ARGS="<arguments>"])
endif
	@echo "INFO: Executing $(SCRIPTS_DIR)/$(SCRIPT) $(ARGS) in $(CONTROLLER_CONTAINER)..."
	docker exec $(CONTROLLER_CONTAINER) $(SCRIPTS_DIR)/$(SCRIPT) $(ARGS)

# CVSS 분석 및 위험도 평가
.PHONY: cvss-analysis
cvss-analysis:
	@echo "INFO: Generating CVSS 3.1 risk assessment..."
	$(call ensure_container_running,$(CONTROLLER_CONTAINER))
	docker exec $(CONTROLLER_CONTAINER) python3 $(SCRIPTS_DIR)/calc_cvss.py --format table
	@echo ""
	@echo "INFO: Detailed CVSS analysis saved to artifacts/cvss_analysis.json"
	docker exec $(CONTROLLER_CONTAINER) python3 $(SCRIPTS_DIR)/calc_cvss.py --output $(ARTIFACTS_DIR)/cvss_analysis.json

# SMTP 응답 코드 분석
.PHONY: smtp-response-analysis
smtp-response-analysis:
	@echo "INFO: Analyzing SMTP response codes from latest PCAPs..."
	$(call ensure_container_running,$(CONTROLLER_CONTAINER))
	@if docker exec $(CONTROLLER_CONTAINER) find $(ARTIFACTS_DIR) -name "*.pcap" -type f | head -1 >/dev/null 2>&1; then \
		latest_pcap=$$(docker exec $(CONTROLLER_CONTAINER) find $(ARTIFACTS_DIR) -name "*.pcap" -type f | sort -r | head -1); \
		echo "INFO: Analyzing $$latest_pcap"; \
		docker exec $(CONTROLLER_CONTAINER) $(SCRIPTS_DIR)/analyze_smtp_responses.sh $$latest_pcap; \
	else \
		echo "WARN: No PCAP files found for analysis"; \
	fi

# 프로젝트 상태 대시보드
.PHONY: status
status:
	@echo "======================================================"
	@echo "        SMTP & DNS Vulnerability Lab - Status"
	@echo "======================================================"
	@echo ""
	@echo "Container Status:"
	@docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "(controller|mua-debian|mail-postfix|dns-dnsmasq)" || echo "No lab containers running"
	@echo ""
	@echo "Recent Test Results:"
	@if [ -d "$(HOST_ARTIFACTS_DIR)" ]; then \
		echo "Latest 5 test runs:"; \
		ls -lt $(HOST_ARTIFACTS_DIR)/ | grep -E "(analysis_|comprehensive_)" | head -5 | awk '{print "  " $$9 " (" $$6" "$$7" "$$8")"}' || echo "  No test results found"; \
	else \
		echo "  Artifacts directory not found"; \
	fi
	@echo ""
	@echo "Available Reports:"
	@if [ -d "$(HOST_ARTIFACTS_DIR)" ]; then \
		ls -1 $(HOST_ARTIFACTS_DIR)/*.html 2>/dev/null | tail -3 | sed 's/^/  /' || echo "  No HTML reports found"; \
	fi
	@echo ""
	@echo "Security Baseline:"
	$(call ensure_container_running,$(CONTROLLER_CONTAINER))
	@docker exec $(CONTROLLER_CONTAINER) grep -E "(smtpd_relay_restrictions|smtpd_tls_security_level)" /etc/postfix/main.cf 2>/dev/null | sed 's/^/  /' || echo "  Postfix configuration not accessible"

# 실험 환경 완전 정리
.PHONY: deep-clean
deep-clean: clean
	@echo "INFO: Performing deep cleanup..."
	@echo "INFO: Removing all artifacts and backups..."
	rm -rf $(HOST_ARTIFACTS_DIR)/* || true
	rm -rf ./backups/* || true
	rm -rf ./logs/* || true
	@echo "INFO: Removing all Docker images..."
	docker rmi -f $$(docker images -q --filter "reference=*smtp-dns*") 2>/dev/null || true
	docker rmi -f $$(docker images -q --filter "dangling=true") 2>/dev/null || true
	@echo "INFO: Deep cleanup completed"

# 종합 보안 평가 (모든 분석 도구 실행)
.PHONY: security-assessment
security-assessment: comprehensive-test cvss-analysis smtp-response-analysis
	@echo ""
	@echo "======================================================"
	@echo "        Complete Security Assessment Finished"
	@echo "======================================================"
	@echo ""
	@echo "Generated Artifacts:"
	@ls -la $(HOST_ARTIFACTS_DIR)/ | grep -E "\.(html|json|pcap)$$" | tail -10
	@echo ""
	@echo "Next Steps:"
	@echo "1. Review HTML reports in artifacts/ directory"
	@echo "2. Check CVSS analysis for risk prioritization"
	@echo "3. Examine SMTP response patterns"
	@echo "4. Apply security hardening: make postfix-harden"

# 개발자를 위한 디버깅 도구
.PHONY: debug-logs
debug-logs:
	@echo "INFO: Collecting debug information..."
	@echo ""
	@echo "=== Container Logs (last 50 lines each) ==="
	@for container in controller mua-debian mail-postfix dns-dnsmasq; do \
		echo "--- $$container ---"; \
		docker logs --tail 50 $$container 2>&1 | head -20 || echo "Container $$container not available"; \
		echo ""; \
	done
	@echo ""
	@echo "=== Network Information ==="
	@docker network ls | grep smtp
	@echo ""
	@echo "=== Recent Script Executions ==="
	@docker exec $(CONTROLLER_CONTAINER) find $(ARTIFACTS_DIR) -name "*.json" -type f -exec grep -l "timestamp" {} \; | sort -r | head -5 | xargs -I {} basename {} || echo "No recent JSON logs"

# 도움말 업데이트
.PHONY: help
help:
	@echo "======================================================"
	@echo "    SMTP & DNS Vulnerability Lab - Make Targets"
	@echo "======================================================"
	@echo ""
	@echo "빠른 시작 (권장):"
	@echo "  make comprehensive-test - 완전한 자동화된 보안 테스트 + 보고서 생성"
	@echo "  make status            - 현재 랩 환경 상태 확인"
	@echo "  make security-assessment - 종합 보안 평가 (CVSS 포함)"
	@echo ""
	@echo "기본 운영:"
	@echo "  make up                - 모든 컨테이너 시작"
	@echo "  make demo              - 빠른 오픈 릴레이 데모 (기본)"
	@echo "  make down              - 컨테이너 중지 및 제거"
	@echo "  make deep-clean        - 완전한 정리 (컨테이너 + 데이터)"
	@echo ""
	@echo "개별 보안 테스트:"
	@echo "  make check-starttls    - STARTTLS 다운그레이드 취약점 테스트"
	@echo "  make check-relay       - 오픈 릴레이 취약점 테스트"
	@echo "  make check-dns         - DNS 재귀 쿼리 및 DANE/MTA-STS 테스트"
	@echo "  make check-auth        - 평문 인증 취약점 테스트"
	@echo "  make check-spfdkim     - SPF/DKIM/DMARC 인증 테스트"
	@echo ""
	@echo "분석 및 보고서:"
	@echo "  make cvss-analysis     - CVSS 3.1 위험도 점수 생성"
	@echo "  make smtp-response-analysis - SMTP 응답 패턴 분석"
	@echo "  make generate-report   - 종합 HTML 보고서 생성"
	@echo "  make analyze-all       - 모든 캡처된 패킷 데이터 분석"
	@echo ""
	@echo "설정 관리:"
	@echo "  make postfix-harden    - 보안 강화 적용"
	@echo "  make postfix-restore   - 취약한 설정으로 복원"
	@echo ""
	@echo "개발 및 디버깅:"
	@echo "  make debug-logs        - 컨테이너 로그 및 디버그 정보 표시"
	@echo "  make exec SCRIPT=<name> - 컨트롤러에서 커스텀 스크립트 실행"
	@echo ""
	@echo "추천 워크플로우:"
	@echo "  # 완전한 평가:"
	@echo "  make security-assessment"
	@echo ""
	@echo "  # 커스텀 테스트:"
	@echo "  make up && make run-checks && make cvss-analysis"
	@echo ""
	@echo "  # 문제 해결:"
	@echo "  make status && make debug-logs"
	@echo ""
	@echo "품질 지표:"
	@echo "  - 유의미한 보안 강화: 5xx 거부 응답 증가 또는 10% 이상 트래픽 감소"
	@echo "  - 패킷 분석 기준: 최소 10개 패킷 또는 10% 감소 시 효과적"
	@echo "  - CVSS 점수: 9.0+ (Critical), 7.0-8.9 (High), 4.0-6.9 (Medium)"

# 패킷 분석 상태 확인 (디버깅용)
.PHONY: check-analysis-status
check-analysis-status:
	@echo "INFO: ===== PACKET ANALYSIS STATUS CHECK ====="
	@echo "INFO: Current Run ID: $(DEMO_RUN_ID)"
	@echo "INFO: "
	@echo "INFO: PCAP Files Status:"
	@if [ -f "$(HOST_ARTIFACTS_DIR)/smtp_$(DEMO_RUN_ID)_BEFORE.pcap" ]; then \
		size_before=$$(stat -f%z "$(HOST_ARTIFACTS_DIR)/smtp_$(DEMO_RUN_ID)_BEFORE.pcap" 2>/dev/null || stat -c%s "$(HOST_ARTIFACTS_DIR)/smtp_$(DEMO_RUN_ID)_BEFORE.pcap" 2>/dev/null || echo "0"); \
		echo "INFO: ✓ BEFORE PCAP exists ($$size_before bytes)"; \
	else \
		echo "INFO: ✗ BEFORE PCAP missing"; \
	fi
	@if [ -f "$(HOST_ARTIFACTS_DIR)/smtp_$(DEMO_RUN_ID)_AFTER.pcap" ]; then \
		size_after=$$(stat -f%z "$(HOST_ARTIFACTS_DIR)/smtp_$(DEMO_RUN_ID)_AFTER.pcap" 2>/dev/null || stat -c%s "$(HOST_ARTIFACTS_DIR)/smtp_$(DEMO_RUN_ID)_AFTER.pcap" 2>/dev/null || echo "0"); \
		echo "INFO: ✓ AFTER PCAP exists ($$size_after bytes)"; \
	else \
		echo "INFO: ✗ AFTER PCAP missing"; \
	fi
	@echo "INFO: "
	@echo "INFO: Analysis Files Status:"
	@if [ -f "$(HOST_ARTIFACTS_DIR)/analysis_$(DEMO_RUN_ID)_BEFORE.txt" ]; then \
		lines_before=$$(wc -l < "$(HOST_ARTIFACTS_DIR)/analysis_$(DEMO_RUN_ID)_BEFORE.txt" 2>/dev/null || echo "0"); \
		echo "INFO: ✓ BEFORE analysis exists ($$lines_before lines)"; \
	else \
		echo "INFO: ✗ BEFORE analysis missing"; \
	fi
	@if [ -f "$(HOST_ARTIFACTS_DIR)/analysis_$(DEMO_RUN_ID)_AFTER.txt" ]; then \
		lines_after=$$(wc -l < "$(HOST_ARTIFACTS_DIR)/analysis_$(DEMO_RUN_ID)_AFTER.txt" 2>/dev/null || echo "0"); \
		echo "INFO: ✓ AFTER analysis exists ($$lines_after lines)"; \
	else \
		echo "INFO: ✗ AFTER analysis missing"; \
	fi
	@echo "INFO: "
	@echo "INFO: Report Files Status:"
	@ls -la $(HOST_ARTIFACTS_DIR)/ | grep "$(DEMO_RUN_ID)" | grep -E "\.(html|json)$$" | head -5 || echo "INFO: No report files found for $(DEMO_RUN_ID)"
	@echo "INFO: ===== STATUS CHECK COMPLETED ====="