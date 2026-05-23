# frozen_string_literal: true

require_relative 'table_handler_utils'

module RubyPureMysql
  # テーブル操作に関連するハンドラメソッドをまとめたモジュール
  module TableHandlers
    include TableHandlerUtils

    def handle_create_table(client, result)
      if @storage_engine.create_table(result[:table_name], result[:columns]) || result[:if_not_exists]
        send_ok_packet(client, 1)
      else
        send_err_packet(client, 1, "Table '#{result[:table_name]}' already exists", 1050)
      end
    end

    def handle_drop_table(client, result)
      if @storage_engine.drop_table(result[:table_name])
        send_ok_packet(client, 1)
      else
        send_err_packet(client, 1, "Table '#{result[:table_name]}' doesn't exist", 1051)
      end
    end

    def handle_show_tables(client, _result)
      tables = @storage_engine.list_tables
      rows = tables.map { |t| [t] }
      send_result_set(client, rows, ['Tables_in_mysql'])
    end

    def handle_describe(client, result)
      table_name = result[:table_name]
      columns = @storage_engine.get_columns(table_name)
      return send_err_packet(client, 1, "Table '#{table_name}' doesn't exist", 1146) unless columns

      rows = columns.map { |col| [col, 'VARCHAR(255)'] }
      send_result_set(client, rows, %w[Field Type])
    end

    def prepare_where_clauses(client, columns, where)
      return [] if where.nil?

      compile_where_clauses(client, columns, where)
    end

    def handle_insert(client, result)
      columns = validate_table(client, result[:table_name])
      return unless columns

      if @storage_engine.insert(result[:table_name], result[:values])
        send_ok_packet(client, 1)
      else
        send_err_packet(client, 1, "Failed to insert into '#{result[:table_name]}'", 1000)
      end
    end

    def handle_update(client, result)
      columns = validate_table(client, result[:table_name])
      return unless columns

      where_clauses = prepare_where_clauses(client, columns, result[:where])
      return unless where_clauses

      # 複数カラム更新を想定し、StorageEngineへ渡す
      return unless @storage_engine.update_rows_with_where(result[:table_name], where_clauses, result[:set])

      send_ok_packet(client, 1)
    end

    def handle_delete(client, result)
      columns = validate_table(client, result[:table_name])
      return unless columns

      where_clauses = prepare_where_clauses(client, columns, result[:where])
      return unless where_clauses

      return unless @storage_engine.delete_rows_with_where(result[:table_name], where_clauses)

      send_ok_packet(client, 1)
    end
  end
end
