# frozen_string_literal: true
class SupportTicketTemplatesController < ::DymondDash::ApplicationController
  before_action :authorize_templates!
  before_action :set_template, only: %i[edit update destroy]

  def index
    @templates = NevaehTicketTemplate.for_user(current_user).order(:name, :id)
  end

  def new
    @template = NevaehTicketTemplate.new
    prepare_form
  end

  def create
    @template = NevaehTicketTemplate.new(user: current_user, name: params.dig(:nevaeh_ticket_template, :name), sections: sections_params)
    if @template.save
      redirect_to support_ticket_templates_path, notice: 'Ticket template saved.'
    else
      prepare_form
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    prepare_form
  end

  def update
    if @template.update(name: params.dig(:nevaeh_ticket_template, :name), sections: sections_params)
      redirect_to support_ticket_templates_path, notice: 'Ticket template updated.'
    else
      prepare_form
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @template.destroy!
    redirect_to support_ticket_templates_path, notice: 'Ticket template deleted. Previously submitted tickets are preserved.'
  end

  private

  def authorize_templates!
    authorize! :create, Marlon::Ticket
  end

  def set_template
    # Templates and custom values stay private to their creator on this instance.
    @template = NevaehTicketTemplate.for_user(current_user).find(params[:id])
  end

  def sections_params
    params.fetch(:structured_ticket, ActionController::Parameters.new).permit(sections: {}).fetch(:sections, {}).to_h.values
  end

  def prepare_form
    @editing_ticket_template = true
    @structured_values = {'sections' => @template.sections.to_a.each_with_index.to_h { |row, index| [index.to_s, row] }}
    @structured_sites = LightekSettings::WebsiteIdentity.sites_for(current_user).order(:name).limit(200)
  end
end
