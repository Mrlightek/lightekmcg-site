require 'strscan'
require 'bigdecimal'
module LightekAccounting
  class SheetFormula
    class Unsupported < ArgumentError; end
    class CalculationError < Unsupported; end
    FUNCTIONS = %w[SUM MIN MAX COUNT AVERAGE IF IFERROR ROUND ABS SUMIF COUNTIF].freeze
    PRECEDENCE = {'='=>1,'<>' =>1,'<'=>1,'>'=>1,'<='=>1,'>='=>1,'&'=>2,'+'=>3,'-'=>3,'*'=>4,'/'=>4,'^'=>5}.freeze
    def initialize(schema)
      @sheets = schema.fetch('sheets').to_h { |s| [s.fetch('name'),s.fetch('cells')] }
      @cache, @visiting, @operations = {}, [], 0
    end
    def cell(sheet,address)
      entered = false
      key = [sheet,address.delete('$').upcase]
      return @cache[key] if @cache.key?(key)
      raise Unsupported, 'Circular or excessively deep formula reference' if @visiting.include?(key) || @visiting.size > 100
      @operations += 1
      raise Unsupported, 'Workbook calculation limit reached' if @operations > 200_000
      data = @sheets.fetch(sheet).fetch(key.last,{'value'=>'','type'=>'text'})
      @visiting << key
      entered = true
      value = if data['formula']
        raise Unsupported, 'Shared/array formulas require explicit conversion' if data['formula_mode'] && data['formula_mode'] != 'normal'
        Parser.new(data['formula'],sheet).parse.then { |ast| evaluate(ast) }
      elsif data['type'] == 'number' && data['value'].to_s.present?
        BigDecimal(data['value'].to_s)
      else data['value']
      end
      raise Unsupported,'Formula result is outside native numeric limits' if value.is_a?(Numeric) && (!value.finite? || value.abs > BigDecimal('1e24'))
      @cache[key] = value
    rescue KeyError
      raise Unsupported, 'Formula references an unknown worksheet'
    ensure
      @visiting.pop if entered
    end
    def number(value)
      return BigDecimal('0') if value.nil? || value == ''
      return value if value.is_a?(BigDecimal)
      raise Unsupported, 'Formula expected a numeric value' unless value.is_a?(Numeric)
      BigDecimal(value.to_s)
    end
    def evaluate(node)
      @operations += 1
      raise Unsupported, 'Workbook calculation limit reached' if @operations > 200_000
      case node[0]
      when :literal then node[1]
      when :ref then cell(node[1],node[2])
      when :range
        first,last = node[2..3].map { |v| [WorkbookSchema.column_number(v[/[A-Z]+/]),v[/\d+/].to_i] }
        raise Unsupported, 'Formula range too large or reversed' if first[0] > last[0] || first[1] > last[1] || (last[0]-first[0]+1)*(last[1]-first[1]+1)>10000
        @operations += (last[0]-first[0]+1)*(last[1]-first[1]+1)
        raise Unsupported, 'Workbook calculation limit reached' if @operations > 200_000
        (first[1]..last[1]).flat_map { |r| (first[0]..last[0]).map { |c| cell(node[1],"#{WorkbookSchema.column(c)}#{r}") } }
      when :unary then -number(evaluate(node[1]))
      when :binary
        a,b = evaluate(node[2]),evaluate(node[3])
        case node[1]
        when '+' then number(a)+number(b)
        when '-' then number(a)-number(b)
        when '*' then number(a)*number(b)
        when '/' then raise CalculationError,'Division by zero' if number(b).zero?; number(a)/number(b)
        when '^' then raise Unsupported,'Exponent limit exceeded' unless number(b).frac.zero? && number(b).abs <= 12; number(a)**number(b).to_i
        when '&' then [a,b].map { |v| v.is_a?(BigDecimal) ? v.to_s('F').sub(/\.0\z/,'') : v.to_s }.join
        when '=', '<>', '<', '>', '<=', '>='
          a,b = a.downcase,b.downcase if a.is_a?(String) && b.is_a?(String)
          a,b = number(a),number(b) if [a,b].all? { |v| v.is_a?(Numeric) || v.nil? || v == '' }
          raise Unsupported,'Mixed-type comparisons require review' unless (a.is_a?(Numeric) && b.is_a?(Numeric)) || a.class == b.class
          order = a <=> b
          raise Unsupported,'Comparison requires review' if order.nil?
          {'='=>order.zero?,'<>'=>!order.zero?,'<'=>order.negative?,'>'=>order.positive?,'<='=>order<=0,'>='=>order>=0}.fetch(node[1])
        end
      when :call
        name,args = node[1],node[2]
        if name == 'IF'
          raise Unsupported,'IF needs three arguments' unless args.size == 3
          condition = evaluate(args[0])
          truth = condition.is_a?(Numeric) ? !condition.zero? : condition == true
          raise Unsupported,'IF condition must be numeric or boolean' unless condition.is_a?(Numeric) || [true,false,'',nil].include?(condition)
          return evaluate(truth ? args[1] : args[2])
        end
        if name == 'IFERROR'
          raise Unsupported,'IFERROR needs two arguments' unless args.size == 2
          begin
            return evaluate(args[0])
          rescue CalculationError, ZeroDivisionError
            return evaluate(args[1])
          end
        end
        arity = {'COUNTIF'=>[2], 'SUMIF'=>[2,3], 'ROUND'=>[2], 'ABS'=>[1]}
        raise Unsupported,'Function argument count requires review' if arity.key?(name) && !arity.fetch(name).include?(args.size)
        raise Unsupported,'Function requires arguments' if args.empty?
        values = args.map { |arg| evaluate(arg) }
        if %w[SUMIF COUNTIF].include?(name)
          range,criterion,sum_range = values
          raise Unsupported,'Invalid conditional range' unless range.is_a?(Array) && (sum_range.nil? || (sum_range.is_a?(Array) && sum_range.size == range.size))
          selected = range.each_index.select { |i| matches?(range[i],criterion) }
          return BigDecimal(selected.size.to_s) if name == 'COUNTIF'
          return selected.sum(BigDecimal('0')) { |i| number((sum_range || range)[i]) }
        end
        raise Unsupported,'Direct text and boolean function arguments require review' if values.any? { |v| v.is_a?(String) || v == true || v == false }
        flat = values.flatten
        nums = flat.select { |v| v.is_a?(Numeric) }.map { |v| number(v) }
        case name
        when 'SUM' then nums.sum(BigDecimal('0'))
        when 'MIN' then nums.min || BigDecimal('0')
        when 'MAX' then nums.max || BigDecimal('0')
        when 'COUNT' then BigDecimal(nums.size.to_s)
        when 'AVERAGE' then raise Unsupported,'AVERAGE has no numbers' if nums.empty?; nums.sum(BigDecimal('0'))/nums.size
        when 'ROUND'
          digits = number(values.fetch(1,0)).to_i
          raise Unsupported,'ROUND precision out of range' unless (-10..10).cover?(digits)
          number(values.fetch(0)).round(digits).to_d
        when 'ABS' then number(values.fetch(0)).abs
        end
      end
    rescue FloatDomainError, ZeroDivisionError, TypeError, NoMethodError, ArgumentError => error
      raise error if error.is_a?(Unsupported)
      raise Unsupported,'Formula could not be evaluated with these inputs'
    end
    def matches?(value,criterion)
      raise Unsupported,'Wildcard criteria require review' if criterion.is_a?(String) && criterion.match?(/[?*~]/)
      if criterion.is_a?(String) && (match=criterion.match(/\A(<=|>=|<>|=|<|>)?(-?\d+(?:\.\d+)?)\z/))
        return false unless value.is_a?(Numeric) || value.nil? || value == ''
        left,right = number(value),BigDecimal(match[2])
        return {'<='=>-> {left<=right},'>='=>-> {left>=right},'<>' =>-> {left!=right},'='=>-> {left==right},'<'=>-> {left<right},'>'=>-> {left>right}}.fetch(match[1] || '=').call
      end
      return value == criterion if criterion.is_a?(Numeric)
      value.to_s.casecmp?(criterion.to_s)
    end
    class Parser
      def initialize(source,sheet)
        raise Unsupported,'Formula exceeds 4 KB' if source.bytesize > 4000
        @scanner,@sheet = StringScanner.new(source.delete_prefix('=')),sheet
        @tokens=[]
        until @scanner.eos?
          next if @scanner.scan(/\s+/)
          token = if (v=@scanner.scan(/"(?:[^"]|"")*"/))
            [:literal,v[1...-1].gsub('""','"')]
          elsif (v=@scanner.scan(/\d+(?:\.\d+)?/))
            [:literal,BigDecimal(v)]
          elsif (v=@scanner.scan(/[A-Za-z_][A-Za-z0-9_.]*(?=\s*\()/))
            name=v.upcase
            raise Unsupported,"Unsupported formula function #{name}" unless FUNCTIONS.include?(name)
            [:function,name]
          elsif (v=@scanner.scan(/(?:(?:'[^']+'|[A-Za-z_][A-Za-z0-9_ .]*)!)?\$?[A-Za-z]{1,3}\$?[1-9]\d*(?::\$?[A-Za-z]{1,3}\$?[1-9]\d*)?/))
            prefix,ref = v.include?('!') ? v.split('!',2) : [@sheet,v]
            prefix=prefix.delete_prefix("'").delete_suffix("'")
            refs=ref.delete('$').upcase.split(':')
            refs.length==2 ? [:range,prefix,*refs] : [:ref,prefix,refs[0]]
          elsif (v=@scanner.scan(/TRUE|FALSE/i))
            [:literal,v.upcase=='TRUE']
          elsif (v=@scanner.scan(/<=|>=|<>|[+*\/\^&=<>(),%\-]/))
            v
          else
            raise Unsupported,'Unsupported formula syntax or external reference'
          end
          @tokens << token
          raise Unsupported,'Formula token limit reached' if @tokens.size > 500
        end
        @index=0
      end
      def peek = @tokens[@index]
      def take = @tokens[@index].tap { @index+=1 }
      def expect(token) = (take == token || (raise Unsupported,'Malformed formula'))
      def parse
        value=expression(0)
        raise Unsupported,'Unexpected formula tokens' unless peek.nil?
        value
      end
      def expression(min)
        token=take
        left = if token == '-'
          [:unary,expression(6)]
        elsif token == '+'
          expression(6)
        elsif token == '('
          value=expression(0);expect(')');value
        elsif token.is_a?(Array) && token[0] == :function
          expect('(');args=[]
          unless peek == ')'
            loop do
              args << expression(0)
              break unless peek == ','
              take
            end
          end
          expect(')');[:call,token[1],args]
        elsif token.is_a?(Array)
          token
        else
          raise Unsupported,'Malformed formula value'
        end
        if peek == '%'
          take;left=[:binary,'/',left,[:literal,BigDecimal('100')]]
        end
        while peek.is_a?(String) && PRECEDENCE.fetch(peek,-1)>=min
          operator=take;power=PRECEDENCE.fetch(operator)
          left=[:binary,operator,left,expression(power+1)]
        end
        left
      end
    end
  end
end
