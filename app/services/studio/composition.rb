require_relative "operation_catalog"
require_relative "composition_validator"
require_relative "composition_compiler"

module Studio
  class Composition
    class Invalid < ArgumentError
      attr_reader :errors

      def initialize(errors)
        @errors = errors.freeze
        super(errors.map { |error| error.fetch(:detail) }.join("; "))
      end
    end

    def self.from_record(record, catalog_options: {})
      metadata = record.body.fetch("composition")
      new(site: record.site, definition: metadata.fetch("definition"), catalog_options: catalog_options,
        thick_only: metadata.fetch("thick_only", false))
    end

    attr_reader :warnings

    def initialize(site:, definition:, catalog_options: {}, thick_only: false)
      @site = site
      @definition = JSON.parse(JSON.generate(definition))
      @catalog_options = catalog_options.dup
      @thick_only = thick_only
    end

    def to_recipe
      body, references, _, steps = compile
      @warnings = steps.filter_map do |step|
        next if step.operation.runnable?

        error(step.index, step.operation.id, :unavailable_operation,
          "Operation #{step.operation.id} is not currently runnable because its engine CLI is unavailable")
      end
      Recipe.new(body, before_run: ->(ancestry) { verify!(body, references, ancestry: ancestry) })
    end

    def save!(published: false, owner: nil)
      body, references, handles = compile
      exposes = body.fetch("parameters").keys.map { |name| {"parameter" => name} } +
        body.fetch("inputs").keys.map { |name| {"input" => name} }
      operation = {
        "id" => @definition.fetch("id"), "display_name" => body.fetch("name"),
        "surface" => @definition.fetch("surface"), "description" => @definition.fetch("description"),
        "recipe" => body, "exposes" => exposes, "returns" => handles,
        "composition" => {"definition" => @definition, "references" => references, "thick_only" => @thick_only}
      }
      attributes = {site: @site, operation_id: operation.fetch("id"), surface: operation.fetch("surface"),
        version: body.fetch("version"), body: operation, published: published}
      attributes[:owner_id] = owner.id if owner
      OperationRecord.create!(attributes)
    end

    def verify!(stored_recipe, stored_references, ancestry: [])
      body, references, = compile(ancestry: ancestry)
      mismatches = references.each_index.filter_map do |index|
        next if references[index] == stored_references[index]

        id = references[index].fetch("id")
        error(index, id, :invalid_binding, "Catalog operation #{id} changed since compilation")
      end
      if (body != stored_recipe || references.length != stored_references.length) && mismatches.empty?
        mismatches << error(nil, nil, :invalid_binding, "Compiled recipe changed since it was saved")
      end
      raise Invalid.new(mismatches) unless mismatches.empty?

      true
    end

    private

    def compile(ancestry: [])
      begin
        header = validate_header!
      rescue ArgumentError, KeyError => failure
        raise Invalid.new([error(nil, nil, :invalid_binding, failure.message)])
      end

      identity = [@site.id, @definition.fetch("id"), @definition.fetch("surface")]
      if ancestry.include?(identity)
        raise Invalid.new([error(nil, identity[1], :invalid_binding, "Composition dependency cycle: #{identity[1]}")])
      end

      options = @thick_only ? @catalog_options.merge(include_thin: false, match_display_names: false) : @catalog_options
      catalog = OperationCatalog.for_site(@site, **options)
      validator = CompositionValidator.new(@definition, catalog, ancestry: ancestry + [identity])
      steps, handles = validator.validate!
      engine = steps.first.operation.engine
      body = header.merge("engine" => engine, "steps" => CompositionCompiler.new(steps, handles.keys).commands)
      begin
        Recipe.new(body)
      rescue ArgumentError => failure
        raise Invalid.new([error(nil, nil, :invalid_binding, failure.message)])
      end
      [body, steps.map { |step| snapshot(step.operation) }, handles, steps]
    rescue CompositionCompiler::BindingError => failure
      raise Invalid.new([error(failure.index, failure.operation_id, :invalid_binding, failure.message)])
    end

    def validate_header!
      unless @site.is_a?(DymondSite::Site) && @site.persisted?
        raise ArgumentError, "Composition needs a persisted Studio site"
      end
      unless @definition.is_a?(Hash) && @definition["id"].is_a?(String) && Operation::Thick::ID.match?(@definition["id"]) &&
          %w[image motion].include?(@definition["surface"]) &&
          @definition["description"].is_a?(String) && !@definition["description"].strip.empty?
        raise ArgumentError, "Composition needs a Studio operation ID, image or motion surface, and description"
      end

      header = {
        "name" => @definition.fetch("name"), "version" => @definition.fetch("version"),
        "parameters" => @definition.fetch("parameters", {}), "inputs" => @definition.fetch("inputs", {})
      }
      Recipe.new(header.merge("engine" => Operation::Thin::SURFACES.key(@definition["surface"].to_sym),
        "steps" => [{"command" => "composition.validate", "params" => {}}]))
      header
    end

    def error(index, id, kind, detail)
      {step_index: index, step_operation_id: id, kind: kind, detail: detail}
    end

    def snapshot(operation)
      {
        "id" => operation.id, "engine" => operation.engine, "surface" => operation.surface.to_s,
        "source" => operation.source.to_s, "origin" => (operation.origin.to_s if operation.source == :thick),
        "version" => (operation.recipe.version if operation.source == :thick),
        "returns" => operation.returns, "accepts" => operation.accepts,
        "parameters" => operation.params_schema, "inputs" => operation.inputs_schema,
        "requires" => (operation.requires.map(&:to_s) if operation.source == :thin)
      }
    end
  end
end
