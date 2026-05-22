# frozen_string_literal: true

require_relative 'table_handler_utils'

module RubyPureMysql
  # テーブル操作に関連するハンドラメソッドをまとめたモジュール
  module TableHandlers
    include TableHandlerUtils

    def handle_create_table(client, result)
      @storage_engine.create_table(result[:table_name], result[:columns])
      send_ok_packet(client, 1, 0, 0)
    end

    def handle_drop_table(client, result)
      @storage_engine.drop_table(result[:table_name])
      send_ok_packet(client, 1, 0, 0)
    end

    def handle_insert(client, result)
      columns = @storage_engine.get_columns(result[:table_name])
      unless columns
        return send_err_packet(client, 1, "Table '#{result[:table_name]}' doesn't exist", 1146)
      end

      @storage_engine.insert(result[:table_name], result[:values])
      send_ok_packet(client, 1, 0, 0)
    end

    def handle_update(client, result)
      @storage_engine.update(result[:table_name], result[:column], result[:value], result[:where])
      send_ok_packet(client, 1, 0, 0)
    end

    def handle_delete(client, result)
      @storage_engine.delete(result[:table_name], result[:where])
      send_ok_packet(client, 1, 0, 0)
    end

    def handle_select(client, result)
      rows = @storage_engine.select(result[:table_name], result[:columns], result[:where])
      send_result_set(client, rows, result[:columns])
    end

    def handle_show_tables(client, _result)
      tables = @storage_engine.show_tables
      send_result_set(client, tables.map { |t| [t] }, ['Tables_in_mysql'])
    end

    def handle_describe(client, result)
      columns = @storage_engine.get_columns(result[:table_name])
      unless columns
        return send_err_packet(client, 1, "Table '#{result[:table_name]}' doesn't exist", 1146)
      end

      # MySQLのDESCRIBE出力形式に合わせる
      # 現時点では簡易的にTypeをtext、NullをYESとして返却
      rows = columns.map do |col|
        [col, 'text', 'YES', '', nil, '']
      end

      send_result_set(client, rows, ['Field', 'Type', 'Null', 'Key', 'Default', 'Extra'])
    end
  end
end
