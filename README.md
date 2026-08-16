# Seagull contracts

The messages Seagull components exchange: agents, the ingest gateway, the
control plane and everything downstream of the event backbone.

It lives on its own because none of those components owns it. An agent must be
able to speak the contract without depending on the platform, and the platform
must be able to change internally without asking an agent to upgrade.

## What is here

```text
proto/seagull/event/v1/        the canonical security event
proto/seagull/ingest/v1/       what an agent sends and what it is told back
proto/seagull/platform/v1/     the descriptor an agent negotiates against
gen/go/                        generated Go, committed
```

The generated code is committed so that a consumer needs no code generator to
build. CI regenerates it and fails on any difference.

## Using it from Go

```go
import (
    eventv1 "github.com/dynasmon/Seagull-contracts/gen/go/seagull/event/v1"
    ingestv1 "github.com/dynasmon/Seagull-contracts/gen/go/seagull/ingest/v1"
)
```

```bash
go get github.com/dynasmon/Seagull-contracts@v0.1.0
```

While the repository is private, consumers need `GOPRIVATE=github.com/dynasmon/*`
and credentials that can read it.

## The event

An event carries who observed it, when it happened, and one typed body. There is
no free-form map: a new kind of telemetry means a new message, which is the
friction that keeps the schema describable.

Three timestamps are distinct and never collapsed:

| Field | Written by | Meaning |
|---|---|---|
| `time.event_time` | the producer | when it happened on the endpoint |
| `time.observed_time` | the producer | when the collector saw it |
| `reception.ingest_time` | the platform | when the platform accepted it |

`reception` and the identity fields in `origin` are assigned by the platform,
never merged with what a producer sent. A producer cannot choose its own
identity, its tenant, or its place in the platform's timeline.

The shape is aligned with OCSF where that buys interoperability, and departs
from it where Seagull has its own need. It does not carry OCSF identifiers.

## The acknowledgement

`BatchAck` is the reason an agent can let go of data. It may drop its local copy
of a batch only when all three agree: `accepted`, `durable`, and a `received`
count matching what it sent. Anything else means the agent keeps the batch and
retries.

## Evolving it

```bash
make lint       # style
make generate   # regenerate gen/go
make check      # fail when the committed bindings are stale
make breaking   # fail when a change breaks compatibility with main
make verify     # all of the above
```

Fields are added, never renamed, renumbered or removed. `make breaking` runs on
every pull request and refuses the rest.

Releases are tagged `vX.Y.Z`. A new field or message is a minor release; a new
`vN` package directory is how an incompatible shape arrives, so consumers can
migrate on their own schedule instead of in lockstep.
