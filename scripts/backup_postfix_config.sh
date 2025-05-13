#!/bin/bash
# Postfix 설정 백업 스크립트

# 스크립트 디렉토리 설정 (상대 경로 사용)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# PROJECT_ROOT는 컨테이너 내부에서는 / 이므로 직접 경로를 지정하는 것이 더 안전합니다.

# utils.sh 함수 사용
source "${SCRIPT_DIR}/utils.sh"

# 백업 디렉토리 설정 - /artifacts 하위로 변경하여 호스트와 공유
BACKUP_DIR="/artifacts/backups/postfix"
# CONTAINER_NAME="mail-postfix" # 사용되지 않음

# 로그 디렉토리 및 파일 설정 - /artifacts 하위로 변경
LOG_DIR="/artifacts/logs"
LOG_FILE="${LOG_DIR}/postfix_backup.log"

# Postfix 설정 파일이 위치한 controller 컨테이너 내 경로
POSTFIX_CONF_DIR_IN_CONTROLLER="/shared/postfix"


# 디렉토리 확인 및 생성
mkdir -p "$BACKUP_DIR"
mkdir -p "$LOG_DIR"

# 로그 파일 덮어쓰기 방지
safe_logfile "$LOG_FILE"

# log 함수 대체: log_ndjson 사용
log() {
  log_ndjson "$LOG_FILE" "\"$1\""
  echo "[$(iso8601_now)] $1"
}

