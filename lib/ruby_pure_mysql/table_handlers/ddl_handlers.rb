# frozen_string_literal: true

module RubyPureMysql
  # DDL操作に関連するハンドラメソッド
  module DdlHandlers
    def handle_create_table(client, result)
      created = @storage_engine.create_table(result[:table_name], result[:columns], result[:indexes] || {})
      if created || result[:if_not_exists]
        send_ok_packet(client, 1)
      else
        send_err_packet(client, 1, "Table '#{result[:table_name]}' already exists", 1050)
      end
    end

    def handle_drop_table(client, result)
      if @storage_engine.drop_table(result[:table_name]) || result[:if_exists]
        send_ok_packet(client, 1)
      else
        send_err_packet(client, 1, "Table '#{result[:table_name]}' doesn't exist", 1051)
      end
    end

    def handle_show_tables(client, _result)
      tables = @storage_engine.list_tables
      rows = tables.zip
      send_result_set(client, rows, ['Tables_in_mysql'])
    end

    def handle_describe(client, result)
      table_name = result[:table_name]
      columns = @storage_engine.get_columns(table_name)
      return send_err_packet(client, 1, "Table '#{table_name}' doesn't exist", 1146) unless columns

      rows = columns.map { |col| [col, 'VARCHAR(255)'] }
      send_result_set(client, rows, %w[Field Type])
    end
  end
end
