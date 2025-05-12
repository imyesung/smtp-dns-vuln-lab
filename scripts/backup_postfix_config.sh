#!/bin/bash
# Postfix 설정 백업 스크립트

# 스크립트 디렉토리 설정 (상대 경로 사용)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# 백업 디렉토리 설정
BACKUP_DIR="${PROJECT_ROOT}/backups/postfix"
CONTAINER_NAME="mail-postfix"

# 로그 디렉토리 및 파일 설정
LOG_DIR="${PROJECT_ROOT}/logs"
LOG_FILE="${LOG_DIR}/postfix_backup.log"

# 디렉토리 확인 및 생성
mkdir -p "$BACKUP_DIR"
mkdir -p "$LOG_DIR"

# 로깅 함수
log() {
  local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  echo "[$timestamp] $1" >> "$LOG_FILE"
  echo "[$timestamp] $1"
}

# 백업 함수 - 핵심 백업 기능만 담당
backup_postfix_config() {
  # 타임스탬프 생성
  local TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
  local BACKUP_FILE="${BACKUP_DIR}/postfix_config_${TIMESTAMP}.tar.gz"

  # 컨테이너 존재 확인
  docker ps | grep -q $CONTAINER_NAME
  if [ $? -ne 0 ]; then
    log "오류: $CONTAINER_NAME 컨테이너가 실행 중이 아님"
    return 1
  fi

  # 임시 디렉토리 생성
  local TMP_DIR=$(mktemp -d)
  if [ $? -ne 0 ]; then
    log "오류: 임시 디렉토리 생성 실패"
    return 1
  fi

  # 백업 정보 파일 생성
  echo "백업 시간: $(date)" > "${TMP_DIR}/backup_info.txt"
  echo "컨테이너: $CONTAINER_NAME" >> "${TMP_DIR}/backup_info.txt"

  # main.cf 파일 백업
  log "main.cf 파일 백업 중..."
  docker exec $CONTAINER_NAME cat /etc/postfix/main.cf > "${TMP_DIR}/main.cf" 2>/dev/null
  if [ $? -ne 0 ]; then
    log "경고: main.cf 파일 백업 실패"
  fi

  # master.cf 파일 백업
  log "master.cf 파일 백업 중..."
  docker exec $CONTAINER_NAME cat /etc/postfix/master.cf > "${TMP_DIR}/master.cf" 2>/dev/null
  if [ $? -ne 0 ]; then
    log "경고: master.cf 파일 백업 실패"
  fi

  # 현재 Postfix 설정 덤프
  log "현재 Postfix 설정 덤프 중..."
  docker exec $CONTAINER_NAME postconf > "${TMP_DIR}/postconf_output.txt" 2>/dev/null
  if [ $? -ne 0 ]; then
    log "경고: postconf 출력 백업 실패"
  fi

  # 기타 중요 설정 파일 백업
  log "기타 Postfix 설정 파일 백업 중..."
  for file in aliases access canonical generic header_checks relocated transport virtual; do
    docker exec $CONTAINER_NAME test -f "/etc/postfix/${file}" && \
      docker exec $CONTAINER_NAME cat "/etc/postfix/${file}" > "${TMP_DIR}/${file}" 2>/dev/null
  done

  # 백업 파일 생성
  log "백업 파일 압축 중: $BACKUP_FILE"
  tar -czf "$BACKUP_FILE" -C "$TMP_DIR" .
  if [ $? -eq 0 ]; then
    log "백업 파일 생성 성공: $BACKUP_FILE"
    
    # 백업 파일 권한 설정
    chmod 600 "$BACKUP_FILE"
    
    # 오래된 백업 정리 (15일 이상 지난 백업 삭제)
    find "$BACKUP_DIR" -name "postfix_config_*.tar.gz" -type f -mtime +15 -delete
    
    # 임시 디렉토리 정리
    rm -rf "$TMP_DIR"
    
    return 0
  else
    log "오류: 백업 파일 생성 실패"
    rm -rf "$TMP_DIR"
    return 1
  fi
}

# 메인 실행
log "Postfix 설정 백업 프로세스 시작"
backup_postfix_config
result=$?

if [ $result -eq 0 ]; then
  log "Postfix 설정 백업 완료: 성공"
  exit 0
else
  log "Postfix 설정 백업 실패"
  exit 1
fi