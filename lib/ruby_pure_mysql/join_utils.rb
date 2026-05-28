# frozen_string_literal: true

module RubyPureMysql
  # JOIN操作の実行を支援するモジュール
  module JoinUtils
    def perform_join(client, params)
      left_idx, right_idx, all_cols = resolve_join_indices(
        client, params[:cols1], params[:cols2], params[:on], params[:table_map]
      )
      return [[], all_cols] if left_idx.nil? || right_idx.nil?

      [execute_join_loop(params[:rows1], params[:rows2], left_idx, right_idx, params[:join_type], params[:cols2].size), all_cols]
    end

    def resolve_join_indices(client, cols1, cols2, on_condition, table_map)
      left_expr, right_expr = on_condition.split('=').map(&:strip)
      all_cols = cols1 + cols2
      [
        get_column_index(client, all_cols, left_expr, table_map),
        get_column_index(client, all_cols, right_expr, table_map),
        all_cols
      ]
    end

    def execute_join_loop(rows1, rows2, left_idx, right_idx, join_type, right_col_count)
      joined_rows = []
      rows1.each do |r1|
        matched = false
        rows2.each do |r2|
          row = r1 + r2
          next if row[left_idx].nil? || row[right_idx].nil?

          if row[left_idx] == row[right_idx]
            joined_rows << row
            matched = true
          end
        end
        if !matched && join_type == 'LEFT'
          joined_rows << (r1 + Array.new(right_col_count, nil))
        end
      end
      joined_rows
    end
  end
end
