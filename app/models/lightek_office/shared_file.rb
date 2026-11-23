# frozen_string_literal: true

module LightekOffice
  class SharedFile < ApplicationRecord
    self.table_name = 'lightek_office_files'
    KINDS = {'document'=>'Document', 'spreadsheet'=>'Spreadsheet', 'presentation'=>'Presentation'}.freeze

    belongs_to :channel, class_name: 'LightekTeam::Channel', optional: true
    belongs_to :drive_entry, class_name: 'LightekWorkspace::DriveEntry', optional: true, inverse_of: :office_file
    validate :one_location
    after_save :sync_drive_name, if: :saved_change_to_title?
    belongs_to :creator, class_name: 'User'
    belongs_to :editor, class_name: 'User'
    validates :kind, inclusion: {in: KINDS.keys}
    validates :title, presence: true, length: {maximum: 160}
    validates :content, presence: true
    validate :valid_content

    def kind_label = KINDS.fetch(kind)

    private

    def one_location
      errors.add(:base, 'Choose one drive or channel') if channel_id.present? == drive_entry.present?
      errors.add(:drive_entry, 'must be a file entry') if drive_entry && (drive_entry.folder? || drive_entry.upload.attached?)
    end

    def sync_drive_name
      # The Office title is the source of truth for Drive listing and search.
      drive_entry&.update_columns(name: title, updated_at: Time.current)
    end

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
