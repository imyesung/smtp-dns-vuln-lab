#!/bin/bash

# Postfix 하드닝 및 백업 스크립트

# 스크립트 디렉토리 설정 (상대 경로 사용)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BACKUP_SCRIPT="${SCRIPT_DIR}/backup_postfix_config.sh"

# utils.sh 함수 사용
source "${SCRIPT_DIR}/utils.sh"

# 컨테이너 이름 변수
CONTAINER_NAME="mail-postfix"

# 로그 디렉토리 및 파일 설정 - 프로젝트 내 로그 디렉토리 사용으로 일관성 유지
LOG_DIR="${PROJECT_ROOT}/logs"
LOG_FILE="${LOG_DIR}/postfix_harden.log"

# 디렉토리 확인 및 생성
mkdir -p "$LOG_DIR"

# 로그 파일 덮어쓰기 방지
safe_logfile "$LOG_FILE"

# log 함수 대체: log_ndjson 사용
log() {
  log_ndjson "$LOG_FILE" "\"$1\""
  echo "[$(iso8601_now)] $1"
}

# 백업 실행 함수
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

# Postfix 하드닝 함수
harden_postfix() {
  log "Postfix 하드닝 시작"
  
  # 백업 먼저 실행
  run_backup
  if [ $? -ne 0 ]; then
    log "경고: 백업 실패, 하드닝 계속 진행..."
  fi
  
  # Postfix 설정 강화 (공유 볼륨 기반 main.cf 직접 수정)
  log "Postfix 보안 설정 적용 중..."
  POSTFIX_CONF="${PROJECT_ROOT}/configs/postfix/main.cf"
  if [ ! -f "$POSTFIX_CONF" ]; then
    log "오류: main.cf 파일이 존재하지 않음 ($POSTFIX_CONF)"
    return 1
  fi

  echo "smtpd_helo_required = yes" >> "$POSTFIX_CONF"
  # 필요시 추가 하드닝 옵션도 직접 main.cf에 append

  # 하드닝 후 설정 확인 (생략 또는 필요시 구현)
  # log "설정 변경사항 확인: ..."

  # Postfix 재시작 신호 전달 (Makefile에서 reload)
  touch "${PROJECT_ROOT}/configs/postfix/restart_trigger"
  
  # 하드닝 후 백업 다시 실행 (변경된 설정 백업)
  log "변경된 설정 백업 중..."
  run_backup
  
  log "Postfix 하드닝 완료"
  return 0
}

# 메인 실행
harden_postfix
exit $?