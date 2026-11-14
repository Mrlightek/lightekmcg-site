# Quran, hadith and Islamic learning

Open **Digital Factory → Quran & Hadith**. This workspace extends the existing native model and training pipeline. It does not use an external language-model provider.

## Import and inspect the Quran

Choose **Download Quran from Tanzil** to import the official Arabic Uthmani text. The downloader accepts only the fixed Tanzil HTTPS endpoint, with time and size limits. It checks all 114 surahs and 6,236 ordered verse references. This is a structural check, not a claim of independent scholarly authentication. The original passage wording and downloaded copyright notice are retained.

Alternatively upload the complete Tanzil text in `surah|ayah|text` format. Inspect the edition, attribution, text and license (use the passage preview and complete source download), then mark the source reviewed. Search by reference such as `2:256` or by literal words. All matching reviewed editions are available; an exact reference search does not silently choose a translation or tradition. Searches return at most 30 results; choose a specific edition to narrow them. Text search uses literal substrings, not semantic or Arabic morphological matching.

Training permission is recorded separately from reference use. Record the applicable permission or license basis when enabling training. Translations and modern editions may have different terms from the underlying Arabic works. Imports without training permission remain searchable after review. To add permission or correct content, import a new immutable source edition.

## Add hadith, translations and commentary

Upload an authorized JSON export. Each source has one kind, language and edition. Import translations and commentary separately from the Quran or hadith they discuss. Translation sources must name their translator. Optional tradition attribution describes the source; it is not a system-wide sect selection.

This is a **format example containing placeholders**, not a hadith:

```json
{
  "source": {
    "name": "Collection name",
    "kind": "hadith",
    "language": "en",
    "edition": "Publisher and edition",
    "tradition": "Source tradition, if applicable",
    "source_url": "https://example.org/authorized-edition",
    "attribution": "Publisher, translator and required credits",
    "license": "Applicable license text",
    "training_permitted": false
  },
  "records": [
    {
      "reference": "Collection-specific stable reference",
      "text": "Insert exact text from an authorized source here.",
      "narrator": "Narrator as recorded by the source",
      "assessments": [
        {
          "scholar": "Scholar responsible for this assessment",
          "grade": "The source's exact grade",
          "reference": "Where this assessment was published"
        }
      ]
    }
  ]
}
```

Kinds: `quran`, `translation`, `hadith`, `commentary`, `ethics`. Add `translator` for translations. Add `permission_evidence` when `training_permitted` is true. Omit `assessments` or use an empty array when no grading is supplied. Multiple assessments remain separate; the importer never invents a grade or resolves a disagreement by majority vote.

Each upload is limited to 16 MB and 50,000 passages. Split larger editions into named volumes. Duplicate reference keys within an edition are rejected. Identical imports return the existing source. Source text and permission metadata are immutable through the application; corrections produce a new fingerprint and edition record.

Sunnah.com provides an API requiring an access key and access to only part of its data. Its website prohibits scraping. This release accepts authorized exports; it does not scrape Sunnah.com, bundle its collections, or claim to contain all hadith. Sources: <https://sunnah.com/developers>, <https://sunnah.com/about>, <https://tanzil.net/docs/Text_License>.

## Train on the source material

1. Review a source edition with recorded training permission.
2. Choose **Create draft training batches**. Passages are split into lossless parts within the native model's response budget. Each example retains its source, reference, part number, assessments and checksums in dataset provenance.
3. Review each draft batch in Neural training. Source-derived examples must match their saved provenance. For corrections, import a corrected edition or make a separate manual teaching dataset with honest attribution.
4. Approve a batch and select a model. The model now supports up to 64 hidden units and a vocabulary limit of 2,048. These are bounded extensions of the native small model, not a large general-purpose model.
5. Train the batch. Inspect training loss, held-out loss, unknown response tokens, parent checkpoint and retention loss.
6. Activate a passing checkpoint **before requesting the next batch**. Each request captures the active parent. Requesting every batch at once would train siblings from the same parent, not a cumulative sequence.

Continuation copies existing weights and vocabulary, extends dimensions when configured, and retains bounded rehearsal/evaluation examples. Old checkpoints remain immutable. Activation rejects a stale branch when another checkpoint has become active since its request. Activation also requires at least 95% training-response token coverage, so learning to predict unknown tokens cannot masquerade as learning the source text. The explicit **Restore this checkpoint** control can restore another passing checkpoint when a deliberate rollback is needed; ordinary activation still rejects a stale training branch. Loss acceptance includes a regression check on retained examples when available. This small sample cannot prove that every earlier lesson was retained.

Model growth cannot shrink an existing vocabulary or hidden layer. The training time budget remains 90 seconds plus evaluation. A full Quran or hadith corpus is much larger than one batch; importing it does not mean it has already been trained. The tokenizer keeps Arabic combining marks with their words. Vocabulary limits and context length still constrain what this model can learn; the unknown-token metric helps identify coverage gaps.

## Teach conduct and evaluate it

For a reviewed Quran source with training permission, choose **Create ethical conduct lessons**. This creates twelve draft application examples covering uncertainty, trust, fairness, privacy, verifying reports, commitments, respectful treatment and attributed differences. They include Quran references for review. They are human-authored application policies, not quotations, translations, hadith, religious rulings or claims of scholarly consensus.

Review the interpretations and examples before approving them. Training loss measures prediction, not ethical reliability. Test real scenarios before relying on the model's behavior. Existing application permissions and Gatekeeper remain the enforcement boundary for actions.

## Exact source access from Ruby

```ruby
NevaehIntelligences::Islamic::Library.lookup(source_id: source.id, reference: "2:256")
```

The result includes exact text, edition, translator, tradition, assessments and fingerprints, with `generated: false`. Generated neural replies remain drafts. This release exposes source lookup in the factory; it does not automatically ground every conversation reply in retrieved passages or certify generated religious advice.