# 백업 함수 - 핵심 백업 기능만 담당
backup_postfix_config() {
  # 타임스탬프 생성
  local TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
  local BACKUP_FILE="${BACKUP_DIR}/postfix_config_${TIMESTAMP}.tar.gz"

  # 임시 디렉토리 생성
  local TMP_DIR=$(mktemp -d)
  if [ $? -ne 0 ]; then
    log "오류: 임시 디렉토리 생성 실패"
    return 1
  fi

  # 백업 정보 파일 생성
  echo "백업 시간: $(date)" > "${TMP_DIR}/backup_info.txt"
  # echo "컨테이너: $CONTAINER_NAME" >> "${TMP_DIR}/backup_info.txt" # 이 정보는 controller에서 실행되므로 의미가 다를 수 있음

  # main.cf 파일 백업 (공유 볼륨 기반)
  log "main.cf 파일 백업 중 (${POSTFIX_CONF_DIR_IN_CONTROLLER}/main.cf)..."
  if [ -f "${POSTFIX_CONF_DIR_IN_CONTROLLER}/main.cf" ]; then
    cp "${POSTFIX_CONF_DIR_IN_CONTROLLER}/main.cf" "${TMP_DIR}/main.cf"
  else
    log "경고: main.cf 파일이 존재하지 않음 (${POSTFIX_CONF_DIR_IN_CONTROLLER}/main.cf)"
  fi

  # master.cf 파일 백업 (공유 볼륨 기반)
  log "master.cf 파일 백업 중 (${POSTFIX_CONF_DIR_IN_CONTROLLER}/master.cf)..."
  if [ -f "${POSTFIX_CONF_DIR_IN_CONTROLLER}/master.cf" ]; then
    cp "${POSTFIX_CONF_DIR_IN_CONTROLLER}/master.cf" "${TMP_DIR}/master.cf"
  else
    log "경고: master.cf 파일이 존재하지 않음 (${POSTFIX_CONF_DIR_IN_CONTROLLER}/master.cf)"
  fi

  # 현재 Postfix 설정 덤프 (postconf 결과는 mail-postfix 컨테이너에서 가져와야 함)
  # log "현재 Postfix 설정 덤프 중..."
  # docker exec mail-postfix postconf -n > "${TMP_DIR}/postconf_output.txt"
  # 위 방식은 이 스크립트가 controller에서 실행되므로, mail-postfix에 접근하려면 docker exec 필요.
  # 단순화를 위해 이 단계는 생략하거나, Makefile에서 별도로 처리하는 것을 고려.

  # 기타 중요 설정 파일 백업 (공유 볼륨 기반)
  log "기타 Postfix 설정 파일 백업 중 (${POSTFIX_CONF_DIR_IN_CONTROLLER}/)..."
  for file in aliases access canonical generic header_checks relocated transport virtual; do
    if [ -f "${POSTFIX_CONF_DIR_IN_CONTROLLER}/${file}" ]; then
      cp "${POSTFIX_CONF_DIR_IN_CONTROLLER}/${file}" "${TMP_DIR}/${file}"
    fi
  done

  # 중요 파일 정의
  CRITICAL_FILES="main.cf master.cf" # postconf_output.txt는 현재 생성 안 함

  # 중요 파일 체크섬 계산 및 저장
  log "중요 파일 체크섬 계산 중..."
  for file in $CRITICAL_FILES; do
    if [ -f "${TMP_DIR}/${file}" ]; then
      # 파일명에서 . 를 _로 변환하여 변수 이름으로 사용
      varname=$(echo "$file" | tr '.' '_')
      eval "CHECKSUM_${varname}=$(sha256sum "${TMP_DIR}/${file}" | awk '{print $1}')"
      log "파일 '$file' 체크섬: $(eval echo \$CHECKSUM_${varname})"
    else
      log "경고: 중요 파일 '$file'이 백업 소스에 없습니다 (${TMP_DIR}/${file})"
    fi
  done

  # 백업 파일 생성
  log "백업 파일 압축 중: $BACKUP_FILE"
  tar -czf "$BACKUP_FILE" -C "$TMP_DIR" .
  if [ $? -eq 0 ]; then
    log "백업 파일 생성 성공: $BACKUP_FILE"
    
    # 무결성 검증 - 중요 파일만 검증
    log "중요 파일 무결성 검증 중..."
    VERIFY_DIR=$(mktemp -d)
    tar -xzf "$BACKUP_FILE" -C "$VERIFY_DIR"
    
    # 파일 수 기본 검증 (옵션)
    ORIG_FILES=$(find "$TMP_DIR" -type f | wc -l)
    BACKUP_FILES=$(find "$VERIFY_DIR" -type f | wc -l)
    
    if [ "$ORIG_FILES" -ne "$BACKUP_FILES" ]; then
      log "경고: 백업된 파일 수가 다릅니다 (원본: $ORIG_FILES, 백업: $BACKUP_FILES)"
      # 경고만 하고 실패로 처리하지 않음
    fi
    
    # 중요 파일 검증
    VALIDATION_PASSED=true
    for file in $CRITICAL_FILES; do
      if [ -f "${TMP_DIR}/${file}" ] && [ -f "${VERIFY_DIR}/${file}" ]; then
        # 파일명에서 . 를 _로 변환하여 변수 이름으로 사용
        varname=$(echo "$file" | tr '.' '_')
        HASH_AFTER=$(sha256sum "${VERIFY_DIR}/${file}" | awk '{print $1}')
        HASH_BEFORE=$(eval echo \$CHECKSUM_${varname})
        
        if [ "$HASH_BEFORE" != "$HASH_AFTER" ]; then
          log "오류: ${file} 파일 SHA-256 해시값이 일치하지 않습니다"
          log "원본: $HASH_BEFORE"
          log "백업: $HASH_AFTER"
          VALIDATION_PASSED=false
        else
          log "검증 성공: ${file} SHA-256 해시값 일치"
        fi
      elif [ -f "${TMP_DIR}/${file}" ]; then # 원본은 있었는데 백업에 없는 경우
        log "오류: ${file} 파일이 백업 압축 해제 후 없습니다 (${VERIFY_DIR}/${file})"
        VALIDATION_PASSED=false
      # else # 원본 파일 자체가 없었던 경우는 위에서 이미 경고했으므로, 여기서는 검증 실패로 처리하지 않음
      fi
    done

    if [ "$VALIDATION_PASSED" = false ]; then
      log "오류: 주요 파일 내용 검증 실패"
      rm -f "$BACKUP_FILE" # 실패한 백업 파일 삭제
      rm -rf "$TMP_DIR" "$VERIFY_DIR"
      return 1
    else
      log "백업 검증 성공: 모든 (존재하는) 중요 파일 체크섬 일치"
    fi
    
    rm -rf "$VERIFY_DIR"
    
    # 백업 파일 권한 설정
    chmod 600 "$BACKUP_FILE"
    
    # 오래된 백업 정리 (15일 이상 지난 백업 삭제)
    find "$BACKUP_DIR" -name "postfix_config_*.tar.gz" -type f -mtime +15 -delete
    log "오래된 백업 정리 완료 (15일 초과)"
    
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