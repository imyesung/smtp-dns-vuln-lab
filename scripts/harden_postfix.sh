#!/bin/bash
# scripts/harden_postfix.sh - Postfix 보안 강화 스크립트

set -e

echo "=== Postfix 하드닝 시작 ==="

# 릴레이 제한 적용
postconf -e "smtpd_relay_restrictions=permit_mynetworks,reject_unauth_destination"

# 네트워크 접근 제한 (내부 네트워크만 허용 예시)
postconf -e "mynetworks=127.0.0.0/8, 172.18.0.0/16"

# 수신자 검증 강화
postconf -e "smtpd_recipient_restrictions=reject_unknown_recipient_domain,permit_mynetworks,reject"

# HELO 검증 (선택적 강화)
postconf -e "smtpd_helo_required=yes"

# 설정 적용
postfix reload

echo "=== Postfix 하드닝 완료 ==="