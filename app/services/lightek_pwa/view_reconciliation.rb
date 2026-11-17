require 'csv'
require 'digest'
require 'bigdecimal'
module LightekPwa
  class ViewReconciliation
    # A whole-channel daily Analytics export includes platform/free video rows.
    # The finalized AdSense channel amount scales all rows proportionally before
    # the historical paid-member share is calculated. This prevents selection of
    # only member videos from assigning them the entire channel payment.
    HEADERS = %w[date video_id estimated_revenue_usd views].freeze
    def self.call!(site:, actor:, month:, finalized_cents:, source_reference:, report:, finalized_receipt:, complete_channel:)
      MemberBackends.operator!(site, actor)
      raise ArgumentError, 'Confirm this is the complete channel daily revenue export, including free and platform videos' unless complete_channel
      first = Date.iso8601(month.to_s)
      raise ArgumentError, 'Choose the first day of a completed month' unless first.day == 1 && first.end_of_month < Date.current
      amount = Integer(finalized_cents)
      raise ArgumentError, 'Finalized proceeds must be a nonnegative USD cent amount' unless amount.between?(0, 100_000_000_000)
      raise ArgumentError, 'Enter the finalized AdSense channel receipt reference' unless source_reference.to_s.strip.length.between?(1, 300)
      raise ArgumentError, 'Attach the complete CSV under 8 MB and the finalized channel receipt under 2 MB' unless report && report.size.between?(1, 8.megabytes) && finalized_receipt && finalized_receipt.size.between?(1, 2.megabytes)
      bytes, receipt_bytes = report.read, finalized_receipt.read
      digest, receipt_digest = Digest::SHA256.hexdigest(bytes), Digest::SHA256.hexdigest(receipt_bytes)
      channel = LaunchSettings.value('youtube_channel_id')
      rows = CSV.parse(bytes.force_encoding('UTF-8'), headers: true)
      raise ArgumentError, 'Use date,video_id,estimated_revenue_usd,views columns; one row per video/reporting day' unless rows.headers == HEADERS && rows.size.between?(1, 50_000)
      seen = {}; total = 0; weights = Hash.new(0); views = Hash.new(0)
      rows.each do |row|
        date = Date.iso8601(row['date']); video = row['video_id'].to_s
        raise ArgumentError, 'Invalid video or date outside the finalized month' unless video.match?(Youtube::ID) && date.between?(first, first.end_of_month)
        raise ArgumentError, 'Duplicate video/reporting day' if seen[[video, date]]
        seen[[video, date]] = true
        value = row['estimated_revenue_usd'].to_s
        raise ArgumentError, 'Revenue must be nonnegative USD with at most six decimal places' unless value.match?(/\A\d{1,9}(?:\.\d{1,6})?\z/)
        micros = (BigDecimal(value) * 1_000_000).to_i
        count = Integer(row['views'], 10)
        raise ArgumentError, 'Views must be nonnegative integers' if count.negative?
        total += micros
        upload = YoutubeUpload.where(site: site, video_id: video).first
        next unless upload
        share = RevenueEligibility.share_for!(user_id: upload.user_id, site: site, first: date, last: date)
        next if share.zero?
        key = [upload.user_id, video]
        weights[key] += micros * share
        views[key] += count
      end
      raise ArgumentError, 'Channel report has no positive estimated proceeds to reconcile' unless total.positive?
      result = nil
      site.with_lock do
        if (existing = ViewBatch.find_by(channel_id: channel, month: first))
          raise ArgumentError, 'This channel month is finalized already; reconcile adjustments separately without replacing paid history' unless existing.site_id == site.id && existing.finalized_cents == amount && existing.report_sha256 == digest && existing.finalized_receipt_sha256 == receipt_digest
          return existing
        end
        allocations = weights.transform_values { |weight| amount * weight / (total * 10_000) }
        result = ViewBatch.create!(site: site, recorded_by: actor, channel_id: channel, month: first,
          finalized_cents: amount, estimated_micros: total, creator_liability_cents: allocations.values.sum,
          source_reference: source_reference.strip, report_sha256: digest, finalized_receipt_sha256: receipt_digest)
        allocations.each do |(user_id, video), cents|
          result.view_earnings.create!(user_id: user_id, video_id: video, views: views[[user_id, video]], amount_cents: cents)
        end
        result.report.attach(io: StringIO.new(bytes), filename: 'channel-daily-revenue.csv', content_type: 'text/csv')
        result.finalized_receipt.attach(io: StringIO.new(receipt_bytes), filename: 'finalized-channel-receipt.bin', content_type: 'application/octet-stream')
      end
      result
    rescue CSV::MalformedCSVError, Encoding::InvalidByteSequenceError, Encoding::UndefinedConversionError
      raise ArgumentError, 'Upload a valid UTF-8 daily channel CSV'
    end
  end
end
