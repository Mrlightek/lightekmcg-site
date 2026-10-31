# Isolated Rails protocol + workspace controller/view harness. Session login and
# DymondDash base controller are fixtures; native authentication, private engines,
# PostgreSQL concurrency and live SMTP acceptance remain host integration checks.
source = File.expand_path("../..", __dir__)
require "#{source}/test/support/lightek_mail_fixture"
module DymondDash
  class ApplicationController < ActionController::Base
    prepend_view_path File.expand_path("../../app/views", __dir__)
    helper_method :current_user
    def current_user = User.find(session[:fixture_user_id])
  end
end
class FixtureSessionsController < ActionController::Base
  def create
    session[:fixture_user_id] = User.find_by!(email_address: params[:email_address]).id
    redirect_to '/dashboard/mail'
  end
end
routes = File.read("#{source}/config/routes.rb").split('scope "/dashboard/mail", controller: "dashboard/mail_studio" do', 2).last.split('get "/dashboard/live"', 2).first
Rails.application.routes.draw do
  post '/session', to: 'fixture_sessions#create'
  instance_eval('scope "/dashboard/mail", controller: "dashboard/mail_studio" do' + routes)
end
require "#{source}/test/integration/lightek_mail_test"

require "#{source}/test/integration/lightek_mail_conversations_test"
