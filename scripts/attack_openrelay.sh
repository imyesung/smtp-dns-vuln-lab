#!/bin/bash
set -x # 실행되는 모든 명령어를 터미널에 출력

# 인자로 ATTACK_ID 받기
ATTACK_ID="$1"
if [[ -z "$ATTACK_ID" ]]; then
    TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
    ATTACK_ID="ORT-${TIMESTAMP}"
fi

# 설정 변수
TARGET="mail-postfix"
PORT=25
FROM="attacker@example.com"
TO="victim@example.com"
SUBJECT="Open Relay Test"
BODY="This is an unauthenticated mail test."
LOG_DIR="/artifacts"
LOG_FILE="${LOG_DIR}/openrelay_${ATTACK_ID}.log"

mkdir -p "$LOG_DIR"

# 1. 공격 시작 로그
CURRENT_ISO_TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
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

# 네트워크 연결 테스트 (nc 사용)
NC_TEST_TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
NC_OUTPUT_FILE=$(mktemp "${LOG_DIR}/nc_output_${ATTACK_ID}_XXXXXX.tmp")
echo "INFO: Attempting to connect to $TARGET:$PORT with netcat..." >> "$NC_OUTPUT_FILE"
# nc 명령어 실행 결과를 임시 파일에 저장 (표준 출력 및 표준 에러 모두)
if nc -zv "$TARGET" "$PORT" -w 5 >> "$NC_OUTPUT_FILE" 2>&1; then
  NC_EXIT_CODE=0
  NC_STATUS="SUCCESS"
  echo "INFO: Netcat connection to $TARGET:$PORT successful." >> "$NC_OUTPUT_FILE" # 성공 메시지도 파일에 추가
else
  NC_EXIT_CODE=$?
  NC_STATUS="FAILURE"
  # 실패 메시지는 nc가 이미 출력하므로 중복 기록 방지. 필요시 추가 가능
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

# 기본 옵션 선언
SWAKS_OPTS=(
  --to "$TO"
  --from "$FROM"
  --server "$TARGET" # TARGET 변수에는 호스트명만 포함되어야 합니다.
  --port "$PORT"   # PORT 변수에는 포트 번호만 포함되어야 합니다.
  --timeout 10
  --header "Subject: $SUBJECT"
  --body "$BODY"
  --protocol SMTP
)

# --verbose 지원 여부 검사 후 추가
if swaks --help 2>&1 | grep -q -- "--verbose"; then
  SWAKS_OPTS+=("--verbose")
fi

# --show-raw-message 지원 여부 검사 후 추가
if swaks --help 2>&1 | grep -q -- "--show-raw-message"; then
  SWAKS_OPTS+=("--show-raw-message")
fi

echo "DEBUG: SWAKS_OPTS array: ${SWAKS_OPTS[@]}" # SWAKS_OPTS 배열 내용 확인
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
CURRENT_ISO_TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
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

# 결과 판단
RESULT_STATUS=""
RESULT_MESSAGE=""
if [ $EXIT_CODE -eq 0 ]; then
  RESULT_STATUS="SUCCESS"
  RESULT_MESSAGE="오픈 릴레이 취약점 존재 가능성 있음"
else
  RESULT_STATUS="FAILURE"
  RESULT_MESSAGE="오픈 릴레이 방어 정상 작동 중 또는 swaks 실행 오류 (종료 코드: $EXIT_CODE)"
fi

# 3. 공격 종료 로그
CURRENT_ISO_TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
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

# 결과 출력
echo ""
echo "공격 테스트 완료. 로그 저장 위치: $LOG_FILE (NDJSON 형식)"
echo "공격 ID: $ATTACK_ID (패킷 캡처와 연계 시 사용)"

# swaks 실패 시 경고 출력
if [ $EXIT_CODE -ne 0 ]; then
  echo "WARNING: swaks execution failed with exit code $EXIT_CODE. See $LOG_FILE for details." >&2
  exit $EXIT_CODE
fi