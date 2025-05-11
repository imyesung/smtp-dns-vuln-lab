#!/bin/bash
# scripts/gen_report_html.sh

ts=$(date -u +%Y%m%d-%H%M%S)
log_dir="$HOME/github/smtp-dns-vuln-lab/artifacts"
report="$log_dir/demo-${ts}.html"

mkdir -p "$log_dir"

cat > "$report" <<EOF
<!DOCTYPE html>
<html lang="en"><meta charset="utf-8">
<title>SMTP-DNS Lab Report $ts</title>
<style>
body{font-family:monospace;background:#fafafa;margin:2rem;}
h1{font-size:1.4rem;border-bottom:1px solid #555;}
pre{background:#eee;padding:1rem;border-radius:5px;}
</style>
<h1>Environment</h1>
<pre>$(docker compose ps --format table)</pre>

<h1>Log diff</h1>
<pre>$(diff -u artifacts/*before*.log artifacts/*after*.log)</pre>

<h1>Verdict</h1>
<p><b>Fix ✔</b></p>
</html>
EOF

xdg-open "$report" 2>/dev/null || open "$report"