#!/bin/bash
# Postfix 하드닝 스크립트 - Enhanced with common utilities

# 공통 함수 로드
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_SCRIPT="${SCRIPT_DIR}/backup_postfix_config.sh"
source "${SCRIPT_DIR}/utils.sh"

# 공통 초기화
init_common
SCRIPT_START_TIME=$(date +%s)

log_info "Starting Postfix hardening script"

# 필수 명령어 확인
check_required_commands cp grep || exit 1

# 로그 설정
LOG_DIR="/artifacts/logs"
LOG_FILE="${LOG_DIR}/postfix_harden.log"
ensure_directory "$LOG_DIR"
safe_logfile "$LOG_FILE"

# Postfix 설정 파일 경로 (Controller 관점)
POSTFIX_CONF_DIR="/shared/postfix"
CURRENT_CONF="${POSTFIX_CONF_DIR}/main.cf"
SECURE_CONF="${POSTFIX_CONF_DIR}/main.cf.secure"
VULNERABLE_CONF="${POSTFIX_CONF_DIR}/main.cf.vulnerable"

# 로그 함수 (NDJSON + 표준 출력)
log() {
  log_ndjson "$LOG_FILE" "\"$1\""
  log_info "$1"
}

# 백업 실행
run_backup() {
  log "Postfix 설정 백업 시작"
  
  if [ -f "$BACKUP_SCRIPT" ]; then
    bash "$BACKUP_SCRIPT"
    if [ $? -eq 0 ]; then
      log "백업 성공"
    else
      log "백업 실패"
      return 1
    fi
  else
    log "백업 스크립트를 찾을 수 없음: $BACKUP_SCRIPT"
    return 1
  fi
  
  return 0
}

# Postfix 하드닝 - 전체 설정 파일 교체
harden_postfix() {
  log "Postfix 하드닝 시작"
  
  # 백업 먼저 실행
  run_backup
  if [ $? -ne 0 ]; then
    log "경고: 백업 실패, 하드닝 계속 진행..."
  fi
  
  # 보안 설정 파일 존재 확인
  if [ ! -f "$SECURE_CONF" ]; then
    log "오류: 보안 설정 파일이 존재하지 않음 ($SECURE_CONF)"
    return 1
  fi
  
  # 현재 설정 파일 존재 확인
  if [ ! -f "$CURRENT_CONF" ]; then
    log "오류: 현재 설정 파일이 존재하지 않음 ($CURRENT_CONF)"
    return 1
  fi
  
  # 설정 파일 교체
  log "취약한 설정을 보안 설정으로 교체 중..."
  cp "$SECURE_CONF" "$CURRENT_CONF"
  
  if [ $? -eq 0 ]; then
    log "설정 파일 교체 완료: $CURRENT_CONF"
    
    # Controller가 Docker socket을 통해 mail-postfix 컨테이너에 설정 적용
    log "Controller를 통해 mail-postfix 컨테이너에 설정 적용 중..."
    docker exec mail-postfix cp /postfix/main.cf /etc/postfix/main.cf
    if [ $? -eq 0 ]; then
      log "mail-postfix 컨테이너 설정 파일 적용 완료"
    else
      log "경고: mail-postfix 컨테이너 설정 파일 적용 실패"
    fi
  else
    log "오류: 설정 파일 교체 실패"
    return 1
  fi
  
  # 실제 Postfix 경로로도 복사 - Controller orchestration을 통해
  log "Controller를 통해 mail-postfix 컨테이너에 설정 적용 중..."
  docker exec mail-postfix cp /postfix/main.cf.secure /etc/postfix/main.cf
  
  if [ $? -eq 0 ]; then
    log "mail-postfix 컨테이너 보안 설정 파일 적용 완료"
  else
    log "오류: mail-postfix 컨테이너 설정 파일 적용 실패"
    return 1
  fi
  
  # 설정 파일 내용 확인 (로그용)
  log "적용된 주요 보안 설정:"
  grep -E "^(mynetworks|smtpd_.*_restrictions|relay_domains)" "$CURRENT_CONF" | while read -r line; do
    log "  $line"
  done
  
  log "Postfix 하드닝 완료. Postfix reload는 Makefile에서 수행됩니다."
  return 0
}

# 설정 복구 함수
restore_vulnerable_config() {
  log "취약한 설정으로 복구 시작"
  
  if [ -f "$VULNERABLE_CONF" ]; then
    cp "$VULNERABLE_CONF" "$CURRENT_CONF"
    
    # Controller를 통해 mail-postfix 컨테이너에 취약한 설정 적용
    log "Controller를 통해 mail-postfix 컨테이너에 취약한 설정 적용 중..."
    docker exec mail-postfix cp /postfix/main.cf.vulnerable /etc/postfix/main.cf
    
    if [ $? -eq 0 ]; then
      log "mail-postfix 컨테이너 취약한 설정 적용 완료"
    else
      log "경고: mail-postfix 컨테이너 설정 복구 실패"
      return 1
    fi
    
    log "취약한 설정으로 복구 완료"
  else
    log "경고: 취약한 설정 파일을 찾을 수 없음"
    return 1
  fi
}

# 메인 실행
case "${1:-harden}" in
  "harden")
    harden_postfix
    ;;
  "restore")
    restore_vulnerable_config
    ;;
  *)
    echo "Usage: $0 [harden|restore]"
    exit 1
    ;;
esac

exit $?