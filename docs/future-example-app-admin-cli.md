# Future Example App: Admin CLI

Status: idea for later
Date: 2026-05-10

## Summary

Build an example app that shows Rally as a typed multi-client framework, not
only a full-stack web app framework.

The app should have:

- a public web surface for end users
- an admin web surface for human operators
- a Rust CLI that acts as another admin interface, mainly for AI agents

The CLI should not be a separate product surface. It should use the same admin
load/save contract as the admin web app, over an HTTP request/result transport
instead of the browser WebSocket transport.

## Candidate Domain

A help desk or concierge board is the strongest fit so far.

Public users can submit requests and track status by claim code. Human admins
manage the queue in the admin app. An AI agent can act on behalf of an admin
through the Rust CLI.

The app avoids full account auth. Public access uses unguessable claim codes.
Admin and agent actions can use simple tokens while the example stays focused
on multi-client architecture.

## Surfaces

### Public Web Client

- mount: `public`
- route root: `/`
- generated Rally browser transport
- submit a request
- view request status by claim code
- receive live status and reply updates

### Admin Web Client

- mount: `admin`
- route root: `/admin`
- generated Rally browser transport
- view the request queue
- inspect request details
- label, prioritize, assign, reply, and resolve requests
- see live updates when the CLI changes a request

### Rust Admin CLI

- built from the `admin` mount's typed load/save contract
- HTTP request/result transport
- intended for AI agents and scripts
- same admin capability boundary as the admin web app, possibly with a narrower
  token scope

Possible commands:

```sh
adminctl requests list --status new
adminctl requests show REQ-8K42
adminctl requests label REQ-8K42 billing
adminctl requests note REQ-8K42 "Customer mentioned invoice #1241"
adminctl requests draft-reply REQ-8K42
adminctl requests mark-review REQ-8K42
```

## What This Proves

- Rally can serve multiple web surfaces from one app.
- The public and admin mounts can have separate route roots and page contracts.
- The admin contract can support both the browser transport and an HTTP tool transport.
- A Rust CLI can use the same typed admin contract as the admin Lustre app.
- CLI changes can push live updates into the admin UI.
- Public pages can receive live updates when admin actions publish user-visible
  changes.

The demo moment:

1. A public user submits a request.
2. The admin UI sees it appear live.
3. An agent uses `adminctl` to label it or draft a response.
4. The admin UI updates live from that HTTP action.
5. When a public reply is posted, the public status page updates live.

## Why This Is Better Than A Normal CRUD Example

Rally Scoreboard Example proves the page-local contract path. This example should prove the
more specific Rally advantage: one typed server contract can serve multiple
surfaces with different transports and different user experiences.

The Rust CLI matters because it is not a side demo. It is another admin surface.
That makes tool transports feel like part of the framework story rather than
extra plumbing.
