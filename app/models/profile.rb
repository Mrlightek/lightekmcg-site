class Profile < ApplicationRecord
  belongs_to :user

  has_many :lightek_messaging_participations,
           class_name:
             "LightekMessaging::Participant",
           dependent: :restrict_with_error

  has_many :lightek_messaging_conversations,
           through:
             :lightek_messaging_participations,
           source: :conversation

  has_many :created_lightek_conversations,
           class_name:
             "LightekMessaging::Conversation",
           foreign_key:
             :created_by_profile_id,
           dependent: :restrict_with_error

  has_many :sent_lightek_messages,
           class_name:
             "LightekMessaging::Message",
           foreign_key:
             :sender_profile_id,
           dependent: :restrict_with_error

  has_many :lightek_social_following_edges,
           class_name:
             "LightekSocial::Follow",
           foreign_key:
             :follower_profile_id,
           dependent:
             :destroy

  has_many :lightek_social_follower_edges,
           class_name:
             "LightekSocial::Follow",
           foreign_key:
             :followed_profile_id,
           dependent:
             :destroy

  has_many :requested_lightek_friendships,
           class_name:
             "LightekSocial::Friendship",
           foreign_key:
             :requester_profile_id,
           dependent:
             :restrict_with_error

  has_many :received_lightek_friendships,
           class_name:
             "LightekSocial::Friendship",
           foreign_key:
             :addressee_profile_id,
           dependent:
             :restrict_with_error

  has_many :lightek_social_blocks_created,
           class_name:
             "LightekSocial::Block",
           foreign_key:
             :blocker_profile_id,
           dependent:
             :destroy

  has_many :lightek_social_blocks_received,
           class_name:
             "LightekSocial::Block",
           foreign_key:
             :blocked_profile_id,
           dependent:
             :destroy

  has_many :lightek_social_circles,
           class_name:
             "LightekSocial::Circle",
           foreign_key:
             :owner_profile_id,
           dependent:
             :destroy

  has_many :lightek_social_circle_memberships,
           class_name:
             "LightekSocial::CircleMembership",
           dependent:
             :destroy

  has_many :lightek_social_relationship_events_sent,
           class_name:
             "LightekSocial::RelationshipEvent",
           foreign_key:
             :actor_profile_id,
           dependent:
             :restrict_with_error

  has_many :lightek_social_relationship_events_received,
           class_name:
             "LightekSocial::RelationshipEvent",
           foreign_key:
             :target_profile_id,
           dependent:
             :restrict_with_error

  has_many :lightek_social_connection_opportunities,
           class_name:
             "LightekSocial::ConnectionOpportunity",
           dependent:
             :destroy

  include Visitable
  tracks_unique_visits

  PROFILE_TYPES =
    %w[
      person
      creator
      organization
    ].freeze

  AVAILABLE_SECTIONS =
    %w[
      featured
      series
      clips
      playlists
      posts
      about
      friends
      communities
      events
      members
      custom
    ].freeze

  DEFAULT_SECTIONS = {
    "person" => %w[
      posts
      friends
      communities
      events
      about
    ],

    "creator" => %w[
      featured
      series
      clips
      playlists
      posts
      about
    ],

    "organization" => %w[
      featured
      series
      members
      events
      posts
      about
    ]
  }.freeze

  has_many :profile_sections,
           -> {
             order(
               :position,
               :id
             )
           },
           dependent: :destroy,
           inverse_of: :profile

  accepts_nested_attributes_for :profile_sections

  validates :user_id,
            uniqueness: true

  validates :profile_type,
            inclusion: {
              in: PROFILE_TYPES
            }

  validates :display_name,
            length: {
              maximum: 80
            },
            allow_blank: true

  validates :handle,
            presence: true,
            uniqueness: {
              case_sensitive: false
            },
            format: {
              with: /\A[a-z0-9][a-z0-9_-]*\z/,
              message:
                "may only contain lowercase letters, numbers, underscores, and hyphens"
            },
            length: {
              minimum: 3,
              maximum: 40
            }

  validates :bio,
            length: {
              maximum: 2_000
            },
            allow_blank: true

  before_validation :normalize_handle

  after_create :seed_default_sections!

  def public_display_name
    display_name.presence ||
      "Lightek Member"
  end

  def display_handle
    "@#{handle}"
  end

  def default_section_keys
    DEFAULT_SECTIONS.fetch(
      profile_type,
      DEFAULT_SECTIONS.fetch("person")
    )
  end

  def ensure_default_sections!
    return if profile_sections.exists?

    seed_default_sections!
  end

  def reset_sections_to_defaults!
    transaction do
      profile_sections.delete_all
      seed_default_sections!
    end

    profile_sections.reload
  end

  private

  def normalize_handle
    self.handle =
      handle
        .to_s
        .strip
        .downcase
        .delete_prefix("@")
  end

  def seed_default_sections!
    default_section_keys
      .each_with_index do |key, index|
        profile_sections
          .find_or_create_by!(
            key: key
          ) do |section|
            section.position =
              index + 1

            section.enabled =
              true

            section.settings =
              {}
          end
      end
  end
end
