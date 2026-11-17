require 'csv'
require 'digest'
require 'bigdecimal'
module LightekPwa
  class YoutubeImport
    HEADERS = %w[video_id user_id period_start period_end estimated_revenue_usd creator_share_bps views].freeze
    def self.call(site:, actor:, file:, source_reference:)
      raise Policy::Denied, 'Only the platform owner can record revenue reports' unless actor.role == 'super_admin' && site.tenant == actor
      raise ArgumentError, 'Attach a CSV under 2 MB' unless file && file.size.between?(1, 2.megabytes)
      raise ArgumentError, 'Enter the YouTube report reference' if source_reference.to_s.strip.empty? || source_reference.to_s.length > 300
      bytes = file.read
      digest = Digest::SHA256.hexdigest(bytes)
      rows = CSV.parse(bytes.force_encoding('UTF-8'), headers: true)
      raise ArgumentError, 'Use the provided CSV columns' unless rows.headers == HEADERS
      raise ArgumentError, 'Import between 1 and 1000 rows' unless rows.size.between?(1, 1000)
      created = []
      site.with_lock do
        rows.each do |row|
          video = row['video_id'].to_s
          raise ArgumentError, 'Invalid video ID' unless video.match?(Youtube::ID)
          user_id = Integer(row['user_id'], 10)
          # Only assign earnings for a video this creator actually published in this site.
          posts = Post.where(site: site, user_id: user_id, kind: 'video')
          raise ArgumentError, 'Video and creator do not match this application' unless posts.any? { |p| p.metadata['youtube_video_id'] == video }
          first, last = Date.iso8601(row['period_start']), Date.iso8601(row['period_end'])
          raise ArgumentError, 'Use a valid completed reporting period' unless first <= last && last < Date.current
          value = row['estimated_revenue_usd'].to_s
          raise ArgumentError, 'Revenue must be a nonnegative USD amount with at most two decimals' unless value.match?(/\A\d{1,9}(?:\.\d{1,2})?\z/)
          amount = (BigDecimal(value) * 100).to_i
          share = RevenueEligibility.share_for!(user_id: user_id, site: site, first: first, last: last)
          raise ArgumentError, 'Use the contractual 80% paid-member share, or 0% for free reporting periods' unless Integer(row['creator_share_bps'], 10) == share
          views = Integer(row['views'], 10)
          raise ArgumentError, 'Views must be a nonnegative integer' if views.negative?
          existing = YoutubeRevenue.where(site: site, video_id: video).where('period_start <= ? AND period_end >= ?', last, first).first
          if existing
            next if existing.report_sha256 == digest && existing.user_id == user_id && existing.amount_cents == amount && existing.views == views && existing.creator_share_bps == share && existing.period_start == first && existing.period_end == last
            raise ArgumentError, 'This video already has revenue for an overlapping period. Review the existing receipt instead of importing twice.'
          end
          entry = YoutubeRevenue.create!(site: site, user_id: user_id, recorded_by: actor, video_id: video,
            period_start: first, period_end: last, views: views, amount_cents: amount, creator_share_bps: share,
            source_reference: source_reference.strip, report_sha256: digest, currency: 'usd')
          entry.report.attach(io: StringIO.new(bytes), filename: 'youtube-revenue.csv', content_type: 'text/csv')
          created << entry
        end
      end
      created
    rescue CSV::MalformedCSVError, Encoding::InvalidByteSequenceError
      raise ArgumentError, 'Upload a valid UTF-8 CSV'
    end
  end
end
