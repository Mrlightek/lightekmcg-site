get '/dashboard/website-audits', to: 'dashboard/website_audits#index', as: :dashboard_website_audits
post '/dashboard/website-audits', to: 'dashboard/website_audits#create'
post '/dashboard/website-audits/findings/:finding_id/preview', to: 'dashboard/website_audits#prepare_fix', as: :prepare_website_audit_fix
patch '/dashboard/website-audits/findings/:id/dismiss', to: 'dashboard/website_audits#dismiss', as: :dismiss_website_audit_finding
post '/dashboard/website-audits/fixes/:id/apply', to: 'dashboard/website_audits#apply_fix', as: :apply_website_audit_fix
post '/dashboard/website-audits/fixes/:id/rollback', to: 'dashboard/website_audits#rollback_fix', as: :rollback_website_audit_fix
post '/dashboard/website-audits/fixes/:id/recheck', to: 'dashboard/website_audits#recheck_fix', as: :recheck_website_audit_fix
