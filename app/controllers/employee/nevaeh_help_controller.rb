# frozen_string_literal: true
module Employee
  class NevaehHelpController < Employee::ApplicationController
    before_action { authorize! :manage, NevaehWorkflow }
    def show
      response.set_header('Cache-Control', 'private, no-store')
      result = NevaehIntelligences::ContextualHelp.find(params[:topic])
      field = params[:field].to_s.first(120)
      if field.present?
        specifics = case field.downcase
        when /repeat|interval/ then 'Enter elapsed minutes, with a minimum of five. Leave empty for manual runs. Each interval repeats the saved inputs.'
        when /weight/ then 'A rule weight multiplies its keyword coverage score. Use 0–10; higher weights favor a matching plan. This rule score is separate from neural parameters.'
        when /epoch/ then 'An epoch visits the training response tokens once. Start with 10 and inspect training and held-out loss. The run records how many epochs actually completed.'
        when /hidden/ then 'Hidden units control the native neural model capacity. Start at 16; more units increase computation and checkpoint size.'
        when /vocab/ then 'The vocabulary contains the most frequent training tokens plus control tokens. Unseen tokens map to unknown. Start at 256 and inspect held-out results.'
        when /editorial|instruction/ then 'Use Tone: warm, formal, direct or enthusiastic; Max words: 80; Opening: Welcome to {topic}; Closing: {call_to_action}. Preview the applied and unsupported directives.'
        when /keyword/ then 'Enter topic words or phrases, separated by commas. Vocabulary synonyms normalize matching terms. At least one keyword must match unless the rule has no keywords.'
        when /required context/ then 'List context field names such as topic, goal or facts. A required field must be explicitly supplied; a default does not satisfy it.'
        when /topic/ then 'Describe the subject. Symbolic inference matches topic terms to rules and examples. Neural training uses the complete prompt/response pairs in its dataset.'
        when /sample test|expected/ then 'Specify inputs and exact expected output. These independent examples run against the generated service before capability activation.'
        when /availability|visibility/ then 'Internal models are available to administrators. Shared models are available to Studio users; choose a training corpus intended for that audience.'
        else nil
        end
        result = result.merge(title: field, body: [specifics, result[:body]].compact.join("\n\n"))
      end
      library = NevaehIntelligences::SoftwareLibrary.new
      matches = params[:topic] == 'library' && field.present? ? library.search(query: field).first(3) : []
      if matches.any?
        references = matches.map do |doc|
          excerpt = doc[:body].lines.reject { |line| line.start_with?('#', '```') || line.strip.empty? }.first(4).join.strip.first(700)
          "#{doc[:title]}\n#{excerpt}"
        end
        result = result.merge(body: "References in your installed software documentation:\n\n" + references.join("\n\n"))
      end
      document = matches.first || library.documents.find { |doc| doc[:path] == result[:document_path] }
      result = result.merge(related_documents: matches.map { |doc| {title: doc[:title], url: employee_software_library_path(id: doc[:id])} })
      render json: result.merge(document_url: document ? employee_software_library_path(id: document[:id]) : employee_software_library_path)
    rescue ArgumentError
      head :not_found
    end
  end
end
