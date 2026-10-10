# Lightek Media & Communications Group

> **An organization whose operational and creative state is versioned, queryable, explainable, projectable, and increasingly self-correcting.**

Lightek is an operating ecosystem, not a collection of disconnected applications. It is built around shared data, reusable capabilities, governed execution, durable knowledge, projection, and a system intelligence named **Nevaeh**.

**Nevaeh is Lightek's system intelligence. Creativity is one expression of it.**

The long-term objective is for Lightek to know what is happening, know why it happened, know what it knows, know what it does not know, project what could happen next, act through governed capabilities, observe the result, and improve future execution.

---

## System Thesis

Lightek treats the database as canonical operational truth.

```text
LIVE REALITY
    |
    v
DATABASE
    |
    +--> current state
    +--> events
    +--> work items
    +--> network state
    +--> capabilities
    +--> tickets
    +--> production state
    +--> relationships
    +--> financial state
    +--> audience state
    |
    v
NEVAEH
    |
    +--> Knowledge Base
    +--> policy / procedure
    +--> projection
    +--> planning
    |
    v
GATEKEEPER
    |
    v
DYMOND DISPATCH
    |
    v
EXECUTION
    |
    v
NEW DATABASE STATE
    |
    v
OBSERVE -> COMPARE -> LEARN -> REPEAT
```

The database tells Nevaeh **what is true now**.

The Knowledge Base tells Nevaeh **what Lightek has learned**.

Tickets represent **unknown, unresolved, or human-required conditions**.

Capabilities represent **what Nevaeh knows how to do**.

Gatekeeper represents **what Nevaeh is allowed to cause**.

DymondDispatch represents **what Nevaeh is doing**.

History and provenance explain **how Lightek became what it is**.

Projection represents **what could happen next**.

---

# Nevaeh

## What Nevaeh Is

Nevaeh is Lightek's universal orchestration and system-intelligence layer.

At the code level, `Nevaeh.handle(...)` is the front door into a pipeline that resolves an event into intent, resolves a registered capability, consults relevant knowledge, builds a plan, requests Gatekeeper authorization, and dispatches approved work.

```text
event
  -> intent
  -> capability
  -> knowledge
  -> plan
  -> Gatekeeper authorization
  -> DymondDispatch work item
  -> result
```

Nevaeh does not use one giant undifferentiated "memory" bucket. Lightek separates state by meaning.

| Concern | Canonical role |
| --- | --- |
| Database | Live operational reality |
| Dymond KB | Durable knowledge, procedures, references and troubleshooting |
| Marlon tickets | Unknowns, unresolved conditions, human escalation and validated resolution |
| Nevaeh capabilities | Skills Nevaeh knows how to perform |
| Gatekeeper | Authorization, policy and execution boundary |
| DymondDispatch | Asynchronous execution and work-item lifecycle |
| Development lineage | Where the system came from and how it changed |
| Correlation / causation | Why events belong together and what caused what |
| Projection | Candidate future states before reality changes |

---

## Nevaeh as Lightek's Git

A useful mental model is that Nevaeh is **Lightek's semantic Git**.

Not because Nevaeh stores source code, but because Lightek is designed as a continuously evolving, inspectable body of state.

| Git concept | Lightek / Nevaeh equivalent |
| --- | --- |
| Working tree | Live database state |
| Commit | Persisted meaningful change |
| History | Operational and development lineage |
| Diff | Before-state vs. after-state |
| Branch | Candidate future / projected outcome |
| Merge | Reconcile compatible outcomes |
| Conflict | Contradictory state, policy, intent or canon |
| Revert | Restore a validated known-good state |
| Tag | Validated milestone, release or canon checkpoint |
| Blame | Provenance: who or what caused a change |
| Hook | Event-driven capability |
| Repository | The Lightek ecosystem |
| Remote | External service, platform or partner |

Git can tell you what changed. Nevaeh is being designed to determine:

- Why did it change?
- What caused it?
- Which policy authorized it?
- Which procedure was followed?
- What else changed because of it?
- Was the downstream effect expected?
- Did the action succeed?
- Did the fix create another issue?
- What was learned?
- Should the procedure change?
- What future states are now possible?

---

## Nevaeh's Operating Foundation

Implemented foundations include:

