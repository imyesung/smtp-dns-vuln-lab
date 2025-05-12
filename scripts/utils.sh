# ISO 8601 타임스탬프 생성 함수
iso8601_now() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

# 로그 파일 덮어쓰기 방지 (동일 파일명 존재 시 타임스탬프 붙여 백업)
safe_logfile() {
  local logfile="$1"
  if [ -f "$logfile" ]; then
    local ts=$(date +"%Y%m%d_%H%M%S")
    mv "$logfile" "${logfile%.log}_$ts.log"
  fi
}

# NDJSON 형식으로 로그 기록
log_ndjson() {
  local logfile="$1"
  shift
  local msg="$*"
  local ts=$(iso8601_now)
  echo "{\"@timestamp\":\"$ts\",\"msg\":$msg}" >> "$logfile"
}