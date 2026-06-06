---
# rally-1zld
title: Maybe evaluate PostgreSQL support
status: draft
type: feature
priority: deferred
created_at: 2026-06-06T15:10:24Z
updated_at: 2026-06-06T15:10:24Z
---

Maybe someday, evaluate whether Rally should support PostgreSQL as an additional framework-backed database foundation. This is not a committed direction.

Possible stack to evaluate:
- `pog` for PostgreSQL connectivity
- `squirrel` for typed/query ergonomics
- Rally conventions equivalent to the current SQLite + Marmot path

Questions to answer before promoting this:
- Does PostgreSQL support fit Rally's opinionated conventions, or does it make the framework less focused?
- Can it be supported without adding per-app glue or split-brain database paths?
- What would migrations, test DB setup, generated query access, deployment config, and local development look like?
- Would PostgreSQL become a first-class tested Rally foundation, or should apps that need it fork Rally and submit a focused PR?

Acceptance for this maybe-bean is only a written recommendation. No implementation should start from this bean without an explicit decision to promote it.
