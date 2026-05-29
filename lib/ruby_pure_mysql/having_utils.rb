# frozen_string_literal: true

require_relative 'column_utils'
require_relative 'aggregate_utils'

module RubyPureMysql
  # HAVING句の評価を支援するモジュール
  module HavingUtils
    include ColumnUtils
    include AggregateUtils

    class HavingError < StandardError; end

    def evaluate_having_condition(group_val, group_rows, clause, group_ctx)
      val = resolve_having_value(group_val, group_rows, clause[:column], group_ctx)
      raise HavingError, 'Unknown column' if %i[no_column error].include?(val)

      apply_filter(val, clause[:operator], clause[:value])
    end

    def resolve_having_value(group_val, group_rows, col_expr, group_ctx)
      if (m = col_expr.match(AggregateUtils::AGGREGATE_REGEX))
        return resolve_aggregate_having_value(group_rows, m, group_ctx[:columns])
      end

      resolve_group_column_having_value(group_val, col_expr, group_ctx)
    end

    def resolve_aggregate_having_value(group_rows, match, columns)
      agg = RubyPureMysql::SqlParser.parse_aggregate_column(match, nil)
      compute_single_aggregate_value(group_rows, columns, agg)
    end

    def resolve_group_column_having_value(group_val, col_expr, group_ctx)
      col_idx = get_column_index(nil, group_ctx[:columns], col_expr, group_ctx[:table_map])
      return :no_column unless col_idx

      group_idx = group_ctx[:indices].index(col_idx)
      msg = "Column '#{col_expr}' must appear in the GROUP BY clause or be used in an aggregate function"
      raise HavingError, msg if group_idx.nil?

      group_val[group_idx]
    end
  end
end
