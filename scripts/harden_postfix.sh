#!/bin/bash

# Postfix 하드닝 스크립트 - 전체 설정 파일 교체 방식

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_SCRIPT="${SCRIPT_DIR}/backup_postfix_config.sh"

# utils.sh 함수 사용
source "${SCRIPT_DIR}/utils.sh"

LOG_DIR="/artifacts/logs"
LOG_FILE="${LOG_DIR}/postfix_harden.log"

# Postfix 설정 파일 경로
POSTFIX_CONF_DIR="/shared/postfix"
CURRENT_CONF="${POSTFIX_CONF_DIR}/main.cf"
SECURE_CONF="${POSTFIX_CONF_DIR}/main.cf.secure"
VULNERABLE_CONF="${POSTFIX_CONF_DIR}/main.cf.vulnerable"

mkdir -p "$LOG_DIR"
safe_logfile "$LOG_FILE"

log() {
  log_ndjson "$LOG_FILE" "\"$1\""
  echo "[$(iso8601_now)] $1"
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
  else
    log "오류: 설정 파일 교체 실패"
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