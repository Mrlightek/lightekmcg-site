# frozen_string_literal: true

require "test_helper"

class SupportsControllerTest < ActionDispatch::IntegrationTest
  PASSWORD = "support-hub-test-password"

  setup do
    @customer = customer
    post session_path, params: { email_address: @customer.email_address, password: PASSWORD }
    assert_response :redirect
    assert Session.exists?(user: @customer)
  end

  test "technical support intake returns the persisted customer ticket" do
    post supports_path, params: { ticket: { category: "technical", title: "Mail delivery",
      description: "Mail is delayed", priority: "medium", urgency: 5 } }, as: :json
    assert_response :success
    receipt = response.parsed_body
    ticket = Marlon::Ticket.find(receipt.fetch("id"))
    assert_equal @customer, ticket.submitted_by
    assert_equal "support_hub", ticket.extra_fields.fetch("source")
    assert_equal ticket.number, receipt.dig("ticket", "num")
    assert_equal "Ticket submitted", receipt.dig("ticket", "events", 0, "action")
  end

  test "replies are scoped to the owning customer and return a public timeline" do
    ticket = support_ticket(@customer)
    foreign_ticket = support_ticket(customer)
    ticket.log!(action: "nevaeh_backlog_escalated", detail: "private engineering plan")
    ticket.log!(action: "nevaeh_backlog_job_completed", detail: "private job receipt")

    assert_no_difference -> { foreign_ticket.events.count } do
      patch reply_support_path(foreign_ticket), params: { detail: "Follow-up" }, as: :json
      assert_response :not_found
    end

    patch reply_support_path(ticket), params: { detail: "Mail has arrived." }, as: :json
    assert_response :success
    timeline = response.parsed_body.dig("ticket", "events")
    assert_equal ["Nevaeh support update", "#{@customer.full_name} replied"], timeline.pluck("action")
    assert_equal "Mail has arrived.", timeline.last.fetch("detail")
    refute_includes response.body, "private engineering plan"
    refute_includes response.body, "private job receipt"
  end

  test "closed tickets cannot be changed through customer replies" do
    ticket = support_ticket(@customer, status: "resolved")
    assert_no_difference -> { ticket.events.count } do
      patch reply_support_path(ticket), params: { detail: "Follow-up" }, as: :json
      assert_response :conflict
    end
  end

  test "customer confirmation closes an owned support case and preserves tenant scope" do
    ticket = support_ticket(@customer)
    other = support_ticket(customer)

    patch confirm_resolution_support_path(other), params: {confirmed: true}, as: :json
    assert_response :not_found
    patch confirm_resolution_support_path(ticket), params: {confirmed: false}, as: :json
    assert_response :unprocessable_entity
    assert_equal "open", ticket.reload.status

    patch confirm_resolution_support_path(ticket), params: {confirmed: true}, as: :json
    assert_response :success
    assert_equal "resolved", response.parsed_body.dig("ticket", "status")
    assert_equal "resolved", ticket.reload.status
  end

  private

  def customer
    User.create!(email_address: "support-#{SecureRandom.hex(8)}@example.test",
      first_name: "Support", last_name: "Customer", role: "client", password: PASSWORD)
  end

  def support_ticket(owner, status: "open")
    Marlon::Ticket.create!(submitted_by: owner, category: "technical", title: "Mail delivery",
      description: "Mail is delayed", priority: "medium", urgency: 5, status: status)
  end
end
