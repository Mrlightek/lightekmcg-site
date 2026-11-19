# frozen_string_literal: true
module Studio
  module Workflows
    module ScenePlan
      EXAMPLE="A nighttime park with a character sitting on a bench"
      PATTERN=/\A(?:a )?(?:(daytime|nighttime|day|night) )?park(?: at (day|night))?(?: with (?:(\d+) trees(?: and (\d+) benches)?|(a character sitting on a bench)))?(?: (?:with|and) (?:a )?(?:slow |gentle )?(?:parallax|camera pan)(?: (left|right))?)?\z/i
      def self.parse(prompt,seed:nil)
        text=prompt.to_s.strip.delete_suffix(".").gsub(/\s+/," ")
        breeze=!!text.sub!(/ (?:and|with) (?:a )?gentle breeze\z/i,"")
        words=%w[zero one two three four five six seven eight]
        text=text.gsub(/\b(?:#{words.join('|')})\b/i) { |word| words.index(word.downcase).to_s }
        match=PATTERN.match(text)
        raise ArgumentError,"Use a supported scene prompt, such as: #{EXAMPLE}. You can edit its layers and add your own images afterward." unless match && text.length<=300
        seed=seed.nil? ? SecureRandom.random_number(2**32) : Studio::Layered::Composition.integer(seed,0,2**32-1)
        graph=Studio::Layered::Templates.park(seed:seed,night:[match[1],match[2]].compact.any? { |time| time.downcase.start_with?("night") },
          trees:match[3]&.to_i,benches:match[4]&.to_i,character:match[5].present?,pan:match[6].to_s.downcase=="left" ? -0.08 : 0.08)
        if breeze
          visit=lambda do |nodes|
            nodes.each do |node|
              if node["children"]
                visit.call(node["children"])
              elsif node["template"]=="tree.oak"
                node["motion"]=Studio::Layered::Motion.preset("sway",amount:0.008,duration:3+(node["id"].delete_prefix("tree-").to_i%3)*0.5)
              end
            end
          end
          visit.call(graph["nodes"])
        end
        Studio::Layered::Composition.normalize(graph)
      end
    end
  end
end
