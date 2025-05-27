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

.PHONY: up down logs ps build clean-artifacts demo demo-before demo-after analyze-all help exec postfix-restore postfix-harden generate-report

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

help:
	@echo "Available commands:"
	@echo "  make up                - Start all Docker services."
	@echo "  make down              - Stop and remove all Docker services."
	@echo "  make logs              - Follow logs from all services."
	@echo "  make ps                - Show running Docker containers."
	@echo "  make build             - Rebuild Docker images without cache."
	@echo "  make clean-artifacts   - Remove all files from ./artifacts directory."
	@echo "  make demo              - Run the full demo sequence."
	@echo "  make demo-before       - Run tests before hardening."
	@echo "  make demo-after        - Run tests after hardening."
	@echo "  make analyze-all       - Analyze PCAPs from both stages."
	@echo "  make postfix-restore   - Restore postfix config to default or backup."
	@echo "  make generate-report   - Generate an HTML security report from analysis files."

exec:
ifndef SCRIPT
	$(error SCRIPT is not set. Usage: make exec SCRIPT=<script_name.sh> [ARGS="<arguments>"])
endif
	@echo "INFO: Executing $(SCRIPTS_DIR)/$(SCRIPT) $(ARGS) in $(CONTROLLER_CONTAINER)..."
	docker exec $(CONTROLLER_CONTAINER) $(SCRIPTS_DIR)/$(SCRIPT) $(ARGS)