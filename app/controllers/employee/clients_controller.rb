# frozen_string_literal: true
module Employee
  class ClientsController < Employee::ApplicationController
    def index
      authorize! :read, User
      @clients = User.where(role: "client").order(:last_name, :first_name)
    end

    def show
      @client = User.where(role: "client").find(params[:id])
      authorize! :read, @client

      @invoices         = @client.invoices.order(created_at: :desc)
      @subscription     = @client.subscription
      @linked_accounts  = @client.linked_accounts.active
      @notifications    = defined?(DymondDash::Notification) ?
                             DymondDash::Notification.for_recipient(@client).recent.limit(10) : []
    end
  end
end
