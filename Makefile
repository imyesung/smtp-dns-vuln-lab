# Makefile for SMTP & DNS Vulnerability Lab

SHELL := /bin/bash
COMPOSE := docker-compose
CONTROLLER_CONTAINER := controller
SCRIPTS_DIR := /scripts
ARTIFACTS_DIR := /artifacts # 컨테이너 내부 경로용
HOST_ARTIFACTS_DIR := ./artifacts # 호스트 경로용
ATTACK_ID_PREFIX := EXP
CURRENT_TIMESTAMP := $(shell LC_ALL=C date +%Y%m%d_%H%M%S)
DEMO_RUN_ID := $(ATTACK_ID_PREFIX)_$(CURRENT_TIMESTAMP)

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

.PHONY: up down logs ps build clean-artifacts demo demo-before demo-after analyze-all help exec postfix-restore postfix-harden report-placeholder

up:
	@echo "INFO: Starting all Docker services..."
	$(COMPOSE) up -d --build

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

demo: up demo-before postfix-harden demo-after analyze-all report-placeholder postfix-restore down
	@echo "INFO: Full demo sequence complete. Run ID: $(DEMO_RUN_ID)"

demo-before:
	@echo "INFO: === Stage: Before Hardening (ID: $(DEMO_RUN_ID)_BEFORE) ==="
	docker exec $(CONTROLLER_CONTAINER) bash -c "$(SCRIPTS_DIR)/capture_smtp.sh $(DEMO_RUN_ID)_BEFORE & echo \$$! > /tmp/capture.pid && touch $(ARTIFACTS_DIR)/capture_started"
	$(call wait_for_file,$(HOST_ARTIFACTS_DIR)/capture_started,30)
	docker exec $(CONTROLLER_CONTAINER) $(SCRIPTS_DIR)/attack_openrelay.sh $(DEMO_RUN_ID)_BEFORE
	$(call wait_for_file,$(HOST_ARTIFACTS_DIR)/smtp_$(DEMO_RUN_ID)_BEFORE.pcap,90)
	docker exec $(CONTROLLER_CONTAINER) $(SCRIPTS_DIR)/analyze_pcap.sh $(ARTIFACTS_DIR)/smtp_$(DEMO_RUN_ID)_BEFORE.pcap $(ARTIFACTS_DIR)/analysis_$(DEMO_RUN_ID)_BEFORE.txt
	cp configs/postfix/main.cf configs/postfix/main.cf.bak

postfix-restore:
	@echo "INFO: [postfix-restore] main.cf 원본 복원 및 postfix reload"
	if [ -f configs/postfix/main.cf.bak ]; then \
		mv configs/postfix/main.cf.bak configs/postfix/main.cf; \
		echo "INFO: [postfix-restore] 복원 완료"; \
	else \
		echo "WARN: main.cf.bak 파일이 없어 복원 생략"; \
		echo "INFO: Recreating main.cf with default content..."; \
		cat <<EOF > configs/postfix/main.cf; \
	EOF
	# Default Postfix Configuration
	smtpd_recipient_restrictions = permit_mynetworks, reject_unauth_destination
	smtpd_helo_required = no
	disable_vrfy_command = no
	EOF
		echo "INFO: Default main.cf recreated."; \
	fi
	@echo "INFO: Reloading postfix in container..."
	docker exec mail-postfix postfix reload && \
		echo "INFO: Postfix reload 성공" || \
		(echo "ERROR: Postfix reload 실패"; exit 1)

	# main.cf 설정 안전하게 갱신 예시
	@echo "INFO: smtpd_helo_required 설정 갱신"
	if grep -q '^smtpd_helo_required' configs/postfix/main.cf; then \
		sed -i '' 's/^smtpd_helo_required.*/smtpd_helo_required = yes/' configs/postfix/main.cf; \
	else \
		echo "smtpd_helo_required = yes" >> configs/postfix/main.cf; \
	fi

postfix-harden:
	@echo "INFO: Hardening Postfix..."
	docker exec $(CONTROLLER_CONTAINER) $(SCRIPTS_DIR)/harden_postfix.sh
	@echo "INFO: Reloading Postfix..."
	docker exec mail-postfix postfix reload
	@echo "INFO: Postfix hardened successfully."

demo-after:
	@echo "INFO: === Stage: After Hardening (ID: $(DEMO_RUN_ID)_AFTER) ==="
	docker exec $(CONTROLLER_CONTAINER) bash -c "$(SCRIPTS_DIR)/capture_smtp.sh $(DEMO_RUN_ID)_AFTER & echo \$$! > /tmp/capture.pid && touch $(ARTIFACTS_DIR)/capture_started_after"
	$(call wait_for_file,$(HOST_ARTIFACTS_DIR)/capture_started_after,30)
	docker exec $(CONTROLLER_CONTAINER) $(SCRIPTS_DIR)/attack_openrelay.sh $(DEMO_RUN_ID)_AFTER
	$(call wait_for_file,$(HOST_ARTIFACTS_DIR)/smtp_$(DEMO_RUN_ID)_AFTER.pcap,90)
	docker exec $(CONTROLLER_CONTAINER) $(SCRIPTS_DIR)/analyze_pcap.sh $(ARTIFACTS_DIR)/smtp_$(DEMO_RUN_ID)_AFTER.pcap $(ARTIFACTS_DIR)/analysis_$(DEMO_RUN_ID)_AFTER.txt

analyze-all:
	@echo "INFO: Analyzing PCAPs for BEFORE and AFTER states..."
	docker exec $(CONTROLLER_CONTAINER) $(SCRIPTS_DIR)/analyze_pcap.sh $(ARTIFACTS_DIR)/smtp_$(DEMO_RUN_ID)_BEFORE.pcap $(ARTIFACTS_DIR)/analysis_$(DEMO_RUN_ID)_BEFORE.txt
	docker exec $(CONTROLLER_CONTAINER) $(SCRIPTS_DIR)/analyze_pcap.sh $(ARTIFACTS_DIR)/smtp_$(DEMO_RUN_ID)_AFTER.pcap $(ARTIFACTS_DIR)/analysis_$(DEMO_RUN_ID)_AFTER.txt

report-placeholder:
	@echo "INFO: (Placeholder) Report generation skipped or done."

help:
	@echo "Available commands:"
	@echo "  make up                - Start all Docker services."
	@echo "  make down              - Stop and remove all Docker services."
	@echo "  make logs              - Follow logs from all services."
	@echo "  make ps                - Show running Docker containers."
	@echo "  make build             - Rebuild Docker images without cache."
	@echo "  make clean-artifacts   - Remove all files from ./artifacts directory."
	@echo ""
	@echo "  make demo              - Run the full demo sequence."
	@echo "  make demo-before       - Run tests before hardening."
	@echo "  make demo-after        - Run tests after hardening."
	@echo "  make analyze-all       - Analyze PCAPs from both stages."
	@echo "  make postfix-restore   - Restore postfix config to default or backup."
	@echo ""
	@echo "  make exec SCRIPT=<script.sh> ARGS=\"<args>\" - Run arbitrary script inside controller container."

exec:
ifndef SCRIPT
	$(error SCRIPT is not set. Usage: make exec SCRIPT=<script_name.sh> [ARGS="<arguments>"])
endif
	@echo "INFO: Executing $(SCRIPTS_DIR)/$(SCRIPT) $(ARGS) in $(CONTROLLER_CONTAINER)..."
	docker exec $(CONTROLLER_CONTAINER) $(SCRIPTS_DIR)/$(SCRIPT) $(ARGS)