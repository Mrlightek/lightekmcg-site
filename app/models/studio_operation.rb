class StudioOperation < ApplicationRecord
  STATUSES = %w[awaiting_planning awaiting_approval awaiting_payment pending running completed failed cancelled].freeze

  belongs_to :studio_project
  belongs_to :production, optional: true
  belongs_to :studio_scene, optional: true
  has_many :artifacts, dependent: :destroy

  validates :operation_type, :provider, :capability, presence: true
  validates :status, inclusion: { in: STATUSES }
  validate :json_payloads_must_be_objects

  scope :recent_first, -> { order(created_at: :desc) }
  scope :active, -> { where(status: %w[awaiting_planning awaiting_approval pending running]) }

  def payment_required? = status == "awaiting_payment"

  def paid?
    return false unless defined?(DymondBank::Transaction)

    DymondBank::Transaction
      .succeeded
      .where(payable: self)
      .exists?
  end

  def payment_succeeded!(transaction)
    with_lock do
      current_metadata = metadata.to_h.deep_dup

      payment_metadata =
        current_metadata.fetch("payment", {}).merge(
          "transaction_id" => transaction.id,
          "status" => "succeeded",
          "paid_at" => Time.current.iso8601
        )

      update!(
        status: "pending",
        metadata: current_metadata.merge("payment" => payment_metadata),
        error_message: nil
      )
    end

    ExecuteStudioOperationJob.perform_later(id)

    self
  end

  def payment_failed!(transaction, message: nil)
    with_lock do
      current_metadata = metadata.to_h.deep_dup

      payment_metadata =
        current_metadata.fetch("payment", {}).merge(
          "transaction_id" => transaction.id,
          "status" => "failed",
          "failed_at" => Time.current.iso8601
        )

      update!(
        status: "awaiting_payment",
        metadata: current_metadata.merge("payment" => payment_metadata),
        error_message: message.to_s.presence
      )
    end

    self
  end

  def terminal? = status.in?(%w[completed failed cancelled])
  def executable? = status.in?(%w[pending awaiting_approval])

  private

  def json_payloads_must_be_objects
    %i[intent manifest cost_quote metadata].each do |attribute|
      errors.add(attribute, "must be a JSON object") unless public_send(attribute).is_a?(Hash)
    end
  end
end
