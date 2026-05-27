# frozen_string_literal: true

module RubyPureMysql
  # クエリ操作に関連するハンドラメソッド
  module QueryHandlers
    def handle_select(client, result)
      columns = validate_table(client, result[:table_name])
      return unless columns

      if result[:aggregate]
        handle_aggregate(client, columns, result)
      else
        handle_standard_select(client, columns, result)
      end
    end

    def handle_aggregate(client, columns, result)
      rows = fetch_and_filter_rows(client, columns, result.merge(limit: nil, offset: nil, order: nil))
      return if rows.nil?

      val = result[:aggregate] == :count ? rows.size : calculate_column_aggregate(client, columns, rows, result)
      return if val == :error

      send_aggregate_result(client, val, result)
    end

    def send_aggregate_result(client, val, result)
      res_rows = [[val]]
      final_rows = apply_offset_and_limit(res_rows, result)
      col_header = result[:aggregate_column] ? "#{result[:aggregate].upcase}(#{result[:aggregate_column]})" : 'COUNT(*)'
      send_result_set(client, final_rows, [col_header])
    end

    def calculate_column_aggregate(client, columns, rows, result)
      col_idx = columns.index(result[:aggregate_column])
      return handle_unknown_column(client, result[:aggregate_column]) if col_idx.nil?

      values = rows.filter_map { |r| r[col_idx] }
      return nil if values.empty?

      perform_aggregation(values, result[:aggregate])
    end

    def handle_unknown_column(client, col_name)
      send_err_packet(client, 1, "Unknown column '#{col_name}' in 'field list'", 1054)
      :error
    end

    def perform_aggregation(values, type)
      case type.to_s.downcase
      when 'sum' then values.map(&:to_i).sum
      when 'avg' then values.map(&:to_f).sum / values.size
      when 'min' then values.map(&:to_i).min
      when 'max' then values.map(&:to_i).max
      end
    end

    def handle_standard_select(client, columns, result)
      rows = fetch_and_filter_rows(client, columns, result)
      return if rows.nil?

      rows, final_columns = project_rows(client, rows, columns, result[:columns])
      return if rows.nil?

      rows.uniq! if result[:distinct]

      rows = apply_order_by(client, result[:order], final_columns, rows) if result[:order]
      return if rows.nil?

      rows = apply_offset_and_limit(rows, result)
      send_result_set(client, rows, final_columns)
    end

    def fetch_and_filter_rows(client, columns, result)
      rows = @storage_engine.select(result[:table_name])
      rows = filter_rows(client, columns, rows, result[:where]) if result[:where]
      return nil if rows.nil?

      rows
    end

    def apply_offset_and_limit(rows, result)
      rows = rows.drop(result[:offset] || 0)
      result[:limit] ? rows.first(result[:limit]) : rows
    end

    def filter_rows(client, columns, rows, where)
      where_clauses = prepare_where_clauses(client, columns, where)
      return nil if where_clauses.nil?

      rows.select { |row| @storage_engine.send(:match_row?, row, columns, where_clauses) }
    end

    def project_rows(client, rows, columns, selected_columns)
      if selected_columns && !selected_columns.include?('*')
        return nil unless validate_selected_columns?(client, columns, selected_columns)

        selected_indices = selected_columns.map { |col| columns.index(col) }
        projected_rows = rows.map { |row| selected_indices.map { |idx| row[idx] } }
        [projected_rows, selected_columns]
      else
        [rows, columns]
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
