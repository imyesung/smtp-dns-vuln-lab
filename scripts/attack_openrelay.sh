#!/bin/bash
set -x

# 인자로 ATTACK_ID 받기
ATTACK_ID="$1"
if [[ -z "$ATTACK_ID" ]]; then
    TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
    ATTACK_ID="ORT-${TIMESTAMP}"
fi

# 설정 변수
TARGET="mail-postfix"
TARGET_IP="$TARGET"

echo "INFO: TARGET=$TARGET, TARGET_IP=$TARGET_IP"

# 네트워크 디버깅 추가 (공격 전)
echo "DEBUG: Network debugging before attack..."
echo "DEBUG: Checking DNS resolution..."
nslookup mail-postfix || echo "DEBUG: nslookup failed"
echo "DEBUG: Checking network connectivity..."
ping -c 1 mail-postfix || echo "DEBUG: ping failed"
echo "DEBUG: Checking port connectivity..."
nc -zv mail-postfix 25 -w 5

PORT=25
# DNS 조회 실패를 피하기 위해 로컬 도메인 사용
FROM="attacker@external.com"
TO="victim@localhost"  # localhost로 변경하여 DNS 조회 회피
SUBJECT="Open Relay Test"
BODY="This is an open relay test."
LOG_DIR="/artifacts"
LOG_FILE="${LOG_DIR}/openrelay_${ATTACK_ID}.log"

mkdir -p "$LOG_DIR"

# 1. 공격 시작 로그
CURRENT_ISO_TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M%SZ")
START_INFO_JSON=$(cat <<EOF
{
"event_type": "attack_start",
"attack_id": "$ATTACK_ID",
"timestamp_utc": "$CURRENT_ISO_TIMESTAMP",
"target_host": "$TARGET",
"target_port": $PORT,
"from_address": "$FROM",
"to_address": "$TO",
"subject": "$SUBJECT",
"body_preview": "$(echo "$BODY" | head -c 50)"
}
EOF
)
echo "$START_INFO_JSON" | sed 's/^[[:space:]]*//' >> "$LOG_FILE"

# 네트워크 연결 테스트
NC_TEST_TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M%SZ")
NC_OUTPUT_FILE=$(mktemp "${LOG_DIR}/nc_output_${ATTACK_ID}_XXXXXX.tmp")
echo "INFO: Attempting to connect to $TARGET:$PORT with netcat..." >> "$NC_OUTPUT_FILE"
if nc -zv "$TARGET" "$PORT" -w 5 >> "$NC_OUTPUT_FILE" 2>&1; then
  NC_EXIT_CODE=0
  NC_STATUS="SUCCESS"
  echo "INFO: Netcat connection to $TARGET:$PORT successful." >> "$NC_OUTPUT_FILE"
else
  NC_EXIT_CODE=$?
  NC_STATUS="FAILURE"
