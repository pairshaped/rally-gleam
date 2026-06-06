# Keep Page Domain Models Local

## Status

Accepted

## Decision

Page data shapes belong to the page that renders and updates them. A list page,
detail page, and form page may duplicate similar fields because they describe
different page needs.

Page modules should not import page payload types from other page modules. If
two pages both need game data, `games.gleam` can define `GameSummary`,
`games/id_.gleam` can define `GameDetail`, and `games/edit.gleam` can define
`GameForm`. Those types may share fields, but they are independent contracts.

Extract a shared type only when it is a stable application concept independent
of a page, such as an identifier, enum, topic, or value object. Page payloads,
form models, table rows, detail data, and save responses stay page local.

## Consequences

Page protocols can diverge without turning one page's current data need into a
hidden app-wide contract.

Libero and Rally can treat each page module as an owning wire boundary. Two
pages may both define `Item` or `GameSummary` without competing for a global
domain model name.
