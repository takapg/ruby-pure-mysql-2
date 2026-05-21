# frozen_string_literal: true

require_relative 'sql_parser/evaluator'

module RubyPureMysql
  # SqlParserは、SQLクエリを解析し、簡易的な計算を実行するクラスです。
  class SqlParser
    extend Evaluator

    # 指定されたSQLクエリを解析し、結果を返します。
    #
    # @param query [String] 解析対象のSQLクエリ
    # @return [Hash] 解析結果またはエラー情報を含むハッシュ
    def self.parse(query)
      case query
      when /\ACREATE\s+TABLE/i then parse_create_table(query)
      when /\AINSERT\s+INTO/i  then parse_insert(query)
      when /\ASELECT\s+.+?\s+FROM/i then parse_select_from(query)
      else
        parts = query.split(/\s+UNION\s+/i).map(&:strip)
        process_parts(parts)
      end
    end

    def self.parse_create_table(query)
      match = query.match(/\ACREATE\s+TABLE\s+(IF\s+NOT\s+EXISTS\s+)?(\w+)\s*\((.+)\)\s*;?\s*\z/i)
      return { error: 'Invalid CREATE TABLE syntax' } unless match

      {
        type: :create_table,
        if_not_exists: !match[1].nil?,
        table_name: match[2],
        columns: split_columns(match[3])
      }
    end

    def self.parse_insert(query)
      match = query.match(/\AINSERT\s+INTO\s+(\w+)\s+VALUES\s*\((.+)\)\s*;?\s*\z/i)
      return { error: 'Invalid INSERT syntax' } unless match

      values = match[2].split(',').map(&:strip).map do |val|
        val.match?(/\A(['"])(.*?)\1\z/) ? val.match(/\A(['"])(.*?)\1\z/)[2] : val.to_i
      end

      { type: :insert, table_name: match[1], values: values }
    end

    def self.parse_select_from(query)
      match = query.match(/\ASELECT\s+(.+?)\s+FROM\s+(\w+)\s*;?\s*\z/i)
      return { error: 'Invalid SELECT syntax' } unless match

      { type: :select_from, table_name: match[2], columns: match[1].split(',').map(&:strip) }
    end

    def self.split_columns(definition)
      cols = []
      buf = +''
      depth = 0
      definition.each_char { |char| depth, buf = process_char(char, depth, buf, cols) }
      cols << buf.strip unless buf.strip.empty?
      cols
    end

    def self.process_char(char, depth, buf, cols)
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

    def self.process_parts(parts)
      state = { expected: nil, columns: nil }
      rows = parts.map do |part|
        res = process_single_part(part, state)
        return res if res.key?(:error)

        res[:result]
      end
      { result: rows, columns: state[:columns] }
    end

    def self.process_single_part(part, state)
      res = validate_part(part, state[:expected])
      return res if res.key?(:error)

      state[:expected] ||= res[:size]
      state[:columns] ||= res[:columns]
      res
    end

    def self.validate_part(part, expected_columns)
      result = parse_part(part)
      return result if result.key?(:error)

      if expected_columns && result[:result].size != expected_columns
        return { error: 'The used SELECT statements have a different number of columns' }
      end

      { result: result[:result], columns: result[:columns], size: result[:result].size }
    end

    def self.parse_part(part)
      match = part.match(/\ASELECT\s+(.+?)\s*;?\s*\z/i)
      return { error: 'Invalid SQL' } unless match

      columns = match[1].split(',').map(&:strip)
      values = columns.map { |col| evaluate_expression(col) }
      return { error: 'Unsupported expression' } if values.include?(:error)

      { result: values, columns: columns }
    end

    private_class_method :parse_part, :process_parts, :validate_part,
                         :process_single_part, :split_columns, :process_char,
                         :parse_insert, :parse_select_from, :parse_create_table
  end
end
