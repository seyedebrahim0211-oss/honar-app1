#!/usr/bin/env bash
set -euo pipefail
mkdir -p assets/fonts
for weight in Regular Bold; do
  name="Vazirmatn-${weight}.ttf"
  target="assets/fonts/${name}"
  url="https://raw.githubusercontent.com/rastikerdar/vazirmatn/v33.003/fonts/ttf/${name}"
  fallback="https://cdn.jsdelivr.net/gh/rastikerdar/vazirmatn@v33.003/fonts/ttf/${name}"
  if ! curl -fLSs --retry 3 --connect-timeout 12 --max-time 90 "$url" -o "$target"; then
    curl -fLSs --retry 3 --connect-timeout 12 --max-time 90 "$fallback" -o "$target"
  fi
  python3 - "$target" <<'PY'
from pathlib import Path
import sys
data = Path(sys.argv[1]).read_bytes()
if len(data) < 10000 or data[:4] not in (b'\x00\x01\x00\x00', b'OTTO', b'true'):
    raise SystemExit('Downloaded font is invalid')
print('Bundled font verified:', Path(sys.argv[1]).name, len(data), 'bytes')
PY
done
