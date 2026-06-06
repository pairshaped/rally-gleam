---
# rally-3hou
title: Rename save hook to handle_save
status: completed
type: task
priority: normal
created_at: 2026-06-06T19:09:43Z
updated_at: 2026-06-06T19:18:56Z
---

Rename Rally's page-owned save hook from handle to handle_save across generator discovery, generated code, tests, docs, ADRs, and app scaffolding/docs.

## Summary of Changes

- Renamed the page-owned save hook contract from `handle` to `handle_save` in Rally discovery, generated server WS calls, scaffold output, tests, docs, guides, ADRs, and llms.txt.
- Updated Rally Libero generation calls for the current Libero API by passing explicit empty endpoint and push-dispatch lists for Rally seed-driven generation.
- Preserved unrelated runtime/http handler naming.

## Validation

- gleam format
- git diff --check
- gleam test: 193 passed
