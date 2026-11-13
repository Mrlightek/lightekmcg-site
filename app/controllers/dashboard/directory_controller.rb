class Dashboard::DirectoryController < Dashboard::SettingsHomeController
  skip_before_action :require_settings_operator!
  protect_from_forgery with: :exception
  before_action :context!
  rescue_from LightekPeople::Access::Denied, Gatekeeper::Hosting::Access::Denied, with: ->(_) { head :forbidden }
  rescue_from ActiveRecord::RecordNotFound, with: ->(_) { head :not_found }
  rescue_from ActiveRecord::RecordInvalid, ArgumentError, with: ->(error) { redirect_to dashboard_directory_path(employer_id: @employer&.id), alert: error.message }
  def index
    @organization_policy = LightekIdentity::OrganizationPolicy.find_by(employer: @employer)
    @connection = LightekIdentity::Connection.find_by(employer: @employer)
    @realm = LightekIdentity::Realm.find_by(employer: @employer)
    @members = LightekPeople::Employment.where(employer: @employer).includes(:worker)
    @departments = LightekPeople::Department.where(employer: @employer)
    @grants = @access.directory_admin? ? LightekIdentity::ResourceGrant.where(employer: @employer).includes(:subject,:resource) : []
    @nodes = @access.directory_admin? ? GatekeeperNode.where(owner_type: 'User', owner_id: @employer.id) : GatekeeperNode.where(owner_type: 'User',owner_id: @employer.id,id: LightekIdentity::Permissions.ids(current_user,'GatekeeperNode','read'))
    @applications = @access.directory_admin? ? GatekeeperHostedApplication.where(owner: @employer) : GatekeeperHostedApplication.where(owner: @employer,id: LightekIdentity::Permissions.ids(current_user,'GatekeeperHostedApplication','read'))
    @bindings = @realm ? @realm.node_bindings.includes(:gatekeeper_node) : []
  end
  def policy
    it_admin!
    record = LightekIdentity::OrganizationPolicy.find_or_initialize_by(employer: @employer)
    record.update!(mfa_required: params[:mfa_required] == '1')
    audit!('organization_mfa_policy_changed',record)
    back!('Company MFA policy saved. Financial access and privileged staff retain mandatory protection.')
  end
  def connection
    it_admin!
    values = params.require(:connection).permit(:slug,:issuer,:authorization_endpoint,:token_endpoint,:jwks_uri,:client_id,:enabled)
    @employer.with_lock do
      record = LightekIdentity::Connection.find_or_initialize_by(employer: @employer)
      if record.persisted? && record.issuer != values[:issuer]
        raise ArgumentError, 'Create a reviewed identity migration before changing an issuer with linked subjects' if LightekIdentity::Subject.exists?(connection: record)
      end
      record.assign_attributes(values)
      record.save!
      if params[:connection][:client_secret].present?
        LightekVault::Service.store!(name: "Organization SSO · #{@employer.id}", slug: LightekIdentity::Oidc.slug(record),
          payload: {'client_secret'=>params[:connection][:client_secret]}, provider: 'oidc', purpose: 'organization_sso',
          access_policy: {'consumers'=>[LightekIdentity::Oidc.name], 'purposes'=>['organization_sso']}, requested_by: current_user.email_address)
      end
      audit!('organization_sso_configured',record)
    end
    back!('Organization sign-in saved')
  end
  def grant
    it_admin!
    subject_key = params[:subject_key].to_s.split(':',2)
    resource_key = params[:resource_key].to_s.split(':',2)
    params[:subject_type], params[:subject_id] = subject_key if subject_key.length == 2
    params[:resource_type], params[:resource_id] = resource_key if resource_key.length == 2
    type = params[:subject_type].to_s
    subject = case type
    when 'employment' then LightekPeople::Employment.where(employer: @employer).find(params[:subject_id])
    when 'department' then LightekPeople::Department.where(employer: @employer).find(params[:subject_id])
    else raise ArgumentError, 'Choose an employee membership or department'
    end
    resource = case params[:resource_type]
    when 'server' then GatekeeperNode.where(owner_type: 'User', owner_id: @employer.id).find(params[:resource_id])
    when 'application' then GatekeeperHostedApplication.where(owner: @employer).find(params[:resource_id])
    else raise ArgumentError, 'Choose a server or application'
    end
    @employer.with_lock do
      record = LightekIdentity::ResourceGrant.find_or_create_by!(employer: @employer, subject: subject, resource: resource, permission: params[:permission])
      audit!('directory_permission_granted',record)
    end
    back!('Permission granted; directory login changes are queued for joined servers')
  end
  def revoke
    it_admin!
    @employer.with_lock do
      record = LightekIdentity::ResourceGrant.where(employer: @employer).find(params[:id])
      audit!('directory_permission_revoked',record)
      record.destroy!
    end
    back!('Permission revoked; active application checks change immediately and server login reconciliation is queued')
  end
  def realm
    it_admin!
    @employer.with_lock do
      record = LightekIdentity::Realm.find_or_initialize_by(employer: @employer)
      values = params.require(:realm).permit(:domain,:enabled,:auto_join)
      raise ArgumentError, 'A joined realm cannot change domain in place' if record.persisted? && record.domain != values[:domain] && record.node_bindings.exists?
      record.assign_attributes(values)
      record.save!
      if params[:realm][:join_password].present?
        LightekVault::Service.store!(name: "Directory join · #{@employer.id}", slug: "directory-realm-#{@employer.id}",
          payload: {'username'=>params[:realm][:join_user], 'password'=>params[:realm][:join_password]}, purpose: 'directory_join', provider: 'active_directory',
          access_policy: {'consumers'=>['DirectoryNodeSyncJob'], 'purposes'=>['directory_join']}, requested_by: current_user.email_address)
      end
      audit!('directory_realm_configured',record)
    end
    DirectorySyncJob.perform_later(@employer.id)
    back!('Realm settings saved; joined server allowlists will reconcile')
  end
  def join
    it_admin!
    realm = LightekIdentity::Realm.find_by!(employer: @employer, enabled: true)
    node = GatekeeperNode.where(owner_type: 'User', owner_id: @employer.id).find(params[:id])
    binding = LightekIdentity::NodeBinding.find_or_create_by!(realm: realm, gatekeeper_node: node)
    DirectoryNodeSyncJob.perform_later(binding.id)
    audit!('directory_join_requested',binding)
    back!('Domain join / permission reconciliation queued')
  end
  def member
    it_admin!
    @employer.with_lock do
      record = LightekPeople::Employment.where(employer: @employer).find(params[:id])
      values = params.require(:membership).permit(:directory_principal, :department_id)
      record.assign_attributes(values)
      record.save!
      audit!('it_directory_membership_saved',record)
    end
    back!('Directory identity and department assignment saved; server allowlists will reconcile')
  end
  def retry_application
    app = GatekeeperHostedApplication.where(owner: @employer).find(params[:id])
    LightekIdentity::Permissions.application!(current_user,app,'manage')
    Gatekeeper::Hosting::Applications.retry!(actor: current_user,app: app)
    back!('Existing application setup retry queued')
  end
  private
  def context!
    response.headers['Cache-Control'] = 'no-store'
    head(:forbidden) and return if Current.session&.connect_delegation.present?
    @employers = LightekPeople::Access.employers_for(current_user)
    @employer = params[:employer_id].present? ? @employers.find(params[:employer_id]) : @employers.first
    return redirect_to(dashboard_people_path) unless @employer
    @access = LightekPeople::Access.new(actor: current_user,employer: @employer)
    LightekPeople::StarterDepartments.ensure!(@employer) if @access.directory_admin?
  end
  def it_admin!
    @access.require!(:directory)
    raise LightekPeople::Access::Denied unless current_user.authenticate(params[:password].to_s) && LightekIdentity::Mfa.fresh?(Current.session)
  end
  def back!(notice) = redirect_to(dashboard_directory_path(employer_id: @employer.id),notice: notice,status: :see_other)
  def audit!(action,record) = LightekPeople::AuditEvent.record!(employer: @employer,actor: current_user,action: action,record: record)
end
