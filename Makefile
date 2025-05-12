# Makefile for SMTP & DNS Vulnerability Lab

# Shell to use
SHELL := /bin/bash

# Docker Compose command
COMPOSE := docker-compose

# Controller container name
CONTROLLER_CONTAINER := controller

# Scripts directory within the controller container
SCRIPTS_DIR := /scripts

# Artifacts directory (mounted in controller and mua-debian)
ARTIFACTS_DIR := /artifacts

# Default Attack ID Prefix
ATTACK_ID_PREFIX := EXP

# Generate a unique ID for each full demo run or use a fixed one for simplicity
# This approach uses a timestamp for uniqueness in full demos.
# For individual steps, fixed IDs are used for clarity.
CURRENT_TIMESTAMP := $(shell date +%Y%m%d_%H%M%S)
DEMO_RUN_ID := $(ATTACK_ID_PREFIX)_$(CURRENT_TIMESTAMP)

# --- Helper Functions (as shell variables) ---
# Function to wait for file to exist (with timeout)
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

# --- Docker Environment Control ---
.PHONY: up down logs ps build clean-artifacts

# Start all services in detached mode
up:
	@echo "INFO: Starting all Docker services..."
	$(COMPOSE) up -d --build || { echo "ERROR: Failed to start Docker services"; exit 1; }

# Stop and remove all services
down:
	@echo "INFO: Stopping and removing all Docker services..."
	$(COMPOSE) down -v || { echo "ERROR: Failed to stop Docker services"; exit 1; }

# Show logs for all services
logs:
	$(COMPOSE) logs -f

# Show running containers
ps:
	$(COMPOSE) ps

# Force build images
build:
	@echo "INFO: Building Docker images..."
	$(COMPOSE) build --no-cache || { echo "ERROR: Failed to build Docker images"; exit 1; }

