# Seagull contracts

The messages Seagull components exchange: agents, the ingest gateway, the
control plane and everything downstream of the event backbone.

It lives on its own because none of those components owns it. An agent must be
able to speak the contract without depending on the platform, and the platform
must be able to change internally without asking an agent to upgrade.

## What is here

```text
proto/seagull/event/v1/         the canonical security event
proto/seagull/ingest/v1/        what an agent sends and what it is told back
proto/seagull/platform/v1/      the descriptor an agent negotiates against
proto/seagull/detection/v1/     what the rules decided about an event
proto/seagull/hunt/v1/          what a person may ask of what was stored
proto/seagull/control/v1/       who a caller is and what they may do
proto/seagull/ruleset/v1/       the rules a platform runs, and which set of them
proto/seagull/alert/v1/         what an operator does about what the rules found
proto/seagull/incident/v1/      the higher-order story a correlation tells
proto/seagull/agent/v1/         the machines the platform admits telemetry from, and what they report
proto/seagull/inventory/v1/     what an asset was observed to have
proto/seagull/vulnerability/v1/ what a source says is wrong with software
proto/seagull/policy/v1/        how an agent is told to run, signed off the platform
proto/seagull/update/v1/        which releases an agent may install, signed off the platform
proto/seagull/assessment/v1/    the checks a policy asks an agent to run, and what it found
gen/go/                         generated Go, committed
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
`Correlation` on the detection names the event that satisfied each stage and the
agent that sent it, and carries how far the clocks that ordered them disagreed —
ordering rests on the producer's clock, so a spread wider than the story's own
span means the order is not established by the data. A detection is named by the
events it was decided from, each by its agent and its identifier, so the same
events name the same detection whichever of them arrived last; a story whose
stages came from several agents is about the agent of its last stage.

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
declares them, each with the agent that sent it, so the story can be traced back
to its component events and, through `detection_id`, to what decided it. Nothing an operator does to an
incident writes to any of them.

`Confidence` is the platform's and not the rule author's. Severity says how much
a story would matter if it happened in that order; confidence says how far the
clocks that timed it support that order at all, measured as the clock spread the
correlation carries against the story's own span and against the window the rule
looked through. A rule cannot declare how well the clocks of an estate agree.

## The agent

An `Agent` is the administrative record of one machine: which tenant it belongs
to, what somebody said it was, the certificate identity bound to it, and who last
moved it. It is not a picture of a running machine. `State` is closed, and its
three endings mean different things — `DISABLED` is reversible and says an
operator stopped listening, `REVOKED` says the credential is not to be trusted,
`DECOMMISSIONED` says the machine is gone — because only that distinction decides
whether a certificate may be issued for the identity again.

`last_seen` is the one field that is not decided but observed, and it is read
back from where the telemetry landed rather than kept beside the others. An agent
sends continuously and is registered once; a registry that recorded every arrival
would be a write on the ingest path, and the ingest path may not depend on the
control plane's store.

`Admission` is what the data plane is told, and it is deliberately less than the
record: an agent, a tenant, a state and the revision it was written from. It
crosses a compacted topic keyed by the agent, so a gateway replays it before it
serves and follows it afterwards, and learns that an identity is no longer
honoured without learning who stopped honouring it or why.

## The agent status

A `Status` is what one agent says of itself at one moment: whether it and each
of its parts run as they should, what it holds and has not delivered, its
certificate, the settings and the policy it runs on, what it may do on its host,
and how the run before this one ended. An agent sends one every `interval` it
announces, on a stream of its own beside events and inventory, so an agent on a
host nobody logs into is still heard from. A `StatusBatch` is answered and
refused with the same `BatchAck` and `Rejection` as every other batch, and the
platform stamps who sent a report and when it arrived exactly as it stamps an
event.

A report stands on its own. The platform keeps the newest of each agent, and an
agent sends its newest rather than a backlog: one that never arrived is made up
for by the next, and status never competes with telemetry for room or order.
`installation_id`, `sequence` and `run.boot_id` are what tell one source from
two: a sequence counts every report an installation writes, across restarts,
and is never reused, so a copy of an installation shows as one count advancing
in two places.

What a report says of the agent's own build, privileges and configuration is a
claim and never an attestation, since a changed binary holding the key reports
whatever it chooses. `Agent.liveness` is what the platform observes instead: how
recently reports arrived, against the interval the newest one announced, and
whether that one said the agent was stopping. Silence is a fact about the
reports; it never disables or revokes an agent.

`update` says where the newest update the platform asked of the agent stands,
and its `failure` keeps an update that went wrong apart from a platform that
could not be reached, so a rollout can stop on the one without stopping on the
other. `compatibility` says what the agent speaks — the contracts release it was
built with, the protocol and the schema of every record it writes or reads — and
whether it takes updates, in which format, over which state, and the newest root
and catalog it verified, so a platform knows which agents a release or a change
of its own can reach before it asks anything of them. Like `build`, it is a
claim.

## The agent policy

A `Policy` changes how agents run without anybody visiting them, and it is
signed where it is written rather than where it is stored. The key that signs it
belongs to whoever administers the estate and is held off the platform: the
platform checks a policy against the public keys it was given, records it and
hands it to the agents it names, and it cannot write one. An agent accepts a
policy only under a public key it was provisioned with out of band, the way it
was given its trust in the platform. A control plane somebody took can withhold
what was signed and cannot sign anything else.

`SignedPolicy` is a DSSE envelope with DSSE's own field names and numbers. The
signature covers the payload type and the payload bytes exactly as they travel,
so a verifier checks it before it decodes anything and nothing is re-encoded to
be checked, and the platform serves the payload byte for byte as it was
signed.

A policy names the agents it is for by the identifier each was issued, and an
agent applies only one that names it. Its `revision` increases across every
policy published into a tenant, whichever `policy_id` it carries: an agent is
handed the highest revision that names it and refuses any lower than the one it
holds, so moving an agent between policies cannot be replayed backwards, and
going back to earlier settings is signing them again under a newer revision.
Publishing is activating, because the signature is the authorisation; there is
no pointer to move.

`expires_at` is required and at most a year after `issued_at`. A policy already
expired is refused; one that expires while in force stays in force, because an
agent cannot do better than the last policy it verified, and the agent reports
that it is running on an expired one — which is how a platform that stopped
handing out newer policies is noticed.

What a policy sets is a bounded subset of an agent's own configuration: the log
level, which modules collect and how often, what the files module watches, and
budgets. A budget lowers the ceiling an agent's configuration sets and never
raises it, and nothing in a policy names the platform, what the agent trusts,
its identity or its timeouts, so no policy can turn a verification off or take a
ceiling away. An agent refuses a policy whole, keeping the one it holds, when
the configuration it would make is one it does not run on. A policy also
carries the checks the assessment module runs, which no agent's own
configuration names.

## The agent update

An update is authorized off the platform, the way a policy is, and by the roles
of The Update Framework rather than by a single key. A `Root` names the keys of
two roles and how many of each must sign: the root role signs the next root and
the catalog role signs a `Catalog`, the list of every release agents may
install. Nobody holds any of those keys on the platform: it verifies what it is
given exactly as an agent does, keeps it and hands it on, so a control plane
somebody took can withhold an update and cannot authorize one. Both travel as
DSSE envelopes, checked before they are decoded and served byte for byte as they
were signed.

An agent is provisioned with a root out of band, beside its trust in the
platform, and moves to a newer one only through the chain: each version is
trusted when a threshold of the previous root's root keys and a threshold of its
own signed it. Rotating or revoking a key is publishing the next root without
it. No role is online, so there is no timestamp role, and expiry is the
freshness an agent relies on: an agent installs nothing under a root or a
catalog that ran out, and an operator signs a new catalog before the one in
force does.

A catalog's `version` only increases, and an agent refuses one lower than the
highest it verified, so a catalog that withdrew a release cannot be swapped for
an older one that still named it. Each `Release` is one package for one
platform: its version, the digest and size of the package, the revision it was
built from, the oldest version it may be installed over and the generation of
the local state it keeps. An agent never installs an older release than the one
it runs, unless that release names the one it runs in `replaces`, which is how
an operator takes agents back from a release that went wrong, and never one
that cannot read the state it keeps.

The catalog says what may be installed; which agent runs which release, and
when, is the platform's to decide and is never signed. An `Assignment` points
agents at a version the newest catalog names, and an `Offer` is what an agent is
handed when it asks: the roots, the newest catalog and the version the platform
wants it to run. The platform keeps a package by its digest and hands it only to
an agent it wants to run that release, and the agent checks every byte against
the catalog before anything installs it. Whatever the platform decides, it can
move an agent only between releases an operator authorized.

A `Rollout` moves the agents of a tenant to a release a wave at a time, and is
the platform's decision too, never signed. A `Wave` names agents one by one, as a
canary, or opens a share of the rollout, and an agent's place in it is drawn from
the rollout and the agent alone, so reconnecting, renewing a certificate or
rotating a key never moves an agent from one wave to another. The platform opens
the next wave once the open one ran for its soak and enough agents run the
release, and pauses the rollout once as many agents failed it as the rollout
allows, by what their status says: an agent that could not reach the platform,
or refused the release, has not failed it. A paused rollout asks nothing of any
agent, so the agents that had not moved keep the release they run, and a
`RolloutChange` pauses, resumes, advances or aborts one. A release assigned to an
agent one by one outweighs its tenant's rollout.

## The assessment

A `Checklist` is what an operator expects of the hosts a policy names, and it
travels inside the signed policy and nowhere else: an agent's own configuration
names no checks, so what an agent assesses is always what an operator signed,
and every result names the policy revision that asked for it. A `Check` is one
typed test with bounded parameters — a path's metadata, the host's account
files, a kernel parameter or module, a package, a service unit, a directive of
sshd or login.defs — read from what a host keeps and never by running a command.
No test reads more of a file than the directive it names.

An `Outcome` is closed, and only `PASS` says the host is as the check expects.
`ERROR` says the agent could not read what the check is about, `UNSUPPORTED`
that it does not run such a check, and `NOT_APPLICABLE` that what the check is
about is not on the host and the check says that leaves nothing to judge; none
of them reads as a pass. A check an agent cannot read whole, because a test or a
value in it is newer than its build, is answered `UNSUPPORTED` rather than
refused, so a policy can carry checks some of the agents it names do not run.

An `Assessment` answers every check of the revision it names, once each, so the
newest assessment of an agent is its posture, and one that answers nothing says
its policy asks for none. Assessments travel on a stream of their own, are
answered and refused with the same `BatchAck` and `Rejection` as every other
batch, and are stamped with the identity and reception the platform writes, as
an event is. An agent keeps each assessment that changed something until the
platform holds it, so what a posture was over time can be read back, and the
newest one is carried when one agent is read.

## The vulnerability advisory

An `Advisory` is what a source says about one vulnerability, as the platform
translated it: which versions of which packages are affected, the other ids the
vulnerability has, and how severe its authors say it is. It is intelligence and
not a finding — it says nothing about any asset — and it is named by the source
and the id the source gave it, a version of it by the moment the source last
changed it.

An ecosystem is named with its release — `Debian:12`, `Ubuntu:22.04:LTS`,
`Alpine:v3.19` — because a package is compared against one release of its
distribution, and a package by the name that ecosystem's advisories use, which
for most distributions is the source package. A version is affected when it lies
in any of an entry's ranges or is listed in its versions; a list that only
expands a range is kept whole all the same, because telling the two apart needs
the ecosystem's ordering of versions. Severities are the vectors or ratings their
authors wrote, never a score computed from them.

`Provenance` is the platform's to write and never the feed's: the feed and the
version of its index the advisory was read from, the location, when, the digest
of the bytes as fetched, the format they were in and the rules they were
translated with. `aliases` name the same vulnerability; `upstream` names what a
distribution's advisory derives from, which is not the same vulnerability;
`related` names the rest.

A `FeedSync` is what one attempt to follow a feed found. `synced_at` is when the
platform last held everything the feed listed and is carried forward by an
attempt that did not complete, so the freshness of intelligence never looks
better than it is; `newest_listed` is how current the feed itself is. `Record`
carries either, so the log both travel on has one decode path.

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
