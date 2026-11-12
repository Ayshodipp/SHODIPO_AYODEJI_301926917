# Portfolio 2 — Query Optimisation: Before / After Results

**Student:** Ayodeji Shodipo · 2026/A/MIT/0725
**Run date:** `[paste real run date here]`
**Codespace machine:** `[paste real machine spec — e.g. 4 vCPU, 16 GB RAM]`
**Seed size:** `[paste real row count from P1 — e.g. bookings = 52,438]`

> Every value below is a placeholder. After running `run_p2.sh`, **replace each
> `[paste real output here]` with the actual text copied from your terminal.**
> Do not invent or estimate numbers. The CA brief and the student's own honesty
> rules forbid fabricated timings.

---

## Summary table — execution time before vs after indexes

| Query | Plan node before | Exec time before (ms) | Plan node after | Exec time after (ms) | Speed-up |
|---|---|---|---|---|---|
| Q1 Free slots at Lekki for a date | `[paste real node]` (e.g. Seq Scan on booking) | `[paste real time]` | `[paste real node]` (e.g. Bitmap Heap Scan via idx_booking_status_start) | `[paste real time]` | `[paste real ratio]`× |
| Q2 Revenue per location per month | `[paste real node]` | `[paste real time]` | `[paste real node]` | `[paste real time]` | `[paste real ratio]`× |
| Q3 Peak-hour usage | `[paste real node]` | `[paste real time]` | `[paste real node]` | `[paste real time]` | `[paste real ratio]`× |
| Q4 Top teams by bookings | `[paste real node]` | `[paste real time]` | `[paste real node]` | `[paste real time]` | `[paste real ratio]`× |
| Q5 No-show rate | `[paste real node]` | `[paste real time]` | `[paste real node]` | `[paste real time]` | `[paste real ratio]`× |
| Q6 Pitch utilisation % | `[paste real node]` | `[paste real time]` | `[paste real node]` | `[paste real time]` | `[paste real ratio]`× |

---

## Q1 — Free slots at a location for a given date

**Indexes used by the optimiser (after):**
- `idx_booking_status_start` (partial index on `booking(start_time)` filtered to
  `status IN ('confirmed','completed','no_show')`)

### Before — EXPLAIN ANALYZE plan
```
[paste real output here — copy the whole plan from the terminal]
```
**Key line (Execution Time):** `[paste real execution time in ms]`

### After — EXPLAIN ANALYZE plan
```
[paste real output here — copy the whole plan from the terminal]
```
**Key line (Execution Time):** `[paste real execution time in ms]`

**Commentary:** `[your own one-paragraph comment: which scan node changed, why the
partial index helped, and how big the speed-up was]`

---

## Q2 — Revenue per location per month

**Indexes used by the optimiser (after):**
- `idx_payment_paid_at_succeeded` (partial index on `payment(paid_at)`
  filtered to `status = 'succeeded'`)
- `idx_payment_booking_id` (join index)

### Before — EXPLAIN ANALYZE plan
```
[paste real output here]
```
**Execution Time:** `[paste real time]`

### After — EXPLAIN ANALYZE plan
```
[paste real output here]
```
**Execution Time:** `[paste real time]`

**Commentary:** `[your own comment on the change in plan node and time]`

---

## Q3 — Peak-hour usage

**Indexes used by the optimiser (after):**
- `idx_booking_status_start` (range scan on `start_time`)
- `idx_booking_time_range_gist` (GiST on `time_range`)

### Before — EXPLAIN ANALYZE plan
```
[paste real output here]
```
**Execution Time:** `[paste real time]`

### After — EXPLAIN ANALYZE plan
```
[paste real output here]
```
**Execution Time:** `[paste real time]`

**Commentary:** `[your own comment]`

---

## Q4 — Top teams by number of bookings

**Indexes used by the optimiser (after):**
- `idx_team_id_booking` (group-by index)

### Before — EXPLAIN ANALYZE plan
```
[paste real output here]
```
**Execution Time:** `[paste real time]`

### After — EXPLAIN ANALYZE plan
```
[paste real output here]
```
**Execution Time:** `[paste real time]`

**Commentary:** `[your own comment]`

---

## Q5 — No-show rate

**Indexes used by the optimiser (after):**
- `idx_booking_status_start` (filter on `status = 'no_show'` AND
  `start_time < now()`)

### Before — EXPLAIN ANALYZE plan
```
[paste real output here]
```
**Execution Time:** `[paste real time]`

### After — EXPLAIN ANALYZE plan
```
[paste real output here]
```
**Execution Time:** `[paste real time]`

**Commentary:** `[your own comment]`

---

## Q6 — Pitch utilisation %

**Indexes used by the optimiser (after):**
- `idx_booking_status_start` (range scan on `start_time` for the last 30 days)

### Before — EXPLAIN ANALYZE plan
```
[paste real output here]
```
**Execution Time:** `[paste real time]`

### After — EXPLAIN ANALYZE plan
```
[paste real output here]
```
**Execution Time:** `[paste real time]`

**Commentary:** `[your own comment]`

---

## Honest reflection (to be filled in by the student after running)

> Which index gave the biggest speed-up? Which query did not benefit from the
> index and why? Did the planner ever ignore an index you added? Did `ANALYZE`
> change the plan? Write 3–5 sentences of your own — `[your own reflection here]`.