- database-backed capability registration;
- event and intent resolution;
- capability resolution;
- Dymond KB lookup;
- plan construction;
- Gatekeeper authorization;
- DymondDispatch execution;
- correlation-aware work items;
- ticket-backed escalation paths;
- DB-backed runtime introspection;
- Nevaeh self-knowledge and development lineage;
- visible GitHub project synchronization progress;
- Studio capability orchestration;
- canonical project tracking projected to GitHub Project and Lightek tickets.

Nevaeh's self-model explicitly distinguishes **live DB truth** from **historical provenance**. History is not a competing source of current state.

---

## Nevaeh Learning Loop

```text
observe condition
    |
    v
consult DB + KB
    |
    v
known?
  /   \
yes   no
 |     |
 v     v
plan   trouble ticket
 |     |
 v     v
Gatekeeper    human resolves / validates
 |                     |
 v                     v
execute             KB / procedure
 |                     |
 v                     |
observe result <--------+
 |
 v
reuse improved behavior
```

The goal is not uncontrolled self-modification. It is **evidence-backed, governed improvement**.

New learned behavior should be observable, explainable, attributable, authorized, validated, recorded, and reusable.

---

# Lightek Operating Loop

Across domains, Nevaeh follows the same loop:

```text
OBSERVE
  -> UNDERSTAND
  -> CONSULT KNOWLEDGE
  -> PROJECT
  -> PLAN
  -> AUTHORIZE
  -> ACT
  -> OBSERVE CONSEQUENCES
  -> LEARN
```

The domain can change without changing the intelligence pattern.

The same loop can diagnose infrastructure, route work, operate financial workflows, manage production, reason about community effects, or create media.

---

# Gatekeeper

Gatekeeper is Lightek's capability and security boundary.

Nevaeh can determine what should happen, but execution is not automatically assumed to be allowed.

Gatekeeper validates registered and enabled capabilities, subject contracts, policy, and execution context.

> **Nevaeh reasons. Gatekeeper authorizes. DymondDispatch executes.**

Gatekeeper also acts as a client-facing server-driven contract for Lightek thin clients.

---

# DymondDispatch

DymondDispatch is the execution plane.

Work items can carry capability, handler, subject, arguments, queue, priority, correlation ID, lifecycle state, result, error, and dispositions.

Work is inspectable rather than magical.

---

# No Silent Transmission States

Lightek treats observability as a product requirement.

If Nevaeh can know that an operation is occurring, the user should be able to know its state too.

Long-running work should expose, when available:

```text
operation
stage
current
total
percent
elapsed
estimated_remaining
status
correlation_id
work_item_id
capability
handler
queue
started_at
finished_at
result_or_error
```

> **No silent transmission states.**

This applies to development tooling and production software.

---

# Causal Intelligence

Lightek is moving beyond state observation toward **causal observation**.

Important operations should increasingly preserve enough evidence to answer:

- What changed?
- What caused it?
- What else did it affect?
- Did the effect match the intent?
- Did the correction introduce another problem?
- What procedure should improve?

Useful causal fields include:

```text
correlation_id
causation_id
parent_event_id
actor
capability
policy
procedure
before_state
intended_effect
observed_effect
affected_entities
affected_services
started_at
finished_at
result
error
```

The same causal engine can serve infrastructure, business workflows, communities and narrative worlds.

---

# Projection: Branch the Future Before Committing Reality

Projection is the next step beyond causality.

```text
                  CURRENT STATE
                       |
          +------------+------------+
          |            |            |
       FUTURE A     FUTURE B     FUTURE C
          |            |            |
          +------------+------------+
                       |
                 evaluate impact
                       |
                 choose / reconcile
                       |
                       v
                   NEW STATE
```

For infrastructure:

- What happens if this service moves?
- What happens if this node disappears?
- What happens if this policy changes?

For business:

- What happens if pricing changes?
- What happens if usage grows sharply?

For Studio:

- What happens if a character reveals this now?
- What happens if the reveal is delayed?
- Which storyline creates the strongest future while preserving canon?

Projection turns the Git metaphor into a practical system design: **branch the future without committing it to reality**.

---

# Lightek Studio

Lightek Studio is not simply an application containing Nevaeh.

**Studio is one of Nevaeh's creative execution bodies.**

