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
      agents: NevaehOsAgent.where(user:current_user).order(:id).map { |a| a.attributes.slice('id','name','role','birth_date','birth_time','birth_place','system_key','enabled','autonomy','allowed_capabilities') },
      host_control: current_user.role=='super_admin',
      agent_workers: NevaehAgentWorker.where(user:current_user).includes(:nevaeh_os_agent).order(id: :desc).limit(30).map { |worker| {id:worker.id,agent_id:worker.nevaeh_os_agent_id,agent:worker.nevaeh_os_agent.name,name:worker.name,enabled:worker.enabled?,interval_minutes:worker.interval_minutes,next_run_at:worker.next_run_at,last_status:worker.runs.order(id: :desc).first&.execution_status} },
      memory: memory_state,
      actions: NevaehOsAction.where(user:current_user).order(id: :desc).limit(12).map { |a| receipt(a) },
      kernel: {language_models: NevaehLanguageModel.where(enabled:true).where.not(active_checkpoint_id:nil).count, chart_accuracy:'illustrative', ethics_scores:'not_measured'}
    }
  end
  def ask
    render json: NevaehOs::Conversation.new(actor:current_user,host:request.host,origin:request.base_url).ask(text:params.require(:q),request_key:params.require(:request_key),agent:params[:agent],mode:params[:mode])
  end
  def download
    NevaehOs::UbuntuPackages.authorize!(current_user)
    path=NevaehOs::Applications.checked_path(NevaehOs::Applications.workspace(current_user),params.require(:filename),existing:true)
    send_file path,type:'application/octet-stream',disposition:'attachment'
  end
  def upload
    NevaehOs::UbuntuPackages.authorize!(current_user)
    file=params.require(:file)
    raise ArgumentError,'Choose a file up to 100 MB' unless file.respond_to?(:tempfile) && file.size.between?(1,100.megabytes)
    name=File.basename(file.original_filename.to_s).gsub(/[^a-zA-Z0-9_.-]/,'_')[0,100]
    name="#{SecureRandom.hex(6)}-#{name}"
    path=NevaehOs::Applications.workspace(current_user).join(name)
    File.open(path,File::WRONLY|File::CREAT|File::EXCL,0o600) { |target| IO.copy_stream(file.tempfile,target) }
    render json:{file:name,bytes:File.size(path)}
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
