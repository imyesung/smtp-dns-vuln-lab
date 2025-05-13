#!/bin/bash

# Postfix 하드닝 및 백업 스크립트

# 스크립트 디렉토리 설정 (상대 경로 사용)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# PROJECT_ROOT는 컨테이너 내부에서는 / 이므로 직접 경로를 지정하는 것이 더 안전합니다.
# HOST_PROJECT_ROOT와 혼동하지 않도록 주의합니다.

BACKUP_SCRIPT="${SCRIPT_DIR}/backup_postfix_config.sh"

# utils.sh 함수 사용
source "${SCRIPT_DIR}/utils.sh"

# 컨테이너 이름 변수 (이 스크립트는 controller에서 실행되므로 mail-postfix 직접 제어 안 함)
# CONTAINER_NAME="mail-postfix" # 사용되지 않음

# 로그 디렉토리 및 파일 설정 - /artifacts 하위로 변경하여 호스트와 공유
LOG_DIR="/artifacts/logs"
LOG_FILE="${LOG_DIR}/postfix_harden.log"

# Postfix 설정 파일이 위치한 controller 컨테이너 내 경로
POSTFIX_CONF_DIR_IN_CONTROLLER="/shared/postfix"

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
    # backup_postfix_config.sh는 이미 올바른 경로를 사용하도록 수정될 예정
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
  POSTFIX_CONF="${POSTFIX_CONF_DIR_IN_CONTROLLER}/main.cf"
  if [ ! -f "$POSTFIX_CONF" ]; then
    log "오류: main.cf 파일이 존재하지 않음 ($POSTFIX_CONF)"
    return 1
  fi

  # 기존 smtpd_helo_required 설정이 있으면 수정, 없으면 추가
  if grep -q "^smtpd_helo_required" "$POSTFIX_CONF"; then
    sed -i 's/^smtpd_helo_required.*/smtpd_helo_required = yes/' "$POSTFIX_CONF"
  else
    echo "smtpd_helo_required = yes" >> "$POSTFIX_CONF"
  fi
  log "smtpd_helo_required = yes 설정 적용"
  
  # 예시: smtpd_relay_restrictions 추가 또는 수정
  # 실제 적용할 하드닝 규칙에 따라 아래 내용을 수정/추가합니다.
  # 예시: permit_mynetworks, reject_unauth_destination 외에 추가 제한
  RELAY_RESTRICTIONS="smtpd_relay_restrictions = permit_mynetworks, permit_sasl_authenticated, reject_unauth_destination"
  if grep -q "^smtpd_relay_restrictions" "$POSTFIX_CONF"; then
    sed -i "s|^smtpd_relay_restrictions.*|$RELAY_RESTRICTIONS|" "$POSTFIX_CONF"
  else
    echo "$RELAY_RESTRICTIONS" >> "$POSTFIX_CONF"
  fi
  log "\"$RELAY_RESTRICTIONS\" 설정 적용"


  # 하드닝 후 설정 확인 (postconf는 mail-postfix 컨테이너에서 실행해야 함)
  # 이 스크립트는 controller에서 실행되므로, postconf 직접 실행은 어려움.
  # 대신, Makefile에서 docker exec mail-postfix postconf -n 등으로 확인 가능.
  log "설정 변경사항 확인: (직접 main.cf 파일 확인 또는 mail-postfix 컨테이너에서 postconf 실행 필요)"

  # Postfix 재시작 신호 전달 (Makefile에서 reload)
  # restart_trigger 파일 위치를 공유 볼륨으로 변경
  # touch "${POSTFIX_CONF_DIR_IN_CONTROLLER}/restart_trigger" # 이 방식 대신 Makefile의 postfix reload 사용 권장

  # 변경된 설정 백업 (선택 사항, 또는 백업 전략에 따라 조정)
  # log "변경된 설정 백업 중..."
  # run_backup
  
  log "Postfix 하드닝 완료. Postfix reload는 Makefile에서 수행됩니다."
  return 0
}

# 메인 실행
harden_postfix
exit $?