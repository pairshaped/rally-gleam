# Separate Mutation Results From Broadcast Events

## Status

Accepted

## Decision

Mutations have two outputs with different audiences.

The correlated request result goes back to the connection that sent the command.
It carries the success or error payload that the initiating page needs to finish
its local workflow. That payload is page-local and command-specific.

Broadcast events go to other subscribed connections. They carry the state event
those other connections need to converge on the server state. Broadcast event
types that are consumed across pages live in `src/broadcasts.gleam`. The
broadcast payload can differ from the correlated result payload.

Broadcast-aware pages expose `broadcast_subscriptions(...)` for subscription
interest and `apply_broadcast(...)` for applying decoded broadcast events to
their model. These hooks live together in a `// BROADCAST` section by
convention.

Pages expose typed topic values, such as `broadcasts.Topic`, not raw wire
strings. Generated Rally glue maps typed topics through the app-owned topic-name
function before syncing transport state. The wire topic key is a stable domain
key such as `games` or `game:3`, not a rendered Gleam constructor such as
`GameTopic(3)`.

Topic synchronization is a small text WebSocket control protocol. The client
sends the complete current topic set as `sub:topic` or `sub:topic,other-topic`;
it sends `unsub` when the complete current set is empty. These frames are
transport control frames, not page-local ETF payloads.

`sub:` frames are full replacement, not incremental subscribe operations. The
server calculates the join/leave diff for each connection and stores that
connection's current topic set.

Broadcast filtering happens on the server. The browser should not receive every
broadcast and filter locally.

The server does not infer topic changes from page load requests. A load request
is not always a navigation, not every navigation has a load request, and topics
may change after local updates or broadcast events. Generated browser glue syncs
topics after page state changes because the browser owns the active page model.

For dynamic pages, generated page state retains route params and generated Rally
browser glue can pass those params to the page's topic hook. Route-backed pages
can declare interest before load data arrives.

The origin connection is excluded from the broadcast caused by its own mutation.
Other connections on the same page, including other browser tabs for the same
user, still receive the broadcast when subscribed.

## Consequences

The initiating page updates from its request result. Other clients update from
broadcasts. Rally owns request correlation and transport mechanics. Application
code owns the page-local command result shape, root broadcast event shape,
sender-side broadcast meaning, and page-level subscription policy.
