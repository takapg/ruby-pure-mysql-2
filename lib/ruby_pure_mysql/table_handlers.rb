# frozen_string_literal: true

require_relative 'table_handler_utils'

module RubyPureMysql
  # テーブル操作に関連するハンドラメソッドをまとめたモジュール
  module TableHandlers
    include TableHandlerUtils

    # 共通のソートロジックを確実に動作させるためにオーバーライド
    def apply_order_by(_client, order, columns, rows)
      col_idx = columns.index(order[:column])
      return rows unless col_idx

      # 破壊的変更を避けるために sort_by を使用
      sorted_rows = rows.sort_by { |row| row[col_idx] }

      # directionがシンボルや文字列で渡される可能性があるため、明示的に文字列化して比較
      # stripを追加して余分な空白を除去
      direction = order[:direction].to_s.upcase.strip

      direction == 'DESC' ? sorted_rows.reverse : sorted_rows
    end

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

    def handle_select(client, result)
      columns = validate_table(client, result[:table_name])
      return unless columns

      rows = @storage_engine.select(result[:table_name])
      rows = filter_rows(client, columns, rows, result[:where]) if result[:where]
      rows = apply_order_by(client, result[:order], columns, rows) if result[:order]
      rows = rows.first(result[:limit]) if result[:limit]

      send_selected_columns(client, rows, columns, result[:columns])
    end

    def filter_rows(client, columns, rows, where)
      where_clauses = prepare_where_clauses(client, columns, where)
      return rows unless where_clauses

      rows.select { |row| @storage_engine.send(:match_row?, row, columns, where_clauses) }
    end

    def send_selected_columns(client, rows, columns, selected_columns)
      if selected_columns && !selected_columns.include?('*')
        selected_indices = selected_columns.map { |col| columns.index(col) }
        rows = rows.map { |row| selected_indices.map { |idx| row[idx] } }
        send_result_set(client, rows, selected_columns)
      else
        send_result_set(client, rows, columns)
      end
    end

    def handle_update(client, result)
      columns = validate_table(client, result[:table_name])
      return unless columns

      where_clauses = prepare_where_clauses(client, columns, result[:where])
      return unless where_clauses

      col_idx = get_column_index(client, columns, result[:column])
      return unless col_idx

      perform_update(client, result, where_clauses, col_idx)
    end

    def perform_update(client, result, where_clauses, col_idx)
      if @storage_engine.update_rows_with_where(result[:table_name], where_clauses, col_idx, result[:value])
        send_ok_packet(client, 1)
      else
        send_err_packet(client, 1, 'Update failed', 1000)
      end
    end

    def get_column_index(client, columns, column_name)
      col_idx = columns.index(column_name)
      if col_idx.nil?
        send_err_packet(client, 1, "Unknown column '#{column_name}'", 1054)
        return nil
      end
      col_idx
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
