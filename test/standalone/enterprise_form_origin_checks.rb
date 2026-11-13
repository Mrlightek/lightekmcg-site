# Regression for the production 422: browser form origins and CSRF stay enforced.
require_relative 'enterprise_connect_mfa_checks'
class EnterpriseFormOriginChecks < EnterpriseHttpChecks
  def self.runnable_methods = super.grep(/test_origin_/)
  def setup
    super
    https!
    @controllers = [IdentitySecurityController, IdentityChallengesController, ConnectManagementController, Dashboard::AccountingController]
    @controllers.each do |controller|
      controller.allow_forgery_protection = true
      controller.forgery_protection_origin_check = true
    end
  end
  def teardown
    @controllers.each do |controller|
      controller.allow_forgery_protection = false
      controller.forgery_protection_origin_check = false
    end
    super
  end
  def token
    Nokogiri::HTML(response.body).at_css('input[name="authenticity_token"]')['value']
  end
  def start_enrollment
    LightekIdentity::OrganizationPolicy.create!(employer: @employer, mfa_required: true)
    post session_path, params: {email_address: @employer.email_address, password: 'fixture-password'}
    assert_redirected_to identity_security_path
    get identity_security_path
    assert_response :success
    assert_equal 'same-origin', response.headers['Referrer-Policy']
    assert_equal 'no-store', response.headers['Cache-Control']
    token
  end
  def test_origin_enrollment_and_confirmation_with_real_csrf
    csrf = start_enrollment
    post enroll_identity_security_path, params: {password: 'fixture-password', authenticity_token: csrf}, headers: {'Origin' => 'https://example.test'}
    assert_response :success
    assert_equal 'same-origin', response.headers['Referrer-Policy']
    assert_includes response.body, 'Scan with your authenticator'
    if (directory = ENV['MFA_QR_CAPTURE_DIR'])
      FileUtils.mkdir_p(directory)
      File.write(File.join(directory, 'enroll.html'), response.body)
    end
    factor = LightekIdentity::Factor.find_by!(user: @employer)
    secret = LightekIdentity::Sealed.open(factor.secret_box, context: "mfa:#{@employer.id}")['secret']
    post confirm_identity_security_path, params: {otp: LightekIdentity::Mfa.code(secret, Time.current.to_i / 30), authenticity_token: token}, headers: {'Origin' => 'https://example.test'}
    assert_response :success
    assert_includes response.body, 'Save your recovery codes'
    refute @employer.sessions.last.mfa_enrollment_only?
    assert LightekIdentity::Mfa.fresh?(@employer.sessions.last)
    get '/after-login'
    assert_response :success
  end
  def test_origin_null_origin_reproduces_the_old_browser_failure
    csrf = start_enrollment
    assert_raises(ActionController::InvalidAuthenticityToken) do
      post enroll_identity_security_path, params: {password: 'fixture-password', authenticity_token: csrf}, headers: {'Origin' => 'null'}
    end
    refute LightekIdentity::Factor.exists?(user: @employer)
  end
  def test_origin_cross_site_or_missing_token_cannot_enroll
    csrf = start_enrollment
    assert_raises(ActionController::InvalidAuthenticityToken) do
      post enroll_identity_security_path, params: {password: 'fixture-password', authenticity_token: csrf}, headers: {'Origin' => 'https://other.test'}
    end
    assert_raises(ActionController::InvalidAuthenticityToken) do
      post enroll_identity_security_path, params: {password: 'fixture-password'}, headers: {'Origin' => 'https://example.test'}
    end
    refute LightekIdentity::Factor.exists?(user: @employer)
  end
  def test_origin_wrong_password_is_an_explained_redirect_not_a_422
    csrf = start_enrollment
    post enroll_identity_security_path, params: {password: 'wrong', authenticity_token: csrf}, headers: {'Origin' => 'https://example.test'}
    assert_redirected_to identity_security_path
    assert_equal 'Enter your current password', flash[:alert]
    refute LightekIdentity::Factor.exists?(user: @employer)
  end
end
