class ProfilesController < ApplicationController
  layout "profiles",
         only: %i[
           show
           new
           edit
           create
           update
         ]

  before_action :set_profile,
                only: :show

  before_action :set_owned_profile,
                only: %i[
                  edit
                  update
                  destroy
                ]

  before_action :prepare_section_catalog,
                only: :edit

  def index
    @profiles =
      Profile
        .includes(:user)
        .order(:id)
  end

  def show
  end

  def new
    if current_user.profile
      redirect_to edit_profile_path(
        current_user.profile
      )

      return
    end

    @profile =
      current_user.build_profile(
        handle:
          "member-#{current_user.id}",
        profile_type:
          "person"
      )
  end

  def edit
  end

  def create
    if current_user.profile
      redirect_to edit_profile_path(
        current_user.profile
      ),
      alert:
        "Your Lightek profile already exists."

      return
    end

    @profile =
      current_user.build_profile(
        profile_params
      )

    respond_to do |format|
      if @profile.save
        format.html {
          redirect_to @profile,
                      notice:
                        "Public profile created."
        }

        format.json {
          render :show,
                 status: :created,
                 location: @profile
        }
      else
        format.html {
          render :new,
                 status:
                   :unprocessable_content
        }

        format.json {
          render json: @profile.errors,
                 status:
                   :unprocessable_content
        }
      end
    end
  end

  def update
    respond_to do |format|
      if @profile.update(
        profile_params
      )
        format.html {
          redirect_to @profile,
                      notice:
                        "Public profile updated.",
                      status: :see_other
        }

        format.json {
          render :show,
                 status: :ok,
                 location: @profile
        }
      else
        prepare_section_catalog

        format.html {
          render :edit,
                 status:
                   :unprocessable_content
        }

        format.json {
          render json: @profile.errors,
                 status:
                   :unprocessable_content
        }
      end
    end
  end

  def destroy
    redirect_to @profile,
                alert:
                  "Your Lightek profile is part of your account and cannot be deleted separately.",
                status: :see_other
  end

  private

  def set_profile
    @profile =
      Profile.find(
        params.expect(:id)
      )
  end

  def set_owned_profile
    @profile =
      current_user.profile

    unless @profile &&
           @profile.id ==
             params.expect(:id).to_i
      raise ActiveRecord::RecordNotFound
    end
  end

  def prepare_section_catalog
    existing =
      @profile
        .profile_sections
        .map(&:key)

    next_position =
      @profile
        .profile_sections
        .map(&:position)
        .compact
        .max
        .to_i

    Profile::AVAILABLE_SECTIONS.each do |key|
      next if existing.include?(key)

      next_position += 1

      @profile
        .profile_sections
        .build(
          key: key,
          position: next_position,
          enabled: false,
          settings: {}
        )
    end
  end

  def profile_params
    params
      .require(:profile)
      .permit(
        :display_name,
        :handle,
        :profile_type,
        :bio,
        :avatar_url,
        :cover_image_url,
        profile_sections_attributes: [
          :id,
          :key,
          :position,
          :enabled
        ]
      )
  end
end
