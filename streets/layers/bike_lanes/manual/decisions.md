# Coding decisions

| Date | Decision | Applies to |
|---|---|---|
| 2026-10-10 | Buffered lanes (Buffered, Conventional/Curbside Buffered) count as class I (protected); Curbside is class II | `lookup_bikelane_types.xlsx` |
| 2026-10-10 | A blank pre-modification type in the manual sheet means the type did not change (sheet rule) | `layers/bike_lanes/scripts/03_time_windows.R` (was nyc_bikelanes 002) |
| 2026-10-11 | Central Park drives count as protected from the date they became fully car-free, not from the painted bike lane (present throughout) or the earlier auto-limited dates. Manual sheet comments give e.g. "Autos limited 2012-09-15. Fully auto-free 2018-06-27" | park drives in `evidence/aerial_labelling/out/review_checklist.csv` (category park_drive_definition); to be applied as manual overrides |
| 2026-10-11 | Aerial labels are evidence, not ground truth: only Street View-confirmed dates enter the manual overrides | `evidence/aerial_labelling/` |
| 2026-10-12 | Projects reviewed with a buffered lane before protection: buffered counts as protected, so treatment starts at the buffered lane date (the earlier of the pipeline date and the reviewed physical-protection date) | `layers/bike_lanes/manual/04_build_overrides.R` (rule "buffered counts as protected", 4 projects) |
| 2026-10-12 | M010 1 Av: protected from 2012-06 | `layers/bike_lanes/manual/protection_overrides.csv` |
| 2026-10-12 | M068 Broadway and M124 Willis Av Bridge approach: always protected (protected before the review period) | `layers/bike_lanes/manual/04_build_overrides.R` (`always_protected`) |
| 2026-10-12 | M029 3 Av: first seen protected 2026-04, nothing visible up to 2024-09. Record as a window (after 2024-09, by 2026-04), not a point date; the overrides still carry 2026-04 until date windows are supported | `layers/bike_lanes/manual/protection_overrides.csv`; see TODO (3 Av) |
| 2026-10-14 | Facility texts new in the DOT 2026 release coded in the lookup: Conventional = II (the 2026 name for Standard), Conventional Buffered = I (as Buffered Conventional; buffered counts as protected), Wide Parking Lane = no facility (the 2026 name for Bike-Friendly Parking, which is no facility; e.g. 5 Av 69229), Unpaved = II (as Dirt Trail) | `layers/bike_lanes/manual/lookup_bikelane_types.xlsx` |
| 2026-10-14 | Bike lane windows built from the DOT 2026 version history (all boroughs) instead of the 2020 release plus Manhattan 2025 updates; the manual Street View checks on the 2020 release replace the DOT history up to that release for the segments they cover | `layers/bike_lanes/scripts/03_time_windows.R`; the previous windows are kept as `bike_lanes_time_windows_dot2020.RDS` |
