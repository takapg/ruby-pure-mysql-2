# frozen_string_literal: true

require_relative 'group_by_handlers'
require_relative '../group_utils'
require_relative '../aggregate_handler_utils'

module RubyPureMysql
  # クエリ操作に関連するハンドラメソッド
  module QueryHandlers
    include GroupByHandlers
    include GroupUtils
    include AggregateHandlerUtils

    def handle_select(client, result)
      table_map = initialize_table_map(client, result)
      columns = table_map.values.first
      return unless columns

      if result[:join]
        join_res = handle_join_logic(client, result, columns, table_map)
        return unless join_res

        result[:joined_rows], columns = join_res
      end

      dispatch_select_type(client, columns, result, table_map)
    end

    def initialize_table_map(client, result)
      columns = validate_table(client, result[:table_name])
      return {} unless columns

      { result[:table_alias] || result[:table_name] => columns }
    end

    def handle_join_logic(client, result, columns, table_map)
      cols2 = validate_table(client, result[:join][:table2])
      return nil unless cols2

      alias_name = result[:join][:alias2] || result[:join][:table2]
      table_map[alias_name] = cols2
      perform_inner_join(client, build_join_params(result, columns, cols2, table_map))
    end

    def build_join_params(result, columns, cols2, table_map)
      {
        rows1: @storage_engine.select(result[:table_name]),
        cols1: columns,
        rows2: @storage_engine.select(result[:join][:table2]),
        cols2: cols2,
        on: result[:join][:on],
        table_map: table_map
      }
    end

    def dispatch_select_type(client, columns, result, table_map)
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

      rows.select do |row|
        where_clauses.all? do |c|
          target = c[:regex] || c[:value]
          apply_filter(row[c[:col_idx]], c[:operator], target)
        end
      end
    end
  end
end
