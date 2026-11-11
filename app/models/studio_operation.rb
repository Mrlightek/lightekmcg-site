class StudioOperation < ApplicationRecord
  STATUSES = %w[awaiting_planning awaiting_approval awaiting_payment pending running completed failed cancelled].freeze

  has_one_attached :blender_bundle
  has_many_attached :performance_sources
  has_one_attached :blender_source
  after_create :capture_blender_source
  after_create :capture_performance_sources

  belongs_to :studio_project
  belongs_to :production, optional: true
  belongs_to :studio_scene, optional: true
  has_many :artifacts, dependent: :destroy

  validates :operation_type, :provider, :capability, presence: true
  validates :status, inclusion: { in: STATUSES }
  validate :json_payloads_must_be_objects

  scope :recent_first, -> { order(created_at: :desc) }
  scope :active, -> { where(status: %w[awaiting_planning awaiting_approval awaiting_payment pending running]) }

  def payment_required? = status == "awaiting_payment"

  def paid?
    return false unless defined?(DymondBank::Transaction)

    DymondBank::Transaction
      .succeeded
      .where(payable: self)
      .exists?
  end

  def payment_succeeded!(transaction)
    enqueue = false
    with_lock do
      payment = metadata.to_h.fetch("payment", {})
      return self if payment["transaction_id"].to_s == transaction.id.to_s && payment["status"] == "succeeded" && %w[pending running completed cancelled].include?(status)
      cancelled = status == "cancelled"
      current_metadata = metadata.to_h.deep_dup

      payment_metadata =
        current_metadata.fetch("payment", {}).merge(
          "transaction_id" => transaction.id,
          "status" => "succeeded",
          "paid_at" => Time.current.iso8601
        )
      payment_metadata["requires_review"] = true if cancelled

      update!(
        status: cancelled ? "cancelled" : "pending",
        metadata: current_metadata.merge("payment" => payment_metadata),
        error_message: cancelled ? "Payment received for a cancelled operation; review it in billing." : nil
      )
      enqueue = !cancelled
    end

    ExecuteStudioOperationJob.perform_later(id) if enqueue

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
        status: status == "cancelled" ? "cancelled" : "awaiting_payment",
        metadata: current_metadata.merge("payment" => payment_metadata),
        error_message: message.to_s.presence
      )
    end

    self
  end

  def terminal? = status.in?(%w[completed failed cancelled])
  def executable? = status.in?(%w[pending awaiting_approval])

  private

  def capture_performance_sources
    return unless Array(manifest.dig("scene","objects")).any? { |object| object.dig("definition","character_profile") || object.dig("definition","performance") }
    raise ArgumentError,"Use at most sixteen Cast members in a shot" if Array(manifest.dig("scene","objects")).count { |object| object.dig("definition","character_profile") }>16
    access=Studio::PwaAccess.new("user_id"=>intent["user_id"] || studio_project.owner_id,"site_id"=>studio_project.site_id)
    Array(manifest.dig("scene","objects")).each do |object|
      definition=object.fetch("definition",{})
      if (profile=definition["character_profile"])
        asset=StudioAsset.for_actor(access).find(definition.fetch("asset_id"))
        raise ArgumentError,"The character source changed. Register its new version in Cast." unless asset.native.attached? && asset.native.blob.id==profile["source_blob_id"]
        performance_sources.attach(asset.native.blob)
      end
      if (take=definition["performance"])
        audio=StudioAsset.for_actor(access).find(take.fetch("audio_asset_id"))
        raise ArgumentError,"The performance recording changed. Save the take again." unless audio.file.attached? && audio.file.blob.id==take["audio_blob_id"]
        performance_sources.attach(audio.file.blob)
      end
    end
  end

  def capture_blender_source
    blender_source.attach(studio_scene.blender_source.blob) if studio_scene&.blender_source&.attached?
    blender_bundle.attach(studio_scene.blender_bundle.blob) if studio_scene&.blender_bundle&.attached?
  end

  def json_payloads_must_be_objects
    %i[intent manifest cost_quote metadata].each do |attribute|
      errors.add(attribute, "must be a JSON object") unless public_send(attribute).is_a?(Hash)
    end
  end
end
