# frozen_string_literal: true

module Studio
  module Broadcasting
    class BroadcastReportArchive < ApplicationRecord
      self.table_name = "studio_broadcast_report_archives"
      belongs_to :site, class_name: "DymondSite::Site"
    end
  end
end
