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

  # SqlParserは、SQLクエリを解析し、簡易的な計算を実行するクラスです。
  class SqlParser
    extend Evaluator
    extend SqlParserUtils

    def self.parse(query)
      case query
      when /\ACREATE\s+TABLE/i then parse_create_table(query)
      when /\ADROP\s+TABLE/i   then parse_drop_table(query)
      when /\AINSERT\s+INTO/i  then parse_insert(query)
      when /\AUPDATE\s+/i      then parse_update(query)
      when /\ADELETE\s+/i      then parse_delete(query)
      when /\ASELECT\s+.+?\s+FROM/i then parse_select_from(query)
      else
        parts = query.split(/\s+UNION\s+/i).map(&:strip)
        process_parts(parts, self)
      end
    end

    def self.parse_create_table(query)
      match = query.match(/\ACREATE\s+TABLE\s+(IF\s+NOT\s+EXISTS\s+)?(\w+)\s*\((.+)\)\s*;?\s*\z/i)
      return { error: 'Invalid CREATE TABLE syntax' } unless match

      {
        type: :create_table,
        if_not_exists: !match[1].nil?,
        table_name: match[2],
        columns: split_columns(match[3]).map do |col_def|
          col_def.split(/\s+/, 2).first.delete_prefix('`').delete_suffix('`')
        end
      }
    end

    def self.parse_drop_table(query)
      match = query.match(/\ADROP\s+TABLE\s+(IF\s+EXISTS\s+)?(\w+)\s*;?\s*\z/i)
      return { error: 'Invalid DROP TABLE syntax' } unless match

      {
        type: :drop_table,
        if_exists: !match[1].nil?,
        table_name: match[2]
      }
    end

    def self.parse_insert(query)
      match = query.match(/\AINSERT\s+INTO\s+(\w+)\s+VALUES\s*\((.+)\)\s*;?\s*\z/i)
      return { error: 'Invalid INSERT syntax' } unless match

      values = split_insert_values(match[2]).map { |val| convert_value(val) }
      error = values.find { |v| v.is_a?(Hash) && v[:error] }
      return error if error

      { type: :insert, table_name: match[1], values: values }
    end

    def self.parse_update(query)
      match = query.match(/\AUPDATE\s+(\w+)\s+SET\s+(\w+)\s*=\s*(.+?)(?:\s+WHERE\s+(.+))?\s*;?\s*\z/i)
      return { error: 'Invalid UPDATE syntax' } unless match

      value = convert_value(match[3].strip)
      return value if value.is_a?(Hash) && value[:error]

      result = { type: :update, table_name: match[1], column: match[2], value: value }
      if match[4]
        where = parse_where_clause(match[4])
        return where if where.is_a?(Hash) && where[:error]
        result[:where] = where
      end
      result
    end

    def self.parse_delete(query)
      match = query.match(/\ADELETE\s+FROM\s+(\w+)(?:\s+WHERE\s+(.+))?\s*;?\s*\z/i)
      return { error: 'Invalid DELETE syntax' } unless match

      result = { type: :delete, table_name: match[1] }
      if match[2]
        where = parse_where_clause(match[2])
        return where if where.is_a?(Hash) && where[:error]
        result[:where] = where
      end
      result
    end

    def self.convert_value(val)
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

    def self.parse_select_from(query)
      match = query.match(/\ASELECT\s+(.+?)\s+FROM\s+(\w+)(?:\s+WHERE\s+(.+?))?\s*;?\s*\z/i)
      return { error: 'Invalid SELECT syntax' } unless match

      result = { type: :select_from, table_name: match[2], columns: match[1].split(',').map(&:strip) }

      if match[3]
        where = parse_where_clause(match[3])
        return where if where.is_a?(Hash) && where[:error]

        result[:where] = where
      end

      result
    end

    def self.parse_where_clause(clause)
      where_match = clause.match(/\A(\w+)\s*=\s*(.+)\z/)
      return { error: 'Invalid WHERE clause' } unless where_match

      # 値からセミコロンを除去
      value_str = where_match[2].strip.delete_suffix(';')
      value = convert_value(value_str)
      return { error: 'Unsupported WHERE value' } if value.is_a?(Hash) && value[:error]

      { column: where_match[1], value: value }
    end

    private_class_method :parse_insert, :parse_select_from, :parse_create_table,
                         :parse_drop_table, :convert_value, :parse_where_clause,
                         :parse_update, :parse_delete
  end
end