The Studio product law is:

> **What should Marlon have to do to create something? Minimize that work. Backend complexity belongs to Lightek.**

The Studio experience law is:

> **Intent first. UI/UX first. Templates compress complexity. The PWA is the approachable control surface. Nevaeh is the production intelligence. Gatekeeper is the capability and security boundary. Blender remains the authoritative production runtime.**

Studio foundations include:

- PWA-first production control;
- authenticated server-driven navigation;
- Studio bootstrap contracts;
- SceneObject lifecycle and mutation;
- browser-side Three.js interaction;
- local interactive transforms followed by canonical persistence;
- Rails fallback surfaces;
- Blender-backed preview/render proof;
- Studio blueprint compilation and generation;
- provenance-tracked generated artifacts;
- intent-first creation;
- reusable capability contracts.

Blender remains the high-fidelity authoritative runtime. The browser is an approachable control and projection surface, not a replacement for Blender.

---

# Creative Intelligence

Nevaeh's creative role follows the same state / knowledge / projection / execution model as the rest of Lightek.

The goal is not "ask an LLM to write a show."

The goal is a structured creative operating system:

```text
current canon
+
character / relationship state
+
causal story graph
+
audience state
+
category template
+
available assets
+
production constraints
+
learned creative knowledge
        |
        v
project possible futures
        |
        v
rank valid trajectories
        |
        v
story beats
        |
        v
script
        |
        v
asset requirements
        |
        v
fabrication
        |
        v
production
        |
        v
publish
        |
        v
observe audience response
        |
        v
learn
        |
        v
project again
```

---

## Narrative State Graph

A story world should be represented as structured state, not only screenplay text.

Possible graph concepts include characters, locations, communities, relationships, conflicts, goals, secrets, possessions, permissions, past events, unresolved setup, canon facts, causal edges, emotional state, and production assets.

That allows Nevaeh to reason over the story instead of merely generating prose.

---

## Narrative Comprehension Engine

Important story facts can carry relationships such as:

```text
introduced_in
explained_in
reinforced_in
contradicted_by
caused_by
causes
known_by_character
known_by_audience
suspected_by_audience
hidden_from_character
hidden_from_audience
required_for
paid_off_by
```

This enables a critical question:

> **Does the audience possess everything required for this event to make sense?**

That supports plot-hole detection, missing-cause detection, setup/payoff tracking, exposition requirements, timeline clarity, continuity checking and comprehension-risk projection.

---

## Audience State

The creative system can model two parallel transitions:

```text
STORY STATE BEFORE
        |
      SCENE
        |
STORY STATE AFTER
```

and:

```text
AUDIENCE STATE BEFORE
what viewers know
what viewers believe
what viewers suspect
what viewers remember
what viewers feel
what viewers misunderstand
        |
      SCENE
        |
AUDIENCE STATE AFTER
```

Audience response becomes evidence for future creative decisions.

The system can compare expected audience state to observed response and learn which techniques create which comprehension and emotional outcomes.

---

## Audience State Reconciliation

Different audience interpretations do not necessarily require contradictory canon.

A future episode can be projected to satisfy several audience states at once:

```text
group A wants an answer
group B formed a compatible theory
group C misunderstood chronology
        |
        v
one canon-compatible future episode
        |
        +--> answers A
        +--> rewards the valid part of B
        +--> clarifies C
```

The goal is to reconcile useful audience evidence with story causality and creative intent.

---

## Creative Steering Timeline

Audience influence is **opt-in and changeable over time**.

A production can choose different steering policies by series, season, arc, episode or event.

| Mode | Behavior |
| --- | --- |
| Director Locked | Observe audience response but do not alter creative direction from it |
| Advisory | Surface theories, confusion and opportunities; require approval |
| Audience Responsive | Adapt future writing while preserving canon and production rules |
| Audience Driven | Audience-state objectives can directly influence projected story futures |

A show can deliberately change modes during its run.

This makes emotional design temporal:

```text
establish trust
  -> destabilize
  -> wild audience-responsive run
  -> let consequences land
  -> repair confusion
  -> pay emotional debt
  -> resolution
```

Negative emotion is not automatically failure. Anger, grief, dread, betrayal, frustration or confusion can be intentional dramatic states when the active policy says they are.

