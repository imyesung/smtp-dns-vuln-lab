# ===== SMTP & DNS Vulnerability Lab - Common Utilities =====
# 공통 함수 라이브러리: 모든 스크립트에서 중복되는 로직 통합

# ===== 타임스탬프 및 ID 생성 함수 =====

# ISO 8601 타임스탬프 생성
iso8601_now() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

# 실험 ID 생성 (접두사 지정 가능)
generate_attack_id() {
  local prefix="${1:-EXP}"
  local timestamp=$(date +"%Y%m%d_%H%M%S")
  echo "${prefix}_${timestamp}"
}

# ===== 로깅 함수 =====

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

# 표준화된 로그 함수들 (색상 지원)
setup_logging() {
  # 색상 정의 (터미널 지원 시에만)
  if [ -t 1 ]; then
    export LOG_RED='\033[0;31m'
    export LOG_GREEN='\033[0;32m'
    export LOG_YELLOW='\033[1;33m'
    export LOG_BLUE='\033[0;34m'
    export LOG_NC='\033[0m' # No Color
  else
    export LOG_RED=''
    export LOG_GREEN=''
    export LOG_YELLOW=''
    export LOG_BLUE=''
    export LOG_NC=''
  fi
}

log_step() { 
  echo -e "${LOG_GREEN}[$(date +"%H:%M:%S")] [STEP] $1${LOG_NC}" 
}

log_info() { 
  echo -e "${LOG_BLUE}[$(date +"%H:%M:%S")] [INFO] $1${LOG_NC}" 
}

log_warn() { 
  echo -e "${LOG_YELLOW}[$(date +"%H:%M:%S")] [WARN] $1${LOG_NC}" 
}

log_error() { 
  echo -e "${LOG_RED}[$(date +"%H:%M:%S")] [ERROR] $1${LOG_NC}" 
}

# ===== 컨테이너 상태 확인 함수 =====

# 컨테이너 존재 및 실행 상태 확인
check_container_status() {
  local container_name="$1"
  
  if ! docker ps -a -q -f name="$container_name" | grep -q .; then
    return 1  # 컨테이너 존재하지 않음
  elif ! docker ps -q -f name="$container_name" -f status=running | grep -q .; then
    return 2  # 컨테이너 존재하지만 실행되지 않음
  else
    return 0  # 컨테이너 실행 중
  fi
}

# 컨테이너 응답성 확인 (exec 명령 실행 가능 여부)
check_container_responsive() {
  local container_name="$1"
  local timeout="${2:-30}"
  local counter=0
  
  while [ $counter -lt $timeout ]; do
    if docker exec "$container_name" true >/dev/null 2>&1; then
      return 0
    fi
    counter=$((counter + 1))
    sleep 1
  done
  return 1
}

# 컨테이너 시작 및 대기
ensure_container_running() {
  local container_name="$1"
  local timeout="${2:-60}"
  
  log_info "Ensuring container $container_name is running..."
  
  case $(check_container_status "$container_name") in
    1)
      log_warn "Container $container_name does not exist, starting..."
      docker-compose up -d --no-recreate "$container_name" || return 1
      ;;
    2)
      log_warn "Container $container_name is not running, starting..."
      docker start "$container_name" || return 1
      ;;
    0)
      log_info "Container $container_name is already running"
      ;;
  esac
  
  # 응답성 확인
  if check_container_responsive "$container_name" "$timeout"; then
    log_info "Container $container_name is responsive"
    return 0
  else
    log_error "Container $container_name is not responsive after $timeout seconds"
    return 1
  fi
}

# ===== 파일 및 서비스 대기 함수 =====

# 파일 존재 대기
wait_for_file() {
  local filepath="$1"
  local timeout="${2:-60}"
  local counter=0
  
  log_info "Waiting for file $filepath (timeout: ${timeout}s)..."
  
  while [ ! -f "$filepath" ] && [ $counter -lt $timeout ]; do
    counter=$((counter + 1))
    sleep 1
    if [ $((counter % 5)) -eq 0 ]; then
      log_info "Still waiting for $filepath... ($counter/$timeout)"
    fi
  done
  
  if [ -f "$filepath" ]; then
    log_info "File $filepath found after $counter seconds"
    return 0
  else
    log_error "Timeout waiting for $filepath after ${timeout}s"
    return 1
  fi
}

