# frozen_string_literal: true
module Employee
  class NevaehLessonsController < Employee::ApplicationController
    before_action :authorize_lessons!
    before_action :set_lesson, only: %i[edit update]

    def index
      @lessons = DymondKb::Article.where("metadata ->> 'nevaeh_procedure' IS NOT NULL").order(:id)
      @available = NevaehIntelligences::KnowledgeProcedures.available
    end

    def enable_central
      NevaehIntelligences::ReportingEnrollment.enable!(actor: current_user, base_url: request.base_url)
      redirect_to employee_nevaeh_lessons_path, notice: "Central support enabled. Gatekeeper is connecting eligible customer installations."
    rescue NevaehIntelligences::WorkOrder::Invalid, Gatekeeper::Fleet::Rollouts::Invalid => error
      redirect_to employee_nevaeh_lessons_path, alert: error.message
    end

    def edit
      @contract = @lesson.metadata.fetch("nevaeh_procedure")
    end

    def update
      values = params.require(:lesson).permit(:label, :body, :acceptance_criteria, :status).to_h
      @lesson.with_lock do
        metadata = @lesson.metadata.to_h.deep_stringify_keys
        contract = metadata.fetch("nevaeh_procedure").merge("label" => values.fetch("label"),
          "acceptance_criteria" => values.fetch("acceptance_criteria").lines.map(&:strip).reject(&:empty?))
        raise NevaehIntelligences::KnowledgeProcedures::Invalid, "Choose available or withdrawn" unless %w[available withdrawn].include?(values["status"])
        raise NevaehIntelligences::KnowledgeProcedures::Invalid, "Write the complete lesson" unless values["body"].to_s.strip.length.between?(20, 64000)
        # Validate the registered worker/input/verifier contract before changing
        # availability. Withdrawing knowledge never registers another executor.
        draft = Struct.new(:id, :metadata, :body).new(@lesson.id, {"nevaeh_procedure" => contract.merge("status" => "available")}, values["body"])
        NevaehIntelligences::KnowledgeProcedures.definition(draft)
        contract["status"] = values["status"]
        metadata["nevaeh_procedure"] = contract
        history = metadata.fetch("nevaeh_lesson_revisions", [])
        history << {"actor_id" => current_user.id, "changed_at" => Time.current.iso8601,
          "previous_procedure_sha256" => NevaehIntelligences::TicketApproval.fingerprint({"contract" => @lesson.metadata.fetch("nevaeh_procedure"), "body" => @lesson.body.to_s}),
          "previous_body_sha256" => Digest::SHA256.hexdigest(@lesson.body.to_s), "status" => values["status"]}
        metadata["nevaeh_lesson_revisions"] = history.last(100)
        @lesson.update!(title: values["label"], body: values["body"], metadata: metadata)
      end
      redirect_to employee_nevaeh_lessons_path, notice: "Lesson saved. Existing work retains its previous revision and requires review if the lesson changed."
    rescue NevaehIntelligences::WorkOrder::Invalid, ActiveRecord::RecordInvalid => error
      @contract = @lesson.metadata.fetch("nevaeh_procedure")
      @lesson.errors.add(:base, error.message)
      render :edit, status: :unprocessable_entity
    end

    private

    def authorize_lessons!
      authorize! :execute_nevaeh, Marlon::Ticket
    end

    def set_lesson
      @lesson = DymondKb::Article.where("metadata ->> 'nevaeh_procedure' IS NOT NULL").find(params[:id])
    end
  end
end
