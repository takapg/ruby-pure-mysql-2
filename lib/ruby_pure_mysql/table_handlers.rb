# frozen_string_literal: true

require_relative 'table_handler_utils'

module RubyPureMysql
  # スキーマ操作に関連するハンドラメソッドをまとめたモジュール
  module SchemaHandlers
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

    def handle_describe(client, result)
      table_name = result[:table_name]
      columns = @storage_engine.get_columns(table_name)
      return send_err_packet(client, 1, "Table '#{table_name}' doesn't exist", 1146) unless columns

      rows = columns.map { |col| [col, 'VARCHAR(255)'] }
      send_result_set(client, rows, ['Field', 'Type'])
    end

    def prepare_where_clauses(client, columns, where)
      return [] unless where

      compile_where_clauses(client, columns, where)
    end

    def handle_delete(client, result)
      columns = validate_table(client, result[:table_name])
      return unless columns

      where_clauses = prepare_where_clauses(client, columns, result[:where])
      return unless where_clauses

      if @storage_engine.delete_rows_with_where(result[:table_name], where_clauses)
        send_ok_packet(client, 1)
      end
    end
  end
end
