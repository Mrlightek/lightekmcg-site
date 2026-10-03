# frozen_string_literal: true

module LightekSocial
  module_function

  def profile_id(value)
    value.respond_to?(:id) ?
      value.id :
      value
  end

  def pair_ids(left, right)
    ids = [
      profile_id(left).to_i,
      profile_id(right).to_i
    ]

    if ids.any?(&:zero?) ||
       ids.uniq.length != 2
      raise ArgumentError,
            "relationship requires two distinct profiles"
    end

    ids.sort
  end

  def pair_key(left, right)
    pair_ids(
      left,
      right
    ).join(":")
  end

  def blocked_between?(left, right)
    left_id =
      profile_id(left)

    right_id =
      profile_id(right)

    Block.where(
      blocker_profile_id:
        left_id,
      blocked_profile_id:
        right_id
    ).or(
      Block.where(
        blocker_profile_id:
          right_id,
        blocked_profile_id:
          left_id
      )
    ).exists?
  end
end
