# Documentation, KB and native neural training

Imported documentation, reviewed knowledge, training examples, trained weights and executable capabilities are separate artifacts.

## Learn from a documentation page

```text
/learn https://docs.blender.org/manual/en/latest/
/read sources SOURCE_ID
/review SOURCE_ID
```

Replace SOURCE_ID with the import receipt's ID. Inspect the extracted text and source checksum before reviewing. Review adds reference material to KB. Pages with at least five explanatory sections also produce a draft prompt/response dataset; short references enter KB without invented training pairs.

Search documents with `/search Blender` or Software Library. Imported web text does not authorize actions, activate adapters or change executable code.

## Train and activate a native model

1. Open Digital Factory → Training. Create or inspect the generated dataset.
2. Correct examples; inspect their provenance. Use real representative prompts and accurate responses.
3. Approve the dataset with `/approve DATASET_ID`.
4. Create/select a language model and request training.

```text
/train MODEL_ID {"dataset_id":123,"epochs":10}
/checkpoint CHECKPOINT_ID
/model MODEL_ID Help me plan a production
```

Replace each ID with the record returned by that stage. Inspect training and held-out loss before activation. A completed training job is not automatically an active checkpoint; only a passing checkpoint can be activated. Internal models are for administrators; shared models are available to the intended users.

The native model is small and its replies are drafts. Fluent text is not verified knowledge or an executable plan. Add representative examples and evaluate held-out behavior rather than assuming broad reasoning from a low training loss.
