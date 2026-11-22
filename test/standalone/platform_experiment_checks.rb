require_relative 'marketing_copilot_checks'

require ROOT.join('db/migrate/20261122134000_create_lightek_experiments')
CreateLightekExperiments.new.migrate(:up)
ActiveRecord::Schema.define { add_column :lightek_commerce_orders, :created_at, :datetime }
LightekCommerce::Order.reset_column_information
%w[experiment assignment outcome].each { |file| require ROOT.join("app/models/lightek_experiments/#{file}") }
%w[surfaces experience workspace].each { |file| require ROOT.join("app/services/lightek_experiments/#{file}") }
require ROOT.join('app/controllers/dashboard/experiments_controller')
Dashboard::ExperimentsController.prepend_view_path ROOT.join('app/views')
Dashboard::ExperimentsController.layout false

SalesCrmChecks.prepend(Module.new do
  def setup
    [LightekExperiments::Outcome, LightekExperiments::Assignment, LightekExperiments::Experiment].each(&:delete_all)
    super
  end
end)

class PlatformExperimentChecks < MarketingCopilotChecks
  def self.runnable_methods = instance_methods(false).grep(/^test_/).map(&:to_s)

  def workspace = LightekExperiments::Workspace.new(actor: @owner, site: @site)
  def definition(surface = 'commerce_checkout')
    { name: 'Checkout wording', surface: surface, control: 'Pay now', challenger: 'Continue to payment' }
  end

  def experience(site: @site, host: @site.host, headers: {}, jar: @jar ||= {})
    request = Struct.new(:host, :headers) do
      def head? = false
      def ssl? = true
    end.new(host, headers)
    cookies = Struct.new(:signed).new(jar)
    def cookies.signed = @hash_proxy ||= signed_proxy(self[:signed])
    def cookies.signed_proxy(jar)
      Class.new do
        define_method(:[]) { |key| jar[key] }
        define_method(:[]=) { |key, spec| jar[key] = spec.fetch(:value) }
      end.new
    end
    @response_headers = {}
    response = Object.new
    data = @response_headers
    response.define_singleton_method(:set_header) { |key, value| data[key] = value }
    LightekExperiments::Experience.new(site: site, request: request, response: response, cookies: cookies)
  end

  def test_assigns_once_respects_privacy_and_preserves_the_rollout
    row = workspace.start!(definition)
    assert_equal row.id, workspace.start!(definition).id
    assert_raises(ArgumentError) { workspace.start!(definition.merge(challenger: 'Different')) }
    arm_copy = experience.copy(surface: 'commerce_checkout', default: 'Original')
    assert_includes [row.control, row.challenger], arm_copy
    assert_equal 'private, no-store', @response_headers['Cache-Control']
    assert_equal arm_copy, experience.copy(surface: 'commerce_checkout', default: 'Original')
    assert_equal 1, row.assignments.count
    assert_equal 'Original', experience(headers: {'Sec-GPC' => '1'}).copy(surface: 'commerce_checkout', default: 'Original')
    assert_equal 'private, no-store', @response_headers['Cache-Control']
    assert_equal 'Original', experience(host: @foreign_site.host).copy(surface: 'commerce_checkout', default: 'Original')
    assert_equal 'Original', experience(headers: {'Sec-Purpose' => 'prefetch'}, jar: {}).copy(surface: 'commerce_checkout', default: 'Original')
    assert_equal 1, row.assignments.count
    workspace.finish!(row.id, winner: 'challenger')
    assert_equal row.challenger, experience(jar: {}).copy(surface: 'commerce_checkout', default: 'Original')
    assert_equal 1, row.assignments.count
    assert_raises(ArgumentError) { workspace.finish!(row.id, winner: 'control') }
    second = workspace.start!(definition)
    workspace.finish!(second.id, winner: nil)
    assert_equal 'Original', experience(jar: {}).copy(surface: 'commerce_checkout', default: 'Original')
  end

  def test_uses_verified_outcomes_without_recounting_retries
    row = workspace.start!(definition)
    experience.copy(surface: 'commerce_checkout', default: 'Original')
    order = LightekCommerce::Order.create!(site: @site, customer_email: 'sample@example.test')
    foreign = LightekCommerce::Order.create!(site: @foreign_site, customer_email: 'sample@example.test')
    2.times { experience.record('checkout', order) }
    experience.record('checkout', foreign)
    assert_equal 1, LightekExperiments::Outcome.count
    arm = -> { workspace.report(row.id).fetch('arms').find { |entry| entry['visitors'] == 1 } }
    assert_equal({'checkout' => 1, 'checkout_paid' => 0}, arm.call.fetch('outcomes'))
    order.update!(paid_at: Time.current, status: 'paid')
    assert_equal({'checkout' => 1, 'checkout_paid' => 1}, arm.call.fetch('outcomes'))
    assert_equal 100.0, arm.call.dig('rates', 'checkout_paid')
  end

  def test_dashboard_checks_site_scope_and_csrf_and_renders_a_report
    path = dashboard_experiments_path(site_id: @site.id)
    get path, headers: headers
    assert_response :success
    assert_includes response.body, 'Start A/B test'
    assert_raises(ActiveRecord::RecordNotFound) { get path, headers: headers(@other) }
    assert_raises(ActionController::InvalidAuthenticityToken) { post path, params: {experiment: definition}, headers: headers }
    post path, params: {experiment: definition, authenticity_token: token}, headers: headers
    assert_response :see_other
    row = workspace.experiments.sole
    follow_redirect! headers: headers
    assert_includes response.body, 'Checkout paid'
    patch finish_dashboard_experiment_path(row, site_id: @site.id),
      params: {winner: 'control', authenticity_token: token}, headers: headers
    assert_response :see_other
    assert_equal 'control', row.reload.winner
  end

  def test_nevaeh_commands_parse_as_scoped_website_operations
    command = NevaehOs::Command.parse('/website ab_report 12 {"experiment_id":7}')
    assert_equal ['website_marketing', 'ab_report', 12], command.values_at('kind', 'operation', 'site_id')
    assert_equal 7, command.dig('values', 'experiment_id')
  end
end
