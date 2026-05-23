# frozen_string_literal: true

module RubyPureMysql
  # クエリ操作に関連するハンドラメソッド
  module QueryHandlers
    def handle_select(client, result)
      columns = validate_table(client, result[:table_name])
      return unless columns

      rows = fetch_and_filter_rows(client, columns, result)
      return if rows.nil?

      send_selected_columns(client, rows, columns, result[:columns])
    end

    def fetch_and_filter_rows(client, columns, result)
      rows = @storage_engine.select(result[:table_name])
      rows = filter_rows(client, columns, rows, result[:where]) if result[:where]
      if result[:order]
        rows = apply_order_by(client, result[:order], columns, rows)
        return nil if rows.nil?
      end
      rows = rows.first(result[:limit]) if result[:limit]
      rows
    end

    def filter_rows(client, columns, rows, where)
      where_clauses = prepare_where_clauses(client, columns, where)
      return rows unless where_clauses

      rows.select { |row| @storage_engine.send(:match_row?, row, columns, where_clauses) }
    end

    def send_selected_columns(client, rows, columns, selected_columns)
      if selected_columns && !selected_columns.include?('*')
        return unless validate_selected_columns?(client, columns, selected_columns)

        selected_indices = selected_columns.map { |col| columns.index(col) }
        rows = rows.map { |row| selected_indices.map { |idx| row[idx] } }
        send_result_set(client, rows, selected_columns)
      else
        send_result_set(client, rows, columns)
      end
    end

    def validate_selected_columns?(client, columns, selected_columns)
      selected_columns.each do |col|
        unless columns.include?(col)
          send_err_packet(client, 1, "Unknown column '#{col}' in 'field list'", 1054)
          return false
        end
      end
      true
    end

    def apply_order_by(client, order, columns, rows)
      col_idx = columns.index(order[:column])
      if col_idx.nil?
        send_err_packet(client, 1, "Unknown column '#{order[:column]}' in 'order clause'", 1054)
        return nil
      end

      sort_rows(rows, col_idx, order[:direction])
    end

    def sort_rows(rows, col_idx, direction)
      sorted_rows = rows.sort_by do |row|
        val = row[col_idx]
        [val.nil? ? 0 : 1, val]
      end
      direction.to_s.upcase.strip == 'DESC' ? sorted_rows.reverse : sorted_rows
    end
  end
end
