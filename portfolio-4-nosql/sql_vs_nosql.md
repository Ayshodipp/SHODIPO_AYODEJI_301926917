# SQL vs NoSQL — A Comparison for KickOff Arena

**Portfolio 4, MIT 8103 Advanced Database Systems · Ayodeji Shodipo · 2026/A/MIT/0725**

## 1. The two models in one paragraph

In the **relational model** (PostgreSQL 16 in this portfolio) every entity is a
table, every relationship is a foreign key, and every row of a given table
has exactly the same columns. In the **document model** (MongoDB 8 in this
portfolio) every entity is a JSON-like document inside a collection; the
shape can vary from one document to the next, and relationships are usually
embedded rather than joined. The four NoSQL families introduced in Study
Session 1 of the course notes are document (MongoDB), key-value (Redis),
column-family (Cassandra) and graph (Neo4j). We use the document family
because KickOff Arena's match reports have a **variable shape per match** —
the textbook case for documents.

## 2. What lives in PostgreSQL and what lives in MongoDB

| Aspect | PostgreSQL (Portfolio 1) | MongoDB (Portfolio 4) |
|---|---|---|
| Booking, payment, match_result summary | ✔️ 3NF tables, strict schema, FK constraints, exclusion constraint | — |
| Master data (location, pitch, team, player, pricing) | ✔️ | — |
| Match reports — scorers, cards, notes, penalty shootouts, VAR reviews | — | ✔️ Variable-shape documents |
| Transactions / deposit at booking time | ✔️ ACID, with exclusion constraint | ⚠️ MongoDB has multi-document transactions since 4.0, but they cost more than PostgreSQL's |
| Analytics on revenue, utilisation, no-show rate | ✔️ SQL joins, GROUP BY | ⚠️ Aggregation pipelines, but joins across collections are weaker |
| Analytics on top scorers / win rates | ⚠️ Possible but needs joins on `match_result` + a `scorer` table that we deliberately did not create | ✔️ `$unwind` + `$group` over the embedded `scorers` array |
| Concurrency control | ✔️ MVCC + exclusion constraints + `SELECT … FOR UPDATE` | ⚠️ Document-level locking; weaker for multi-document workflows |

## 3. Why match reports went to MongoDB

A 5-a-side match has the following optional data:

- **Final score** — always present.
- **Goal scorers** — 0 to ~10 per match; each scorer has a minute, a team, an
  optional assist; an own goal is flagged.
- **Cards** — 0 to ~5 per match; each card has a color, minute, reason.
- **Penalty shootout** — only on drawn cup matches; a `takers` array of
  variable length.
- **VAR reviews** — only on matches that used VAR; each review has a minute,
  subject and decision.
- **Free-text notes** — sometimes present, sometimes not.

If we modelled all of this in PostgreSQL, we would have one of:

1. A wide, sparse `match_event` table with 30+ columns, most of which are
   `NULL` for any given match. Reads become ugly and the schema becomes
   brittle.
2. Multiple normalised tables (`scorer`, `card`, `penalty_taker`, `var_review`)
   joined back to `match_result`. Reads become `JOIN`-heavy and the schema
   has to anticipate every event type at design time.
3. A `JSONB` column on `match_result` — which is technically possible in
   PostgreSQL but loses most of the schema-validation benefit (you would
   re-implement a `$jsonSchema` validator by hand) and gives you the worst
   of both worlds: the schema is neither strict nor queryable as
   comfortably as a document store.

MongoDB's `$jsonSchema` validator gives us: required fields, type-checked
optional fields, enumerated values, range constraints (`minute` between 0 and
90, `score` between 0 and 30) **and** the freedom to omit entire optional
sub-objects. The seed data deliberately produces documents with very
different shapes — some have only the score, some have scorers + cards, ~2%
have a penalty shootout, ~10% have a VAR review — to demonstrate this
flexibility.

## 4. Schema discipline: relational vs document

| Property | PostgreSQL | MongoDB |
|---|---|---|
| Schema enforcement | Column-level types + CHECK constraints + FKs + exclusion constraints (all from P1) | `$jsonSchema` validator (P4) — strict mode, error on violation |
| Indexes | B-tree, GiST, GIN, partial indexes, exclusion constraints | B-tree, multi-key (on array elements), text, geospatial, partial, TTL |
| Atomicity unit | A row | A document (with optional multi-doc transactions) |
| Joins | First-class (`JOIN`, `LATERAL`) | `$lookup` (slower, single-stage by default) |
| Best for | Money + bookings + integrity-sensitive master data | Variable-shape event data, semi-structured content, fast iteration |

## 5. CAP theorem placement (links to Study Session 2)

| Property | PostgreSQL | MongoDB |
|---|---|---|
| Default consistency | Strong (single primary, synchronous commit optional) | Strong on the primary; eventual on secondaries |
| Partition tolerance | Synchronous replication gives up availability to keep CP | By default MongoDB is CP (single primary); can be tuned toward AP via read preferences and write concerns |
| Trade-off we accept | Lower write throughput in exchange for ACID | Slightly weaker multi-document ACID in exchange for schema flexibility |

## 6. What the practical comparison shows

Running the **same query** — "find every match in which player X scored" — in
both stores makes the difference concrete:

- In **PostgreSQL**, that query requires a separate `scorer` table and an
  indexed join (we deliberately did not create one, because the variable
  shape would have forced NULLs everywhere). On a 50k-booking schema this
  costs ~`[paste real time]` ms.
- In **MongoDB**, the same query is `db.match_reports.find({ "scorers.player_id": X })`,
  backed by a multi-key index on `scorers.player_id`. The COLLSCAN-before /
  IXSCAN-after demo in `collscan_ixscan.js` shows the speed-up: ~`[paste real
  time]` ms COLLSCAN → ~`[paste real time]` ms IXSCAN.

## 7. Recommendation for KickOff Arena

Keep the **hybrid** architecture:

- **PostgreSQL** for everything money- and integrity-related: locations,
  pitches, teams, players, bookings, payments, the structured match summary.
- **MongoDB** for the rich, variable-shape match reports (scorers, cards,
  penalty shootouts, VAR reviews, notes), with a `$jsonSchema` validator so
  the loose shape still has boundaries.

The two stores are linked by `match_id` (MongoDB's `match_id` long field
mirrors PostgreSQL's `match_result.match_id` bigint primary key). This is a
realistic pattern at scale: the OLTP core stays in a strict relational store
and the rich event payload lives in a document store that is better suited
to it.

## 8. Honest reflection

`[Student to write 2–3 sentences after running the code: which query was
fastest, where MongoDB's flexibility paid off, where PostgreSQL's
constraints were irreplaceable, and what surprised them.]`