# Clean artifacts directory (use with caution)
clean-artifacts:
	@echo "WARNING: This will remove all files in ./artifacts. Are you sure? (y/N)"
	@read -r response; \
	if [[ "$$response" =~ ^([yY][eE][sS]|[yY]) ]]; then \
		echo "INFO: Cleaning ./artifacts directory..."; \
		rm -rf ./artifacts/* || { echo "ERROR: Failed to clean artifacts directory"; exit 1; }; \
		mkdir -p ./artifacts || { echo "ERROR: Failed to create artifacts directory"; exit 1; }; \
		echo "INFO: ./artifacts directory cleaned."; \
	else \
		echo "INFO: Cleanup cancelled."; \
	fi


# --- Experiment Workflow ---
.PHONY: demo demo-before capture-start-before attack-before capture-stop-before analyze-before harden demo-after capture-start-after attack-after capture-stop-after analyze-after report

# Full Demo
demo: up demo-before harden demo-after analyze-all report-placeholder down
	@echo "INFO: Full demo sequence complete. Run ID: $(DEMO_RUN_ID)"

# Stage 1: Before Hardening
demo-before:
	@echo "INFO: === Stage: Before Hardening (ID: $(DEMO_RUN_ID)_BEFORE) ==="
	@echo "INFO: Starting packet capture..."
	
	# Start capture and save signal file when ready
	docker exec $(CONTROLLER_CONTAINER) bash -c "$(SCRIPTS_DIR)/capture_smtp.sh $(DEMO_RUN_ID)_BEFORE & \
		echo \$$! > /tmp/capture.pid && \
		touch /tmp/capture_started && \
		echo 'INFO: Capture started with PID: '\$$(cat /tmp/capture.pid)" || \
		{ echo "ERROR: Failed to start packet capture"; exit 1; }
	
	# Wait for capture to be ready (file exists check)
	docker exec $(CONTROLLER_CONTAINER) bash -c "timeout=30; \
		counter=0; \
		while [ ! -f /tmp/capture_started ] && [ \$$counter -lt \$$timeout ]; do \
			counter=\$$((counter + 1)); \
			sleep 1; \
			if [ \$$((counter % 5)) -eq 0 ]; then \
				echo 'INFO: Waiting for capture to start... (\$$counter/\$$timeout)'; \
			fi; \
		done; \
		if [ ! -f /tmp/capture_started ]; then \
			echo 'ERROR: Timed out waiting for capture to start'; \
			exit 1; \
		fi; \
		echo 'INFO: Capture confirmed started'" || \
		{ echo "ERROR: Capture startup verification failed"; exit 1; }
	
	@echo "INFO: Running attack script..."
	docker exec $(CONTROLLER_CONTAINER) $(SCRIPTS_DIR)/attack_openrelay.sh $(DEMO_RUN_ID)_BEFORE || \
		{ echo "ERROR: Attack script failed"; exit 1; }
	
	@echo "INFO: Attack finished. Waiting for capture to complete..."
	
	# Wait for PCAP file to appear (with reasonable timeout)
	docker exec $(CONTROLLER_CONTAINER) bash -c "timeout=90; \
		counter=0; \
		while [ ! -f $(ARTIFACTS_DIR)/smtp_$(DEMO_RUN_ID)_BEFORE.pcap ] && [ \$$counter -lt \$$timeout ]; do \
			counter=\$$((counter + 1)); \
			sleep 1; \
			if [ \$$((counter % 10)) -eq 0 ]; then \
				echo 'INFO: Waiting for PCAP file... (\$$counter/\$$timeout)'; \
			fi; \
		done; \
		if [ ! -f $(ARTIFACTS_DIR)/smtp_$(DEMO_RUN_ID)_BEFORE.pcap ]; then \
			echo 'ERROR: Timed out waiting for PCAP file'; \
			exit 1; \
		fi; \
		echo 'INFO: PCAP file detected'" || \
		{ echo "ERROR: PCAP file verification failed"; exit 1; }
	
	@echo "INFO: Analyzing PCAP for BEFORE state..."
	docker exec $(CONTROLLER_CONTAINER) $(SCRIPTS_DIR)/analyze_pcap.sh $(ARTIFACTS_DIR)/smtp_$(DEMO_RUN_ID)_BEFORE.pcap || \
		{ echo "ERROR: PCAP analysis failed"; exit 1; }
	
	@echo "INFO: --- Before Hardening Stage Complete ---"

# Stage 2: Apply Hardening
harden:
	@echo "INFO: === Stage: Applying Hardening ==="
	docker exec $(CONTROLLER_CONTAINER) $(SCRIPTS_DIR)/harden_postfix.sh || \
		{ echo "ERROR: Hardening process failed"; exit 1; }
	@echo "INFO: --- Hardening Stage Complete ---"

# Stage 3: After Hardening
demo-after:
	@echo "INFO: === Stage: After Hardening (ID: $(DEMO_RUN_ID)_AFTER) ==="
	@echo "INFO: Starting packet capture..."
	
	# Similar approach as demo-before with error handling
	docker exec $(CONTROLLER_CONTAINER) bash -c "$(SCRIPTS_DIR)/capture_smtp.sh $(DEMO_RUN_ID)_AFTER & \
		echo \$$! > /tmp/capture.pid && \
		touch /tmp/capture_started_after && \
		echo 'INFO: Capture started with PID: '\$$(cat /tmp/capture.pid)" || \
		{ echo "ERROR: Failed to start packet capture"; exit 1; }
	
	# Wait for capture to be ready
	docker exec $(CONTROLLER_CONTAINER) bash -c "timeout=30; \
		counter=0; \
		while [ ! -f /tmp/capture_started_after ] && [ \$$counter -lt \$$timeout ]; do \
			counter=\$$((counter + 1)); \
			sleep 1; \
			if [ \$$((counter % 5)) -eq 0 ]; then \
				echo 'INFO: Waiting for capture to start... (\$$counter/\$$timeout)'; \
			fi; \
		done; \
		if [ ! -f /tmp/capture_started_after ]; then \
			echo 'ERROR: Timed out waiting for capture to start'; \
			exit 1; \
		fi; \
		echo 'INFO: Capture confirmed started'" || \
		{ echo "ERROR: Capture startup verification failed"; exit 1; }
	
	@echo "INFO: Running attack script..."
	docker exec $(CONTROLLER_CONTAINER) $(SCRIPTS_DIR)/attack_openrelay.sh $(DEMO_RUN_ID)_AFTER || \
		{ echo "ERROR: Attack script failed"; exit 1; }
	
	@echo "INFO: Attack finished. Waiting for capture to complete..."
	
	# Wait for PCAP file
	docker exec $(CONTROLLER_CONTAINER) bash -c "timeout=90; \
		counter=0; \
		while [ ! -f $(ARTIFACTS_DIR)/smtp_$(DEMO_RUN_ID)_AFTER.pcap ] && [ \$$counter -lt \$$timeout ]; do \
			counter=\$$((counter + 1)); \
			sleep 1; \
			if [ \$$((counter % 10)) -eq 0 ]; then \
				echo 'INFO: Waiting for PCAP file... (\$$counter/\$$timeout)'; \
			fi; \
		done; \
		if [ ! -f $(ARTIFACTS_DIR)/smtp_$(DEMO_RUN_ID)_AFTER.pcap ]; then \
			echo 'ERROR: Timed out waiting for PCAP file'; \
			exit 1; \
		fi; \
		echo 'INFO: PCAP file detected'" || \
		{ echo "ERROR: PCAP file verification failed"; exit 1; }
	
	@echo "INFO: Analyzing PCAP for AFTER state..."
	docker exec $(CONTROLLER_CONTAINER) $(SCRIPTS_DIR)/analyze_pcap.sh $(ARTIFACTS_DIR)/smtp_$(DEMO_RUN_ID)_AFTER.pcap || \
		{ echo "ERROR: PCAP analysis failed"; exit 1; }
	
	@echo "INFO: --- After Hardening Stage Complete ---"

analyze-all:
	@echo "INFO: === Stage: Analyzing all data ==="
	@echo "INFO: Analyzing PCAP for BEFORE state (ID: $(DEMO_RUN_ID)_BEFORE)..."
	docker exec $(CONTROLLER_CONTAINER) $(SCRIPTS_DIR)/analyze_pcap.sh $(ARTIFACTS_DIR)/smtp_$(DEMO_RUN_ID)_BEFORE.pcap \
		$(ARTIFACTS_DIR)/analysis_$(DEMO_RUN_ID)_BEFORE.txt || \
		{ echo "ERROR: BEFORE state analysis failed"; exit 1; }
	
	@echo "INFO: Analyzing PCAP for AFTER state (ID: $(DEMO_RUN_ID)_AFTER)..."
	docker exec $(CONTROLLER_CONTAINER) $(SCRIPTS_DIR)/analyze_pcap.sh $(ARTIFACTS_DIR)/smtp_$(DEMO_RUN_ID)_AFTER.pcap \
		$(ARTIFACTS_DIR)/analysis_$(DEMO_RUN_ID)_AFTER.txt || \
		{ echo "ERROR: AFTER state analysis failed"; exit 1; }
	
	@echo "INFO: --- Analysis Stage Complete ---"

report-placeholder:
	@echo "INFO: === Stage: Generating Report (Placeholder) ==="
	@echo "INFO: Report generation script (gen_report_html.sh) is not yet implemented."
	@echo "INFO: Manual check of artifacts recommended:"
	@echo "INFO: Attack logs: $(ARTIFACTS_DIR)/openrelay_$(DEMO_RUN_ID)_BEFORE.log, $(ARTIFACTS_DIR)/openrelay_$(DEMO_RUN_ID)_AFTER.log"
	@echo "INFO: PCAP analysis: $(ARTIFACTS_DIR)/analysis_$(DEMO_RUN_ID)_BEFORE.txt, $(ARTIFACTS_DIR)/analysis_$(DEMO_RUN_ID)_AFTER.txt"
	@echo "INFO: --- Report Placeholder Complete ---"

# --- Utility Targets ---
.PHONY: help

help:
	@echo "Available commands:"
	@echo "  make up                - Start all Docker services."
	@echo "  make down              - Stop and remove all Docker services."
	@echo "  make logs              - Follow logs from all services."
	@echo "  make ps                - Show running Docker containers."
	@echo "  make build             - Rebuild Docker images without cache."
	@echo "  make clean-artifacts   - Remove all files from ./artifacts directory."
	@echo ""
	@echo "  make demo              - Run the full demo sequence (up, before, harden, after, analyze, report-placeholder, down)."
	@echo "  make demo-before       - Run tests before hardening (capture, attack, analyze)."
	@echo "  make harden            - Apply Postfix hardening."
	@echo "  make demo-after        - Run tests after hardening (capture, attack, analyze)."
	@echo "  make analyze-all       - Analyze PCAPs from both before and after stages."
	@echo "  make report-placeholder- Generate a placeholder report message (actual report script to be implemented)."
	@echo ""
	@echo "  Individual script execution examples (manual IDs recommended):"
	@echo "  make exec SCRIPT=attack_openrelay.sh ARGS=MY_TEST_ID"
	@echo "  make exec SCRIPT=analyze_pcap.sh ARGS=/artifacts/smtp_MY_TEST_ID.pcap"

# Generic script exec target
exec:
ifndef SCRIPT
	$(error SCRIPT is not set. Usage: make exec SCRIPT=<script_name.sh> [ARGS="<arguments>"])
endif
	@echo "INFO: Executing $(SCRIPTS_DIR)/$(SCRIPT) $(ARGS) in $(CONTROLLER_CONTAINER)..."
	docker exec $(CONTROLLER_CONTAINER) $(SCRIPTS_DIR)/$(SCRIPT) $(ARGS) || \
		{ echo "ERROR: Script execution failed"; exit 1; }