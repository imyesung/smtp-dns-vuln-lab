#!/bin/bash
# SMTP Open Relay Attack Script - Enhanced with common utilities

# 공통 함수 로드
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils.sh"

# 공통 초기화
init_common
SCRIPT_START_TIME=$(date +%s)

# 인자로 ATTACK_ID 받기
ATTACK_ID="$1"
if [[ -z "$ATTACK_ID" ]]; then
    ATTACK_ID=$(generate_attack_id "ORT")
fi

log_info "Starting SMTP Open Relay Attack - ID: $ATTACK_ID"

# 필수 명령어 확인
check_required_commands swaks nc ping || exit 1

# 설정 변수
TARGET="mail-postfix"
TARGET_IP="$TARGET"
PORT=25
FROM="attacker@external.com"
TO="postmaster@localhost"  # 일반적으로 존재하는 메일박스
SUBJECT="Open Relay Test"
BODY="This is an open relay test."

log_info "Target: $TARGET:$PORT"

# 로그 설정
LOG_DIR="/artifacts"
LOG_FILE="${LOG_DIR}/openrelay_${ATTACK_ID}.log"
ensure_directory "$LOG_DIR"
safe_logfile "$LOG_FILE"

# 네트워크 연결성 사전 확인
log_step "Performing network connectivity checks..."
test_dns_resolution "$TARGET" || log_warn "DNS resolution failed for $TARGET"
test_network_connectivity "$TARGET" "$PORT" 10 || {
    log_error "Cannot connect to $TARGET:$PORT"
    exit 1
}

# 1. 공격 시작 로그
log_step "Starting open relay attack..."
START_INFO_JSON=$(generate_experiment_json "$ATTACK_ID" "attack_start" "RUNNING" "Open relay test started")
echo "$START_INFO_JSON" >> "$LOG_FILE"

# 추가 상세 정보 로깅
DETAILED_START_JSON=$(cat <<EOF
{
    "event_type": "attack_start_details",
    "attack_id": "$ATTACK_ID",
    "timestamp_utc": "$(iso8601_now)",
    "target_host": "$TARGET",
    "target_port": $PORT,
    "from_address": "$FROM",
    "to_address": "$TO",
    "subject": "$SUBJECT",
    "body_preview": "$(echo "$BODY" | head -c 50)"
}
EOF
)
echo "$DETAILED_START_JSON" >> "$LOG_FILE"

# 2. SWAKS 옵션 구성
log_step "Configuring SWAKS options..."
SWAKS_OPTS=(
  --to "$TO"
  --from "$FROM"
  --server "$TARGET_IP"
  --port "$PORT"
  --timeout 30
  --header "Subject: $SUBJECT"
  --body "$BODY"
  --suppress-data
)

log_info "SWAKS options: ${SWAKS_OPTS[*]}"

# 3. SWAKS 실행
log_step "Executing SWAKS attack..."
TEMP_OUTPUT=$(mktemp)
TEMP_FILES="$TEMP_FILES $TEMP_OUTPUT"

# SWAKS 실행 - exit code를 별도로 처리
set +e  # 일시적으로 errexit 비활성화
swaks "${SWAKS_OPTS[@]}" > "$TEMP_OUTPUT" 2>&1
EXIT_CODE=$?
set -e  # errexit 다시 활성화

log_info "SWAKS finished with exit code: $EXIT_CODE"

