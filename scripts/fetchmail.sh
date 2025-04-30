#!/bin/sh

echo "[*] Weirdbot is now monitoring the mail dimension..."
echo "[*] Use Ctrl+C to escape the log vortex."

docker logs -f mail-postfix | grep --line-buffered 'postfix/' | while read -r line
do
  echo "[MAIL] $line"
done
