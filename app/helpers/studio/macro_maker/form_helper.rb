module Studio
  module MacroMaker
    module FormHelper
      def render_step_fields(operation, step_definition = {}, run_form: false)
        if operation.is_a?(Operation::Thick)
          operation = Serializer.new(command_schema_directory: Rails.root.join("config/studio/command_schemas"))
            .operation_detail(operation)
        end
        operation = operation.with_indifferent_access
        step = step_definition.with_indifferent_access
        safe_join(%w[params inputs].map do |group|
          schema = operation.fetch(group == "params" ? "params_schema" : "inputs_schema")
          fields = schema.fetch("properties").map do |name, spec|
            required = schema.fetch("required").include?(name)
            value = step.fetch(group, {}).fetch(name) { spec["default"] }
            accepted = operation.fetch("accepts")[name] || (spec["studio_type"] == "layer_id" ? ["layer_id"] : [])
            step_field(group, name, spec, value, required, accepted, run_form: run_form)
          end
          next if fields.empty?

          tag.fieldset(safe_join([tag.legend(group == "params" ? "Parameters" : "Inputs"), *fields]))
        end.compact)
      end

      private

      def step_field(group, name, spec, value, required, accepted, run_form:)
        kind = spec["studio_type"] || spec.fetch("type")
        show_binding = !run_form && (accepted.any? || (value.is_a?(Hash) && (value.keys & Recipe::TOKENS).any?))
        label = name.tr("_", " ").sub(/\A./, &:upcase)
        tag.div(class: "macro-field", data: {
          controller: "handle-binding", macro_field: true, group: group, field_name: name, kind: kind,
          required: required.to_s, accepted: accepted.to_json, initial: value.to_json
        }) do
          safe_join([
            tag.div(literal_control(kind, label, spec, value, required, run_form: run_form), data: {handle_binding_target: "literal"}),
            tag.label(safe_join([tag.span("Bind #{label.downcase} to output"),
              tag.select(tag.option("Enter a value", value: ""), data: {binding_select: true,
                handle_binding_target: "select", action: "change->handle-binding#change"})]),
              class: "macro-binding", hidden: !show_binding, data: {binding_row: true}),
            tag.output("", hidden: true, data: {handle_binding_target: "display"})
          ])
        end
      end

      def literal_control(kind, label, spec, value, required, run_form:)
        title = required ? "#{label} (required)" : label
        data = {literal_value: true}
        case kind
        when "point"
          tag.div do
            safe_join([tag.span(title, class: "macro-field-label"), tag.div(class: "macro-point") do
              safe_join(%w[X Y].each_with_index.map do |axis, index|
                tag.label(safe_join([tag.span(axis), number_control(spec.fetch("items"),
                  value.is_a?(Array) ? value[index] : nil, data.merge(axis: index))]))
              end)
            end])
          end
        when "polygon", "any"
          tag.label(safe_join([tag.span(title), tag.textarea(value.nil? ? "" : value.to_json, rows: 3, data: data)]))
        when "color"
          text = value.is_a?(String) ? value : ""
          valid_hex = text.match?(/\A#[0-9a-fA-F]{6}\z/)
          tag.div(class: "macro-color") do
            safe_join([
              tag.label(safe_join([tag.span(title), tag.input(type: "text", value: text, pattern: "#[0-9a-fA-F]{6}",
                data: data)])),
              tag.input(type: "color", value: valid_hex ? text : "#000000", aria: {label: "#{label} picker"},
                data: {color_picker: true})
            ])
          end
        when "layer_id"
          if run_form
            return tag.label(safe_join([tag.span(title), number_control(spec, value, data)]))
          end

          tag.div(safe_join([tag.span(title, class: "macro-field-label"),
            tag.span(value.is_a?(Integer) ? "Layer #{value}" : "Choose a prior layer output", data: {layer_value_label: true}),
            tag.input(type: "hidden", value: value.is_a?(Integer) ? value : nil, data: data)]))
        when "number", "integer"
          tag.label(safe_join([tag.span(title), number_control(spec, value.is_a?(Numeric) ? value : nil, data)]))
        when "string"
          tag.label(safe_join([tag.span(title), tag.input(type: "text", value: value.is_a?(String) ? value : nil,
            minlength: spec["minLength"], maxlength: spec["maxLength"], data: data)]))
        else
          raise ArgumentError, "Unsupported macro maker field type: #{kind}"
        end
      end

      def number_control(spec, value, data)
        tag.input(type: "number", value: value, min: spec["minimum"], max: spec["maximum"],
          step: spec["type"] == "integer" ? 1 : "any", data: data)
      end
    end
  end
end
