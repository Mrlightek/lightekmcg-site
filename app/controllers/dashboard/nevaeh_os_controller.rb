# frozen_string_literal: true
class Dashboard::NevaehOsController < ::ApplicationController
  # Available to signed-in clients too; every operation has its own resource policy.
  protect_from_forgery with: :exception
  before_action do
    response.set_header('Cache-Control','private, no-store')
  end
  rate_limit to: 60, within: 1.minute, only: :ask
  rescue_from ArgumentError, ActiveRecord::RecordInvalid, ActiveRecord::StaleObjectError, ActiveRecord::RecordNotDestroyed do |error|
    render json: {error:error.message}, status: :unprocessable_entity
  end
  rescue_from Gatekeeper::AuthorizationDenied, CanCan::AccessDenied, LightekPwa::Policy::Denied do |error|
    render json: {error:error.message}, status: :forbidden
  end
  rescue_from ActiveRecord::RecordNotFound do
    render json: {error:'Record not found'}, status: :not_found
  end
  def index
    render layout: false
  end
  def state
    render json: {
      user: {id:current_user.id,name:current_user.respond_to?(:first_name) ? current_user.first_name : 'Operator'},
      resources: NevaehOs::Resources.catalog(current_user),
      agents: NevaehOsAgent.where(user:current_user).order(:id).map { |a| a.attributes.slice('id','name','role','birth_date','birth_time','birth_place') },
      memory: memory_state,
      actions: NevaehOsAction.where(user:current_user).order(id: :desc).limit(12).map { |a| receipt(a) },
      kernel: {language_models: NevaehLanguageModel.where(enabled:true).where.not(active_checkpoint_id:nil).count, chart_accuracy:'illustrative', ethics_scores:'not_measured'}
    }
  end
  def ask
    render json: NevaehOs::Conversation.new(actor:current_user,host:request.host,origin:request.base_url).ask(text:params.require(:q),request_key:params.require(:request_key),agent:params[:agent],mode:params[:mode])
  end
  def action
    render json: receipt(NevaehOsAction.where(user:current_user).find(params[:id]))
  end
  def consent
    category = params.require(:category).to_s
    raise ArgumentError, 'Unknown memory category' unless NevaehOsConsent::CATEGORIES.include?(category)
    NevaehOsConsent.transaction do
      row = NevaehOsConsent.find_or_create_by!(user:current_user,category:category)
      row.with_lock do
        row.update!(enabled:ActiveModel::Type::Boolean.new.cast(params.require(:enabled)))
        NevaehOsMemory.where(user:current_user,category:category).destroy_all unless row.enabled?
      end
    end
    render json: memory_state
  end
  def remember
    row = NevaehOsConsent.where(user:current_user,category:params.require(:category),enabled:true).first!
    row.with_lock do
      raise ArgumentError, 'Memory category is disabled' unless row.enabled?
      NevaehOsMemory.create!(user:current_user,category:row.category,text:params.require(:text))
    end
    render json: memory_state
  end
  def forget
    NevaehOsMemory.where(user:current_user).find(params[:id]).destroy!
    render json: memory_state
  end
  private
  def memory_state
    consent = NevaehOsConsent.where(user:current_user).pluck(:category,:enabled).to_h
    {categories:NevaehOsConsent::CATEGORIES.index_with { |key| consent.fetch(key,false) },items:NevaehOsMemory.where(user:current_user).order(:id).map { |m| {id:m.id,c:m.category,t:m.text} }}
  end
  def receipt(action)
    NevaehOs::Receipts.for(action)
  end
end
