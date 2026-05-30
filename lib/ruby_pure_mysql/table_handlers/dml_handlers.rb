# frozen_string_literal: true

module RubyPureMysql
  # DML操作に関連するハンドラメソッド
  module DmlHandlers
    def handle_insert(client, result)
      columns = validate_table(client, result[:table_name])
      return unless columns

      values = resolve_insert_values(client, columns, result)
      return if insert_value_error?(client, values)

      if @storage_engine.insert(result[:table_name], values)
        send_ok_packet(client, 1)
      else
        send_err_packet(client, 1, "Failed to insert into '#{result[:table_name]}'", 1000)
      end
    end

    def insert_value_error?(client, values)
      if values == :column_count_mismatch
        send_err_packet(client, 1, "Column count doesn't match value count at row 1", 1136)
        return true
      end

      if values.is_a?(String)
        send_err_packet(client, 1, "Unknown column '#{values}'", 1054)
        return true
      end

      false
    end

    def resolve_insert_values(client, columns, result)
      if result[:columns].nil?
        return :column_count_mismatch if result[:values].size != columns.size

        return result[:values]
      end

      map_values_to_columns(client, columns, result[:columns], result[:values])
    end

    def map_values_to_columns(client, table_columns, specified_columns, values)
      return :column_count_mismatch if specified_columns.size != values.size

      row = Array.new(table_columns.size, nil)
      specified_columns.each_with_index do |col_name, idx|
        col_idx = get_column_index(client, table_columns, col_name)
        return col_name unless col_idx

        row[col_idx] = values[idx]
      end
      row
    end

    def handle_update(client, result)
      columns = validate_table(client, result[:table_name])
      return unless columns

      where_clauses = prepare_where_clauses(client, columns, result[:where])
      return unless where_clauses

      update_map = build_update_map(client, columns, result[:updates])
      if update_map.is_a?(Hash) && update_map.key?(:error)
        return send_err_packet(client, 1, "Unknown column '#{update_map[:error]}'", 1054)
      end

      perform_update(client, result, where_clauses, update_map)
    end

    def build_update_map(client, columns, updates)
      updates.each_with_object({}) do |update, map|
        col_idx = get_column_index(client, columns, update[:column])
        return { error: update[:column] } unless col_idx

        map[col_idx] = update[:value]
      end
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