# SWAKS 출력 처리 (JSON 안전 형태로 변환)
SWAKS_RAW_OUTPUT=$(awk '{printf "%s\\n", $0}' "$TEMP_OUTPUT" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g' | sed '$ s/\\n$//')

# 임시 파일 즉시 정리
rm -f "$TEMP_OUTPUT" && log_info "Removed temporary file: $TEMP_OUTPUT" || true

# 4. SMTP 트랜잭션 결과 로깅
SMTP_RESULT_JSON=$(cat <<EOF
{
    "event_type": "smtp_transaction",
    "attack_id": "$ATTACK_ID",
    "timestamp_utc": "$(iso8601_now)",
    "swaks_exit_code": $EXIT_CODE,
    "swaks_raw_output": "$SWAKS_RAW_OUTPUT"
}
EOF
)
echo "$SMTP_RESULT_JSON" >> "$LOG_FILE"

# 5. 결과 분석
log_step "Analyzing attack results..."
RESULT_STATUS=""
RESULT_MESSAGE=""

case $EXIT_CODE in
    0)
        RESULT_STATUS="SUCCESS"
        RESULT_MESSAGE="오픈 릴레이 취약점 확인됨: SMTP 명령 실행 성공"
        log_warn "VULNERABLE: Open relay detected!"
        ;;
    23|24|25)
        if echo "$SWAKS_RAW_OUTPUT" | grep -q "reject_unauth_destination"; then
            RESULT_STATUS="BLOCKED"
            RESULT_MESSAGE="오픈 릴레이 차단됨: reject_unauth_destination 정책으로 외부 릴레이 거부"
            log_info "SECURE: Open relay properly blocked by policy"
        elif echo "$SWAKS_RAW_OUTPUT" | grep -q "Relay access denied"; then
            RESULT_STATUS="BLOCKED"
            RESULT_MESSAGE="오픈 릴레이 차단됨: 릴레이 접근 거부"
            log_info "SECURE: Relay access properly denied"
        elif echo "$SWAKS_RAW_OUTPUT" | grep -q "554.*5.7.1"; then
            RESULT_STATUS="BLOCKED"
            RESULT_MESSAGE="오픈 릴레이 차단됨: 릴레이 정책으로 거부됨"
            log_info "SECURE: Relay blocked by security policy"
        elif echo "$SWAKS_RAW_OUTPUT" | grep -q "Access denied"; then
            RESULT_STATUS="BLOCKED"
            RESULT_MESSAGE="오픈 릴레이 차단됨: 클라이언트 호스트 접근 거부"
            log_info "SECURE: Client host access properly denied"
        else
            RESULT_STATUS="BLOCKED"
            RESULT_MESSAGE="오픈 릴레이 차단됨: SMTP 연결 거부됨 (종료 코드: $EXIT_CODE)"
            log_info "SECURE: Open relay blocked (exit code: $EXIT_CODE)"
        fi
        ;;
    *)
        RESULT_STATUS="FAILURE"
        RESULT_MESSAGE="SMTP 테스트 실행 오류 (종료 코드: $EXIT_CODE)"
        log_error "FAILED: SMTP test execution error"
        ;;
esac

# 6. 공격 종료 로그
END_INFO_JSON=$(generate_experiment_json "$ATTACK_ID" "attack_end" "$RESULT_STATUS" "$RESULT_MESSAGE")
echo "$END_INFO_JSON" >> "$LOG_FILE"

# 7. 요약 로그 생성
SUMMARY_LOG="${LOG_DIR}/openrelay_summary.log"
safe_logfile "$SUMMARY_LOG"
echo "$(date '+%Y-%m-%d %H:%M:%S') [$ATTACK_ID] Target: $TARGET:$PORT, Result: $RESULT_STATUS (ExitCode: $EXIT_CODE)" >> "$SUMMARY_LOG"

# 8. 결과 출력
log_info "=== Attack Summary ==="
log_info "Attack ID: $ATTACK_ID"
log_info "Target: $TARGET:$PORT"
log_info "Status: $RESULT_STATUS"
log_info "Message: $RESULT_MESSAGE"
log_info "Log file: $LOG_FILE"

# 9. 스크립트 완료
show_script_completion "attack_openrelay.sh" "$SCRIPT_START_TIME"

# 10. 적절한 종료 코드 반환
case "$RESULT_STATUS" in
    "SUCCESS"|"BLOCKED"|"PARTIAL_SUCCESS")
        log_info "Test completed successfully (Status: $RESULT_STATUS)"
        exit 0
        ;;
    *)
        log_error "Test failed with exit code $EXIT_CODE"
        exit "$EXIT_CODE"
        ;;
esac
