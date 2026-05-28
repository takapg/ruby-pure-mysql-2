# frozen_string_literal: true

module RubyPureMysql
  # JOIN操作の実行を支援するモジュール
  module JoinUtils
    def perform_inner_join(client, rows1, cols1, rows2, cols2, on_condition, table_map)
      left_idx, right_idx, all_cols = resolve_join_indices(client, cols1, cols2, on_condition, table_map)
      return [[], all_cols] if left_idx.nil? || right_idx.nil?

      [execute_join_loop(rows1, rows2, left_idx, right_idx), all_cols]
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

    def execute_join_loop(rows1, rows2, left_idx, right_idx)
      joined_rows = []
      rows1.each do |r1|
        rows2.each do |r2|
          row = r1 + r2
          next if row[left_idx].nil? || row[right_idx].nil?

          joined_rows << row if row[left_idx] == row[right_idx]
        end
      end
      joined_rows
    end
  end
end