---

## Emotional Debt

Stories can intentionally accumulate unresolved audience emotion:

```text
trust debt       high
grief            high
frustration      high
mystery          very high
hope             low
```

Future episodes can then pay those debts through consequence, explanation, accountability, reconciliation and earned payoff.

That creates an intentional emotional rollercoaster instead of blindly chasing sentiment.

---

# Creative DNA Decomposition

Nevaeh should be able to study existing works as references without merely copying them.

```text
reference work
   |
   v
creative DNA decomposition
   |
   +--> genre grammar
   +--> episode structure
   +--> character functions
   +--> relationship topology
   +--> conflict patterns
   +--> escalation pattern
   +--> setup/payoff cadence
   +--> camera grammar
   +--> lighting grammar
   +--> edit rhythm
   +--> music usage
   +--> audience strategy
   +--> season architecture
   +--> production model
   |
   v
abstract creative template
   |
   v
new characters
new world
new canon
new conflict
new causal graph
new dialogue
new visual identity
new story
```

For third-party works, the system should learn high-level creative mechanics and nonliteral structural principles, not reproduce protected characters, dialogue, lore or distinctive expression.

Over time, Lightek's own production history becomes the more important corpus, allowing a genuine **Nevaeh directorial grammar** to emerge.

---

# Faker as a Creative Primitive

Faker is a content-generation primitive, not the creative intelligence.

Nevaeh wraps generated text in continuity, canon, causal constraints, character state, relationship state, scene purpose, audience-state targets, production requirements, and coherence checks.

```text
Nevaeh determines what must exist and what it must mean
        |
        v
Faker generates candidate text / data primitives
        |
        v
Nevaeh reconciles against continuity and intent
        |
        v
accepted / revised / rejected
```

---

# Asset Projection and Fabrication

Creative projection can drive asset creation.

Instead of asking only "generate a chair," Nevaeh can ask:

> **Based on what this production is becoming, what assets must exist?**

A projected scene can produce requirements for character variants, wardrobe, environments, props, vehicles, architecture, cameras, lighting, materials, FX, audio, graphics, animation and geometry systems.

Studio can resolve:

```text
required asset
   |
   +--> exists -> reuse
   |
   +--> compatible asset -> adapt
   |
   +--> missing -> fabricate
```

This is the basis for a prediction-assisted asset generator.

---

# Production Templates as Grammars

A template is more than saved settings.

A mature production template can encode the grammar of a class of content:

```text
Single-Camera Drama
|
+-- narrative grammar
+-- writing grammar
+-- cinematography grammar
+-- lighting grammar
+-- asset grammar
+-- performance grammar
+-- editorial grammar
+-- audio grammar
+-- delivery grammar
```

Templates compress complexity into user intent.

---

# Content Lifecycle

The long-term Nevaeh-driven content loop is:

```text
IDEATE
  -> PROJECT
  -> WRITE
  -> FABRICATE
  -> PRODUCE
  -> PUBLISH
  -> OBSERVE
  -> LEARN
  -> PROJECT AGAIN
```

The goal is for Nevaeh to increasingly operate Lightek's content pipeline while Marlon can experience Lightek as an audience member.

---

# Measurement and Audience Data

Lightek viewing and content metadata should have canonical internal representations first.

External measurement partners should be adapters over Lightek's own data model.

```text
Lightek viewing events
        |
        v
canonical audience state
        |
        v
aggregation / privacy / deduplication
        |
        v
MeasurementPublication
        |
        +--> measurement partners
        +--> metadata partners
        +--> advertisers / agencies
        +--> internal analytics
        +--> future destinations
```

The exact external payload should remain schema-driven and partner-specific.

Lightek remains the source of truth for its own viewing, content, schedule and production metadata.

---

# Digital Twins

The same causal and projection architecture used for infrastructure can drive digital-twin story worlds.

```text
person performs action
        |
        v
relationship changes
        |
        v
business changes
        |
        v
community conditions change
        |
        v
future storyline conditions change
```

A system action can be modeled the same way:

```text
routing change
        |
        v
latency changes
        |
        v
queue changes
        |
        v
customer experience changes
```

Same causal engine. Different domain semantics.

---

# Lightek Ecosystem

