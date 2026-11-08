# Nevaeh Control Center

Open **Dashboard → Nevaeh Control Center** (`/employee/nevaeh/control-center`). Workers, abilities, execution history, writing services, inference models and personal navigation live in one dashboard. Existing configuration, code-generation and ticket consoles remain available.

## Native inference

`NevaehInferenceModel` is an ActiveRecord object including `NevaehInference`. It runs inside Rails, with no separate inference server, external AI account or model download. The concern provides these extension points:

- `normalize_inference_context`: validate a single context shared by the whole output.
- `extract_inference_terms`: tokenize topic words and normalize synonyms.
- `inference_candidates`: retrieve eligible rules and teaching examples for a format.
- `rank_inference_candidates`: rank matching plans by keyword coverage × configured weight. Equal scores sort by rule ID.
- `realize_inference_plan`: compose plain text from selected blocks and context.
- `validate_inference_definition!` and `inference_fingerprint`: validate and identify the saved model revision.

This implementation performs symbolic rule/example inference. It does not train neural weights or provide the general language understanding of an LLM. Each method can be extended in the existing Ruby model/concern architecture. Generated text never supplies an executable handler.

In **Inference models**, create a model and add rules through the editor. Save vocabulary such as `{"film":["movie","cinema"]}` and teaching examples such as:

```json
[{"format":"caption","topic":"film premiere","templates":["{topic}: {goal}.","{call_to_action}"]}]
```

Examples act as additional candidate plans. Required context fields must be explicitly supplied; generated defaults do not satisfy a requirement. A topic with no matching plan uses the built-in format. The test bench shows selected rule, score, matched terms, fallback status and model fingerprint. Scores measure matching, not statistical confidence. Save before testing.

Create a writing service with the **My inference model** engine and select the model. Rule-based writing services can instead supply their own text blocks. Editorial notes are documentation; they are not interpreted as executable instructions. Supported formats are scripts, captions, posts and descriptions. Explicit context preserves character names, setting, goals, obstacles and facts. Faker supplies fictional example names; it does not supply arbitrary prose or factual knowledge.

In **Studio → Script**, load saved writing services, generate a draft, review it and choose **Use as scene script** or copy the result. Save the workspace to retain the applied script. Publication continues through the existing publication workflow. The two legacy dialogue generators now use connected scene beats instead of unrelated Faker jargon.

## Workers and scheduling

Administrators create reusable structured workers, arrange steps, enter inputs and select manual operation or a repeat interval of 5 minutes or more. Draft, active, paused and archived lifecycle states are supported. Activation authorizes the saved procedure. Editing uses optimistic locking. Scheduled runs use the creator's current permissions; manual runs use the requesting operator's current permissions.

The builder currently composes the existing verified website-page, page-section, Studio-project and reviewed engineering actions, plus the new `content.generate` draft action. The runtime catalog displays all registered abilities, but catalog registration alone does not create a composition adapter or acceptance verifier. Additional implementations use the existing service generator/engineering workflow.

Every requested run saves a frozen section snapshot and creates one Marlon ticket. Execution uses the existing structured ticket → KB → Gatekeeper → DymondDispatch → acceptance → KB evidence path. The draft action stores generated text, context, model/profile fingerprints and a content checksum in the ticket's verified step output. Worker queue acceptance is not verification.

The Sidekiq cron sweep runs every minute. A database row lock and unique workflow/request key protect schedule slots and repeated submissions. A committed queued run is recoverable by later sweeps if Redis submission fails. Pausing cancels future schedule slots; already submitted runs continue. A revoked operator pauses the schedule or blocks a pending run. The `NEVAEH_BACKLOG_ENABLED` switch remains authoritative for execution.

Schedules use elapsed intervals from the sweep time, not wall-clock cron expressions; missed intervals coalesce into one run. History shows the most recent 50 runs and links to the authoritative ticket evidence. Worker and model lists are capped at 100; runtime abilities at 500.

## Personal sidebar

**My sidebar** supports drag/drop and keyboard-accessible move buttons, grouping, labels, hiding and local application shortcuts. Changes persist per account. System destinations keep their permission-filtered paths and icons. Shortcuts cannot grant access to a destination. Restore defaults and save to clear personal preferences. The customize link remains available even if all other entries are hidden.

## Rollout and validation

Run the two new migrations through the normal deployment migration step. They create dashboard state and register two Studio writing capabilities. Restart Sidekiq after deployment so its existing scheduler loads `nevaeh_workflow_sweep` from `config/schedule.yml`. No inference infrastructure is required.

Controlled local checks:

```sh
BUNDLE_GEMFILE=test/standalone/Gemfile bundle exec ruby test/standalone/nevaeh_control_center_render_test.rb
node --check public/lightek/nevaeh/control-center.js
node --check public/lightek/studio-app.js
```

The standalone harness runs real ActiveRecord models, the migration (SQLite JSON translation), tickets, worker scheduling, writing/inference and ActionView templates using controlled host adapters. It does not replace a PostgreSQL/Redis/private-engine acceptance run. Authenticated HTTP tests are in `test/controllers/employee/nevaeh_control_center_test.rb` for the installed application.
