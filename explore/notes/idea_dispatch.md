# When ride-hail apps dispatch taxis

Idea 1 from the 2026-10-24 data audit (dashboard: https://claude.ai/artifact/R7LzCH2b5gYf4H9wMQNqeh; scripts in `explore/`, outputs in `output/explore/`).

## Stylized facts

- From June 2026 the yellow trip files carry `request_source`: the licence of the ride-hail platform that dispatched the trip. About a quarter of yellow trips in June 2026 came through Uber (HV0003). Lyft (HV0005) starts in August 2026 and adds about 5%.
- App-dispatched trips are longer (median 2.6 to 4.4 miles, against 1.6 for a street hail) and dearer (median fare $23, against $13.50).
- Before June 2026 there is no flag, but yellow pickups outside Manhattan jump twice, in March 2024 and in February to May 2025, from about 70,000 to 350,000 a month.
- Over the same period yellow trips below 60th Street fell 47% (2019 to 2025).

## Research question

What happens to a regulated taxi market when the dominant ride-hail platforms start dispatching its cabs?

- **Where cabs work.** Do yellow cabs shift from street hails in Manhattan to app trips in the outer boroughs?
- **Utilisation.** Do cabs carry passengers a larger share of their time, or do they drive empty to reach app pickups?
- **Prices.** App fares are set upfront, not by the regulated meter. Do app trips cost more, and does the fare on street hails change?
- **Who loses.** Do these trips come from the platforms' own drivers, or are they new trips?

Street hailing has search frictions: cabs cruise Manhattan because that is where they find passengers. App dispatch removes that friction, so the outer boroughs, long underserved by street hails, should change most. The related literature studies matching between drivers and passengers (Frechette, Lizzeri and Salz, and Buchholz, on taxi search frictions). The new part here is a platform doing the matching for a regulated competitor instead of replacing it.

## Policy relevance

1. **Around the cap on ride-hail cars.** Since 2018 the TLC has capped new licences for ride-hail cars. Dispatching cabs gives the platforms more cars without new licences, so the cap binds less than it seems. Rules written for two separate markets stop working when one platform runs both.
2. **Two sets of rules for the same trip.** Cab drivers and ride-hail drivers face different rules on minimum pay, fares and congestion surcharges. Through the app, the same trip can fall under either set, which raises a question of consistency and of what drivers earn.
3. **Outer-borough service.** The green "Boro Taxi" programme (from 2013) tried to bring street-hail service to the outer boroughs by regulation, and its trips collapsed (15.8M in 2014 to 0.6M in 2025). App dispatch may be reaching the same goal through the market. Both series are in the store.
4. **The medallion system.** Medallion values crashed and the city had to arrange debt relief. Whether platform dispatch keeps cabs busy, or turns them into spare capacity for the platforms, matters for whether the medallion system still makes sense.
5. **Platform power.** When one platform dispatches both fleets, competition between taxis and ride-hail weakens. This matters for competition policy and for the TLC's fare rules.
6. **Congestion.** If dispatch cuts cruising in Manhattan, it reduces miles driven empty. If it adds empty driving to outer-borough pickups, it increases them. This links to the congestion pricing project.

## Design

- Event studies around each platform's dispatch start (Uber, then Lyft in August 2026) by zone and hour. Zones are compared by how much street hailing they had before.
- From June 2026 `request_source` measures the app share directly. Before that, the breaks in outer-borough pickups, trip length and fares date the rollout.
- Ride-hail trips in the same zones and hours show the substitution.

## Data

- Yellow and ride-hail trip files (zones, times, distances, fares, tips), all in the store; `request_source` from June 2026.
- Dispatch start dates from TLC filings and press. I believe Uber's taxi integration (with Curb/CMT) was announced in spring 2024, which would match the March 2024 break. This still needs checking.

## Risks

- The flag starts only in June 2026, so the earlier rollout has to be inferred.
- Congestion pricing (January 2025) overlaps with the second jump.
- The files carry no vehicle or driver IDs, so utilisation can only be measured per zone and hour, not per cab.

## Overlap

- Close to the tips project, which uses yellow trips. App tipping may differ, so tips should be split by channel. The question here is market structure, not tipping.

## First step

Date the rollout:
- check the 2024–25 breaks against TLC filings and press reports;
- test whether trip length and fares jump at the same dates as outer-borough pickups.

Diagnostic script for `request_source`: `explore/12_request_source.R` (yellow 2026-06 and 2026-08, broken down by borough, vendor, distance and fare).
