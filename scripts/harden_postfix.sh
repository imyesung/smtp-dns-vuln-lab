#!/bin/bash

# Postfix 하드닝 및 백업 스크립트

# 스크립트 디렉토리 설정 (상대 경로 사용)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BACKUP_SCRIPT="${SCRIPT_DIR}/backup_postfix_config.sh"

# 컨테이너 이름 변수
CONTAINER_NAME="mail-postfix"

# 로그 디렉토리 및 파일 설정 - 프로젝트 내 로그 디렉토리 사용으로 일관성 유지
LOG_DIR="${PROJECT_ROOT}/logs"
LOG_FILE="${LOG_DIR}/postfix_harden.log"

# 디렉토리 확인 및 생성
mkdir -p "$LOG_DIR"

# 로깅 함수
log() {
  local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  echo "[$timestamp] $1" >> "$LOG_FILE"
  echo "[$timestamp] $1"
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
  
  # 컨테이너 존재 확인
  docker ps | grep -q $CONTAINER_NAME
  if [ $? -ne 0 ]; then
    log "오류: $CONTAINER_NAME 컨테이너가 실행 중이 아님"
    return 1
  fi
  
  # Postfix 설정 강화
  log "Postfix 보안 설정 적용 중..."
  
  # SMTP 인증 설정 강화
  docker exec $CONTAINER_NAME postconf -e "smtpd_helo_required = yes"
  docker exec $CONTAINER_NAME postconf -e "smtpd_delay_reject = yes"
  docker exec $CONTAINER_NAME postconf -e "disable_vrfy_command = yes"
  
  # 보안 TLS 설정
  docker exec $CONTAINER_NAME postconf -e "smtpd_tls_security_level = may"
  docker exec $CONTAINER_NAME postconf -e "smtp_tls_security_level = may"
  docker exec $CONTAINER_NAME postconf -e "smtp_tls_loglevel = 1"
  docker exec $CONTAINER_NAME postconf -e "smtpd_tls_loglevel = 1"
  
  # 랜덤 지연 시간 추가 (스팸 방지)
  docker exec $CONTAINER_NAME postconf -e "smtpd_error_sleep_time = 1s"
  docker exec $CONTAINER_NAME postconf -e "smtpd_soft_error_limit = 10"
  docker exec $CONTAINER_NAME postconf -e "smtpd_hard_error_limit = 20"
  
  # 하드닝 후 설정 확인
  log "설정 변경사항 확인:"
  docker exec $CONTAINER_NAME postconf | grep "security_level\|error_limit\|vrfy\|helo_required"
  
  # Postfix 재시작
  log "Postfix 서비스 재시작 중..."
  docker exec $CONTAINER_NAME service postfix reload
  
  # 재시작 후 상태 확인
  if docker exec $CONTAINER_NAME service postfix status | grep -q "running"; then
    log "Postfix 서비스 재시작 성공"
  else
    log "오류: Postfix 서비스 재시작 실패"
    return 1
  fi
  
  # 하드닝 후 백업 다시 실행 (변경된 설정 백업)
  log "변경된 설정 백업 중..."
  run_backup
  
  log "Postfix 하드닝 완료"
  return 0
}

# 메인 실행
harden_postfix
exit $?