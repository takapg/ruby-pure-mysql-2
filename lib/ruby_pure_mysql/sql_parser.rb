# frozen_string_literal: true

require_relative 'sql_parser/evaluator'

module RubyPureMysql
  # DDLパースロジック
  module SqlParserDdlParsers
    def parse_create_table(query)
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

      values = split_insert_values(match[2]).map { |val| convert_value(val) }
      error = values.find { |v| v.is_a?(Hash) && v[:error] }
      return error if error

      { type: :insert, table_name: match[1], values: values }
    end

    def parse_update(query)
      match = query.match(/\AUPDATE\s+(\w+)\s+SET\s+(\w+)\s*=\s*(.+?)(?:\s+WHERE\s+(.+))?\s*;?\s*\z/i)
      return { error: 'Invalid UPDATE syntax' } unless match

      value = convert_value(match[3].strip)
      return value if value.is_a?(Hash) && value[:error]

      result = { type: :update, table_name: match[1], column: match[2], value: value }
      return result unless match[4]

      where = parse_where_clause(match[4])
      return where if where.is_a?(Hash) && where[:error]

      result[:where] = where
      result
    end

    def parse_delete(query)
      match = query.match(/\ADELETE\s+FROM\s+(\w+)(?:\s+WHERE\s+(.+))?\s*;?\s*\z/i)
      return { error: 'Invalid DELETE syntax' } unless match

      result = { type: :delete, table_name: match[1] }
      return result unless match[2]

      where = parse_where_clause(match[2])
      return where if where.is_a?(Hash) && where[:error]

      result[:where] = where
      result
    end
  end

  # クエリパースロジック
  module SqlParserQueryParsers
    SELECT_REGEX = Regexp.new(
      '\ASELECT\s+(DISTINCT\s+)?(.+?)\s+FROM\s+(\w+)(?:\s+WHERE\s+(.+?))?' \
      '(?:\s+GROUP\s+BY\s+(.+?))?' \
      '(?:\s+ORDER\s+BY\s+(.+?)(?:\s+(ASC|DESC))?)?' \
      '(?:\s+LIMIT\s+(\d+)(?:\s+OFFSET\s+(\d+))?)?\s*;?\s*\z',
      Regexp::IGNORECASE
    )

    def parse_select_from(query)
      match = query.match(SELECT_REGEX)
      return { error: 'Invalid SELECT syntax' } unless match

      result = {
        type: :select_from,
        distinct: !match[1].nil?,
        table_name: match[3],
        columns: match[2].split(',').map(&:strip)
      }
      detect_aggregates(result)
      parse_select_clauses(result, match)
    end

    def detect_aggregates(result)
      # 緩和: カラム数が1つでなくても、集計関数が含まれていればマークする
      result[:aggregates] = []
      result[:columns].each_with_index do |col, idx|
        m = col.match(/\A(COUNT|SUM|AVG|MIN|MAX)\((.*)\)\z/i)
        next unless m

        result[:aggregates] << {
          type: m[1].downcase.to_sym,
          column: m[2],
          index: idx
        }
      end
      # 後方互換性のために最初の集計関数をセット
      if result[:aggregates].any?
        first = result[:aggregates].first
        result[:aggregate] = first[:type]
        result[:aggregate_column] = first[:column]
        result[:aggregate_index] = first[:index]
      end
    end

    def parse_select_clauses(result, match)
      if match[4]
        where_res = parse_where_clause_into(result, match[4])
        return where_res if where_res.is_a?(Hash) && where_res[:error]
      end
      result[:group_by] = match[5] if match[5]
      parse_order_by_clause(result, match[6], match[7]) if match[6]
      parse_limit_offset_clause(result, match[8], match[9])
      result
    end

    def parse_order_by_clause(result, column, direction)
      # 修正: table_handlers.rb が期待するキー :order に合わせる
      result[:order] = { column: column, direction: (direction || 'ASC').upcase.to_sym }
    end

    def parse_limit_offset_clause(result, limit, offset)
      result[:limit] = limit.to_i if limit
      result[:offset] = offset.to_i if offset
    end

    def parse_where_clause_into(result, clause)
      where = parse_where_clause(clause)
      return where if where.is_a?(Hash) && where[:error]

      result[:where] = where
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

  # ユーティリティメソッドをまとめたモジュール
  module SqlParserUtils
    def split_columns(definition)
      cols = []
      buf = +''
      depth = 0
      definition.each_char { |char| depth, buf = SqlParser.process_char(char, depth, buf, cols) }
      cols << buf.strip unless buf.strip.empty?
      cols
    end

    def split_insert_values(values_str)
      values_str.scan(/(?:'[^']*'|"[^"]*"|[^,])+/).map(&:strip)
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
      parts = split_where_clause(clause)
      results = parts.map { |p| parse_single_where_condition(p) }
      error = results.find { |r| r.is_a?(Hash) && r[:error] }
      error || results
    end

    def split_where_clause(clause)
      parts = []
      buffer = { current: +'', in_quote: nil, index: 0 }

      handle_where_char(clause, buffer, parts) while buffer[:index] < clause.length
      parts << buffer[:current].strip
    end

    def handle_where_char(clause, buffer, parts)
      buffer[:in_quote] = update_quote_state(clause[buffer[:index]], buffer[:index], clause, buffer[:in_quote])

      if buffer[:in_quote].nil? && (match = clause[buffer[:index]..].match(/\A\s+AND\s+/i))
        process_and_operator(match, buffer, parts)
      else
        process_normal_char(clause, buffer)
      end
    end

    def process_and_operator(match, buffer, parts)
      parts << buffer[:current].strip
      buffer[:current] = +''
      buffer[:index] += match[0].length
    end

    def process_normal_char(clause, buffer)
      buffer[:current] << clause[buffer[:index]]
      buffer[:index] += 1
    end

    def update_quote_state(char, index, clause, in_quote)
      if ["'", '"'].include?(char) && (index.zero? || clause[index - 1] != '\\') && (in_quote.nil? || in_quote == char)
        return in_quote == char ? nil : char
      end

      in_quote
    end

    def parse_single_where_condition(condition)
      where_match = condition.match(/\A(\w+)\s*(=|!=|<>|>=|<=|>|<|LIKE)\s*(.+)\z/i)
      return { error: 'Invalid WHERE clause' } unless where_match

      column = where_match[1]
      operator = where_match[2].upcase
      operator = '!=' if operator == '<>'
      value_str = where_match[3].strip.delete_suffix(';')
      value = convert_value(value_str)
      return { error: 'Unsupported WHERE value' } if value.is_a?(Hash) && value[:error]

      { column: column, operator: operator, value: value }
    end
  end

  # SqlParserは、SQLクエリを解析し、簡易的な計算を実行するクラスです。
  class SqlParser
    extend Evaluator
    extend SqlParserDdlParsers
    extend SqlParserDmlParsers
    extend SqlParserQueryParsers
    extend SqlParserUtils

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

    # --- ユーティリティメソッド ---

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

    def self.process_parts(parts, evaluator)
      state = { expected: nil, columns: nil }
      rows = parts.map do |part|
        res = process_single_part(part, state, evaluator)
        return res if res.key?(:error)

        res[:result]
      end
      { result: rows, columns: state[:columns] }
    end

    def self.process_single_part(part, state, evaluator)
      res = validate_part(part, state[:expected], evaluator)
      return res if res.key?(:error)

      state[:expected] ||= res[:size]
      state[:columns] ||= res[:columns]
      res
    end

    def self.validate_part(part, expected_columns, evaluator)
      result = parse_part(part, evaluator)
      return result if result.key?(:error)

      if expected_columns && result[:result].size != expected_columns
        return { error: 'The used SELECT statements have a different number of columns' }
      end

      { result: result[:result], columns: result[:columns], size: result[:result].size }
    end

    def self.parse_part(part, evaluator)
      match = part.match(/\ASELECT\s+(.+?)\s*;?\s*\z/i)
      return { error: 'Invalid SQL' } unless match

      columns = match[1].split(',').map(&:strip)
      values = columns.map { |col| evaluator.evaluate_expression(col) }
      return { error: 'Unsupported expression' } if values.include?(:error)

      { result: values, columns: columns }
    end

    private_class_method :parse_insert, :parse_select_from, :parse_create_table,
                         :parse_drop_table, :parse_update, :parse_delete,
                         :parse_show_tables, :parse_describe,
                         :process_parts, :process_single_part, :validate_part,
                         :parse_part
  end
end
