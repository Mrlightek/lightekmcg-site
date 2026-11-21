# frozen_string_literal: true

module Studio
  module Broadcasting
    class ArchiveNetworkReportsJob < ApplicationJob
      queue_as :default

      def perform
        days = 1.month.ago.to_date.all_month
        active = DymondSite::Site.where(id: Channel.select(:site_id))
          .or(DymondSite::Site.where(id: BroadcastContract.select(:site_id)))
          .or(DymondSite::Site.where(id: CarriageAgreement.select(:outlet_site_id)))
        active.find_each do |site|
          next if BroadcastReportArchive.exists?(site: site, month: days.begin)

          report = NetworkReport.new(site: site, first: days.begin, last: days.end, include_network_finance: true)
          BroadcastReportArchive.create_or_find_by!(site: site, month: days.begin) { |archive| archive.csv = report.csv }
        end
      end
    end
  end
end
