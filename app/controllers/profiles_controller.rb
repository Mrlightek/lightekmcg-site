class ProfilesController < ApplicationController
  before_action :set_profile,
                only: :show

  before_action :set_owned_profile,
                only: %i[
                  edit
                  update
                  destroy
                ]

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
                        "Profile was successfully created."
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
                        "Profile was successfully updated.",
                      status: :see_other
        }

        format.json {
          render :show,
                 status: :ok,
                 location: @profile
        }
      else
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

  def profile_params
    params.expect(
      profile: [
        :display_name,
        :handle,
        :profile_type,
        :bio,
        :avatar_url,
        :cover_image_url
      ]
    )
  end
end
