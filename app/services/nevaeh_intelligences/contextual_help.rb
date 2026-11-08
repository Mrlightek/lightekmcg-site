# frozen_string_literal: true
module NevaehIntelligences
  module ContextualHelp
    TOPICS = {
      'workers' => ['Workers & schedules', 'A worker is a reusable procedure. Add ordered steps, fill their inputs, save as Active and choose Run worker. A run creates a ticket; use its acceptance evidence to confirm completion. Repeat intervals are elapsed minutes. Pausing stops future runs, not work already submitted.', 'docs/nevaeh/control_center.md'],
      'models' => ['Inference models', 'Add topic rules, vocabulary and examples, then save. The test bench shows the matching rule and score. A writing service makes this model available to Studio. Rules are symbolic; the separate Neural training workspace updates actual neural weights.', 'docs/nevaeh/digital_factory.md'],
      'writing' => ['Writing services', 'Choose a format and engine. Rule blocks specify output directly. Native inference chooses contextual blocks. Editorial notes now accept supported directives for tone, length, opening and closing; the preview shows which directives took effect. Save before testing.', 'docs/nevaeh/digital_factory.md'],
      'editorial' => ['Editorial direction', 'Supported notes include Tone: warm, formal, direct or enthusiastic; Max words: 80; Opening: Welcome to {topic}; Closing: {call_to_action}. These directives affect the draft. Unsupported notes are reported and kept for future extensions. They do not execute Ruby.', 'docs/nevaeh/digital_factory.md'],
      'factory' => ['Capability construction', 'Define input fields, transformation steps and expected sample outputs. Build generates real Ruby service, worker, verifier and test artifacts. Verification runs the samples against the compiled service. Activation registers a concrete capability. Runs enter the existing ticket/Gatekeeper pipeline.', 'docs/nevaeh/digital_factory.md'],
      'training' => ['Native neural training', 'Create or generate a dataset, review and approve it, select a model and queue training. The Ruby worker minimizes next-token cross-entropy and saves a checkpoint with training and held-out loss. Activate a passing checkpoint explicitly. Synthetic examples are fictional training material, not external factual knowledge.', 'docs/nevaeh/digital_factory.md'],
      'conversation' => ['Conversation', 'Choose a model with an active checkpoint. Each reply uses the checkpoint weights and recent conversation. Replies are drafts from a small native model. Chat does not execute actions, change permissions or publish content. Construction runs use separate explicit controls.', 'docs/nevaeh/digital_factory.md'],
      'library' => ['Software Library', 'Search the installed repository documentation by title, path or body. The library stays tied to the installed software version. Internal documentation requires administrator access and is not included in the public PWA.', 'docs/nevaeh/digital_factory.md'],
      'navigation' => ['Your sidebar', 'Move entries with the arrow buttons or drag them. Change groups and labels, hide entries or add local application paths. Save my sidebar persists the layout for your account. Restore defaults and save clears customization.', 'docs/nevaeh/control_center.md'],
      'runs' => ['Execution evidence', 'Queued and dispatched are intermediate states. Open the linked ticket for saved inputs, outputs, blockers and acceptance evidence. Verified means the registered acceptance checks completed.', 'docs/nevaeh/control_center.md'],
      'capabilities' => ['Registered abilities', 'This catalog shows the installed capability bindings. Use the construction factory to create an implemented service and verifier, or add a new factory primitive in Ruby when the desired operation is not yet represented.', 'docs/nevaeh/digital_factory.md']
    }.freeze
    module_function
    def find(key)
      row = TOPICS[key.to_s] || raise(ArgumentError, 'Unknown help topic')
      {title: row[0], body: row[1], document_path: row[2]}
    end
  end
end
