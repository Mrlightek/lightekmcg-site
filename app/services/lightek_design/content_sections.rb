module LightekDesign
  module ContentSections
    def self.definitions
      [{"kind"=>"lightek_blog_index", "fields"=>[{"name"=>"heading","label"=>"Heading","type"=>"text"},{"name"=>"intro","label"=>"Introduction","type"=>"text"}],
        "data"=>{"heading"=>"Journal", "intro"=>"Ideas, stories and updates from our team."}}]
    end
  end
end
