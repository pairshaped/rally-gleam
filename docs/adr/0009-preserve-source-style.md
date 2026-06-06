# Preserve Source Style

## Status

Accepted

## Decision

Rally-generated output and Rally-authored scaffolds should preserve stable
Rally/Gleam house style.

Large modules use section comment headers when the regions are large enough to
benefit from them:

```text
// TYPES
// INIT
// UPDATE
// BROADCAST
// VIEW
// EFFECTS
// SERVER
// HELPERS
```

Small modules do not need headers when headers add noise.

Imports are grouped by target:

1. unannotated imports that compile on both targets
2. `@target(erlang)` imports
3. `@target(javascript)` imports

Groups are separated by a blank line. Within each target group, imports are
sorted alphabetically where `gleam format` allows it.

`gleam format` owns final formatting. Rally should emit stable, readable source
and avoid semantic churn, but it should not fight the formatter.

Function comments are reserved for Rally-specific contracts, generated callers,
or behavior that is not obvious from standard Lustre TEA. Straightforward view
functions and small view helpers do not need comments.

## Consequences

Generated and scaffolded code feels trustworthy because it does not churn layout
or hide product behavior behind noisy wrappers.

Style is a framework affordance, not a second parser. Rally validates function
names, signatures, target availability, and wire-visible types instead of
depending on section comments.