fi
NC_RAW_OUTPUT=$(awk '{printf "%s\\n", $0}' "$NC_OUTPUT_FILE" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g' | sed '$ s/\\n$//')
rm "$NC_OUTPUT_FILE"

NC_TEST_JSON=$(cat <<EOF
{
"event_type": "network_connectivity_test",
"attack_id": "$ATTACK_ID",
"timestamp_utc": "$NC_TEST_TIMESTAMP",
"target_host": "$TARGET",
"target_port": $PORT,
"tool": "netcat",
"exit_code": $NC_EXIT_CODE,
"status": "$NC_STATUS",
"raw_output": "$NC_RAW_OUTPUT"
}
EOF
)
echo "$NC_TEST_JSON" | sed 's/^[[:space:]]*//' >> "$LOG_FILE"

# 연결 대기
echo "INFO: Waiting for mail server to be ready..."
for attempt in {1..10}; do
    if nc -zv "$TARGET_IP" "$PORT" -w 5 >/dev/null 2>&1; then
        echo "INFO: Mail server ready on attempt $attempt"
        break
    fi
    echo "INFO: Attempt $attempt/10 failed, retrying in 2 seconds..."
    sleep 2
    if [ $attempt -eq 10 ]; then
        echo "ERROR: Mail server not ready after 10 attempts"
        exit 1
    fi
done

# SWAKS 옵션 - 단순화
SWAKS_OPTS=(
  --to "$TO"
  --from "$FROM"
  --server "$TARGET_IP"
  --port "$PORT"
  --timeout 10
  --header "Subject: $SUBJECT"
  --body "$BODY"
  --quit-after "RCPT"  # RCPT TO 단계까지만 테스트
)

echo "DEBUG: SWAKS_OPTS array: ${SWAKS_OPTS[@]}"
echo "DEBUG: About to run swaks command..."

# swaks 실행
SWAKS_OUTPUT_FILE=$(mktemp "${LOG_DIR}/swaks_raw_${ATTACK_ID}_XXXXXX.tmp")
swaks "${SWAKS_OPTS[@]}" > "$SWAKS_OUTPUT_FILE" 2>&1
EXIT_CODE=$?
echo "DEBUG: swaks command finished with exit code: $EXIT_CODE"

# swaks 출력 처리
SWAKS_RAW_OUTPUT=$(awk '{printf "%s\\n", $0}' "$SWAKS_OUTPUT_FILE" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g' | sed '$ s/\\n$//')
rm "$SWAKS_OUTPUT_FILE"

# 2. SMTP 트랜잭션 로그
CURRENT_ISO_TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M%SZ")
SMTP_RESULT_JSON=$(cat <<EOF
{
"event_type": "smtp_transaction",
"attack_id": "$ATTACK_ID",
"timestamp_utc": "$CURRENT_ISO_TIMESTAMP",
"swaks_exit_code": $EXIT_CODE,
"swaks_raw_output": "$SWAKS_RAW_OUTPUT"
}
EOF
)
echo "$SMTP_RESULT_JSON" | sed 's/^[[:space:]]*//' >> "$LOG_FILE"

# 결과 분석
RESULT_STATUS=""
RESULT_MESSAGE=""

# swaks 종료 코드별 분석
case $EXIT_CODE in
    0)
        RESULT_STATUS="SUCCESS"
        RESULT_MESSAGE="오픈 릴레이 취약점 확인됨: SMTP 명령 실행 성공"
        ;;
    23|24|25)
        if echo "$SWAKS_RAW_OUTPUT" | grep -q "reject_unauth_destination"; then
            RESULT_STATUS="BLOCKED"
            RESULT_MESSAGE="오픈 릴레이 차단됨: reject_unauth_destination 정책으로 외부 릴레이 거부"
        elif echo "$SWAKS_RAW_OUTPUT" | grep -q "Relay access denied"; then
            RESULT_STATUS="BLOCKED"
            RESULT_MESSAGE="오픈 릴레이 차단됨: 릴레이 접근 거부"
        elif echo "$SWAKS_RAW_OUTPUT" | grep -q "554.*5.7.1"; then
            RESULT_STATUS="BLOCKED"
            RESULT_MESSAGE="오픈 릴레이 차단됨: 릴레이 정책으로 거부됨"
        else
            RESULT_STATUS="PARTIAL_SUCCESS"
            RESULT_MESSAGE="SMTP 연결 성공, 일부 제한 적용됨 (종료 코드: $EXIT_CODE)"
        fi
        ;;
    *)
        RESULT_STATUS="FAILURE"
        RESULT_MESSAGE="SMTP 테스트 실행 오류 (종료 코드: $EXIT_CODE)"
        ;;
esac

# 3. 공격 종료 로그
CURRENT_ISO_TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M%SZ")
END_INFO_JSON=$(cat <<EOF
{
"event_type": "attack_end",
"attack_id": "$ATTACK_ID",
"timestamp_utc": "$CURRENT_ISO_TIMESTAMP",
"final_exit_code": $EXIT_CODE,
"result_status": "$RESULT_STATUS",
"result_message": "$RESULT_MESSAGE"
}
EOF
)
echo "$END_INFO_JSON" | sed 's/^[[:space:]]*//' >> "$LOG_FILE"

# 요약 로그
SUMMARY_LOG="${LOG_DIR}/openrelay_summary.log"
echo "$(date '+%Y-%m-%d %H:%M:%S') [$ATTACK_ID] Target: $TARGET:$PORT, Result: $RESULT_STATUS (ExitCode: $EXIT_CODE)" >> "$SUMMARY_LOG"

echo ""
echo "공격 테스트 완료. 로그 저장 위치: $LOG_FILE (NDJSON 형식)"
echo "공격 ID: $ATTACK_ID (패킷 캡처와 연계 시 사용)"

# 성공한 경우에만 exit 0, 나머지는 원래 exit code 유지
if [ "$RESULT_STATUS" = "SUCCESS" ] || [ "$RESULT_STATUS" = "BLOCKED" ] || [ "$RESULT_STATUS" = "PARTIAL_SUCCESS" ]; then
    echo "INFO: Test completed successfully (Status: $RESULT_STATUS)"
    exit 0
else
    echo "WARNING: Test failed with exit code $EXIT_CODE. See $LOG_FILE for details."
    exit $EXIT_CODE
fi