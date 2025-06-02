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

# Container 상태 확인 및 보장
define ensure_container_running
	@echo "INFO: Ensuring container $(1) is running and responsive..."
	# 1. 컨테이너 존재 여부 확인
	@if ! docker ps -a -q -f name=$(1) | grep -q .; then \
		echo "WARN: Container $(1) does not exist. Attempting to create and start with docker-compose..."; \
		$(COMPOSE) up -d --no-recreate $(1); \
		echo "INFO: Waiting for $(1) to become healthy after creation (timeout 60s)..."; \
		timeout_duration=60; \
		elapsed_time=0; \
		while ! docker ps -q -f name=$(1) -f status=running -f health=healthy | grep -q .; do \
			if [ $$elapsed_time -ge $$timeout_duration ]; then \
				echo "ERROR: Timeout waiting for $(1) to become healthy after creation."; \
				docker logs $(1); \
				exit 1; \
			fi; \
			echo "INFO: Still waiting for $(1) to be healthy... ($$elapsed_time/$$timeout_duration)"; \
			sleep 5; \
			elapsed_time=$$((elapsed_time + 5)); \
		done; \
		echo "INFO: Container $(1) is now healthy."; \
		exit 0; \
	fi
	# 2. 실행 상태 확인
	@if ! docker ps -q -f name=$(1) -f status=running | grep -q .; then \
		echo "WARN: Container $(1) is not running, attempting to start..."; \
		docker start $(1); \
		sleep 5; \
	fi
	# 3. 응답성 확인 (최대 30초 대기)
	@echo "INFO: Checking responsiveness of container $(1)..."; \
	responsive_timeout=30; \
	responsive_counter=0; \
	until docker exec $(1) true > /dev/null 2>&1; do \
		if [ $$responsive_counter -ge $$responsive_timeout ]; then \
			echo "ERROR: Timeout waiting for container $(1) to be responsive."; \
			echo "Attempting to restart $(1)..."; \
			docker restart $(1); \
			sleep 10; \
			if ! docker exec $(1) true > /dev/null 2>&1; then \
				echo "ERROR: Container $(1) is still not responsive after restart."; \
				docker logs $(1); \
				exit 1; \
			fi; \
			echo "INFO: Container $(1) is responsive after restart."; \
			break; \
		fi; \
		responsive_counter=$$((responsive_counter + 2)); \
		sleep 2; \
		echo "INFO: Waiting for $(1) to respond... ($$responsive_counter/$$responsive_timeout)"; \
	done; \
	echo "INFO: Container $(1) is running and responsive."
endef

