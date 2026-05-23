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
      rows = apply_where_filter(client, result[:where], table_columns, rows) if result[:where]
      return unless rows

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

    def send_select_result(client, result, rows, table_columns)
      if result[:columns] == ['*']
        send_result_set(client, rows, table_columns)
      else
        handle_projection(client, result, rows, table_columns)
      end
    end

    def apply_where_filter(client, where_clauses, table_columns, rows)
      where_clauses.each do |where_clause|
        col_idx = find_column_index(client, where_clause[:column], table_columns)
        return nil unless col_idx

        rows = filter_rows(rows, col_idx, where_clause)
      end
      rows
    end

    def find_column_index(client, column_name, table_columns)
      col_idx = table_columns.index(column_name)
      return col_idx if col_idx

      send_err_packet(client, 1, "Unknown column '#{column_name}' in WHERE clause", 1054)
      nil
    end

    def filter_rows(rows, col_idx, where_clause)
      operator = where_clause[:operator]
      target_value = where_clause[:value]

      rows.select do |row|
        val = row[col_idx]
        next false if val.nil?

        apply_filter(val, operator, target_value)
      end
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
  end

  # テーブル操作に関連するハンドラメソッドをまとめたモジュール
  module TableHandlers
    include TableHandlerUtils
    include SchemaHandlers
    include QueryHandlers

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

      rows = @storage_engine.select(result[:table_name])
      indices = find_matching_indices(client, rows, columns, result[:where])
      return unless indices

      col_idx = get_column_index(client, columns, result[:set_col])
      return unless col_idx

      if @storage_engine.update_rows(result[:table_name], indices, col_idx, result[:set_val])
        send_ok_packet(client, 1)
      else
        send_err_packet(client, 1, "Update failed", 1000)
      end
    end

    def handle_delete(client, result)
      columns = validate_table(client, result[:table_name])
      return unless columns

      rows = @storage_engine.select(result[:table_name])
      indices = find_matching_indices(client, rows, columns, result[:where])
      return unless indices

      if @storage_engine.delete_rows(result[:table_name], indices)
        send_ok_packet(client, 1)
      else
        send_err_packet(client, 1, "Delete failed", 1000)
      end
    end
  end
end
