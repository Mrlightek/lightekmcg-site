# Nevaeh Digital Factory

Open **Dashboard → Digital Factory**. **Software Library** collects installed repository documentation. The small **i** buttons open a tutorial drawer without leaving your work.

This iteration connects construction, capability registration, ticketed execution, editorial direction, neural training, conversation and internal documentation. All execution remains in the existing Nevaeh/KB/Gatekeeper architecture.

## Build your first implemented capability

1. Open **Construction factory → New construction**.
2. Name it **Welcome message**, with key suffix `welcome_message`.
3. Keep the example definition: accept a `name`, trim it, compose a greeting and require the output.
4. Keep or edit the independent sample tests. The example expects `Welcome, Marlon.` when the input name contains surrounding spaces.
5. **Save construction**, then **Build Ruby implementation & verify**.
6. Open the generated Ruby and test evidence. A passing release has service, worker, verifier and sample-test source, plus source hashes.
7. **Activate capability connection**. This registers `factory.construct.welcome_message`, binds its worker and records its verified procedure in the KB.
8. Fill **Create this service's worker** with run inputs. Choose manual operation or an interval. Optionally run once after saving.
9. Follow the resulting worker into **Execution history → ticket**. Verified step output is the acceptance evidence.

The generated service is executable Ruby and uses the factory runtime. The initial primitive pack supports selection, renaming, text normalization, defaults, text composition and required-field assertions. Names are labels; implementations come from the saved construction operations. New operation families can be added to `Factory::Contract`, `Factory::Runtime` and the editor, with regression tests. The factory does not invent arbitrary Ruby from a service name.

## Construction contract

A definition has typed `input_schema` fields and ordered `steps`. Supported input types are string, number, boolean, object and array.

```json
{
  "input_schema": {"name": "string"},
  "steps": [
    {"op": "normalize", "field": "name", "mode": "strip"},
    {"op": "template", "field": "greeting", "text": "Welcome, {name}."},
    {"op": "require", "fields": ["greeting"]}
  ]
}
```

Sample acceptance tests are exact input/output pairs:

```json
[
  {
    "inputs": {"name": "  Marlon  "},
    "expected": {"name": "Marlon", "greeting": "Welcome, Marlon."}
  }
]
```

Construction primitives:

| Operation | Parameters | Behavior |
|---|---|---|
| `select` | `fields` | Keep the selected fields. |
| `rename` | `mapping` | Rename fields, rejecting collisions. |
| `normalize` | `field`, `mode` | Strip, lowercase, uppercase or make a slug. |
| `defaults` | `values` | Supply values only when a key is absent. |
| `template` | `field`, `text` | Compose a scalar output from `{field}` placeholders. |
| `require` | `fields` | Assert that required outputs exist and are nonempty. |

The compiler emits service, worker, verifier and test artifacts from constrained templates. User strings are serialized data, never interpolated Ruby source. During execution the compiler reconstructs and checks the expected source before loading it. Release definitions, sample tests and artifacts are immutable after construction. Downloads are JSON source packages intended for the installed Rails framework, not independently provisioned applications.

A run pins its release and inputs in a structured ticket. Both the outer ticket policy and the concrete construction capability pass Gatekeeper authorization. The worker checks the current operator, reservation, saved revision and inputs. The generated verifier recomputes the deterministic result; independent sample expectations are checked before activation. Pausing the construction blocks future execution. Older active releases can remain pinned by existing workers after a newer release is activated.

## Editorial notes now affect generation

Writing services support executable editorial directives. Enter one per line:

```text
Tone: warm
Max words: 80
Opening: Welcome to {topic}
Closing: {call_to_action}
```

Tone options are warm, formal, direct and enthusiastic. The parser can expand approved context placeholders in opening and closing text and enforce a word limit. It applies after rules, symbolic inference or neural generation. The writing playground and Studio preview display applied and unsupported notes. Existing unsupported prose remains visible in the report; it is not silently treated as a successful instruction. Extend `EditorialDirection` to add more structured directives.

## Create a conversation corpus

1. Open **Neural training → Generate a dataset**.
2. Choose a scenario topic and example count, or select a Software Library document with at least five explanatory sections.
3. Review the resulting prompt/response JSON and provenance.
4. Edit and save the text as needed, then **Approve dataset for training**.

Faker supplies fictional names; explicit dialogue structures supply coherent requests and responses. The generated dataset records that its material is synthetic. Documentation imports record the source path and content hash. Saving changes resets approval. Unreviewed or subsequently changed datasets cannot be consumed by a queued training request.

A dataset contains 5–512 pairs, up to 256 KB. Each prompt and response has a maximum of 2000 characters. At least five distinct prompts are required for a held-out split. Training uses at most 64 response tokens per example and rejects corpora over 12,000 training response tokens. Larger corpora can be split into reviewed datasets as the runtime grows.

## Train actual neural weights

