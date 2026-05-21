class PagesController < ApplicationController
    skip_before_action :require_authentication
    skip_authorization_check
  
    def home
    end
  
    def about
    end
  
    def services
    end
  
    def pricing
    end
  
    def contact
    end
  end