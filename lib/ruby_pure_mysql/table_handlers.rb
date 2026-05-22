# frozen_string_literal: true

require_relative 'table_handler_utils'

module RubyPureMysql
  # テーブル操作に関連するハンドラメソッドをまとめたモジュール
  module TableHandlers
    include TableHandlerUtils

    def handle_insert(client, result)
      columns = @storage_engine.get_columns(result[:table_name])
      unless columns
        return send_err_packet(client, 1, "Table '#{result[:table_name]}' doesn't exist", 1146)
      end

      # 既存の処理（仮定）
      @storage_engine.insert(result[:table_name], result[:values])
      send_ok_packet(client, 1, 0, 0)
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

    # 他のハンドラメソッド（handle_create_table, handle_drop_table, handle_update, handle_delete, handle_select, handle_show_tables）は
    # 既存の実装がここに含まれている前提で記述してください。
    # 今回は修正が必要な箇所のみを明示的に記述しました。
  end
end
