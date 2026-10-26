require "test_helper"
require "timeout"

class LightekMailReservationConcurrencyTest < ActiveSupport::TestCase
  self.use_transactional_tests = false
  self.fixture_table_names = []

  test "two workers cannot exceed a customer limit through separate mailboxes" do
    previous_limit = ENV["LIGHTEK_MAIL_CUSTOMER_MINUTE_LIMIT"]
    skip "PostgreSQL row-lock regression" unless ActiveRecord::Base.connection.adapter_name == "PostgreSQL"
    ENV["LIGHTEK_MAIL_CUSTOMER_MINUTE_LIMIT"] = "1"
    policy = LightekMail::SendingPolicy.create_or_find_by!(id: 1)
    previous_enabled = policy.sending_enabled?
    policy.update!(sending_enabled: true)
    user = User.create!(first_name: "Concurrent", last_name: "Mail", role: "super_admin", email_address: "concurrent-#{SecureRandom.hex(6)}@example.test", password: "Mail-test-2026-password!")
    accounts = 2.times.map do
      domain = LightekMail::Domain.create!(user: user, name: "concurrent-#{SecureRandom.hex(6)}.test", verified_at: Time.current)
      LightekMail::Account.create!(user: user, domain: domain, address: "care@#{domain.name}", display_name: "Concurrency", enabled: true)
    end
    arrived, start, results = Queue.new, Queue.new, Queue.new
    threads = accounts.map do |account|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          arrived << true
          start.pop
          begin
            LightekMail::Submission.create!(account: LightekMail::Account.find(account.id), attributes: {to: "a@example.test", subject: "Update", text: "Hello"})
            results << :accepted
          rescue StandardError => error
            results << error
          end
        end
      end
    end
    Timeout.timeout(15) do
      2.times { arrived.pop }
      2.times { start << true }
      threads.each(&:join)
    end
    outcomes = 2.times.map { results.pop }
    assert_equal 1, outcomes.count(:accepted), outcomes.inspect
    assert_equal 1, outcomes.count { |value| value.is_a?(LightekMail::SendingLimits::Throttled) }, outcomes.inspect
    assert_equal 1, LightekMail::SendReservation.where(user_id: user.id).sum(:recipient_count)
  ensure
    threads&.each { |thread| thread.kill if thread.alive? }
    if user
      ids = LightekMail::Account.where(user_id: user.id).pluck(:id)
      LightekMail::SendReservation.where(account_id: ids).delete_all
      LightekMail::Message.where(account_id: ids).destroy_all
      LightekMail::Account.where(id: ids).destroy_all
      LightekMail::Domain.where(user_id: user.id).destroy_all
      user.destroy!
      policy.update!(sending_enabled: previous_enabled)
    end
    previous_limit.nil? ? ENV.delete("LIGHTEK_MAIL_CUSTOMER_MINUTE_LIMIT") : ENV["LIGHTEK_MAIL_CUSTOMER_MINUTE_LIMIT"] = previous_limit
  end
end