# 파일 존재 대기 함수
define wait_for_file
	@echo "INFO: Waiting for $(1) (timeout: $(2)s)..."
	@timeout=$(2); \
	counter=0; \
	while [ ! -f $(1) ] && [ $$counter -lt $$timeout ]; do \
		counter=$$((counter + 1)); \
		sleep 1; \
		if [ $$((counter % 5)) -eq 0 ]; then \
			echo "INFO: Still waiting for $(1)... ($$counter/$$timeout)"; \
		fi; \
	done; \
	if [ ! -f $(1) ]; then \
		echo "ERROR: Timed out waiting for $(1) after $(2)s"; \
		exit 1; \
	else \
		echo "INFO: File $(1) found after $$counter seconds"; \
	fi
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
	@echo "INFO: === Stage: Before Hardening (ID: $(DEMO_RUN_ID)_BEFORE) ==="
	$(call ensure_container_running,$(MAIL_SERVER_CONTAINER))
	$(MAKE) wait_for_postfix
	$(call ensure_container_running,$(MUA_CONTAINER))
	$(call ensure_container_running,$(CONTROLLER_CONTAINER))
	docker exec $(CONTROLLER_CONTAINER) bash -c "$(SCRIPTS_DIR)/capture_smtp.sh $(DEMO_RUN_ID)_BEFORE & echo \$$! > /tmp/capture.pid && touch $(ARTIFACTS_DIR)/capture_started_before"
	$(call wait_for_file,$(HOST_ARTIFACTS_DIR)/capture_started_before,30)
	@echo "INFO: Waiting 10 seconds for tcpdump to stabilize..."
	sleep 10
	-docker exec $(MUA_CONTAINER) $(SCRIPTS_DIR)/attack_openrelay.sh $(DEMO_RUN_ID)_BEFORE
	@echo "INFO: Waiting 15 seconds for traffic capture..."
	sleep 15
	@echo "INFO: Stopping packet capture..."
	-docker exec $(CONTROLLER_CONTAINER) bash -c "if [ -f /tmp/tcpdump_$(DEMO_RUN_ID)_BEFORE.pid ]; then kill \$$(cat /tmp/tcpdump_$(DEMO_RUN_ID)_BEFORE.pid) 2>/dev/null || true; rm /tmp/tcpdump_$(DEMO_RUN_ID)_BEFORE.pid; fi"
	sleep 10
	$(call wait_for_file,$(HOST_ARTIFACTS_DIR)/smtp_$(DEMO_RUN_ID)_BEFORE.pcap,90)
	@echo "INFO: Checking PCAP file size..."
	-ls -la $(HOST_ARTIFACTS_DIR)/smtp_$(DEMO_RUN_ID)_BEFORE.pcap
	docker exec $(CONTROLLER_CONTAINER) $(SCRIPTS_DIR)/analyze_pcap.sh $(ARTIFACTS_DIR)/smtp_$(DEMO_RUN_ID)_BEFORE.pcap $(ARTIFACTS_DIR)/analysis_$(DEMO_RUN_ID)_BEFORE.txt

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
	@echo "INFO: === Stage: After Hardening (ID: $(DEMO_RUN_ID)_AFTER) ==="
	$(call ensure_container_running,$(MAIL_SERVER_CONTAINER))
	$(MAKE) wait_for_postfix
	$(call ensure_container_running,$(MUA_CONTAINER))
	$(call ensure_container_running,$(CONTROLLER_CONTAINER))
	docker exec $(CONTROLLER_CONTAINER) bash -c "$(SCRIPTS_DIR)/capture_smtp.sh $(DEMO_RUN_ID)_AFTER & echo \$$! > /tmp/capture.pid && touch $(ARTIFACTS_DIR)/capture_started_after"
	$(call wait_for_file,$(HOST_ARTIFACTS_DIR)/capture_started_after,30)
	@echo "INFO: Waiting 5 seconds for tcpdump to stabilize..."
	sleep 5
	-docker exec $(MUA_CONTAINER) $(SCRIPTS_DIR)/attack_openrelay.sh $(DEMO_RUN_ID)_AFTER || echo "WARNING: Attack script failed, but continuing with demo..."
	@echo "INFO: Waiting 10 seconds for traffic capture..."
	sleep 10
	@echo "INFO: Stopping packet capture..."
	-docker exec $(CONTROLLER_CONTAINER) bash -c "if [ -f /tmp/tcpdump_$(DEMO_RUN_ID)_AFTER.pid ]; then kill \$$(cat /tmp/tcpdump_$(DEMO_RUN_ID)_AFTER.pid) 2>/dev/null || true; rm /tmp/tcpdump_$(DEMO_RUN_ID)_AFTER.pid; fi"
	sleep 5
	$(call wait_for_file,$(HOST_ARTIFACTS_DIR)/smtp_$(DEMO_RUN_ID)_AFTER.pcap,90)
	@echo "INFO: Checking PCAP file size..."
	-ls -la $(HOST_ARTIFACTS_DIR)/smtp_$(DEMO_RUN_ID)_AFTER.pcap
	docker exec $(CONTROLLER_CONTAINER) $(SCRIPTS_DIR)/analyze_pcap.sh $(ARTIFACTS_DIR)/smtp_$(DEMO_RUN_ID)_AFTER.pcap $(ARTIFACTS_DIR)/analysis_$(DEMO_RUN_ID)_AFTER.txt

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
	@echo "INFO: Running STARTTLS downgrade attack..."
	$(call ensure_container_running,$(MUA_CONTAINER))
	docker exec $(MUA_CONTAINER) $(SCRIPTS_DIR)/attack_starttls_downgrade.sh $(DEMO_RUN_ID)

