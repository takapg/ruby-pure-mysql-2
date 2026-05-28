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
        '(?:\s+ORDER\s+BY\s+(?<order_col>.+?)(?:\s+(?<order_dir>ASC|DESC))?)?',
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

      res = apply_optional_clauses(result, match)
      return res if res.is_a?(Hash) && res[:error]

      result
    end

    def apply_optional_clauses(result, match)
      result[:group_by] = match[:group_by] if match[:group_by]
      if match[:having]
        res = parse_having_clause(result, match[:having])
        return res if res.is_a?(Hash) && res[:error]
      end

      parse_order_by_clause(result, match[:order_col], match[:order_dir]) if match[:order_col]
      parse_limit_offset_clause(result, match[:limit], match[:offset])
      nil
    end

    def parse_having_clause(result, clause)
      having = parse_where_clause(clause, allow_aggregates: true)
      return having if having.is_a?(Hash) && having[:error]

      result[:having] = having
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
      if (m = col.match(/(.+)\s+AS\s+([a-zA-Z_]\w*)\z/i))
        return { original: m[1].strip, alias: m[2] }
      end

      # 2. 暗黙的な AS: "expr alias"
      # "a + b" のような式を誤って分割しないよう、直前が演算子で終わっていないことを確認する
      if (m = col.match(/(.+)\s+([a-zA-Z_]\w*)\z/))
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
      { type: match[1].downcase.to_sym, column: match[2], index: idx }
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
      tokens = tokenize(clause)
      state = { tokens: tokens, pos: 0 }
      ast = parse_or(state, allow_aggregates)
      return { error: 'Invalid WHERE clause' } if ast.nil?

      ast
    end

    def tokenize(clause)
      clause.scan(/\s*(\(|\)|\bAND\b|\bOR\b|'[^']*'|"[^"]*"|[^\s()]+)\s*/i).flatten
    end

    def parse_or(state, allow_aggregates)
      node = parse_and(state, allow_aggregates)
      return { error: 'Invalid WHERE clause' } if node.is_a?(Hash) && node[:error]

      while state[:pos] < state[:tokens].size && state[:tokens][state[:pos]].upcase == 'OR'
        state[:pos] += 1
        right = parse_and(state, allow_aggregates)
        return { error: 'Invalid WHERE clause' } if right.is_a?(Hash) && right[:error]
        node = { op: :or, left: node, right: right }
      end
      node
    end

    def parse_and(state, allow_aggregates)
      node = parse_primary(state, allow_aggregates)
      return { error: 'Invalid WHERE clause' } if node.is_a?(Hash) && node[:error]

      while state[:pos] < state[:tokens].size && state[:tokens][state[:pos]].upcase == 'AND'
        state[:pos] += 1
        right = parse_primary(state, allow_aggregates)
        return { error: 'Invalid WHERE clause' } if right.is_a?(Hash) && right[:error]
        node = { op: :and, left: node, right: right }
      end
      node
    end

    def parse_primary(state, allow_aggregates)
      return { error: 'Unexpected end of clause' } if state[:pos] >= state[:tokens].size

      if state[:tokens][state[:pos]] == '('
        # グループ化の括弧
        state[:pos] += 1
        node = parse_or(state, allow_aggregates)
        state[:pos] += 1 if state[:pos] < state[:tokens].size && state[:tokens][state[:pos]] == ')'
        node
      else
        # 条件式 (COUNT(*) などの関数呼び出しを含む可能性がある)
        condition = collect_condition_tokens(state)
        return { error: 'Invalid WHERE clause' } if condition.empty?

        parse_single_where_condition(condition)
      end
    end

    def collect_condition_tokens(state)
      condition_tokens = []
      depth = 0
      while state[:pos] < state[:tokens].size
        token = state[:tokens][state[:pos]]
        if token == '('
          depth += 1
        elsif token == ')'
          break if depth.zero?
          depth -= 1
        elsif depth.zero? && %w[AND OR].include?(token.upcase)
          break
        end
        condition_tokens << token
        state[:pos] += 1
      end
      condition_tokens.join(' ').strip
    end

    def parse_single_where_condition(condition)
      # カラム名や集計関数（COUNT(*)など）に対応するため、
      # 最初の演算子が出現するまでをカラム/式として取得する
      where_match = condition.match(/\A(.+?)\s*(=|!=|<>|>=|<=|>|<|LIKE)\s*(.+)\z/i)
      return { error: 'Invalid WHERE clause' } unless where_match

      column = where_match[1].strip
      operator = where_match[2].upcase
      operator = '!=' if operator == '<>'
      value_str = where_match[3].strip.delete_suffix(';')
      value = convert_value(value_str)
      return { error: 'Unsupported WHERE value' } if value.is_a?(Hash) && value[:error]

      { column: column, operator: operator, value: value }
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
