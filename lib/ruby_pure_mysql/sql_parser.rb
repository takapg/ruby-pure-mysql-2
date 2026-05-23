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
      parts = []
      current = +''
      in_quote = nil
      i = 0
      while i < clause.length
        char = clause[i]
        if (char == "'" || char == '"') && (i == 0 || clause[i - 1] != '\\')
          if in_quote == char
            in_quote = nil
          elsif in_quote.nil?
            in_quote = char
          end
        end

        if in_quote.nil? && (clause[i..i + 4] || '') =~ /\A\s+AND\s+/i
          parts << current.strip
          current = +''
          i += 5
          next
        else
          current << char
        end
        i += 1
      end
      parts << current.strip
      parts.map { |c| parse_single_where_condition(c) }
    end

    def parse_single_where_condition(clause)
      # 演算子の正規表現に LIKE を追加し、大文字小文字を区別しないように修正
      where_match = clause.match(/\A(\w+)\s*(=|!=|<>|>=|<=|>|<|LIKE)\s*(.+)\z/i)
      return { error: 'Invalid WHERE clause' } unless where_match

      column = where_match[1]
      operator = where_match[2].upcase # LIKE を大文字に統一
      # <> を != に正規化
      operator = '!=' if operator == '<>'

      # 値からセミコロンを除去
      value_str = where_match[3].strip.delete_suffix(';')
      value = convert_value(value_str)
      return { error: 'Unsupported WHERE value' } if value.is_a?(Hash) && value[:error]

      { column: column, operator: operator, value: value }
    end
  end

  # DDLパースロジック
  module SqlParserDdlParsers
    def parse_create_table(query)
      match = query.match(/\ACREATE\s+TABLE\s+(IF\s+NOT\s+EXISTS\s+)?(\w+)\s*\((.+)\)\s*;?\s*\z/i)
      return { error: 'Invalid CREATE TABLE syntax' } unless match

      {
        type: :create_table,
        if_not_exists: !match[1].nil?,
        table_name: match[2],
        columns: SqlParserUtils.split_columns(match[3]).map do |col_def|
          col_def.split(/\s+/, 2).first.delete_prefix('`').delete_suffix('`')
        end
      }
    end

    def parse_drop_table(query)
      match = query.match(/\ADROP\s+TABLE\s+(IF\s+EXISTS\s+)?(\w+)\s*;?\s*\z/i)
      return { error: 'Invalid DROP TABLE syntax' } unless match

      {
        type: :drop_table,
        if_exists: !match[1].nil?,
        table_name: match[2]
      }
    end
  end

  # DMLパースロジック
  module SqlParserDmlParsers
    def parse_insert(query)
      match = query.match(/\AINSERT\s+INTO\s+(\w+)\s+VALUES\s*\((.+)\)\s*;?\s*\z/i)
      return { error: 'Invalid INSERT syntax' } unless match

      values = SqlParserUtils.split_insert_values(match[2]).map { |val| SqlParserUtils.convert_value(val) }
      error = values.find { |v| v.is_a?(Hash) && v[:error] }
      return error if error

      { type: :insert, table_name: match[1], values: values }
    end

    def parse_update(query)
      match = query.match(/\AUPDATE\s+(\w+)\s+SET\s+(\w+)\s*=\s*(.+?)(?:\s+WHERE\s+(.+))?\s*;?\s*\z/i)
      return { error: 'Invalid UPDATE syntax' } unless match

      value = SqlParserUtils.convert_value(match[3].strip)
      return value if value.is_a?(Hash) && value[:error]

      result = { type: :update, table_name: match[1], column: match[2], value: value }
      return result unless match[4]

      parse_update_where(result, match[4])
    end

    def parse_update_where(result, clause)
      where_clauses = SqlParserUtils.parse_where_clause(clause)
      error = where_clauses.find { |c| c.is_a?(Hash) && c[:error] }
      return error if error

      result[:where_clauses] = where_clauses
      result
    end

    def parse_delete(query)
      match = query.match(/\ADELETE\s+FROM\s+(\w+)(?:\s+WHERE\s+(.+))?\s*;?\s*\z/i)
      return { error: 'Invalid DELETE syntax' } unless match

      result = { type: :delete, table_name: match[1] }
      return result unless match[2]

      where_clauses = SqlParserUtils.parse_where_clause(match[2])
      error = where_clauses.find { |c| c.is_a?(Hash) && c[:error] }
      return error if error

      result[:where_clauses] = where_clauses
      result
    end
  end

  # クエリパースロジック
  module SqlParserQueryParsers
    SELECT_REGEX = Regexp.new(
      '\ASELECT\s+(.+?)\s+FROM\s+(\w+)(?:\s+WHERE\s+(.+?))?' \
      '(?:\s+ORDER\s+BY\s+(\w+)(?:\s+(ASC|DESC))?)?' \
      '(?:\s+LIMIT\s+(\d+)(?:\s+OFFSET\s+(\d+))?)?\s*;?\s*\z',
      Regexp::IGNORECASE
    )

    def parse_select_from(query)
      match = query.match(SELECT_REGEX)
      return { error: 'Invalid SELECT syntax' } unless match

      result = { type: :select_from, table_name: match[2], columns: match[1].split(',').map(&:strip) }
      parse_select_clauses(result, match)
    end

    def parse_select_clauses(result, match)
      if match[3]
        where_res = parse_where_clause_into(result, match[3])
        return where_res if where_res.is_a?(Hash) && where_res[:error]
      end
      parse_order_by_clause(result, match[4], match[5]) if match[4]
      parse_limit_offset_clause(result, match[6], match[7])
      result
    end

    def parse_order_by_clause(result, column, direction)
      result[:order_by] = { column: column, direction: (direction || 'ASC').upcase.to_sym }
    end

    def parse_limit_offset_clause(result, limit, offset)
      result[:limit] = limit.to_i if limit
      result[:offset] = offset.to_i if offset
    end

    def parse_where_clause_into(result, clause)
      where_clauses = SqlParserUtils.parse_where_clause(clause)
      error = where_clauses.find { |c| c.is_a?(Hash) && c[:error] }
      return error if error

      result[:where_clauses] = where_clauses
    end

    def parse_show_tables(_query)
      { type: :show_tables }
    end

    def parse_describe(query)
      match = query.match(/\A(DESCRIBE|DESC)\s+(\w+)\s*;?\s*\z/i)
      return { error: 'Invalid DESCRIBE syntax' } unless match

      { type: :describe, table_name: match[2] }
    end
  end

  # SqlParserは、SQLクエリを解析し、簡易的な計算を実行するクラスです。
  class SqlParser
    extend Evaluator
    extend SqlParserUtils
    extend SqlParserDdlParsers
    extend SqlParserDmlParsers
    extend SqlParserQueryParsers

    PARSERS = {
      /\ACREATE\s+TABLE/i => :parse_create_table,
      /\ADROP\s+TABLE/i => :parse_drop_table,
      /\AINSERT\s+INTO/i => :parse_insert,
      /\AUPDATE\s+/i => :parse_update,
      /\ADELETE\s+/i => :parse_delete,
      /\ASELECT\s+.+?\s+FROM/i => :parse_select_from
    }.freeze

    def self.parse(query)
      return parse_show_tables(query) if query.match?(/\ASHOW\s+TABLES\s*;?\s*\z/i)
      return parse_describe(query) if query.match?(/\A(DESCRIBE|DESC)\s+/i)

      parser_method = PARSERS.find { |regex, _| query.match?(regex) }&.last
      return send(parser_method, query) if parser_method

      parts = query.split(/\s+UNION\s+/i).map(&:strip)
      process_parts(parts, self)
    end

    private_class_method :parse_insert, :parse_select_from, :parse_create_table,
                         :parse_drop_table, :parse_update, :parse_delete,
                         :parse_show_tables, :parse_describe
  end
end
