# frozen_string_literal: true

require_relative 'table_handler_utils'

module RubyPureMysql
  # テーブル操作に関連するハンドラメソッドをまとめたモジュール
  module TableHandlers
    include TableHandlerUtils

    def handle_insert(client, result)
      columns = @storage_engine.get_columns(result[:table_name])
      return send_err_packet(client, 1, "Table '#{result[:table_name]}' doesn't exist", 1146) unless columns

      if result[:values].size != columns.size
        return send_err_packet(client, 1, 'Column count doesn\'t match value count at row 1', 1136)
      end

      success = @storage_engine.insert(result[:table_name], result[:values])
      return send_err_packet(client, 1, "Table '#{result[:table_name]}' doesn't exist", 1146) unless success

      send_ok_packet(client, 1)
    end

    def handle_update(client, result)
      columns = validate_table(client, result[:table_name])
      return unless columns

      indices = get_update_indices(client, columns, result)
      return unless indices

      where_value = result[:where] ? result[:where][:value] : nil
      success = @storage_engine.update(result[:table_name], *indices, result[:value], where_value)
      return send_err_packet(client, 1, "Table '#{result[:table_name]}' doesn't exist", 1146) unless success

      send_ok_packet(client, 1)
    end

    def handle_delete(client, result)
      columns = validate_table(client, result[:table_name])
      return unless columns

      params = get_delete_params(client, columns, result)
      return unless params

      success = @storage_engine.delete(result[:table_name], *params)
      return send_err_packet(client, 1, "Table '#{result[:table_name]}' doesn't exist", 1146) unless success

      send_ok_packet(client, 1)
    end

    def handle_select(client, result)
      table_columns = @storage_engine.get_columns(result[:table_name])
      return send_err_packet(client, 1, "Table '#{result[:table_name]}' doesn't exist", 1146) unless table_columns

      rows = @storage_engine.select(result[:table_name])
      rows = apply_where_filter(client, result[:where], table_columns, rows) if result[:where]
      return unless rows

      send_select_result(client, result, rows, table_columns)
    end

    def send_select_result(client, result, rows, table_columns)
      if result[:columns] == ['*']
        send_result_set(client, rows, table_columns)
      else
        handle_projection(client, result, rows, table_columns)
      end
    end

    def apply_where_filter(client, where_clause, table_columns, rows)
      col_idx = table_columns.index(where_clause[:column])
      unless col_idx
        send_err_packet(client, 1, "Unknown column '#{where_clause[:column]}' in WHERE clause", 1054)
        return nil
      end

      rows.select { |row| row[col_idx] == where_clause[:value] }
    end

    def handle_projection(client, result, rows, table_columns)
      indices = result[:columns].map { |col| table_columns.index(col) }

      if indices.include?(nil)
        send_err_packet(client, 1, 'Unknown column in field list', 1054)
        return
      end

      projected_rows = rows.map { |row| indices.map { |i| row[i] } }
      send_result_set(client, projected_rows, result[:columns])
    end

    def handle_create_table(client, result)
      if @storage_engine.create_table(result[:table_name], result[:columns]) || result[:if_not_exists]
        send_ok_packet(client, 1)
      else
        send_err_packet(client, 1, "Table '#{result[:table_name]}' already exists", 1050)
      end
    end

    def handle_drop_table(client, result)
      if @storage_engine.drop_table(result[:table_name]) || result[:if_exists]
        send_ok_packet(client, 1)
      else
        send_err_packet(client, 1, "Unknown table '#{result[:table_name]}'", 1051)
      end
    end

    def handle_show_tables(client, _result)
      tables = @storage_engine.list_tables
      columns = ['Tables_in_mysql']
      rows = tables.zip
      send_result_set(client, rows, columns)
    end
  end
end
