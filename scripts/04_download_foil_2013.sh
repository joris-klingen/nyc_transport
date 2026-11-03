#!/usr/bin/env bash
# Download the 2013 FOIL taxi files into raw/taxi/foil_2013: the 2013 yellow taxi trips as released
# under Chris Whong's FOIL request (chriswhong.com/open-data/foil_nyc_taxi), now hosted at archive.org
# (archive.org/details/nycTaxiTripData2013). Same trips as the 2013 legacy CSVs, plus hashed medallion
# and hack_license (driver) ids, which TLC dropped from its own files: the only year with driver ids.
# Two 7z archives: trip_data.7z (3.8 GiB, 12 monthly CSVs) and trip_fare.7z (1.6 GiB, 12 monthly CSVs).
#
# Usage (from repo root, Git Bash):  bash scripts/04_download_foil_2013.sh
#
# Per file: curl with resume to .7z.part, size compared with the server's Content-Length, md5 of the
# finished file logged to _meta/foil_2013_md5.csv (file, bytes, md5, date); only then renamed to .7z.
# Re-run after an interruption to resume; files already present are skipped.
# Extract with bsdtar (Windows tar.exe, libarchive reads 7z):  tar -xf trip_data.7z

set -euo pipefail
root="$(grep -E '^NYC_TRANSPORT_DATA=' config.local | cut -d= -f2-)"
root="${NYC_TRANSPORT_DATA:-$root}"
dir="$root/raw/taxi/foil_2013"
log="$root/_meta/foil_2013_md5.csv"
base="https://archive.org/download/nycTaxiTripData2013"
mkdir -p "$dir" "$root/_meta"
[ -f "$log" ] || echo "file,bytes,md5,date" > "$log"

for f in trip_data.7z trip_fare.7z; do
  dest="$dir/$f"
  [ -f "$dest" ] && { echo "$f: already downloaded"; continue; }
  expected="$(curl -sIL "$base/$f" | grep -i '^content-length:' | tail -1 | tr -dc '0-9')"
  echo "$f: $((expected / 1000000)) MB, $(date +%H:%M)"
  # -f: an HTTP error (e.g. 416 when the .part is already complete) writes nothing to the file
  curl -sSfL -C - --retry 20 --retry-delay 30 -o "$dest.part" "$base/$f" || true
  bytes="$(stat -c %s "$dest.part")"
  if [ "$bytes" != "$expected" ]; then echo "$f: SIZE MISMATCH $bytes vs $expected, .part kept"; exit 1; fi
  md5="$(md5sum < "$dest.part" | cut -d' ' -f1)"
  mv "$dest.part" "$dest"
  echo "$f,$bytes,$md5,$(date +%Y-%m-%d)" >> "$log"
  echo "$f: done, md5 $md5, $(date +%H:%M)"
done
