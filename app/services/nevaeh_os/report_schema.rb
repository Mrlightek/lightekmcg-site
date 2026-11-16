# frozen_string_literal: true
require 'json'
module NevaehOs
  module ReportSchema
    module_function
    def definition(version=2)
      name=version==1 ? 'worker_report.v1.schema.json' : 'worker_report.schema.json'
      JSON.parse(File.read(Rails.root.join('config/nevaeh',name)))
    end
    def validate!(value, schema = nil, path = '$')
      schema ||= definition(value.is_a?(Hash) ? value['schema_version'] : 2)
      allowed=%w[$schema $id title type enum properties required additionalProperties items uniqueItems maxItems maxLength minLength pattern minimum]
      raise ArgumentError,'Unsupported report schema keyword' if (schema.keys-allowed).any?
      types=Array(schema['type'])
      valid=types.any? do |type|
        case type
        when 'object' then value.is_a?(Hash) && value.keys.all? { |k| k.is_a?(String) }
        when 'array' then value.is_a?(Array)
        when 'string' then value.is_a?(String)
        when 'integer' then value.is_a?(Integer)
        when 'null' then value.nil?
        else raise ArgumentError,"Unsupported report schema type: #{type}"
        end
      end
      raise ArgumentError,"Invalid report type at #{path}" unless valid
      raise ArgumentError,"Invalid report value at #{path}" if schema['enum'] && !schema['enum'].include?(value)
      if value.is_a?(Hash)
        raise ArgumentError,"Missing report field at #{path}" unless (schema.fetch('required',[])-value.keys).empty?
        props=schema.fetch('properties',{})
        raise ArgumentError,"Unknown report field at #{path}" if schema['additionalProperties']==false && (value.keys-props.keys).any?
        value.each { |key,item| validate!(item,props.fetch(key),"#{path}.#{key}") }
      elsif value.is_a?(Array)
        raise ArgumentError,"Too many report entries at #{path}" if value.size>schema.fetch('maxItems',100)
        raise ArgumentError,"Duplicate report entries at #{path}" if schema['uniqueItems'] && value.uniq.size!=value.size
        value.each_with_index { |item,i| validate!(item,schema.fetch('items'),"#{path}[#{i}]") }
      elsif value.is_a?(String)
        raise ArgumentError,"Invalid report text at #{path}" if value.length<schema.fetch('minLength',0) || value.length>schema.fetch('maxLength',10000) || value.include?("\0")
        raise ArgumentError,"Invalid report pattern at #{path}" if schema['pattern'] && !Regexp.new("\\A(?:#{schema['pattern'].delete_prefix('^').delete_suffix('$')})\\z").match?(value)
      elsif value.is_a?(Integer)
        raise ArgumentError,"Invalid report number at #{path}" if value<schema.fetch('minimum',0)
      end
      if path=='$' && value.is_a?(Hash) && value['schema_version']==2
        value.fetch('dependencies').each do |dependency|
          ref=dependency.fetch('report_ref')
          if ref.start_with?('unresolved:')
            raise ArgumentError,'Unresolved references require a blocked report and dependency' unless value['status']=='blocked' && dependency['status']=='blocked' && ref=="unresolved:#{dependency['task_id']}"
          else
            _,account,task,_digest=ref.split(':')
            raise ArgumentError,'Dependency reference account or UUID mismatch' unless account.to_i==value['account_id'] && task==dependency['task_id']
          end
        end
      end
      value
    end
  end
end
