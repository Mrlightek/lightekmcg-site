# frozen_string_literal: true
require 'ripper'
module NevaehOs
  # Parse a useful Ruby/ActiveRecord vocabulary into data. No eval, send, SQL,
  # blocks, interpolation, callbacks supplied as code, or arbitrary constants.
  module RailsConsole
    METHODS = %w[all count first last find where limit order create create! update update! destroy destroy!].freeze
    SECRET = /password|secret|token|credential|private_key|encrypted|ciphertext|otp|session_id/i
    SERVICE_BOUND = /\A(?:Studio|DymondStudio|Susu|DymondBank|Gatekeeper|NevaehCapability|NevaehIntelligence|Session|ActiveStorage::|LightekVault|NevaehOsAction|NevaehApplicationAdapter|NevaehAgentRun|NevaehAgentWorker|NevaehWatcher|NevaehWatchEvent|NevaehConstructionRelease|NevaehLanguageCheckpoint|NevaehTrainingRun|DymondDispatch::)/
    module_function
    def authorize!(actor)
      raise ArgumentError, 'Rails console administration required' unless actor&.persisted? && %w[admin super_admin].include?(actor.role)
    end
    def models(actor)
      authorize!(actor)
      Rails.application.eager_load! if Rails.respond_to?(:application) && Rails.application
      ActiveRecord::Base.descendants.select { |m| m.name.present? && !m.abstract_class? && m.table_exists? }.sort_by(&:name)
    end
    def model!(name, actor)
      models(actor).find { |m| m.name == name } || raise(ArgumentError, 'Model is not in the installed application. Use /models.')
    end
    def schema(name, actor)
      klass = model!(name, actor)
      {'model'=>klass.name,'table'=>klass.table_name,'fields'=>klass.columns.reject { |c| c.name.match?(SECRET) }.map { |c| {'name'=>c.name,'type'=>c.type.to_s,'nullable'=>c.null} },
        'mutations'=>klass.name.match?(SERVICE_BOUND) ? 'Use the domain capability API' : 'create / update / destroy with model validation and your permissions'}
    end
    def parse(expression)
      tree = Ripper.sexp(expression)
      raise ArgumentError, 'Use one Ruby-style model expression' unless tree && tree[0] == :program && tree[1]&.one?
      model, calls = chain(tree[1].first)
      raise ArgumentError, 'Add a query or operation after the model name' if calls.empty? || calls.length > 8
      {'model'=>model,'calls'=>calls}
    end
    def chain(node)
      case node&.first
      when :var_ref, :const_ref
        token = node[1]
        raise ArgumentError, 'Start with an installed model constant' unless token[0] == :@const
        [token[1], []]
      when :const_path_ref
        name, calls = chain(node[1])
        raise ArgumentError, 'Invalid model namespace' unless calls.empty? && node[2][0] == :@const
        [name+'::'+node[2][1], []]
      when :call
        name, calls = chain(node[1])
        method = node[3][1]
        raise ArgumentError, "Unsupported console method: #{method}" unless METHODS.include?(method)
        [name, calls+[{'method'=>method,'args'=>[]}]]
      when :method_add_arg
        name, calls = chain(node[1])
        args = node[2]
        args = args[1] if args&.first == :arg_paren
        raise ArgumentError, 'Blocks and argument splats are not supported' unless args && args[0] == :args_add_block && args[2] == false
        calls[-1]['args'] = Array(args[1]).map { |v| literal(v) }
        [name,calls]
      else
        raise ArgumentError, 'Use model queries and literal inputs; arbitrary Ruby execution is not supported'
      end
    end
    def literal(node)
      case node&.first
      when :@int then Integer(node[1],10)
      when :@float then Float(node[1])
      when :string_literal
        pieces = node[1]
        raise ArgumentError, 'String interpolation is not supported' unless pieces[0] == :string_content && pieces.drop(1).all? { |p| p[0] == :@tstring_content }
        pieces.drop(1).map { |p| p[1] }.join
      when :symbol_literal
        token=node.dig(1,1)
        raise ArgumentError, 'Use a literal symbol' unless %i[@ident @const @op].include?(token&.first)
        token[1]
      when :var_ref
        token=node[1]
        return {'true'=>true,'false'=>false,'nil'=>nil}.fetch(token[1]) if token[0] == :@kw && %w[true false nil].include?(token[1])
        raise ArgumentError, 'Only literal values are supported'
      when :array then Array(node[1]).map { |v| literal(v) }
      when :hash then associations(node[1] ? node[1][1] : [])
      when :bare_assoc_hash then associations(node[1])
      when :unary
        raise ArgumentError, 'Unsupported unary expression' unless node[1] == :-@ && %i[@int @float].include?(node.dig(2,0))
        -literal(node[2])
      else
        raise ArgumentError, 'Use JSON-compatible literal values'
      end
    end
    def associations(rows)
      Array(rows).to_h do |row|
        raise ArgumentError, 'Hash expansion is not supported' unless row[0] == :assoc_new
        key = row[1][0] == :@label ? row[1][1].delete_suffix(':') : literal(row[1])
        raise ArgumentError, 'Hash keys must be field names' unless key.is_a?(String)
        [key,literal(row[2])]
      end
    end
    def fields!(klass, attributes, write: false)
      raise ArgumentError, 'Use an object of literal field values' unless attributes.is_a?(Hash) && attributes.size <= 30
      blocked = attributes.keys.select { |k| !klass.column_names.include?(k) || k.match?(SECRET) || (write && %w[id created_at updated_at type].include?(k)) }
      raise ArgumentError, "Unavailable fields: #{blocked.join(', ')}" if blocked.any?
      raise ArgumentError, 'Only scalar values or scalar arrays are supported' unless attributes.values.all? { |v| [String,Integer,Float,TrueClass,FalseClass,NilClass].any? { |t| v.is_a?(t) } || (v.is_a?(Array) && v.length <= 100 && v.all? { |a| a.nil? || a.is_a?(String) || a.is_a?(Numeric) }) }
      attributes
    end
    def execute(expression, actor)
      authorize!(actor)
      definition = parse(expression)
      klass = model!(definition.fetch('model'),actor)
      raise ArgumentError,'Use the credential service for credential records' if klass.name.match?(/Vault|Credential|Secret/)
      ability = Ability.new(actor)
      scope = klass.accessible_by(ability,:read)
      record=nil; result=nil
      definition.fetch('calls').each_with_index do |call,index|
        method,args = call.values_at('method','args')
        final = index == definition['calls'].length-1
        raise ArgumentError, 'Only find can precede a record mutation' if record && !%w[update update! destroy destroy!].include?(method)
        case method
        when 'where'
          raise ArgumentError, 'where requires a field hash' unless args.one?
          scope=scope.where(fields!(klass,args.first))
        when 'limit'
          raise ArgumentError, 'limit must be 1–100' unless args.one? && args.first.is_a?(Integer) && args.first.between?(1,100)
          scope=scope.limit(args.first)
        when 'order'
          values=fields!(klass,args.first)
          raise ArgumentError, 'Order needs asc or desc field values' unless args.one? && values.values.all? { |v| %w[asc desc].include?(v.to_s) }
          scope=scope.order(values)
        when 'all'
          raise ArgumentError, 'all takes no arguments' unless args.empty?
        when 'find'
          raise ArgumentError, 'find requires one positive ID' unless args.one? && args.first.is_a?(Integer) && args.first.positive?
          record=scope.find(args.first);result=record
        when 'count','first','last'
          raise ArgumentError, 'Use count/first/last without arguments at the end' unless args.empty? && final
          result = method == 'count' ? scope.count : method == 'first' ? scope.first : scope.last
        when 'create','create!','update','update!','destroy','destroy!'
          raise ArgumentError, 'Mutations must be the final operation' unless final
          raise ArgumentError, 'This model uses domain services. Execute its registered capability instead of bypassing the workflow.' if klass.name.match?(SERVICE_BOUND)
          operation = method.delete_suffix('!')
          if klass.name=='User' && actor.role!='super_admin' && args.first.is_a?(Hash) && (args.first.keys & %w[role roles admin super_admin permissions]).any?
            raise ArgumentError,'Only the super administrator can change account authority'
          end
          if operation == 'create'
            raise ArgumentError, 'create requires one attributes hash without a preceding record' unless args.one? && !record && definition['calls'].one?
            record=klass.new(fields!(klass,args.first,write:true))
          elsif !record
            raise ArgumentError, 'Find the record before updating or destroying it'
          end
          raise ArgumentError, 'Model permission denied' unless ability.can?(operation.to_sym,record)
          if operation == 'destroy'
            raise ArgumentError, 'destroy takes no arguments' unless args.empty?
            value=serialize(record);record.destroy!;result={'deleted'=>value}
          else
            raise ArgumentError, 'update requires one attributes hash' unless args.one?
            record.assign_attributes(fields!(klass,args.first,write:true)) if operation == 'update'
            record.save!;result=record
          end
        end
      end
      result=scope.limit(100).to_a if result.nil? && !record && !%w[first last].include?(definition['calls'].last['method'])
      {'model'=>klass.name,'result'=>serialize(result),'expression'=>expression}
    end
    def serialize(value)
      case value
      when ActiveRecord::Base then serialize(value.attributes)
      when Array then value.first(100).map { |v| serialize(v) }
      when Hash then value.each_with_object({}) { |(k,v),h| h[k]=k.to_s.match?(SECRET) ? '[REDACTED]' : serialize(v) }
      when String then value[0,2000]
      else value
      end
    end
  end
end
