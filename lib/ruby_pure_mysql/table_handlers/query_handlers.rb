# frozen_string_literal: true

module RubyPureMysql
  # クエリ操作に関連するハンドラメソッド
  module QueryHandlers
    def handle_select(client, result)
      columns = validate_table(client, result[:table_name])
      return unless columns

      if result[:group_by]
        handle_group_by_select(client, columns, result)
      elsif result[:aggregates] && !result[:aggregates].empty?
        handle_aggregate(client, columns, result)
      else
        handle_standard_select(client, columns, result)
      end
    end

    def handle_group_by_select(client, columns, result)
      rows = fetch_and_filter_rows(client, columns, result)
      return if rows.nil?

      group_indices = get_group_column_indices(client, columns, result[:group_by])
      return unless group_indices

      res_rows = compute_grouped_results(columns, result, rows, group_indices)
      if res_rows.nil?
        send_err_packet(client, 1, "Unknown column in 'field list'", 1054)
        return
      end

      finalize_and_send_group_results(client, result, res_rows)
    end

    def compute_grouped_results(columns, result, rows, group_indices)
      grouped = rows.group_by { |row| group_indices.map { |idx| row[idx] } }
      res_rows = grouped.map do |group_val, group_rows|
        compute_group_row(columns, result, group_val, group_rows, group_indices)
      end

      res_rows.any? { |row| row.include?(:error) } ? nil : res_rows
    end

    def finalize_and_send_group_results(client, result, res_rows)
      res_rows = apply_order_by(client, result[:order], result[:columns], res_rows) if result[:order]
      return if res_rows.nil?

      res_rows = apply_offset_and_limit(res_rows, result)
      send_result_set(client, res_rows, result[:columns])
    end

    def compute_group_row(columns, result, group_val, group_rows, group_indices)
      result[:columns].each_with_index.map do |col, idx|
        agg = result[:aggregates]&.find { |a| a[:index] == idx }
        if agg
          compute_aggregate_for_group(columns, agg, group_rows)
        else
          resolve_group_column_value(columns, col, group_val, group_rows, group_indices)
        end
      end
    end

    def handle_aggregate(client, columns, result)
      rows = fetch_and_filter_rows(client, columns, result.merge(limit: nil, offset: nil, order: nil))
      return if rows.nil?

      res_row = build_aggregate_row(rows, columns, result)
      return if res_row == :error

      res_rows = [res_row]
      final_rows = apply_offset_and_limit(res_rows, result)
      send_result_set(client, final_rows, result[:columns])
    end

    def build_aggregate_row(rows, columns, result)
      result[:columns].map do |col|
        agg = result[:aggregates].find { |a| a[:index] == result[:columns].index(col) }
        if agg
          val = compute_single_aggregate_value(rows, columns, agg)
          return :error if val == :error

          val
        else
          resolve_aggregate_non_col(rows, columns, col)
        end
      end
    end

    def handle_standard_select(client, columns, result)
      rows = fetch_and_filter_rows(client, columns, result)
      return if rows.nil?

      rows, final_columns = project_rows(client, rows, columns, result[:columns])
      return if rows.nil?

      rows.uniq! if result[:distinct]

      rows = apply_order_by(client, result[:order], final_columns, rows) if result[:order]
      return if rows.nil?

      rows = apply_offset_and_limit(rows, result)
      send_result_set(client, rows, final_columns)
    end

    def fetch_and_filter_rows(client, columns, result)
      rows = @storage_engine.select(result[:table_name])
      rows = filter_rows(client, columns, rows, result[:where]) if result[:where]
      return nil if rows.nil?

      rows
    end

    def filter_rows(client, columns, rows, where)
      where_clauses = prepare_where_clauses(client, columns, where)
      return nil if where_clauses.nil?

      rows.select { |row| @storage_engine.send(:match_row?, row, columns, where_clauses) }
    end
  end
end
