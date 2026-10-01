json.extract! profile,
              :id,
              :display_name,
              :handle,
              :profile_type,
              :bio,
              :avatar_url,
              :cover_image_url,
              :created_at,
              :updated_at

json.public_display_name profile.public_display_name
json.display_handle profile.display_handle

json.sections(
  profile
    .profile_sections
    .ordered
    .where(enabled: true)
) do |section|
  json.extract! section,
                :key,
                :position,
                :settings
end

json.url profile_url(
  profile,
  format: :json
)
