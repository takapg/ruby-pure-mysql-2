# frozen_string_literal: true

module RubyPureMysql
  # ソート操作を支援するモジュール
  module SortUtils
    def apply_order_by(client, order_by, table_columns, rows, selected_columns = nil)
      sort_conditions = []
      order_by.each do |cond|
        idx = resolve_order_by_column_index(client, table_columns, cond[:column], selected_columns)
        if idx.nil?
          send_err_packet(client, 1, "Unknown column '#{cond[:column]}' in 'order clause'", 1054)
          return nil
        end
        sort_conditions << { index: idx, direction: cond[:direction] }
      end

      sort_rows(rows, sort_conditions)
    end

    def resolve_order_by_column_index(client, table_columns, col_name, selected_columns)
      name = col_name
      if selected_columns
        name = selected_columns.find { |c| c.is_a?(Hash) && c[:alias]&.casecmp?(name) }&.dig(:original) || name
      end
      get_column_index(client, table_columns, name)
    end

    def sort_rows(rows, sort_conditions)
      rows.sort do |a, b|
        comparison = 0
        sort_conditions.each do |cond|
          res = compare_values(a, b, cond)
          comparison = res * (cond[:direction] == :DESC ? -1 : 1)
          break if comparison != 0
        end
        comparison
      end
    end

    def compare_values(row_a, row_b, cond)
      val_a = row_a[cond[:index]]
      val_b = row_b[cond[:index]]

      res = (val_a.nil? ? 0 : 1) <=> (val_b.nil? ? 0 : 1)
      return res unless res.zero?

      begin
        (val_a <=> val_b) || 0
      rescue StandardError
        0
      end
    end

    def compare_rows(row_a, row_b, sort_conditions)
      comparison = 0
      sort_conditions.each do |cond|
        res = compare_values(row_a, row_b, cond)
        comparison = res * (cond[:direction] == :DESC ? -1 : 1)
        break if comparison != 0
      end
      comparison
    end

    def resolve_sort_conditions(client, table_columns, order_by, selected_columns = nil)
      order_by.filter_map do |cond|
        idx = resolve_order_by_column_index(client, table_columns, cond[:column], selected_columns)
        next nil unless idx

        { index: idx, direction: cond[:direction] }
      end
    end
  end
end