1. Create a **Language model**, starting with 16 hidden units and a 256-token vocabulary limit.
2. Keep availability **Internal administrators** when training on proprietary documentation. **Available to Studio users** makes a model usable through enabled neural writing profiles, so select a corpus intended for that audience.
3. Select an approved dataset, choose epochs and **Queue neural training**.
4. Refresh to inspect completed epochs, loss history, training loss, held-out loss and optimizer steps.
5. A passing checkpoint offers **Activate these weights**. Activation is explicit.

The native Ruby network is a small fixed-window neural language model: a prompt embedding summary, four position-specific context embeddings, tanh hidden units and a softmax next-token distribution. The training loop computes cross-entropy gradients and updates embedding weights, output weights and biases with SGD. It does not call an external AI API or run a separate inference server.

Checkpoints record immutable weights, dataset identity, metrics and canonical content hashes. A checkpoint qualifies when training loss decreases and held-out loss is finite and no more than 0.25 above its initial baseline. Prompts are grouped before the split so exact duplicate prompts cannot leak across training and evaluation. This loss check verifies a functioning training path; it does not establish general language quality, factual accuracy or broad reasoning ability.

The current implementation initializes a new model for each training run. To incorporate more material, prepare an approved combined corpus and retrain. It does not yet resume optimization from a previous checkpoint. Activate an earlier passing checkpoint to roll back generation behavior.

One trainer runs per application instance, enforced by a database constraint. The worker checks cancellation each epoch. The run budget is 90 seconds plus initialization/evaluation; actual epochs and budget truncation are recorded. A recurring sweep recovers queued runs and invalidates stale leases. Generated weights are stored in the application's database and are included in normal database backups. No model is trained during migration or application boot.

## Converse with your checkpoint

Open **Conversation**, choose a model with an active checkpoint and start a thread. Replies use the actual weights and the last three conversation turns. Turns save the prompt, response, checkpoint identity and token evidence. Repeated request keys do not duplicate turns, and conversations belong to the account that created them.

This is a small native model whose conversational quality depends on its corpus and capacity. Short outputs, repetition and errors can occur. Chat drafts do not execute capabilities or modify software. To act on a request, use a constructed worker and its explicit ticket workflow.

To use neural generation in Studio, create a writing service with **My neural language model**, select a trained model and enable it. Studio's Script workspace loads the service, generates a draft and shows editorial evidence. Internal models remain restricted to administrators; shared models are available to the intended Studio users. Save the workspace after applying a script.

## Software Library and contextual help

**Dashboard → Software Library** searches installed text documentation by title, path and body. Collection filters and a document reader keep it accessible without repository searching. The reader escapes HTML and ERB. It excludes hidden paths, symlinks, dependency trees, temporary data, storage, logs and test fixtures. Files over 512 KB are omitted from the reader.

Library and help endpoints require administrator access, send `private, no-store`, and are not added to the public PWA. Help buttons open an accessible dialog drawer. The framework automatically annotates labelled Dashboard controls; field-specific explanations cover the Nevaeh operations, and the library is the central reference. Other modules can add targeted content through `ContextualHelp::TOPICS` and the reusable `nevaeh_help_button` helper.

## Extension map

| Factory function | Code |
|---|---|
| Perception/context | `NevaehInference`, `WritingEngine`, neural tokenizer/context features |
| Knowledge access | `SoftwareLibrary`, existing KB/ticket resolution |
| Construction | `Factory::Contract`, `Factory::Compiler`, `Factory::Runtime` |
| Action connection | `FactoryWorker`, `Factory::Execution`, Gatekeeper, structured tickets |
| Acceptance | Generated verifier, independent sample tests, ticket evidence |
| Learned language | `NevaehNeuralLanguage`, `Neural::Network`, `Neural::Training` |
| Corpus production | `Neural::CorpusFactory`, reviewed datasets and provenance |
| Interface guidance | `ContextualHelp`, `NevaehHelpHelper`, shared help drawer |

These are concrete software responsibilities that can be extended independently. They are not a claim to reproduce biological brain function.

## Deployment and checks

Run `20261108140000_create_nevaeh_digital_factory` through the normal migration step and restart the existing Sidekiq service to load the training-recovery schedule. Training uses the existing default queue. No new inference service or external provider credential is required.

```sh
BUNDLE_GEMFILE=test/standalone/Gemfile bundle exec ruby test/standalone/nevaeh_digital_factory_test.rb
node --check public/lightek/nevaeh/factory.js
node --check public/lightek/nevaeh/help.js
```

The controlled suite runs the real migration, generated Ruby, sample acceptance, capability registration, ticket/Gatekeeper execution, canonical checkpoint hashing, native optimizer, training/evaluation, conversation privacy, document containment and escaped rendering. Installed-app HTTP tests cover the authenticated routes separately. These checks do not substitute for full acceptance in the installed PostgreSQL/Redis/private-engine environment.

Technical foundations: [neural language modelling](https://d2l.ai/chapter_recurrent-neural-networks/rnn.html) and the [Ruby Faker project](https://github.com/faker-ruby/faker). The implementation here is a native fixed-window model rather than the recurrent example in that reference.
