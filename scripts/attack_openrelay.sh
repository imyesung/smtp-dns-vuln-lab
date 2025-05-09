#!/bin/bash

# 인자로 ATTACK_ID 받기
ATTACK_ID="$1"
if [[ -z "$ATTACK_ID" ]]; then
    TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
    ATTACK_ID="ORT-${TIMESTAMP}" # 인자가 없을 경우에만 자체 생성
fi

# 설정 변수
TARGET="mail-postfix"
PORT=25
FROM="attacker@example.com"
TO="victim@example.com"
SUBJECT="Open Relay Test"
BODY="This is an unauthenticated mail test."
LOG_DIR="/artifacts"
LOG_FILE="${LOG_DIR}/openrelay_${ATTACK_ID}.log" # ATTACK_ID 사용

# 로그 디렉토리 생성
mkdir -p "$LOG_DIR"

# 1. 공격 시작 정보 로깅 (JSON)
# 현재 시간을 RFC3339 UTC 형식으로 기록하여 타임존 문제 최소화 및 정렬 용이성 확보
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
# JSON 문자열에서 불필요한 앞 공백 제거 (here document 사용 시 발생 가능)
echo "$START_INFO_JSON" | sed 's/^[[:space:]]*//' >> "$LOG_FILE"

# swaks 옵션 호환성 확인
SWAKS_OPTS=(
  --to "$TO" 
  --from "$FROM" 
  --server "$TARGET" 
  --port "$PORT" 
  --auth-user "" 
  --auth-password "" 
  --timeout 10 
  --header "Subject: $SUBJECT" 
  --body "$BODY" 
  --hide-all
  --protocol SMTP 
  --tls-optional
)

# show-raw-message 옵션 호환성 확인
if swaks --help 2>&1 | grep -q -- "--show-raw-message"; then
  SWAKS_OPTS+=("--show-raw-message")
fi

# swaks 실행 (배열 확장 구문 사용)
SWAKS_OUTPUT_FILE=$(mktemp "${LOG_DIR}/swaks_raw_${ATTACK_ID}_XXXXXX.tmp")
swaks "${SWAKS_OPTS[@]}" > "$SWAKS_OUTPUT_FILE" 2>&1
EXIT_CODE=$?

# swaks 출력을 JSON 문자열로 안전하게 만들기 위한 처리
# sed를 사용한 기본적인 이스케이프 처리 (백슬래시, 큰따옴표, 개행 문자)
SWAKS_RAW_OUTPUT=$(awk '{printf "%s\\n", $0}' "$SWAKS_OUTPUT_FILE" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g' | sed '$ s/\\n$//')
rm "$SWAKS_OUTPUT_FILE" # 임시 파일 삭제

# 2. SMTP 트랜잭션 결과 로깅 (JSON)
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

# 3. 공격 종료 및 최종 결과 로깅 (JSON)
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

# 요약 로그 파일 생성 (여러 테스트 요약용)
SUMMARY_LOG="${LOG_DIR}/openrelay_summary.log"
echo "$(date '+%Y-%m-%d %H:%M:%S') [$ATTACK_ID] Target: $TARGET:$PORT, Result: $RESULT_STATUS (ExitCode: $EXIT_CODE)" >> "$SUMMARY_LOG"

# 결과 메시지 출력
echo ""
echo "공격 테스트 완료. 로그 저장 위치: $LOG_FILE (NDJSON 형식)"
echo "공격 ID: $ATTACK_ID (패킷 캡처와 연계 시 사용)"