check-relay:
	@echo "INFO: Running open relay attack..."
	$(call ensure_container_running,$(MUA_CONTAINER))
	docker exec $(MUA_CONTAINER) $(SCRIPTS_DIR)/attack_openrelay.sh $(DEMO_RUN_ID)

check-dns:
	@echo "INFO: Running DNS recursion and DANE/MTA-STS attacks..."
	$(call ensure_container_running,$(MUA_CONTAINER))
	docker exec $(MUA_CONTAINER) $(SCRIPTS_DIR)/attack_dns_recursion.sh $(DEMO_RUN_ID)
	docker exec $(MUA_CONTAINER) $(SCRIPTS_DIR)/attack_dane_mta-sts.sh $(DEMO_RUN_ID)

check-auth:
	@echo "INFO: Running plaintext authentication attack..."
	$(call ensure_container_running,$(MUA_CONTAINER))
	docker exec $(MUA_CONTAINER) $(SCRIPTS_DIR)/attack_auth_plaintext.sh $(DEMO_RUN_ID)

check-spfdkim:
	@echo "INFO: Running SPF/DKIM/DMARC analysis..."
	$(call ensure_container_running,$(MUA_CONTAINER))
	docker exec $(MUA_CONTAINER) $(SCRIPTS_DIR)/analyze_headers.sh $(DEMO_RUN_ID)

comprehensive-test: up comprehensive-before postfix-harden comprehensive-after analyze-comprehensive generate-comprehensive-report postfix-restore down
	@echo "INFO: Comprehensive security test completed. Run ID: $(DEMO_RUN_ID)"

comprehensive-before:
	@echo "INFO: === Comprehensive Test: Before Hardening (ID: $(DEMO_RUN_ID)_BEFORE) ==="
	$(call ensure_container_running,$(MAIL_SERVER_CONTAINER))
	$(MAKE) wait_for_postfix
	$(call ensure_container_running,$(MUA_CONTAINER))
	$(call ensure_container_running,$(CONTROLLER_CONTAINER))
	# 패킷 캡처 시작
	docker exec $(CONTROLLER_CONTAINER) bash -c "$(SCRIPTS_DIR)/capture_smtp.sh $(DEMO_RUN_ID)_BEFORE & echo \$$! > /tmp/capture.pid && touch $(ARTIFACTS_DIR)/capture_started_before"
	$(call wait_for_file,$(HOST_ARTIFACTS_DIR)/capture_started_before,30)
	@echo "INFO: Waiting 5 seconds for tcpdump to stabilize..."
	sleep 5
	# 모든 보안 테스트 실행
	-docker exec $(MUA_CONTAINER) $(SCRIPTS_DIR)/attack_starttls_downgrade.sh $(DEMO_RUN_ID)_BEFORE
	-docker exec $(MUA_CONTAINER) $(SCRIPTS_DIR)/attack_openrelay.sh $(DEMO_RUN_ID)_BEFORE
	-docker exec $(MUA_CONTAINER) $(SCRIPTS_DIR)/attack_dns_recursion.sh $(DEMO_RUN_ID)_BEFORE
	-docker exec $(MUA_CONTAINER) $(SCRIPTS_DIR)/attack_dane_mta-sts.sh $(DEMO_RUN_ID)_BEFORE
	-docker exec $(MUA_CONTAINER) $(SCRIPTS_DIR)/attack_auth_plaintext.sh $(DEMO_RUN_ID)_BEFORE
	-docker exec $(MUA_CONTAINER) $(SCRIPTS_DIR)/analyze_headers.sh $(DEMO_RUN_ID)_BEFORE
	@echo "INFO: Waiting 10 seconds for traffic capture..."
	sleep 10
	# 패킷 캡처 중지
	@echo "INFO: Stopping packet capture..."
	-docker exec $(CONTROLLER_CONTAINER) bash -c "if [ -f /tmp/tcpdump_$(DEMO_RUN_ID)_BEFORE.pid ]; then kill \$$(cat /tmp/tcpdump_$(DEMO_RUN_ID)_BEFORE.pid) 2>/dev/null || true; rm /tmp/tcpdump_$(DEMO_RUN_ID)_BEFORE.pid; fi"
	sleep 5
	$(call wait_for_file,$(HOST_ARTIFACTS_DIR)/smtp_$(DEMO_RUN_ID)_BEFORE.pcap,90)

