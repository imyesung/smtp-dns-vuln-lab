#!/bin/sh

# 랜덤 메시지 모음
MOODS=(
  "☕ Wake up and smell the shellscripts!"
  "💥 Boom! SMTP'd your soul."
  "📨 Today's mail brought to you by: pure chaos."
  "🐭 생쥐가 보낸 이메일입니다. 첨부: 치즈"
  "🚨 This is not a drill. Actually, it kind of is."
  "🌐 'echo hello | nc mail-postfix 25'도 귀엽지 않음?"
)

# 랜덤 메시지 선택
INDEX=$(($RANDOM % ${#MOODS[@]}))
BODY="${MOODS[$INDEX]}"

FROM="weirdbot@test.local"
TO="hacker@test.local"
SUBJECT="Your Daily Chaos Report #$RANDOM"

# 메일 전송 (Postfix 컨테이너 안에서 실행)
docker exec -i mail-postfix sendmail -t <<EOF
From: $FROM
To: $TO
Subject: $SUBJECT
X-Lab-Tag: automated-fun

$BODY
EOF

echo "[+] Weirdbot has sent chaos to $TO — subject: $SUBJECT"
