# frozen_string_literal: true

module RubyPureMysql
  # 集計関数の計算ロジックを提供するモジュール
  module AggregateUtils
    AGGREGATE_REGEX = /\A(COUNT|SUM|AVG|MIN|MAX)\((.*)\)\z/i

    def calculate_aggregate_value(values, type)
      return values.size if type == :count
      return nil if values.empty?

      type == :avg ? values.sum / values.size : values.public_send(type)
    end

    def resolve_group_column_value(columns, col, group_val, group_rows, group_indices)
      col_idx = columns.index(col)
      return nil unless col_idx

      rel_idx = group_indices.index(col_idx)
      rel_idx ? group_val[rel_idx] : group_rows.first[col_idx]
    end

    def compute_aggregate_for_group(columns, agg, group_rows)
      agg_type = agg[:type]
      agg_col = agg[:column]
      return group_rows.size if agg_col == '*'

      agg_idx = columns.index(agg_col)
      return :error unless agg_idx

      values = group_rows.filter_map { |r| r[agg_idx] }.map(&:to_f)
      calculate_aggregate_value(values, agg_type)
    end

    def resolve_aggregate_non_col(rows, columns, col)
      col_idx = columns.index(col)
      col_idx ? rows.first&.[](col_idx) : nil
    end

    def compute_single_aggregate_value(rows, columns, agg)
      return rows.size if agg[:column] == '*'

      col_idx = columns.index(agg[:column])
      return :error unless col_idx

      values = rows.filter_map { |r| r[col_idx] }.map(&:to_f)
      calculate_aggregate_value(values, agg[:type])
    end
  end
end