comprehensive-after:
	@echo "INFO: === Comprehensive Test: After Hardening (ID: $(DEMO_RUN_ID)_AFTER) ==="
	$(call ensure_container_running,$(MAIL_SERVER_CONTAINER))
	$(MAKE) wait_for_postfix
	$(call ensure_container_running,$(MUA_CONTAINER))
	$(call ensure_container_running,$(CONTROLLER_CONTAINER))
	# 패킷 캡처 시작
	docker exec $(CONTROLLER_CONTAINER) bash -c "$(SCRIPTS_DIR)/capture_smtp.sh $(DEMO_RUN_ID)_AFTER & echo \$$! > /tmp/capture.pid && touch $(ARTIFACTS_DIR)/capture_started_after"
	$(call wait_for_file,$(HOST_ARTIFACTS_DIR)/capture_started_after,30)
	@echo "INFO: Waiting 5 seconds for tcpdump to stabilize..."
	sleep 5
	# 모든 보안 테스트 재실행
	-docker exec $(MUA_CONTAINER) $(SCRIPTS_DIR)/attack_starttls_downgrade.sh $(DEMO_RUN_ID)_AFTER
	-docker exec $(MUA_CONTAINER) $(SCRIPTS_DIR)/attack_openrelay.sh $(DEMO_RUN_ID)_AFTER
	-docker exec $(MUA_CONTAINER) $(SCRIPTS_DIR)/attack_dns_recursion.sh $(DEMO_RUN_ID)_AFTER
	-docker exec $(MUA_CONTAINER) $(SCRIPTS_DIR)/attack_dane_mta-sts.sh $(DEMO_RUN_ID)_AFTER
	-docker exec $(MUA_CONTAINER) $(SCRIPTS_DIR)/attack_auth_plaintext.sh $(DEMO_RUN_ID)_AFTER
	-docker exec $(MUA_CONTAINER) $(SCRIPTS_DIR)/analyze_headers.sh $(DEMO_RUN_ID)_AFTER
	@echo "INFO: Waiting 10 seconds for traffic capture..."
	sleep 10
	# 패킷 캡처 중지
	@echo "INFO: Stopping packet capture..."
	-docker exec $(CONTROLLER_CONTAINER) bash -c "if [ -f /tmp/tcpdump_$(DEMO_RUN_ID)_AFTER.pid ]; then kill \$$(cat /tmp/tcpdump_$(DEMO_RUN_ID)_AFTER.pid) 2>/dev/null || true; rm /tmp/tcpdump_$(DEMO_RUN_ID)_AFTER.pid; fi"
	sleep 5
	$(call wait_for_file,$(HOST_ARTIFACTS_DIR)/smtp_$(DEMO_RUN_ID)_AFTER.pcap,90)

analyze-comprehensive:
	@echo "INFO: Analyzing comprehensive test results..."
	$(call ensure_container_running,$(CONTROLLER_CONTAINER))
	# 기존 PCAP 분석
	docker exec $(CONTROLLER_CONTAINER) $(SCRIPTS_DIR)/analyze_pcap.sh $(ARTIFACTS_DIR)/smtp_$(DEMO_RUN_ID)_BEFORE.pcap $(ARTIFACTS_DIR)/analysis_$(DEMO_RUN_ID)_BEFORE.txt
	docker exec $(CONTROLLER_CONTAINER) $(SCRIPTS_DIR)/analyze_pcap.sh $(ARTIFACTS_DIR)/smtp_$(DEMO_RUN_ID)_AFTER.pcap $(ARTIFACTS_DIR)/analysis_$(DEMO_RUN_ID)_AFTER.txt

generate-comprehensive-report:
	@echo "INFO: Generating comprehensive security report for Run ID: $(DEMO_RUN_ID)..."
	$(HOST_SCRIPTS_DIR)/gen_report_html.sh "$(DEMO_RUN_ID)" "$(HOST_ARTIFACTS_DIR)/analysis_$(DEMO_RUN_ID)_BEFORE.txt" "$(HOST_ARTIFACTS_DIR)/analysis_$(DEMO_RUN_ID)_AFTER.txt" "$(HOST_ARTIFACTS_DIR)"
	@echo "INFO: Generating text-based comprehensive report..."
	docker exec $(CONTROLLER_CONTAINER) $(SCRIPTS_DIR)/generate_comprehensive_report.sh $(DEMO_RUN_ID)

