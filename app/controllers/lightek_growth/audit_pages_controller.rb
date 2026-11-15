# Internal rendering context only; no routes are exposed for this controller.
module LightekGrowth
  class AuditPagesController < ApplicationController
    helper LightekDesign::StudioHelper
    helper DymondDash::TemplateSchemaHelper
    helper do
      def form_authenticity_token(*) = 'audit-only-not-submittable'
      def csrf_meta_tags = ''.html_safe
    end
  end
end
