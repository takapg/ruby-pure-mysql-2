# frozen_string_literal: true

require_relative 'sql_parser/evaluator'

module RubyPureMysql
  # SqlParserUtilsは、SQLパースのユーティリティメソッドを提供します。
  module SqlParserUtils
    module_function

    def split_columns(definition)
      cols = []
      buf = +''
      depth = 0
      definition.each_char { |char| depth, buf = process_char(char, depth, buf, cols) }
      cols << buf.strip unless buf.strip.empty?
      cols
    end

    def split_insert_values(values_str)
      values_str.scan(/(?:'[^']*'|"[^"]*"|[^,])+/).map(&:strip)
    end

    def process_char(char, depth, buf, cols)
      depth += 1 if char == '('
      depth -= 1 if char == ')' && depth.positive?
      if char == ',' && depth.zero?
        cols << buf.strip
        buf = +''
      else
        buf << char
      end
      [depth, buf]
    end

    def process_parts(parts, evaluator)
      state = { expected: nil, columns: nil }
      rows = parts.map do |part|
        res = process_single_part(part, state, evaluator)
        return res if res.key?(:error)

        res[:result]
      end
      { result: rows, columns: state[:columns] }
    end

    def process_single_part(part, state, evaluator)
      res = validate_part(part, state[:expected], evaluator)
      return res if res.key?(:error)

      state[:expected] ||= res[:size]
      state[:columns] ||= res[:columns]
      res
    end

    def validate_part(part, expected_columns, evaluator)
      result = parse_part(part, evaluator)
      return result if result.key?(:error)

      if expected_columns && result[:result].size != expected_columns
        return { error: 'The used SELECT statements have a different number of columns' }
      end

      { result: result[:result], columns: result[:columns], size: result[:result].size }
    end

    def parse_part(part, evaluator)
      match = part.match(/\ASELECT\s+(.+?)\s*;?\s*\z/i)
      return { error: 'Invalid SQL' } unless match

      columns = match[1].split(',').map(&:strip)
      values = columns.map { |col| evaluator.evaluate_expression(col) }
      return { error: 'Unsupported expression' } if values.include?(:error)

      { result: values, columns: columns }
    end
  end

  # SqlParserConditionParsersは、WHERE句などの条件解析メソッドを提供します。
  module SqlParserConditionParsers
    def convert_value(val)
      if (m = val.match(/\A(['"])(.*?)\1\z/))
        m[2]
      elsif val.casecmp?('NULL')
        nil
      elsif val.match?(/\A-?\d+\z/)
        val.to_i
      else
        { error: "Invalid INSERT value: #{val}" }
      end
    end

    def parse_where_clause(clause)
      split_where_clause(clause).map { |c| parse_single_where_condition(c) }
    end

    def split_where_clause(clause)
      parts = []
      current = +''
      in_quote = nil
      index = 0
      while index < clause.length
        char = clause[index]
        in_quote = update_quote_state(char, index, clause, in_quote)

        if in_quote.nil? && (clause[index..(index + 4)] || '') =~ /\A\s+AND\s+/i
          parts << current.strip
          current = +''
          index += 5
        else
          current << char
          index += 1
        end
      end
      parts << current.strip
      parts
    end

    def update_quote_state(char, index, clause, in_quote)
      if ["'", '"'].include?(char) &&