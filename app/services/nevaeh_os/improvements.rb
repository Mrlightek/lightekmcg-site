module NevaehOs
  module Improvements
    module_function
    def authorize!(actor,operation)
      Language.authorize!(actor)
      raise ArgumentError,'Choose gaps, corpus or language_check' unless %w[gaps corpus language_check].include?(operation)
    end
    def perform!(actor,operation)
      authorize!(actor,operation)
      case operation
      when 'corpus'
        build=NevaehIntelligences::Manuals.request!(actor:actor)
        {'manual_build_id'=>build.id,'status'=>build.status,'text'=>'Installed manuals are being imported into draft training batches and language bindings. Review them before activation.'}
      when 'gaps'
        catalog=Guide.catalog(actor:actor)
        areas=PageContext.coverage(actor,catalog:catalog)
        gaps=catalog.select { |row| row[:availability]!='connected' || row[:coverage]=='schema_needed' }.map { |row| row.slice(:key,:title,:availability,:coverage,:topic) }
        ticket=nil
        if gaps.any? || areas.any? { |area| area[:connected]==0 }
          ticket=Marlon::Ticket.create!(submitted_by:actor,title:'Expand Nevaeh executable capability coverage',description:"Capability coverage audit. Implement the missing adapter/schema and its acceptance verifier before claiming execution support.\n"+JSON.pretty_generate({'capabilities'=>gaps.first(100),'page_areas'=>areas}),category:Marlon::TicketCategories.ids.first,priority:'medium',urgency:5,status:'open')
        end
        {'status'=>'completed','page_areas'=>areas,'gaps'=>gaps.first(100),'total_gaps'=>gaps.size,'ticket_id'=>ticket&.id,'text'=>"#{gaps.size} capability/schema gaps found. #{ticket ? 'An engineering ticket records the first 100 findings.' : 'No registered coverage gaps found.'} This does not certify all application features."}
      when 'language_check'
        checks=NevaehLanguageBinding.where(status:'active').order(:id).limit(500).map do |binding|
          begin
            Language.sources!(binding);Language.available!(binding.command_template,actor:actor)
            raise ArgumentError,'Action contract changed' unless binding.contract_sha256==Language.contract_fingerprint(binding.command_template,actor:actor)
            {id:binding.id,name:binding.name,passed:true}
          rescue ArgumentError,ActiveRecord::RecordNotFound=>error
            {id:binding.id,name:binding.name,passed:false,error:error.message}
          end
        end
        total=NevaehLanguageBinding.where(status:'active').count
        passed=checks.all? { |row| row[:passed] } && checks.size==total
        {'success'=>passed,'status'=>passed ? 'completed' : 'failed','checks'=>checks,'checked'=>checks.size,'total'=>total,'text'=>"Checked #{checks.size} of #{total} active phrase source/action contracts (maximum 500 per audit). This checks contract validity, not unrestricted language understanding."}
      end
    end
  end
end