Nevaeh sits above product boundaries. The surrounding systems are execution, knowledge, distribution and experience surfaces through which Lightek operates.

## Core

### Lightek Kernel
Core platform infrastructure and shared ecosystem behavior.

### Marlon
Shared operational primitives including tickets, project tracking and generated-artifact provenance.

### Lightek UI
Reusable UI components and interface conventions.

### DymondDispatch
Execution and work-item lifecycle.

### Gatekeeper
Capability authorization, infrastructure control and client contract boundary.

### Dymond KB
Durable knowledge, procedures, troubleshooting and references.

## Business and Operations

### Dymond Bank
Billing, invoices, subscriptions, money movement and financial workflows.

### Dymond Compute
Compute and infrastructure capabilities.

### Dymond Catalog
Catalog and reusable product/content records.

### Dymond Booking
Booking workflows.

### Dymond Dash
Human operations and administrative control plane.

### Dymond Site
CMS/site shell and presentation infrastructure.

## Media and Creation

### Dymond Studio / Lightek Studio
Creative production, scene state, assets, templates, Blender orchestration, rendering, fabrication and future autonomous content production.

### Octavia
Server-driven Lightek television / FAST client and distribution surface.

### Lightek Social
Social, community, messaging, posts, clips and media-first audience/community surfaces.

### Lightek Network
Broader Lightek media/network distribution layer.

---

# Thin Clients and Server-Driven Experiences

Lightek increasingly favors thin clients that receive configuration, content, layouts, capability information and experience contracts from the server.

The server owns canonical behavior. Clients render and interact with that behavior.

This supports TV clients, the PWA, future mobile clients, server-driven UI, centralized policy and shared capabilities across form factors.

The UI should never become the canonical owner of business logic.

---

# Product Laws

## 1. Intent First
The user expresses what they want to accomplish. Lightek determines how.

## 2. Minimize the User's Work
> **What should Marlon have to do to create something?**

Minimize that work. Backend complexity belongs to Lightek.

## 3. Database as Live Operational Truth
Nevaeh should query persisted reality rather than invent current state.

## 4. Unknowns Become Knowledge

```text
unknown
  -> ticket
  -> human resolution / validation
  -> KB / procedure
  -> future automated handling
```

## 5. No Silent Transmission States
Long-running operations should expose meaningful progress and failure state.

## 6. Govern Execution
Nevaeh reasons. Gatekeeper authorizes. DymondDispatch executes.

## 7. Capability Over UI
Represent what Lightek can do independently from how any one UI exposes it.

## 8. Templates Compress Complexity
A solved production or workflow should become reusable rather than reconstructed manually.

## 9. Capability Parity, Not Pixel Parity
Different interfaces can look different while sharing the same underlying domain behavior.

## 10. Learn From Evidence
System improvement should be attributable to observed outcomes, validated resolutions and durable knowledge.

---

# Terminology

## Capability
A registered, addressable skill Nevaeh knows how to perform.

## Intent
The resolved meaning of an incoming request or event.

## Plan
The executable description Nevaeh builds from intent, capability, context and knowledge.

## Gatekeeper Decision
The authorization result governing whether a capability may execute.

## Work Item
A DymondDispatch execution record representing queued, running, completed or failed work.

## Correlation ID
Identifier tying related operations together across Nevaeh, Gatekeeper, dispatch, services and results.

## Causation ID
Identifier representing which prior event or action directly caused another event.

## Knowledge Article
Durable guide, reference or troubleshooting knowledge available to Nevaeh.

## Trouble Ticket
A persisted unresolved condition requiring investigation, human action or validation.

## Runtime State
Current DB-backed operational state available to Nevaeh.

## Development Lineage
Versioned provenance explaining how Lightek and Nevaeh evolved.

## Semantic Diff
Meaningful comparison of before-state and after-state rather than only raw record changes.

## Projection
A candidate future state modeled before reality changes.

## Creative Steering Policy
Rules determining how much audience response may influence future creative direction.

## Narrative State
Canonical facts describing the current story world.

## Audience State
What the audience is expected or observed to know, believe, suspect, remember, feel or misunderstand.

## Emotional Debt
Intentionally unresolved audience emotion that later story events are expected to pay off.

## Production Grammar
Reusable creative and technical rules describing how a category of content is constructed.

