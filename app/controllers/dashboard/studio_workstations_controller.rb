class Dashboard::StudioWorkstationsController < Dashboard::SettingsHomeController
  skip_before_action :require_settings_operator!
  before_action :set_access
  protect_from_forgery with: :exception
  rescue_from ActiveRecord::RecordNotFound,with: :missing
  rescue_from LightekPwa::Policy::Denied,LightekCommunity::AccessDenied,with: :denied
  rescue_from ArgumentError,with: :invalid
  def create
    raise ArgumentError,"Native workstations require HTTPS" if Rails.env.production? && !request.ssl?
    session=@access.create!(params.permit(:scene_id,:request_key).to_h,origin:request.base_url)
    render json:{url:dashboard_studio_workstation_path(session.session_key),session_key:session.session_key},status: :accepted
  end
  def show
    @session=@access.find!(params[:id]);@scene=@session.studio_scene
  end
  def status
    render json:present(@access.find!(params[:id]))
  end
  def ticket
    session=@access.find!(params[:id])
    token=Studio::Workstations::Runtime.ticket(session)
    render json:{url:"/studio-workstations/#{session.session_key}/bootstrap?ticket=#{ERB::Util.url_encode(token)}"}
  end
  def workspace
    session=@access.find!(params[:id])
    raise ArgumentError,"Workstation is not ready" unless session.active? && session.status=="ready"
    tasks=%w[layout model sculpt uv animate shade geometry composite sequence render]
    position=tasks.index(params[:task].to_s)
    raise ArgumentError,"Choose a production workspace" unless position
    runtime=Studio::Workstations::Runtime
    temporary=runtime.work(session).join(".workspace-#{SecureRandom.hex(8)}")
    File.open(temporary,File::WRONLY|File::CREAT|File::EXCL|File::NOFOLLOW,0600) { |file| file.write(JSON.generate({task:tasks[position]})) }
    File.rename(temporary,runtime.work(session).join(".studio-workspace-request.json"))
    runtime.command("exec","--env","DISPLAY=:99",session.container_id,"xdotool","key","--clearmodifiers","F8",timeout:8)
    render json:{task:tasks[position],status:"requested"}
  end
  def save
    session=@access.find!(params[:id]);enqueue=false
    session.with_lock do
      raise ArgumentError,"Workstation is not available" unless session.active? && %w[ready saving].include?(session.status)
      if session.status=="ready"
        session.update!(status:"saving",error_message:nil,metadata:session.metadata.merge("save_nonce"=>SecureRandom.hex(8)))
        Studio::Workstations::Runtime.write_state(session);enqueue=true
      end
    end
    StudioWorkstationSaveJob.perform_later(session.id) if enqueue
    render json:present(session),status: :accepted
  end
  def destroy
    session=@access.find!(params[:id]);Studio::Workstations::Runtime.stop(session)
    render json:present(session)
  end
  private
  def set_access
    response.set_header("Cache-Control","private, no-store")
    response.set_header("Referrer-Policy","no-referrer")
    raise LightekCommunity::AccessDenied,"Sign in to use Studio" unless current_user
    site=LightekPwa::SiteContext.resolve(request.host)
    @access=Studio::Workstations::Access.new(user:current_user,site:site)
  end
  def present(session)
    {status:session.expires_at.past? && !%w[stopped failed].include?(session.status) ? "expired" : session.status,error:session.error_message,expires_at:session.expires_at.iso8601,
     saved_asset_id:session.metadata["saved_asset_id"],saved_scene_id:session.metadata["saved_scene_id"],saved_at:session.metadata["saved_at"]}
  end
  def missing = render(json:{error:"Workstation unavailable"},status: :not_found)
  def denied(error) = render(json:{error:error.message},status: :forbidden)
  def invalid(error) = render(json:{error:error.message},status: :unprocessable_entity)
end
