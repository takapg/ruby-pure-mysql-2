# frozen_string_literal: true

module RubyPureMysql
  # テーブル操作の補助メソッドをまとめたモジュール
  module TableHandlerUtils
    def validate_table_and_where(client, result)
      columns = @storage_engine.get_columns(result[:table_name])
      unless columns
        send_err_packet(client, 1, "Table '#{result[:table_name]}' doesn't exist", 1146)
        return nil
      end

      unless result[:where]
        send_err_packet(client, 1, 'WHERE clause is required', 1064)
        return nil
      end

      columns
    end

    def get_column_index(client, columns, column_name)
      idx = columns.index(column_name)
      unless idx
        send_err_packet(client, 1, "Unknown column '#{column_name}'", 1054)
        return nil
      end

      idx
    end

    def get_update_indices(client, columns, result)
      col_idx = get_column_index(client, columns, result[:column])
      return nil unless col_idx

      where_col_idx = get_column_index(client, columns, result[:where][:column])
      return nil unless where_col_idx

      [col_idx, where_col_idx]
    end
  end
end
