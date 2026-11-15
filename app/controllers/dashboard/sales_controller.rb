# frozen_string_literal: true
class Dashboard::SalesController < Dashboard::SettingsHomeController
  skip_before_action :require_settings_operator!
  before_action { head :forbidden unless current_user&.role.in?(%w[super_admin admin white_label client employee]) }
  before_action :set_workspace
  before_action :set_kind, except: :index
  helper_method :record_url
  rescue_from ActiveRecord::RecordInvalid, with: :invalid_record
  rescue_from ActiveRecord::RecordNotUnique do
    redirect_to dashboard_sales_path(site_id: @site.id), alert: 'A matching record was just saved. Search for it and reopen before trying again.'
  end
  rescue_from ActiveRecord::StaleObjectError do
    redirect_to dashboard_sales_path(site_id: @site.id), alert: 'Someone changed this record. Reopen it to review the latest version before saving.'
  end
  rescue_from ArgumentError do |error|
    redirect_to dashboard_sales_path(site_id: @site.id), alert: error.message
  end

  def index
    @tab = params[:tab].to_s.in?(%w[today leads pipeline accounts contacts routing]) ? params[:tab] : 'today'
    raise ActiveRecord::RecordNotFound if @tab == 'routing' && !@manage_routing
    @month = Date.strptime(params[:month].presence || Date.current.strftime('%Y-%m'), '%Y-%m').beginning_of_month
    @owner_id = params[:owner_id].presence
    @owners.find(@owner_id) if @owner_id
    leads = filtered(@workspace.scope('lead'), owner_key: :owner_id)
    deals = filtered(@workspace.scope('opportunity'), owner_key: :owner_id)
    @lead_count = leads.active.count
    @deal_count = deals.open_pipeline.count
    @due_leads = leads.active.where('follow_up_on <= ?', Date.current).order(:follow_up_on).limit(100)
    @due_deals = deals.open_pipeline.where('follow_up_on <= ? OR close_on < ?', Date.current, Date.current).order(:close_on).limit(100)
    @missing_leads = leads.active.where("next_step IS NULL OR next_step = '' OR follow_up_on IS NULL").order(:created_at).limit(100)
    @missing_deals = deals.open_pipeline.where("next_step IS NULL OR next_step = '' OR follow_up_on IS NULL").order(:created_at).limit(100)
    @forecast = LightekSales::Forecast.call(deals, month: @month)
    if @tab == 'pipeline'
      @stage_counts = deals.group(:stage).count
      @pipeline = LightekSales::Opportunity::STAGES.keys.to_h { |stage| [stage, deals.where(stage: stage).includes(:account, :owner).order(:close_on, :id).limit(40)] }
    else
      @records = case @tab
      when 'leads' then leads.includes(:owner).order(updated_at: :desc).limit(200)
      when 'accounts' then filtered(@workspace.scope('account'), owner_key: :owner_id).includes(:owner).order(:name).limit(200)
      when 'contacts' then filtered(@workspace.scope('contact'), owner_key: :sales_owner_id).includes(:sales_account, :sales_owner).order(:email).limit(200)
      when 'routing' then @workspace.scope('routing_rule').includes(:owner).order(:source).limit(200)
      else []
      end
    end
  end

  def new
    @record = @workspace.scope(@kind).new
    @record.close_on = Date.current + 30 if @kind == 'opportunity'
    if params[:account_id].present? && @kind.in?(%w[contact opportunity])
      company = @workspace.find('account', params[:account_id])
      @kind == 'contact' ? @record.sales_account = company : @record.account = company
    end
    @activities = []
    render :show
  end
  def show
    @record = @workspace.find(@kind, params[:id])
    if @kind.in?(%w[account contact])
      key = @kind == 'account' ? :account_id : :contact_id
      @related_deals = @workspace.scope('opportunity').where(key => @record.id).order(updated_at: :desc).limit(50)
      @related_contacts = @workspace.scope('contact').where(sales_account: @record).order(:email).limit(50) if @kind == 'account'
    end
    @activities = LightekSales::Activity.where(site: @site, record: @record).includes(:actor).order(created_at: :desc, id: :desc).limit(100)
  end
  def create
    @record = @workspace.save!(@kind, record_params)
    redirect_to record_url(@kind, @record), notice: 'Saved. Add a next step and follow-up date to keep the sale moving.', status: :see_other
  end
  def update
    @record = @workspace.save!(@kind, record_params, id: params[:id], lock_version: params.require(:record)[:lock_version])
    redirect_to record_url(@kind, @record), notice: 'Sales record updated.', status: :see_other
  end
  def convert
    opportunity = @workspace.convert!(params[:id], params.require(:conversion).permit(:name, :amount, :amount_cents, :currency, :close_on), lock_version: params.require(:conversion)[:lock_version])
    redirect_to record_url('opportunity', opportunity), notice: 'Lead converted. Company and contact records were reused where possible.', status: :see_other
  end
  def activity
    @workspace.activity!(@kind, params[:id], activity_kind: params.require(:activity)[:kind], body: params.require(:activity)[:body])
    redirect_to record_url(@kind, @workspace.find(@kind, params[:id])), notice: 'Activity logged.', status: :see_other
  end

  private
  def set_workspace
    @sites = LightekSales::Access.sites_for(current_user).order(:name)
    @site = params[:site_id].present? ? @sites.find(params[:site_id]) : @sites.first!
    @workspace = LightekSales::Workspace.new(actor: current_user, site: @site)
    @owners = LightekSales::Access.owners_for(@site).order(:email_address)
    @accounts = @workspace.scope('account').order(:name)
    @contacts = @workspace.scope('contact').order(:email)
    @manage_routing = LightekAgency::Access.manage_members?(current_user, @site)
    @commerce_access = LightekSettings::WebsiteIdentity.sites_for(current_user).exists?(id: @site.id)
  end
  def set_kind
    @kind = action_name == 'convert' ? 'lead' : params[:kind].to_s
    raise ActiveRecord::RecordNotFound unless LightekSales::Workspace::RECORDS.key?(@kind)
    raise ActiveRecord::RecordNotFound if @kind == 'routing_rule' && !@manage_routing
  end
  def record_params = params.require(:record).permit(*LightekSales::Workspace::FIELDS.fetch(@kind))
  def record_url(kind, record) = dashboard_sales_record_path(kind: kind, id: record.id, site_id: @site.id)
  def filtered(scope, owner_key:)
    scope = scope.where(owner_key => @owner_id) if @owner_id
    query = params[:q].to_s.strip.first(160)
    if query.present?
      column = scope.klass == LightekMarketing::Contact ? 'email' : 'name'
      scope = scope.where("LOWER(#{column}) LIKE ?", "%#{ActiveRecord::Base.sanitize_sql_like(query.downcase)}%")
    end
    scope
  end
  def invalid_record(error)
    @record = error.record
    # Conversion errors may belong to a company/contact/deal; display the real
    # validation error without presenting that record as an editable lead.
    if action_name.in?(%w[create update])
      @activities = []
      flash.now[:alert] = @record.errors.full_messages.to_sentence
      render :show, status: :unprocessable_entity
    else
      redirect_to dashboard_sales_path(site_id: @site.id), alert: @record.errors.full_messages.to_sentence
    end
  end
end
