#!/usr/bin/env bash
# Gzip the legacy yellow taxi CSVs in place (raw/taxi/yellow_csv_legacy): 123 GB to about 25-30 GB.
# The files stay byte for byte as published once unzipped; fread() reads .csv.gz directly.
#
# Usage (from repo root, Git Bash):  bash scripts/03_gzip_yellow_legacy.sh [jobs]
#   jobs  parallel gzip processes, default 4
#
# Per file: md5 of the CSV, gzip to .csv.gz.part, md5 of the unzipped .part; only when the two
# match is the .part renamed to .csv.gz and the CSV deleted. The md5 of every published CSV is kept
# in _meta/yellow_csv_legacy_md5.csv (file, csv_bytes, md5, gz_bytes, date). Files already gzipped
# are skipped, so the script can be re-run after an interruption.

set -euo pipefail
jobs="${1:-4}"
root="$(grep -E '^NYC_TRANSPORT_DATA=' config.local | cut -d= -f2-)"
root="${NYC_TRANSPORT_DATA:-$root}"
dir="$root/raw/taxi/yellow_csv_legacy"
log="$root/_meta/yellow_csv_legacy_md5.csv"
[ -d "$dir" ] || { echo "no $dir"; exit 1; }
[ -f "$log" ] || echo "file,csv_bytes,md5,gz_bytes,date" > "$log"

one() {
  f="$1"; dir="$2"; log="$3"
  b="$(basename "$f")"
  [ -f "$f.gz" ] && { echo "$b: already gzipped, CSV left in place"; return 0; }
  m1="$(md5sum < "$f" | cut -d' ' -f1)"
  gzip -6 -c "$f" > "$f.gz.part"
  m2="$(gzip -dc "$f.gz.part" | md5sum | cut -d' ' -f1)"
  if [ "$m1" != "$m2" ]; then echo "$b: MD5 MISMATCH, CSV kept"; rm -f "$f.gz.part"; return 1; fi
  csv_bytes="$(stat -c %s "$f")"; gz_bytes="$(stat -c %s "$f.gz.part")"
  mv "$f.gz.part" "$f.gz"
  rm "$f"
  echo "$b,$csv_bytes,$m1,$gz_bytes,$(date +%Y-%m-%d)" >> "$log"
  echo "$b: $((csv_bytes / 1000000)) MB -> $((gz_bytes / 1000000)) MB"
}
export -f one

ls "$dir"/yellow_tripdata_????-??.csv 2>/dev/null | xargs -P "$jobs" -I{} bash -c 'one "$@"' _ {} "$dir" "$log"
echo "done: $(ls "$dir"/*.csv.gz | wc -l) gzipped, $(ls "$dir"/*.csv 2>/dev/null | wc -l) CSV left"
