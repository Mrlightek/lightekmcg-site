# Real MFA requests and branded auth layout, using the enterprise fixture DB.
require_relative '../../app/services/lightek_agency/package_policy'
require_relative 'enterprise_onboarding_checks'
IdentityChallengesController.helper(Module.new do
  def stylesheet_link_tag(*sources, **)
    safe_join(sources.select { |source| source.to_s.start_with?('/lightek/auth-verification.css') }.map { |source| tag.link(rel: 'stylesheet', href: source) })
  end
end)
class IdentityVerificationDesignChecks < EnterpriseHttpChecks
  def self.runnable_methods = super.grep(/^test_verification_/)
  def setup
    super
    https!
    IdentityChallengesController.layout 'auth'
    IdentityChallengesController.allow_forgery_protection = true
    IdentityChallengesController.forgery_protection_origin_check = true
  end
  def teardown
    IdentityChallengesController.layout false
    IdentityChallengesController.allow_forgery_protection = false
    IdentityChallengesController.forgery_protection_origin_check = false
    super
  end
  def begin_challenge
    @seed = LightekIdentity::Mfa.begin!(@employer)
    @recovery = LightekIdentity::Mfa.verify!(@employer, LightekIdentity::Mfa.code(@seed, Time.current.to_i/30), enrolling: true)
    post session_path, params: {email_address: @employer.email_address, password: 'fixture-password'}
    assert_redirected_to identity_challenge_path
    assert_equal 0, @employer.sessions.count
    get identity_challenge_path
    assert_response :success
  end
  def csrf = Nokogiri::HTML(response.body).at_css('input[name="authenticity_token"]')['value']
  def capture(name)
    return unless (directory = ENV['MFA_QR_CAPTURE_DIR'])
    FileUtils.mkdir_p(directory)
    File.write(File.join(directory, name), response.body)
  end
  def test_verification_branded_page_has_one_code_field_and_no_setup_secrets
    begin_challenge
    page = Nokogiri::HTML(response.body)
    assert_equal 1, page.css('main.auth-verification').size
    assert_equal 'Confirm it’s you.', page.at_css('h1').text
    assert_includes page.at_css('title').text, 'Lightek'
    assert page.at_css('link[href^="/lightek/auth-verification.css"]'), 'page stylesheet is loaded by auth layout'
    input = page.at_css('input[name="otp"]')
    assert_equal 'one-time-code', input['autocomplete']
    assert_nil input['pattern'], 'recovery codes must not be restricted to six digits'
    assert_nil input['maxlength'], 'full recovery codes must fit'
    assert_nil input['value'], 'never echo an attempted verification code'
    assert page.at_css("label[for='#{input['id']}']")
    assert_includes page.at_css('.verification-destination').text, 'example.test'
    assert_equal 'no-store', response.headers['Cache-Control']
    assert_equal 'same-origin', response.headers['Referrer-Policy']
    refute_includes response.body, @seed
    @recovery.each { |code| refute_includes response.body, code }
    capture('verification.html')
  end
  def test_verification_invalid_code_is_accessible_and_does_not_create_a_session
    begin_challenge
    post identity_challenge_path, params: {otp: 'bad-code', authenticity_token: csrf}, headers: {'Origin'=>'https://example.test'}
    assert_redirected_to identity_challenge_path
    get identity_challenge_path
    assert_response :success
    page = Nokogiri::HTML(response.body)
    assert page.at_css('[role="alert"]')
    assert_equal 'true', page.at_css('input[name="otp"]')['aria-invalid']
    assert_includes page.at_css('input[name="otp"]')['aria-describedby'], 'verification-error'
    refute_includes response.body, 'value="bad-code"'
    assert_equal 0, @employer.sessions.count
    capture('verification-error.html')
  end
  def test_verification_fresh_authenticator_code_still_completes_sign_in
    begin_challenge
    post identity_challenge_path, params: {otp: LightekIdentity::Mfa.code(@seed, Time.current.to_i/30+1), authenticity_token: csrf}, headers: {'Origin'=>'https://example.test'}
    assert_response :redirect
    assert LightekIdentity::Mfa.fresh?(@employer.sessions.last)
  end
  def test_verification_recovery_code_still_works_only_once
    begin_challenge
    code = @recovery.first
    post identity_challenge_path, params: {otp: code, authenticity_token: csrf}, headers: {'Origin'=>'https://example.test'}
    assert_response :redirect
    assert LightekIdentity::Mfa.fresh?(@employer.sessions.last)
    assert_raises(LightekIdentity::Mfa::Invalid) { LightekIdentity::Mfa.verify!(@employer, code) }
  end
  def test_verification_requires_a_pending_challenge
    get identity_challenge_path
    assert_redirected_to new_session_path
    refute_includes response.body, 'name="otp"'
  end
  def test_verification_rejects_cross_origin_submission
    begin_challenge
    assert_raises(ActionController::InvalidAuthenticityToken) do
      post identity_challenge_path, params: {otp: @recovery.first, authenticity_token: csrf}, headers: {'Origin'=>'https://other.test'}
    end
    assert_equal 0, @employer.sessions.count
  end
  def test_verification_expired_mfa_session_returns_to_the_new_screen
    begin_challenge
    post identity_challenge_path, params: {otp: LightekIdentity::Mfa.code(@seed, Time.current.to_i/30+1), authenticity_token: csrf}, headers: {'Origin'=>'https://example.test'}
    assert_response :redirect
    @employer.sessions.last.update!(mfa_verified_at: 13.hours.ago)
    get '/after-login'
    assert_redirected_to identity_challenge_path
    get identity_challenge_path
    assert_response :success
    assert_includes response.body, 'Confirm it’s you.'
  end
end
