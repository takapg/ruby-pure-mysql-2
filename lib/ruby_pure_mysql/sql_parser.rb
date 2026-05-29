# frozen_string_literal: true

require_relative 'sql_parser/evaluator'
require_relative 'aggregate_utils'

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
      [
        '\ASELECT\s+(?<distinct>DISTINCT\s+)?(?<columns>.+?)\s+FROM\s+(?<table1>\w+)(?:\s+(?:AS\s+)?(?<alias1>\w+))?',
        '(?:\s+(?<join_type>INNER|LEFT)\s+JOIN\s+(?<table2>\w+)' \
        '(?:\s+(?:AS\s+)?(?<alias2>\w+))?\s+ON\s+(?<on_condition>.+?))?',
        '(?:\s+WHERE\s+(?<where>.+?))?',
        '(?:\s+GROUP\s+BY\s+(?<group_by>.+?))?',
        '(?:\s+HAVING\s+(?<having>.+?))?',
        '(?:\s+ORDER\s+BY\s+(?<order_clause>.+?))?',
        '(?:\s+LIMIT\s+(?<limit>\d+)(?:\s+OFFSET\s+(?<offset>\d+))?)?',
        '\s*;?\s*\z'
      ].join,
      Regexp::IGNORECASE
    )

    def parse_select_from(query)
      match = query.match(SELECT_REGEX)
      return { error: 'Invalid SELECT syntax' } unless match

      result = build_select_result(match)
      apply_join_to_result(result, match)
      detect_aggregates(result)
      parse_select_clauses(result, match)
    end

    def parse_select_clauses(result, match)
      if match[:where]
        res = parse_where_clause_into(result, match[:where])
        return res if res.is_a?(Hash) && res[:error]
      end

      apply_optional_clauses(result, match)
      result
    end

    def apply_optional_clauses(result, match)
      result[:group_by] = match[:group_by] if match[:group_by]
      if match[:having]
        res = parse_having_clause(result, match[:having])
        return res if res.is_a?(Hash) && res[:error]
      end

      parse_order_by_clause(result, match[:order_clause]) if match[:order_clause]
      parse_limit_offset_clause(result, match[:limit], match[:offset])
      nil
    end

    def parse_having_clause(result, clause)
      having = parse_where_clause(clause, allow_aggregates: true)
      return having if having.is_a?(Hash) && having[:error]

      result[:having] = having
    end

    def parse_order_by_clause(result, clause)
      result[:order] = clause.split(',').map do |part|
        part = part.strip
        m = part.match(/(.+?)\s+(ASC|DESC)\z/i)
        if m
          { column: m[1].strip, direction: m[2].upcase.to_sym }
        else
          { column: part, direction: :ASC }
        end
      end
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

  # 結果セットの構築を支援するモジュール
  module SqlParserResultBuilder
    def build_select_result(match)
      {
        type: :select_from,
        distinct: !match[:distinct].nil?,
        table_name: match[:table1],
        table_alias: match[:alias1],
        columns: match[:columns].split(',').map { |c| parse_column_alias(c.strip) }
      }
    end

    def apply_join_to_result(result, match)
      return unless match[:table2]

      result[:join] = {
        type: match[:join_type] || 'INNER',
        table2: match[:table2],
        alias2: match[:alias2],
        on: match[:on_condition]
      }
    end

    def parse_column_alias(col)
      # 1. 明示的な AS: "expr AS alias"
      m = col.match(/(.+)\s+AS\s+([a-zA-Z_]\w*)\z/i)
      return { original: m[1].strip, alias: m[2] } if m

      # 2. 暗黙的な AS: "expr alias"
      # "a + b" のような式を誤って分割しないよう、直前が演算子で終わっていないことを確認する
      m = col.match(/(.+)\s+([a-zA-Z_]\w*)\z/)
      if m
        original = m[1].strip
        return { original: col, alias: nil } if original.match?(%r{[+\-*/%]\z})

        return { original: original, alias: m[2] }
      end

      { original: col, alias: nil }
    end

    def detect_aggregates(result)
      # 緩和: カラム数が1つでなくても、集計関数が含まれていればマークする
      result[:aggregates] = result[:columns].each_with_index.filter_map do |col_info, idx|
        col = col_info[:original]
        m = col.match(AggregateUtils::AGGREGATE_REGEX)
        next unless m

        parse_aggregate_column(m, idx)
      end

      return if result[:aggregates].empty?

      assign_first_aggregate(result)
    end

    def parse_aggregate_column(match, idx)
      { type: match[1].downcase.to_sym, distinct: !match[2].nil?, column: match[3], index: idx }
    end

    def assign_first_aggregate(result)
      first = result[:aggregates].first
      result[:aggregate] = first[:type]
      result[:aggregate_column] = first[:column]
      result[:aggregate_index] = first[:index]
    end
  end

  # WHERE句のパースを支援するモジュール
  module SqlParserWhereUtils
    def parse_where_clause(clause, allow_aggregates: false)
      parts = split_where_clause(clause)
      results = parts.map { |p| parse_single_where_condition(p, allow_aggregates: allow_aggregates) }
      error = results.find { |r| r.is_a?(Hash) && r[:error] }
      error || results
    end

    def split_where_clause(clause)
      parts = []
      buffer = { current: +'', in_quote: nil, index: 0, in_between: false }

      handle_where_char(clause, buffer, parts) while buffer[:index] < clause.length
      parts << buffer[:current].strip
    end

    def handle_where_char(clause, buffer, parts)
      buffer[:in_quote] = update_quote_state(clause[buffer[:index]], buffer[:index], clause, buffer[:in_quote])
      return process_normal_char(clause, buffer) if buffer[:in_quote]

      update_between_state(clause, buffer)
      return if handle_and_operator?(clause, buffer, parts)

      process_normal_char(clause, buffer)
    end

    def update_between_state(clause, buffer)
      buffer[:in_between] = true if clause[buffer[:index]..].match?(/\A\s+BETWEEN\s+/i)
    end

    def handle_and_operator?(clause, buffer, parts)
      match = clause[buffer[:index]..].match(/\A\s+AND\s+/i)
      return false unless match

      if buffer[:in_between]
        buffer[:current] << match[0]
        buffer[:index] += match[0].length
        buffer[:in_between] = false
        false
      else
        process_and_operator(match, buffer, parts)
        true
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

    def parse_single_where_condition(condition, allow_aggregates: false)
      column_pattern = allow_aggregates ? '.+?' : '[\w.]+'

      res = parse_is_null_condition(condition, column_pattern)
      return res if res

      parse_standard_where_condition(condition, column_pattern)
    end

    def parse_is_null_condition(condition, column_pattern)
      m = condition.match(/\A(#{column_pattern})\s+IS\s+(NOT\s+)?NULL\z/i)
      if m
        operator = m[2] ? 'IS NOT NULL' : 'IS NULL'
        return { column: m[1], operator: operator, value: nil }
      end

      nil
    end

    def parse_standard_where_condition(condition, column_pattern)
      res = parse_between_condition(condition, column_pattern)
      return res if res

      where_match = condition.match(/\A(#{column_pattern})\s*(=|!=|<>|>=|<=|>|<|LIKE|IN)\s*(.+)\z/i)
      return { error: 'Invalid WHERE clause' } unless where_match

      build_standard_condition(where_match)
    end

    def parse_between_condition(condition, column_pattern)
      match = condition.match(/\A(#{column_pattern})\s+(NOT\s+)?BETWEEN\s+(.+?)\s+AND\s+(.+)\z/i)
      return nil unless match

      column = match[1]
      operator = match[2] ? 'NOT BETWEEN' : 'BETWEEN'
      val1 = convert_value(match[3].strip)
      val2 = convert_value(match[4].strip.delete_suffix(';'))
      return val1 if val1.is_a?(Hash) && val1[:error]
      return val2 if val2.is_a?(Hash) && val2[:error]

      { column: column, operator: operator, value: [val1, val2] }
    end

    def build_standard_condition(match)
      column = match[1]
      operator = match[2].upcase
      operator = '!=' if operator == '<>'
      value_str = match[3].strip.delete_suffix(';')

      value = operator == 'IN' ? parse_in_value(value_str) : convert_value(value_str)
      return value if value.is_a?(Hash) && value[:error]

      { column: column, operator: operator, value: value }
    end

    def parse_in_value(value_str)
      return { error: 'Invalid IN clause syntax' } unless value_str.start_with?('(') && value_str.end_with?(')')

      list_str = value_str[1...-1]
      return { error: 'Invalid IN clause syntax' } if list_str.strip.empty?

      extract_in_values(list_str)
    end

    def extract_in_values(list_str)
      values = split_insert_values(list_str).map { |v| convert_value(v) }
      return { error: 'Unsupported IN value' } if values.any? { |v| v.is_a?(Hash) && v[:error] }

      values
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
      m = val.match(/\A(['"])(.*?)\1\z/)
      return m[2] if m

      if val.casecmp?('NULL')
        nil
      elsif val.match?(/\A-?\d+\z/)
        val.to_i
      else
        { error: "Invalid INSERT value: #{val}" }
      end
    end
  end

  # SqlParserは、SQLクエリを解析し、簡易的な計算を実行するクラスです。
  class SqlParser
    extend Evaluator
    extend SqlParserDdlParsers
    extend SqlParserDmlParsers
    extend SqlParserQueryParsers
    extend SqlParserResultBuilder
    extend SqlParserWhereUtils
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

      col_strs = match[1].split(',').map(&:strip)
      columns = col_strs.map { |col| parse_column_alias(col) }
      values = columns.map { |col_info| evaluator.evaluate_expression(col_info[:original]) }
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