# Postfix 서비스 대기
wait_for_postfix() {
  local timeout="${1:-60}"
  local container="${2:-mail-postfix}"
  
  log_info "Waiting for Postfix service..."
  
  for i in $(seq 1 $timeout); do
    if docker exec "$container" netstat -tuln 2>/dev/null | grep ':25 ' >/dev/null; then
      log_info "Postfix ready after $i seconds"
      sleep 2  # 추가 안정화 시간
      return 0
    fi
    log_info "Waiting for Postfix... ($i/$timeout)"
    sleep 1
  done
  
  log_error "Postfix not ready after $timeout seconds"
  return 1
}

# ===== 네트워크 및 연결성 확인 함수 =====

# 네트워크 연결 테스트
test_network_connectivity() {
  local target="$1"
  local port="$2"
  local timeout="${3:-5}"
  
  if nc -zv "$target" "$port" -w "$timeout" >/dev/null 2>&1; then
    log_info "Network connectivity to $target:$port OK"
    return 0
  else
    log_warn "Network connectivity to $target:$port FAILED"
    return 1
  fi
}

# DNS 해상도 테스트
test_dns_resolution() {
  local hostname="$1"
  
  if nslookup "$hostname" >/dev/null 2>&1; then
    log_info "DNS resolution for $hostname OK"
    return 0
  else
    log_warn "DNS resolution for $hostname FAILED"
    return 1
  fi
}

# ===== 파일 및 디렉터리 관리 함수 =====

# 디렉터리 생성 (존재하지 않는 경우)
ensure_directory() {
  local dir_path="$1"
  local permissions="${2:-755}"
  
  if [ ! -d "$dir_path" ]; then
    mkdir -p "$dir_path"
    chmod "$permissions" "$dir_path"
    log_info "Created directory: $dir_path"
  fi
}

# 백업 파일명 생성
generate_backup_filename() {
  local original_file="$1"
  local timestamp=$(date +"%Y%m%d_%H%M%S")
  echo "${original_file}.bak-${timestamp}"
}

# ===== 에러 핸들링 및 검증 함수 =====

# 필수 명령어 존재 확인
check_required_commands() {
  local missing_commands=()
  
  for cmd in "$@"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      missing_commands+=("$cmd")
    fi
  done
  
  if [ ${#missing_commands[@]} -gt 0 ]; then
    log_error "Missing required commands: ${missing_commands[*]}"
    return 1
  fi
  
  return 0
}

# trap을 사용한 정리 함수 설정
setup_trap_cleanup() {
  local cleanup_function="$1"
  trap "$cleanup_function" EXIT INT TERM
}

# 스크립트 종료 시 정리 작업
cleanup_on_exit() {
  local exit_code=$?
  
  # 백그라운드 프로세스 정리
  for pid in $(jobs -p); do
    if kill -0 "$pid" 2>/dev/null; then
      log_info "Cleaning up background process: $pid"
      kill "$pid" 2>/dev/null || true
    fi
  done
  
  # 임시 파일 정리
  if [ -n "$TEMP_FILES" ]; then
    for temp_file in $TEMP_FILES; do
      if [ -f "$temp_file" ]; then
        rm -f "$temp_file"
        log_info "Removed temporary file: $temp_file"
      fi
    done
  fi
  
  # 임시 디렉터리 정리
  if [ -n "$TEMP_DIRS" ]; then
    for temp_dir in $TEMP_DIRS; do
      if [ -d "$temp_dir" ]; then
        rm -rf "$temp_dir"
        log_info "Removed temporary directory: $temp_dir"
      fi
    done
  fi
  
  if [ $exit_code -ne 0 ]; then
    log_error "Script exited with error code: $exit_code"
  fi
  
  exit $exit_code
}

# ===== JSON 처리 함수 =====

# JSON 형태의 실험 결과 생성
generate_experiment_json() {
  local attack_id="$1"
  local event_type="$2"
  local status="$3"
  local message="$4"
  
  cat <<EOF
{
    "event_type": "$event_type",
    "attack_id": "$attack_id",
    "timestamp_utc": "$(iso8601_now)",
    "status": "$status",
    "message": "$message"
}
EOF
}

# ===== 초기화 함수 =====

# 공통 초기화 (모든 스크립트에서 호출)
init_common() {
  # 에러 발생 시 즉시 종료 설정
  set -euo pipefail
  
  # 로깅 설정
  setup_logging
  
  # 정리 함수 설정
  setup_trap_cleanup cleanup_on_exit
  
  # 전역 변수 초기화
  export TEMP_FILES=""
  export TEMP_DIRS=""
}

# 스크립트 종료 시 출력
show_script_completion() {
  local script_name="$1"
  local start_time="$2"
  local end_time=$(date +%s)
  local duration=$((end_time - start_time))
  
  log_info "=== $script_name completed in ${duration}s ==="
}