help:
	@echo "Available commands:"
	@echo ""
	@echo "Basic Operations:"
	@echo "  make up                - Start all Docker services."
	@echo "  make down              - Stop and remove all Docker services."
	@echo "  make logs              - Follow logs from all services."
	@echo "  make ps                - Show running Docker containers."
	@echo "  make build             - Rebuild Docker images without cache."
	@echo "  make clean-artifacts   - Remove all files from ./artifacts directory."
	@echo ""
	@echo "Demo & Testing:"
	@echo "  make demo              - Run the original demo sequence (open relay test)."
	@echo "  make comprehensive-test - Run comprehensive security tests (all 5 experiments)."
	@echo "  make run-checks        - Run all security checks without hardening."
	@echo ""
	@echo "Individual Security Tests:"
	@echo "  make check-starttls    - Test STARTTLS downgrade vulnerabilities."
	@echo "  make check-relay       - Test open relay vulnerabilities."
	@echo "  make check-dns         - Test DNS recursion and DANE/MTA-STS."
	@echo "  make check-auth        - Test plaintext authentication vulnerabilities."
	@echo "  make check-spfdkim     - Test SPF/DKIM/DMARC authentication."
	@echo ""
	@echo "Configuration Management:"
	@echo "  make postfix-harden    - Apply security hardening to Postfix."
	@echo "  make postfix-restore   - Restore vulnerable Postfix configuration."
	@echo ""
	@echo "Analysis & Reporting:"
	@echo "  make analyze-all       - Analyze PCAPs from demo stages."
	@echo "  make generate-report   - Generate HTML security report."
	@echo ""
	@echo "Advanced:"
	@echo "  make exec SCRIPT=<name> [ARGS=\"<args>\"] - Execute custom script."

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
	@echo "Quick Start:"
	@echo "  make comprehensive-test - 🚀 Full automated security testing"
	@echo "  make status            - 📊 Show current lab status"
	@echo "  make security-assessment - 🔒 Complete security evaluation"
	@echo ""
	@echo "Basic Operations:"
	@echo "  make up                - Start all containers"
	@echo "  make demo              - Quick open relay demo"
	@echo "  make clean             - Stop and remove containers"
	@echo "  make deep-clean        - Complete cleanup (containers + data)"
	@echo ""
	@echo "Security Tests:"
	@echo "  make attack-all        - Run all security attack scripts"
	@echo "  make check-starttls    - Test STARTTLS downgrade vulnerabilities"
	@echo "  make check-relay       - Test open relay vulnerabilities"
	@echo "  make check-dns         - Test DNS recursion and DANE/MTA-STS"
	@echo "  make check-auth        - Test plaintext authentication"
	@echo "  make check-spfdkim     - Test SPF/DKIM/DMARC authentication"
	@echo ""
	@echo "Analysis & Reporting:"
	@echo "  make cvss-analysis     - 📈 Generate CVSS 3.1 risk scores"
	@echo "  make smtp-response-analysis - 📧 Analyze SMTP response patterns"
	@echo "  make generate-report   - 📄 Create comprehensive HTML report"
	@echo "  make analyze-all       - Analyze all captured packet data"
	@echo ""
	@echo "Configuration:"
	@echo "  make postfix-harden    - Apply security hardening"
	@echo "  make postfix-restore   - Restore vulnerable configuration"
	@echo ""
	@echo "Development & Debug:"
	@echo "  make debug-logs        - Show container logs and debug info"
	@echo "  make exec SCRIPT=<name> - Execute custom script in controller"
	@echo ""
	@echo "Example Workflows:"
	@echo "  # Complete assessment:"
	@echo "  make security-assessment"
	@echo ""
	@echo "  # Custom testing:"
	@echo "  make up && make attack-all && make cvss-analysis"
	@echo ""
	@echo "  # Debug issues:"
	@echo "  make status && make debug-logs"