## Creative DNA
Abstract, nonliteral structural properties extracted from a reference work or successful Lightek production.

---

# Technology

The current host application includes:

- Ruby 3.3.6;
- Rails 8.0.x;
- PostgreSQL;
- Redis;
- Sidekiq and Sidekiq Cron;
- Turbo;
- Stimulus;
- Importmap;
- Action Cable;
- S3-compatible object storage;
- MinIO in the Docker stack;
- Puma;
- Docker Compose;
- Traefik;
- Rails 8 native authentication;
- Dymond / Lightek ecosystem gems;
- Faker as a generative primitive;
- Blender through the Studio domain.

PostgreSQL is intentionally central because Lightek relies on structured relational state and JSONB-backed ecosystem data.

---

# Repository Structure

Important areas include:

```text
app/
  models/
    nevaeh.rb
    nevaeh_capability.rb
    network_event.rb
    network_port.rb

  services/
    nevaeh_orchestration/
    gatekeeper/

config/
  project_tracking/
    lightek_studio.json

  nevaeh/
    self_model.json
    development_history.json

db/
  seeds/
    nevaeh_self_knowledge.rb

docs/
  nevaeh/
    development_history.md

script/
  sync_studio_project_to_github.py
  sync_studio_project_to_tickets.rb
  sync_nevaeh_development_history.rb

public/
  lightek/
    index.html
    bootstrap-adapter.js
    studio-viewport.js
    sw.js
```

The repository continues to evolve. The canonical project-tracking manifest should be consulted for active Studio work.

---

# Local Development

## Requirements

At minimum:

- Ruby matching `.ruby-version`;
- PostgreSQL;
- Redis;
- Bundler;
- private-repository access for Lightek / Dymond gems.

For the containerized stack, Docker is also required.

## Database

Typical environment variables include:

```text
DB_HOST
POSTGRES_USER
POSTGRES_PASSWORD
POSTGRES_DB
```

## Redis

```text
REDIS_URL
```

## Object Storage

Typical MinIO variables include:

```text
MINIO_ENDPOINT
MINIO_ROOT_USER
MINIO_ROOT_PASSWORD
MINIO_BUCKETS
```

## Start the Docker Stack

```bash
docker compose up --build
```

The stack includes PostgreSQL, Redis, MinIO, Rails web, Sidekiq and Traefik.

## Prepare the Database

```bash
bin/rails db:prepare
```

## Run Tests

```bash
bin/rails test
```

## Verify Zeitwerk

```bash
bin/rails zeitwerk:check
```

---

# Project Tracking

Lightek Studio uses a canonical manifest:

```text
config/project_tracking/lightek_studio.json
```

That manifest projects into GitHub Project tracking and Lightek `Marlon::Ticket` records.

Useful scripts include:

```text
script/studio_project_status.sh
script/sync_studio_project_to_github.py
script/sync_studio_project_to_tickets.rb
```

The manifest is the canonical roadmap source, not the GitHub issue body.

---

# Architecture Status Language

This README intentionally separates implemented foundations from target architecture.

| Label | Meaning |
| --- | --- |
| Implemented | Present and exercised in the repository |
| Foundation | Core contract exists but broader domain coverage is growing |
| Active roadmap | Explicitly planned in canonical project tracking |
| Target architecture | Designed direction that may not yet be implemented |
| Projection | Candidate behavior or future state, not current reality |

Do not describe roadmap concepts as production-complete simply because the architecture has been designed.

---

# Direction

Lightek is being built toward a system where:

```text
state is observable
change is attributable
knowledge is durable
unknowns are escalated
execution is governed
progress is visible
history is explainable
future states are projectable
creative work is structured
audience response is learnable
assets are reusable
production is increasingly automated
```

Nevaeh is the intelligence connecting those pieces.

She is not merely inside Lightek Studio.

She is not merely an assistant.

She is the system intelligence through which Lightek observes, reasons, creates, governs, acts, learns and evolves.

> **Lightek is the ecosystem.**
> **Nevaeh is the intelligence.**
> **Gatekeeper is the boundary.**
> **DymondDispatch is the execution plane.**
> **The database is live reality.**
> **The Knowledge Base is learned truth.**
> **Studio is creation made executable.**
