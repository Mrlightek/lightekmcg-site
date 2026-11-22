# frozen_string_literal: true

module LightekOffice
  class SharedFile < ApplicationRecord
    self.table_name = 'lightek_office_files'
    KINDS = {'document'=>'Document', 'spreadsheet'=>'Spreadsheet', 'presentation'=>'Presentation'}.freeze

    belongs_to :channel, class_name: 'LightekTeam::Channel'
    belongs_to :creator, class_name: 'User'
    belongs_to :editor, class_name: 'User'
    validates :kind, inclusion: {in: KINDS.keys}
    validates :title, presence: true, length: {maximum: 160}
    validates :content, presence: true
    validate :valid_content

    def kind_label = KINDS.fetch(kind)

    private

    def valid_content
      self.rich_text = false unless kind == 'document'
      if rich_text?
        self.content = Document.prepare!(content.to_s)
      else
        Content.validate!(kind, content.to_s)
      end
    rescue ArgumentError => error
      errors.add(:content, error.message)
    end
  end
end
