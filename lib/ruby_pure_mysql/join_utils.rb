# frozen_string_literal: true

module RubyPureMysql
  # JOIN操作の実行を支援するモジュール
  module JoinUtils
    def perform_join(client, params)
      left_idx, right_idx, all_cols = resolve_join_indices(
        client, params[:cols1], params[:cols2], params[:on], params[:table_map]
      )
      return [[], all_cols] if left_idx.nil? || right_idx.nil?

      options = build_join_options(left_idx, right_idx, params)
      [execute_join_loop(params[:rows1], params[:rows2], options), all_cols]
    end

    private

    def build_join_options(left_idx, right_idx, params)
      {
        left_idx: left_idx,
        right_idx: right_idx,
        join_type: params[:join_type],
        right_col_count: params[:cols2].size
      }
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

    def execute_join_loop(rows1, rows2, options)
      rows1.flat_map do |r1|
        matches = find_matches(r1, rows2, options)
        if matches.empty? && options[:join_type] == 'LEFT'
          [r1 + Array.new(options[:right_col_count], nil)]
        else
          matches
        end
      end
    end

    def find_matches(row1, rows2, options)
      rows2.each_with_object([]) do |row2, acc|
        row = row1 + row2
        acc << row if row[options[:left_idx]] == row[options[:right_idx]] && !row[options[:left_idx]].nil?
      end
    end
  end
end
