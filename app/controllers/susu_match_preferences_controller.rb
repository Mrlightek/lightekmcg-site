class SusuMatchPreferencesController < ApplicationController
  def index
    @preferences = SusuMatchPreference.where(user: current_user).order(created_at: :desc)
  end

  def new
    @preference = SusuMatchPreference.new(
      contribution_amount: 100,
      cycle_frequency: "weekly",
      desired_payout: 400,
      desired_member_count: 4,
      matching_mode: "suggestions",
      status: "open"
    )
  end

  def create
    @preference = SusuMatchPreference.new(match_preference_params.merge(user: current_user, status: "open"))

    if @preference.save
      redirect_to susu_match_preference_path(@preference), notice: "You’re in the Susu matching pool."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def show
    @preference = SusuMatchPreference.find(params[:id])
    return head :forbidden unless @preference.user_id == current_user.id

    @suggestions = Susu::MatchingService.suggestions_for(@preference)
    @enough_for_circle = Susu::MatchingService.enough_for_circle?(@preference)
  end

  def destroy
    @preference = SusuMatchPreference.find(params[:id])
    return head :forbidden unless @preference.user_id == current_user.id

    @preference.update!(status: "closed")
    redirect_to susu_match_preferences_path, notice: "Matching request closed."
  end

  private

  def match_preference_params
    params.require(:susu_match_preference).permit(
      :contribution_amount,
      :cycle_frequency,
      :desired_payout,
      :desired_member_count,
      :matching_mode
    )
  end
end
