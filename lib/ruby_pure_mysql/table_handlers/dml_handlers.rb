# frozen_string_literal: true

module RubyPureMysql
  # DML操作に関連するハンドラメソッド
  module DmlHandlers
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

      update_map = {}
      result[:updates].each do |update|
        col_idx = get_column_index(client, columns, update[:column])
        return send_err_packet(client, 1, "Unknown column '#{update[:column]}'", 1054) unless col_idx

        update_map[col_idx] = update[:value]
      end

      perform_update(client, result, where_clauses, update_map)
    end

    def perform_update(client, result, where_clauses, update_map)
      if @storage_engine.update_rows_with_where(result[:table_name], where_clauses, update_map)
        send_ok_packet(client, 1)
      else
        send_err_packet(client, 1, 'Update failed', 1000)
      end
    end

    def handle_delete(client, result)
      columns = validate_table(client, result[:table_name])
      return unless columns

      where_clauses = prepare_where_clauses(client, columns, result[:where])
      return unless where_clauses

      if @storage_engine.delete_rows_with_where(result[:table_name], where_clauses)
        send_ok_packet(client, 1)
      else
        send_err_packet(client, 1, 'Delete failed', 1000)
      end
    end
  end
end
