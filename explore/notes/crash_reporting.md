# The crash reporting break

Diagnosis of the collapse in property-damage-only (PDO) crash reports found in the 2026-10-24 audit.
Script: `explore/13_crash_reporting.R`. Output: `output/explore/crash_reporting/` (log `crash_reporting.txt`, monthly series by borough, precinct table, NYPD against DMV). DMV counts: `output/explore/dmv/dmv_cases_nyc.csv`.

## Cause: NYPD stopped attending PDO crashes

- **Staten Island pilot from 18 March 2019.** NYPD stopped responding to crashes with property damage only.
- **Citywide from 6 April 2020.** Since then, 911 callers reporting a PDO crash hear a recorded message. Drivers exchange details and file an MV-104 with the DMV when damage exceeds $1,000.
- **Exceptions.** Police still attend crashes where someone is hurt or killed, a domestic animal is hurt, or an unattended car or other property is damaged.

Sources: [NYPD press release](https://www.nyc.gov/site/nypd/news/p0403b/nypd-expanding-successful-non-injury-collision-pilot-save-nypd-resources), [Streetsblog](https://nyc.streetsblog.org/2020/04/03/nypd-gives-a-few-details-of-new-no-report-crash-policy/).

The NYPD crash file holds police reports (MV-104AN) only, so these crashes leave the record.

## What the data show

**The break dates match the policy.**

- Best single break in the monthly PDO-per-injury-crash ratio, 2018–2021:
  - Staten Island: after 2019-03 (ratio 4.8 to 2.2).
  - Bronx, Brooklyn and Queens: after 2020-04 (3.5–3.8 to about 2.0).
  - Manhattan: after 2020-03 (5.0 to 1.9), where COVID and the policy cannot be told apart.
- Weekly data outside Staten Island: the ratio falls from 4.3 to 2.4 in the week starting Monday 6 April 2020. The COVID lockdown weeks before it had kept the ratio at 4.2–4.6.
- Staten Island is an early-treated borough. Its 2019 base was already affected, which is why the audit found a smaller 2019–2025 drop there.

**A second, gradual decline follows.** After the break, the ratio keeps falling in every borough, from about 1.9 (2021) to 1.2–1.4 (2024–25). The pre-2020 ratio applied to injury crashes implies the following share of PDO crashes missing from the record:

| 2019 | 2020 | 2021 | 2022 | 2023 | 2024 | 2025 |
|---|---|---|---|---|---|---|
| 6% | 38% | 53% | 58% | 65% | 67% | 67% |

So it is not one level shift that year effects could absorb. Possible reasons:
- drivers learning not to call;
- police attending fewer of the exception cases;
- a real fall in PDO crashes.

These data cannot separate them.

**No deleted records.** Counts for January–September 2019 are identical in every snapshot from February 2020 to October 2026 (125,915 PDO crashes, 33,948 with an injury). The October 2019 snapshot was simply still filling in.

**What PDO crashes are left.** These are the cases police still attend: outside Staten Island, 2018–19 against 2022–25.

| | 2018–19 | 2022–25 |
|---|---|---|
| Single-vehicle | 18% | 35% |
| Off-street address | 27% | 37% |
| Between midnight and 6 am | 9.5% | 16% |
| Factor "Unspecified" | 24% | 29% |
| Taxi as vehicle 1 | 5.0% | 2.4% |

PDO crashes after 2020 are a selected sample, not a scaled-down version of the earlier ones.

**The drop varies across precincts.** The change in the ratio ranges from −49% to −79%, with the largest drops in Midtown and lower Manhattan (precincts 10, 14, 17, 18). The correlation with the 2018–19 ratio is −0.57: precincts that had many PDO reports per injury crash lost the most. After the break, ratios converge to about 1–2 everywhere. With precinct fixed effects plus year effects, a design spanning 2020 still picks up the reporting change through this heterogeneity.

## Injury crashes are not fully safe either

The NYS DMV crash cases (data.ny.gov `e8ky-4vqe`, 2021–2024 only) include crashes reported by motorists alone (`police_report = N`).

| Year | NYPD injury crashes | DMV injury cases, police report | DMV injury cases, motorist report only |
|---|---|---|---|
| 2021 | 36,233 | 38,728 | 8,502 |
| 2022 | 36,407 | 39,014 | 10,358 |
| 2023 | 37,804 | 40,083 | 11,941 |
| 2024 | 37,106 | 39,957 | 12,759 |

- Police-reported injury crashes are stable, and NYPD counts match the DMV police cases closely.
- Injury crashes reported only by motorists rose 50% in four years: from 18% to 24% of all DMV injury cases.
- Some of the injury crash trend in the NYPD data may therefore reflect reporting too.
- **Caveats.**
  - The DMV "injury" category includes "Property Damage & Injury".
  - Some motorist-only reports may duplicate police reports that the DMV failed to match.
  - The injuries in motorist-only reports are probably minor.

On PDO, NYPD records about twice as many crashes as the DMV's police-reported PDO cases (which require damage over $1,000). About 30% of DMV PDO cases (37% in Manhattan) come from motorists only. DMV PDO cases also fall from 2021 to 2024 (49,800 to 36,200), so filings with the DMV are falling as well.

## What to do in the projects

- **Never use total or PDO crash counts across 2019–2020.** On Staten Island the break is March 2019, elsewhere April 2020.
- **Use injury crashes or injured persons.**
  - Check robustness with killed and seriously injured people. The persons table has `PERSON_INJURY` and `COMPLAINT`, but filter it to the injured, since it lists uninjured people from 2016 on.
  - For trends after 2021, keep in mind that motorist-only reports are growing.
- **Bike lane and congestion pricing projects.** Check whether any outcome uses all crashes. Precinct fixed effects do not absorb the break, because its size varies by precinct.
- **Staten Island** can serve as an early-treated group if the reporting change itself is ever the object of study.

## Can it be "solved"?

The missing reports cannot be recovered: they were never filed with the police. Options:
1. Treat it as a measurement break, as above. This is the default.
2. Add the DMV crash cases to the store (`raw/crashes_dmv/`, county by year, 2021–2024) as a benchmark. They have no coordinates, only county and municipality, so they cannot replace the NYPD file. Older DMV windows (2014–2020) are no longer on data.ny.gov; ITSMR's TSSR might have county totals for those years.
3. Older snapshots do not help: they contain the same records.

## The stale download

The NYC Open Data crash dataset (`h9gi-nx95`) was last updated on 2026-06-15 and its latest crash is on 2026-06-11 (checked 2026-10-24). Nothing can be downloaded until NYPD resumes publication; check again before using 2026.

## A possible paper angle

The Staten Island pilot (March 2019) and the citywide rollout (April 2020) are dated policy shocks to whether police attend minor crashes. Questions:
- **Does traffic clear faster without waiting for police?** TLC speeds near crash locations could show this.
- **What happens to insurance claims and hit-and-runs?**
- **How biased are published Vision Zero evaluations that use all crashes?**

The citywide date coincides with the COVID lockdown, so the Staten Island pilot carries the identification. Ride-hail data only start in February 2019, a month before it, and yellow taxi trips on Staten Island are few.
