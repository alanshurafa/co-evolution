# Brooklyn & Manhattan High Schools Starting at 9:00 AM or Later

**Spreadsheet:** [`brooklyn-manhattan-9am-start-high-schools.csv`](./brooklyn-manhattan-9am-start-high-schools.csv)
**Scope:** Brooklyn + Manhattan public high schools with a school day starting at **9:00 AM or later**.
**Compiled:** June 2026. **Method:** best-effort web research (see limitations).

---

## TL;DR

A 9:00 AM-or-later start is **rare** in NYC. The standard NYC public high
school starts around **8:00–8:20 AM** (e.g., Brooklyn Tech 8:05, Brooklyn Latin
8:20, Millennium Brooklyn 8:00, Institute for Collaborative Education 8:10/8:20,
Harvest Collegiate 8:45). The 2018–2019 DOE "later start" pilot moved schools to
**8:30**, which still does not meet the 9:00 bar.

The schools that genuinely start at 9:00+ cluster in two models:
**early-college schools** (Bard) and **alternative / Consortium / transfer
schools** (City-As-School, Urban Academy).

| Tier | School | Borough | Start | Quality (Niche) | Homework |
|------|--------|---------|-------|-----------------|----------|
| ✅ Confirmed | Bard HSEC Manhattan | Manhattan | 9:00 AM | A+ | High |
| ✅ Confirmed | Bard HSEC Brooklyn | Brooklyn | 9:00 AM | New (2024) | High (expected) |
| ✅ Confirmed | City-As-School | Manhattan | 9:00 AM | B- | Low (non-traditional) |
| ⚠️ Candidate | East Brooklyn Community HS | Brooklyn | ~9:00–9:30? | C+ | Low (likely) |
| ⚠️ Candidate | Urban Academy Laboratory HS | Manhattan | unverified | B+ | Low–moderate |

---

## How to read the two metrics you asked for

**Quality of education** — there is no single objective "quality" number, so the
sheet uses widely cited proxies: **Niche letter grade**, **4-year graduation
rate**, state **test-proficiency** percentages, and college-enrollment / SAT
data where available. Treat these as indicators, not verdicts — Consortium and
transfer schools intentionally de-emphasize standardized tests, so their low
test/graduation numbers reflect a different mission (credit recovery, portfolio
assessment), not necessarily weak teaching.

**Level of homework** — there is **no authoritative dataset** for homework load.
The sheet characterizes it from school model + student/parent review themes:
- **Early-college (Bard):** *High* — college-level reading/writing from junior year.
- **Consortium / experiential (City-As, Urban Academy):** *Low / non-traditional* —
  graded via portfolios, internships, and seminars rather than nightly homework.
- **Transfer (East Brooklyn):** *Low (likely)* — credit-recovery focus.

## Confidence flags (important)

- **Confirmed** = a published source states a 9:00 AM start (Bard's admitted-student
  FAQ; City-As calendar/listings; NYC SIFT hours for Bard Brooklyn).
- **UNVERIFIED** = the school is a plausible candidate but I could **not** confirm a
  9:00+ first-period start. East Brooklyn's "9 AM" is inferred only from its
  breakfast window; Urban Academy's start time was not found. **Do not treat
  these as confirmed.** Notably, Liberation Diploma Plus — another transfer
  school — starts at **8:20**, so "transfer school" does *not* imply a late start.

## Limitations (please read)

This is a **best-effort researched list, not an exhaustive one.** In this
environment:

1. The authoritative source — **NYC Open Data's DOE High School Directory**,
   which contains `start_time`/`end_time` for every school — was **blocked**
   (both the API host and direct fetch were refused). That dataset is the only
   way to produce a *complete, verified* list.
2. Individual school websites **block automated access (HTTP 403)**, so bell
   schedules could not be scraped at scale.
3. Findings therefore rely on **web-search snippets**, which surface quality and
   homework signals well but rarely state exact start times.

**There are almost certainly additional qualifying schools** (other Consortium
schools, transfer schools, and small alternative programs) that this method did
not surface. To get a guaranteed-complete list, pull the DOE directory CSV (next
section) and filter `start_time >= 9:00`.

## How to complete / verify this list yourself

1. Go to **NYC Open Data → "DOE High School Directory"** (latest year), e.g.
   `data.cityofnewyork.us` and search that title.
2. Export the CSV. It includes `start_time`, `end_time`, `boro`, and
   `school_name`.
3. Filter to `boro` = K (Brooklyn) or M (Manhattan) **and** `start_time >= 9:00 AM`.
4. Enrich each row with quality (Niche / GreatSchools / NYC School Quality
   Reports) and homework (Niche student reviews). Drop the results into this CSV
   format — the columns already match.

## Schools checked and EXCLUDED (start before 9:00 AM)

These were verified to start earlier than 9:00 and are **not** in the sheet:
Brooklyn Tech (8:05), Brooklyn Latin (8:20), Millennium Brooklyn (8:00),
Institute for Collaborative Education (8:10/8:20), Harvest Collegiate (8:45),
Liberation Diploma Plus (8:20). Manhattan Comprehensive Night & Day operates a
flexible day-and-evening schedule (building serves students ~8 AM–9:17 PM); its
day session likely starts before 9:00, so it is excluded pending confirmation.

## Sources

Per-row sources are in the CSV's `Sources` column. Primary references:
NYC DOE / NYC Open Data, NYC SIFT, InsideSchools, Niche, GreatSchools, NYSED Data
Site, U.S. News, PublicSchoolReview, Wikipedia, and the schools' own sites
(bhsec.bard.edu, cityas.org, urbanacademy.org, ebchighschool.org).
