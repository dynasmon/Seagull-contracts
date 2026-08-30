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
proto/seagull/detection/v1/    what the rules decided about an event
proto/seagull/hunt/v1/         what a person may ask of what was stored
proto/seagull/control/v1/      who a caller is and what they may do
proto/seagull/ruleset/v1/      the rules a platform runs, and which set of them
proto/seagull/alert/v1/        what an operator does about what the rules found
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

## The ruleset

A rule crosses this boundary as a typed expression tree rather than as the
document somebody wrote it in, so a process that runs rules never learns a file
format. The cases a rule was written for travel with it and are not part of what
names the ruleset: writing a case is not a change to what anything detects.

A published ruleset is immutable and named by its own content. `Record` is what
the ruleset topic carries — every version under its own id, and one pointer
naming the version to run — so activating an older version asks for exactly what
ran before rather than for a reconstruction of it.

## The alert

A detection states what the platform found; an alert is what a person does about
it. They are separate messages because they have separate owners: the analytical
half of an alert is copied from the detection that raised it and never changes,
and the operational half — its state, who holds it, why it was closed — changes
without the detection moving.

An alert is named by the detection that raised it, so re-deciding the same events
against the same rule finds the alert that already exists rather than raising a
second one. `State` is closed and `RESOLVED` is not `FALSE_POSITIVE`: the first
says the platform was right, the second says it was wrong, and only the second
tells a rule author that a rule needs correcting.

Detections that are the same piece of work share a `correlation_key` and fold
into one alert, which counts its `occurrences` and carries the event times of the
first and the last. Folding discards nothing: `Occurrence` names every detection
an alert is made of, so a count can always be read back to the evidence behind
it.

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
