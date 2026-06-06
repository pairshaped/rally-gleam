---
# rally-sonv
title: Use package HexDocs subdomain links
status: completed
type: task
priority: normal
created_at: 2026-06-06T18:58:02Z
updated_at: 2026-06-06T18:59:51Z
---

Update Rally docs to link our packages through their HexDocs subdomains, such as rally.hexdocs.pm, libero.hexdocs.pm, marmot.hexdocs.pm, and proute.hexdocs.pm.

## Summary of Changes

- Linked Marmot, Proute, and Libero in the README Convention Stack through their HexDocs subdomains.
- Added Proute to llms.txt package links using https://proute.hexdocs.pm/.
- Confirmed existing Rally, Libero, and Marmot package links already use subdomain HexDocs URLs after pulling latest master.

## Validation

- git pull --rebase --autostash first
- rg scan confirmed our package docs links use subdomain URLs
- git diff --check

## Additional Note

The README Convention Stack table should link every library in the table, not only Rally-owned packages.

## Summary of Additional Changes

Linked every library in the README Convention Stack table: SQLite, Marmot, Proute, Libero, and Lustre.

## Validation

- git diff --check
