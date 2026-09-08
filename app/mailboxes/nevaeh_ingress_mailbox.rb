class NevaehIngressMailbox < ApplicationMailbox
  def process
    # Convert inbound email to a persistent database record
    db_request = DatabaseRequest.create!(
      requestable_type: "InboundEmail",
      requestable_id: mail.message_id,
      payload: {
        from: mail.from,
        subject: mail.subject,
        body: mail.body.decoded
      }.to_json,
      occurred_at: Time.current
    )

    # DatabaseRequest's `after_create_commit` triggers NevaehAwarenessJob
  end
end