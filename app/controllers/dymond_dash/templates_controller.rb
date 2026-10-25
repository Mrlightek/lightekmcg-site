# frozen_string_literal: true
module DymondDash
  # Presentation templates: pick which one skins the public site (non-destructive —
  # only changes the look), and create/edit template value bundles.
  class TemplatesController < ApplicationController
    helper DymondDash::TemplateSchemaHelper
    before_action :set_site
    before_action :set_template, only: %i[edit update destroy]

    def index
      @templates = DymondSite::SiteTemplate.order(:name)
      @active_id = @site.active_template_id
    end

    # Non-destructive: just point the site at this template.
    def apply
      t = DymondSite::SiteTemplate.find(params[:id])
      @site.update!(active_template: t)
      redirect_to dymond_dash.templates_path, notice: "Now using “#{t.name}”. Your content is unchanged."
    end

    def new
      @template = DymondSite::SiteTemplate.new(settings: default_settings)
    end

    def create
      @template = DymondSite::SiteTemplate.new(template_params)
      if @template.save
        redirect_to dymond_dash.templates_path, notice: "Template created."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit; end

    def update
      if @template.update(template_params)
        redirect_to dymond_dash.templates_path, notice: "Template updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      if @template.preset?
        redirect_to dymond_dash.templates_path, alert: "Preset templates can't be deleted."
      else
        @template.destroy
        redirect_to dymond_dash.templates_path, notice: "Template deleted."
      end
    end

    private

    def set_site     = (@site = DymondSite::Site.first)
    def set_template = (@template = DymondSite::SiteTemplate.find(params[:id]))

    def default_settings
      { "tokens" => { "color_bg" => "#0d0f14", "color_text" => "#e8e8ee",
        "color_primary" => "#4c8bf5", "color_text_muted" => "#8a8a99",
        "font_sans" => "system-ui, sans-serif" },
        "nav_layout" => "left", "footer_style" => "columns" }
    end

    # name/description are columns; settings comes in as a JSON string we parse.
    def template_params
      t = params.fetch(:template, {}).permit(
        :name, :description, :color_bg, :color_text, :color_primary,
        :color_text_muted, :font_sans, :font_heading, :font_mono, :nav_layout, :footer_style, :logo_id
      ).to_h
      { "name" => t["name"], "description" => t["description"],
        "settings" => DymondDash::TemplateSettingsAssembler.build(t) }
    end
  end
end
