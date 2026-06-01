# frozen_string_literal: true

require_relative 'sql_parser/expression_utils'
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
    UPDATE_REGEX = /
      \AUPDATE\s+(`[^`]+`|\w+)\s+SET\s+(.+?)
      (?:\s+WHERE\s+(.+?))?
      (?:\s+ORDER\s+BY\s+(.+?))?
      (?:\s+LIMIT\s+(\d+))?
      \s*;?\s*\z
    /ix

    DELETE_REGEX = /
      \ADELETE\s+FROM\s+(`[^`]+`|\w+)
      (?:\s+WHERE\s+(.+?))?
      (?:\s+ORDER\s+BY\s+(.+?))?
      (?:\s+LIMIT\s+(\d+))?
      \s*;?\s*\z
    /ix

    def parse_insert(query)
      match = query.match(/\AINSERT\s+INTO\s+(`[^`]+`|\w+)(?:\s*\((.+?)\))?\s+VALUES\s*\((.+)\)\s*;?\s*\z/i)
      return { error: 'Invalid INSERT syntax' } unless match

      values = parse_insert_values(match[3])
      return values if values.is_a?(Hash) && values[:error]

      {
        type: :insert,
        table_name: strip_backticks(match[1]),
        columns: parse_insert_columns(match[2]),
        values: values
      }
    end

    def parse_insert_columns(col_list)
      return nil unless col_list

      split_columns(col_list).map { |c| strip_backticks(c) }
    end

    def parse_insert_values(values_str)
      values = split_insert_values(values_str).map { |val| convert_value(val) }
      values.find { |v| v.is_a?(Hash) && v[:error] } || values
    end

    def parse_update(query)
      parts = extract_update_parts(query)
      return { error: 'Invalid UPDATE syntax' } unless parts

      updates = parse_update_set_clause(parts[:set_clause])
      return updates if updates.is_a?(Hash) && updates[:error]

      build_update_result(parts, updates)
    end

    def build_update_result(parts, updates)
      res = {
        type: :update,
        table_name: strip_backticks(parts[:table_name]),
        updates: updates,
        limit: parts[:limit]&.to_i
      }
      SqlParser.parse_order_by_clause(res, parts[:order_clause]) if parts[:order_clause]
      apply_update_where(res, parts[:where_clause])
    end

    def extract_update_parts(query)
      if (match = query.match(UPDATE_REGEX))
        { table_name: match[1], set_clause: match[2], where_clause: match[3], order_clause: match[4], limit: match[5] }
      end
    end

    def apply_update_where(res, where_clause)
      return res unless where_clause

      where = parse_where_clause(where_clause)
      return where if where.is_a?(Hash) && where[:error]

      res.merge(where: where)
    end

    def parse_update_set_clause(set_clause)
      split_insert_values(set_clause).map do |pair|
        col, val = pair.split('=', 2)
        return { error: 'Invalid UPDATE syntax' } unless col && val

        converted_val = convert_value(val.strip)
        return converted_val if converted_val.is_a?(Hash) && converted_val[:error]

        { column: col.strip, value: converted_val }
      end
    end

    def parse_delete(query)
      match = query.match(DELETE_REGEX)
      return { error: 'Invalid DELETE syntax' } unless match

      result = { type: :delete, table_name: strip_backticks(match[1]), limit: match[4]&.to_i }
      SqlParser.parse_order_by_clause(result, match[3]) if match[3]
      return result unless match[2]

      where = parse_where_clause(match[2])
      return where if where.is_a?(Hash) && where[:error]

      result.merge!(where: where)
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
    ALIAS_PATTERN = '(`[^`]+`|[a-zA-Z_]\w*)'
    EXPLICIT_ALIAS_REGEX = Regexp.new("(.+)\\s+AS\\s+#{ALIAS_PATTERN}\\s*\\z", Regexp::IGNORECASE)
    IMPLICIT_ALIAS_REGEX = Regexp.new("(.+)\\s+#{ALIAS_PATTERN}\\s*\\z")

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
      if (m = col.match(EXPLICIT_ALIAS_REGEX))
        return { original: m[1].strip, alias: strip_backticks(m[2]) }
      end

      # 2. 暗黙的な AS: "expr alias"
      if (m = col.match(IMPLICIT_ALIAS_REGEX))
        original = m[1].strip
        # "1 + " のように演算子で終わる場合は、後続の文字列をエイリアスと見なさない
        return { original: col, alias: nil } if original.match?(%r{[+\-*/%]\z})

        return { original: original, alias: strip_backticks(m[2]) }
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
      char = clause[buffer[:index]]
      return if quote_escaped?(clause, buffer, char)

      buffer[:in_quote] = update_quote_state(char, buffer[:index], clause, buffer[:in_quote])
      return process_normal_char(clause, buffer) if buffer[:in_quote]

      process_where_logic(clause, buffer, parts)
    end

    def quote_escaped?(clause, buffer, char)
      return false unless buffer[:in_quote] && char == buffer[:in_quote] && clause[buffer[:index] + 1] == char

      buffer[:current] << char
      buffer[:index] += 1
      buffer[:current] << clause[buffer[:index]]
      buffer[:index] += 1
      true
    end

    def process_where_logic(clause, buffer, parts)
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
        consume_between_and_token(match, buffer)
        return false
      end

      process_and_operator(match, buffer, parts)
      true
    end

    def consume_between_and_token(match, buffer)
      buffer[:current] << match[0]
      buffer[:index] += match[0].length
      buffer[:in_between] = false
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
      return in_quote unless quote_char?(char) && not_escaped?(clause, index) && compatible_quote?(char, in_quote)

      return in_quote if escaped_quote?(clause, index, char, in_quote)

      in_quote == char ? nil : char
    end

    def parse_single_where_condition(condition, allow_aggregates: false)
      column_pattern = allow_aggregates ? '.+?' : '[\w.]+'

      res = parse_is_null_condition(condition, column_pattern)
      return res if res

      parse_standard_where_condition(condition, column_pattern)
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
  end

  # ユーティリティメソッドをまとめたモジュール
  module SqlParserUtils
    def parse_is_null_condition(condition, column_pattern)
      m = condition.match(/\A(#{column_pattern})\s+IS\s+(NOT\s+)?NULL\z/i)
      return nil unless m

      operator = m[2] ? 'IS NOT NULL' : 'IS NULL'
      { column: m[1], operator: operator, value: nil }
    end

    def parse_standard_where_condition(condition, column_pattern)
      res = parse_between_condition(condition, column_pattern)
      return res if res

      where_match = condition.match(/\A(#{column_pattern})\s*(=|!=|<>|>=|<=|>|<|LIKE|IN|REGEXP|RLIKE)\s*(.+)\z/i)
      return { error: 'Invalid WHERE clause' } unless where_match

      build_standard_condition(where_match)
    end

    def quote_char?(char)
      ["'", '"'].include?(char)
    end

    def not_escaped?(clause, index)
      index.zero? || clause[index - 1] != '\\'
    end

    def compatible_quote?(char, in_quote)
      in_quote.nil? || in_quote == char
    end

    def escaped_quote?(clause, index, char, in_quote)
      in_quote && clause[index + 1] == char
    end

    def strip_backticks(str)
      str.delete_prefix('`').delete_suffix('`')
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

    def split_columns(definition)
      cols = []
      buf = +''
      depth = 0
      definition.each_char { |char| depth, buf = SqlParser.process_char(char, depth, buf, cols) }
      cols << buf.strip unless buf.strip.empty?
      cols
    end

    def split_insert_values(values_str)
      # MySQLのダブルクォートエスケープ ('') を考慮した正規表現に変更
      values_str.scan(/(?:'(?:''|[^'])*'|"(?:""|[^"])*"|[^,])+/).map(&:strip)
    end

    def convert_value(val)
      if (m = val.match(/\A(['"])(.*)\1\z/m))
        content = m[2]
        return m[1] == "'" ? content.gsub("''", "'") : content
      end

      return nil if val.casecmp?('NULL')
      return val.to_i if val.match?(/\A-?\d+\z/)

      { error: "Invalid INSERT value: #{val}" }
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

      # UNION (without ALL) が一つでもあれば、全体として重複排除が必要な :union とみなす
      is_all = !query.match?(/\s+UNION\s+(?!ALL\s+)/i)
      parts = query.split(/\s+UNION\s+(?:ALL\s+)?/i).map(&:strip)
      process_parts(parts, self, union_all: is_all)
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

    def self.process_parts(parts, evaluator, union_all: false)
      state = { expected: nil, columns: nil }
      distinct_found = false
      rows = parts.map do |part|
        res = process_single_part(part, state, evaluator)
        return res if res.key?(:error)

        distinct_found ||= res[:distinct]
        res[:result]
      end
      type = determine_union_type(parts.size, union_all)
      { result: rows, columns: state[:columns], type: type, distinct: distinct_found }
    end

    def self.determine_union_type(size, union_all)
      return nil if size <= 1

      union_all ? :union_all : :union
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

      { result: result[:result], columns: result[:columns], size: result[:result].size, distinct: result[:distinct] }
    end

    def self.parse_part(part, evaluator)
      match = part.match(/\ASELECT\s+(?<distinct>DISTINCT\s+)?(?<cols>.+?)\s*;?\s*\z/i)
      return { error: 'Invalid SQL' } unless match

      col_strs = evaluator.split_args(match[:cols])
      return { error: 'Invalid SQL' } if col_strs == :error

      columns = col_strs.map { |col| parse_column_alias(col) }
      values = columns.map { |col_info| evaluator.evaluate_expression(col_info[:original]) }
      return { error: 'Unsupported expression' } if values.include?(:error)

      { result: values, columns: columns, distinct: !match[:distinct].nil? }
    end

    private_class_method :parse_insert, :parse_select_from, :parse_create_table,
                         :parse_drop_table, :parse_update, :parse_delete,
                         :parse_show_tables, :parse_describe,
                         :process_parts, :process_single_part, :validate_part,
                         :parse_part, :extract_update_parts, :build_update_result,
                         :determine_union_type
  end
end
