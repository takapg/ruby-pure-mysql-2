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

      # MySQL DESCRIBE output format: Field, Type, Null, Key, Default, Extra
      column_names = %w[Field Type Null Key Default Extra]
      rows = columns.map do |col|
        [col, 'text', 'YES', '', nil, '']
      end

      send_result_set(client, rows, column_names)
    end
  end

  # クエリ操作に関連するハンドラメソッドをまとめたモジュール
  module QueryHandlers
    def handle_select(client, result)
      table_columns = @storage_engine.get_columns(result[:table_name])
      return send_err_packet(client, 1, "Table '#{result[:table_name]}' doesn't exist", 1146) unless table_columns

      rows = @storage_engine.select(result[:table_name])
      if result[:where_clauses]
        rows = apply_where_filter(client, result[:where_clauses], table_columns, rows)
        return unless rows
      end

      rows = apply_optional_clauses(client, result, table_columns, rows)
      return unless rows

      send_select_result(client, result, rows, table_columns)
    end

    def apply_optional_clauses(client, result, table_columns, rows)
      if result[:order_by]
        rows = apply_order_by(client, result[:order_by], table_columns, rows)
        return nil unless rows
      end

      rows = rows.drop(result[:offset]) if result[:offset]
      rows = rows.take(result[:limit]) if result[:limit]
      rows
    end

    def send_select_result(client, result,