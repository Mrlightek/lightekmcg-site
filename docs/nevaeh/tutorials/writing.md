# Writing services and inference models

Writing services are shared with Studio. They can use fixed templates, symbolic inference or an available native neural checkpoint.

## Generate a first draft

```text
/write caption {"topic":"Opening Night","audience":"our community","call_to_action":"Join us tonight."}
```

Read the returned draft and provider details. Generating a draft does not publish it.

## Configure a reusable writing service

Open Control Center → Writing lab, choose format and provider, add templates/examples and save. Supported template tokens include topic, audience, goal, obstacle, setting, protagonist, companion, call_to_action and facts.

Editorial instructions support Tone: warm/formal/direct/enthusiastic; Max words: 80; Opening: ...; Closing: ... . The preview reports applied and unsupported directives. Arbitrary prose instructions are not executable code.

## Extend symbolic inference

Open Inference models, add rules with keywords and templates, and test the model. Rule weight multiplies matching keyword coverage. Lexicon synonyms normalize topic terms. The selected rule and match evidence are visible in the result.

Rules and examples are symbolic configuration. They are distinct from the neural weights updated in the Training tutorial.

Use a structured content.generate worker to repeat a writing task; the Agents tutorial includes a complete caption-worker definition.
