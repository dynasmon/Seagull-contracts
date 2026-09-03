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
proto/seagull/incident/v1/     the higher-order story a correlation tells
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

A rule may also carry a `Count`, which is what turns a match into a threshold:
how many matching events, sharing which fields, inside which window. It travels
with the rule because it is part of what the rule decides — a published ruleset
that dropped it would run a different rule from the one somebody wrote — and
`Aggregation` on the detection is what such a rule found.

A rule may instead carry a `Sequence`, which is an ordered story rather than a
single event: named stages, satisfied in the order they are written, in event
time, inside one window, by events that share a group. A rule carries a `match`
or a `Sequence` and never both, because the stages are what it matches with.
`Correlation` on the detection names the event that satisfied each stage, and
carries how far the clocks that ordered them disagreed — ordering rests on the
producer's clock, so a spread wider than the story's own span means the order is
not established by the data.

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

## The incident

An incident is what a correlation becomes when a person has to answer for it. It
is a fourth concept and not a fourth name for the same row: an event is an
observation, a detection is a rule matching one, an alert is one detection
somebody owns, and an incident is a story several events tell together. Keeping
them apart is what stops a single alerts table from having to mean all four.

It is named by the correlation detection that produced it, the way an alert is
named by the detection that raised it, so a replayed batch finds the incident
that already exists. `stages` carries one event per stage in the order the rule
declares them, so the story can be traced back to its component events and,
through `detection_id`, to what decided it. Nothing an operator does to an
incident writes to any of them.

`Confidence` is the platform's and not the rule author's. Severity says how much
a story would matter if it happened in that order; confidence says how far the
clocks that timed it support that order at all, measured as the clock spread the
correlation carries against the story's own span and against the window the rule
looked through. A rule cannot declare how well the clocks of an estate agree.

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
