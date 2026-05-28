# frozen_string_literal: true

require_relative 'group_by_handlers'

module RubyPureMysql
  # クエリ操作に関連するハンドラメソッド
  module QueryHandlers
    include GroupByHandlers

    def handle_select(client, result)
      table_map = {}
      columns = validate_table(client, result[:table_name])
      return unless columns
      table_map[result[:table_name]] = columns

      if result[:join]
        cols2 = validate_table(client, result[:join][:table2])
        return unless cols2
        table_map[result[:join][:table2]] = cols2

        rows1 = @storage_engine.select(result[:table_name])
        rows2 = @storage_engine.select(result[:join][:table2])
        
        joined_rows, joined_cols = perform_inner_join(rows1, columns, rows2, cols2, result[:join][:on])
        
        result[:joined_rows] = joined_rows
        columns = joined_cols
      end

      if result[:group_by] || result[:having]
        handle_group_by_select(client, columns, result)
      elsif result[:aggregates] && !result[:aggregates].empty?
        handle_aggregate(client, columns, result)
      else
        handle_standard_select(client, columns, result, table_map)
      end
    end

    def handle_group_by_select(client, columns, result)
      rows, indices = prepare_group_by_data(client, columns, result)
      return if rows.nil? || indices.nil?

      grouped = group_rows_by_indices(rows, indices)
      grouped = apply_having_filter(client, columns, grouped, result, indices) || return

      res_rows = compute_grouped_rows(columns, result, grouped, indices)
      return handle_group_by_error(client) if group_computation_failed?(res_rows)

      finalize_and_send_group_results(client, result, res_rows)
    end

    def prepare_group_by_data(client, columns, result)
      rows = fetch_and_filter_rows(client, columns, result)
      indices = nil
      if rows
        indices = result[:group_by] ? get_group_column_indices(client, columns, result[:group_by]) : []
      end
      [rows, indices]
    end

    def apply_having_filter(client, columns, grouped, result, indices)
      return grouped unless result[:having]

      begin
        filter_grouped_by_having(columns, grouped, result[:having], indices)
      rescue TableHandlerUtils::HavingError
        send_err_packet(client, 1, "Unknown column in 'having clause'", 1054)
        nil
      end
    end

    def group_rows_by_indices(rows, indices)
      return { [] => rows } if indices.empty?

      rows.group_by { |row| indices.map { |idx| row[idx] } }
    end

    def group_computation_failed?(res_rows)
      res_rows.nil? || res_rows.any? { |row| row.include?(:error) }
    end

    def handle_group_by_error(client)
      send_err_packet(client, 1, 'Error executing GROUP BY query', 1105)
    end

    def handle_aggregate(client, columns, result)
      rows = fetch_and_filter_rows(client, columns, result.merge(limit: nil, offset: nil, order: nil))
      return if rows.nil?

      res_row = build_aggregate_row(rows, columns, result)
      return send_err_packet(client, 1, 'Error executing aggregate query', 1105) if res_row == :error

      res_rows = [res_row]
      final_rows = apply_offset_and_limit(res_rows, result)
      send_result_set(client, final_rows, result[:columns])
    end

    def build_aggregate_row(rows, columns, result)
      result[:columns].each_with_index.map do |col, idx|
        agg = result[:aggregates].find { |a| a[:index] == idx }
        if agg
          val = compute_single_aggregate_value(rows, columns, agg)
          return :error if val == :error

          val
        else
          resolve_aggregate_non_col(rows, columns, col)
        end
      end
    end

    def handle_standard_select(client, columns, result, table_map = {})
      rows = fetch_and_filter_rows(client, columns, result, table_map)
      return if rows.nil?

      rows, final_columns = project_rows(client, rows, columns, result[:columns], table_map)
      return if rows.nil?

      rows.uniq! if result[:distinct]

      rows = apply_order_by(client, result[:order], final_columns, rows) if result[:order]
      return if rows.nil?

      rows = apply_offset_and_limit(rows, result)
      send_result_set(client, rows, final_columns)
    end

    def fetch_and_filter_rows(client, columns, result, table_map = {})
      rows = result[:joined_rows] || @storage_engine.select(result[:table_name])
      rows = filter_rows(client, columns, rows, result[:where], table_map) if result[:where]
      return nil if rows.nil?

      rows
    end

    def filter_rows(client, columns, rows, where, table_map = {})
      where_clauses = prepare_where_clauses(client, columns, where, table_map)
      return nil if where_clauses.nil?

      rows.select { |row| @storage_engine.send(:match_row?, row, columns, where_clauses) }
    end
  end
end
