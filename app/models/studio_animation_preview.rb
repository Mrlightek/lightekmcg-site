# frozen_string_literal: true

class StudioAnimationPreview < ApplicationRecord
  CACHE_VERSION = 1
  TIMEOUT = 5.minutes

  belongs_to :studio_asset
  has_one_attached :file

  def self.settings_for(asset, parameters)
    blob = asset.animation_source.blob
    fps = Integer(parameters[:fps].to_s, 10, exception: false)
    raise ArgumentError, "Preview FPS must be 24 or 30" unless [24, 30].include?(fps)
    settings = { "blob_id" => blob.id, "fps" => fps, "starter" => !asset.animation_role? }
    if parameters[:source_revision].present? && parameters[:source_revision].to_s != blob.id.to_s
      raise ArgumentError, "The model changed. Reload the asset before building the preview."
    end
    if parameters[:action_name].present?
      action = parameters[:action_name]
      raise ArgumentError, "Invalid preview action" unless action.is_a?(String) && action.length <= 120
      settings["action"] = action
    end
    if parameters[:pose_frame].present?
      frame = Integer(parameters[:pose_frame].to_s, 10, exception: false)
      raise ArgumentError, "Invalid preview pose frame" unless frame && (0..100_000).cover?(frame)
      settings["pose_frame"] = frame
    end
    settings
  end

  def self.key_for(settings)
    Digest::SHA256.hexdigest([CACHE_VERSION, settings.sort.to_json].join(":"))
  end

  def preview_status
    return "failed" if status == "ready" && !file.attached?
    return "failed" if status == "queued" && updated_at <= TIMEOUT.ago
    status
  end
end
