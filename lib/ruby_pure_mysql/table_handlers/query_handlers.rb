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

      col_idx = resolve_aggregate_column(client, columns, result)
      return if col_idx.nil? && result[:aggregate] != :count

      values = result[:aggregate_column] ? rows.filter_map { |r| r[col_idx] } : []
      res_val = calculate_aggregate_value(result[:aggregate], rows, values)

      send_aggregate_result(client, res_val, result)
    end

    def send_aggregate_result(client, value, result)
      final_rows = apply_offset_and_limit([[value]], result)
      col_name = result[:aggregate_column] ? "#{result[:aggregate].upcase}(#{result[:aggregate_column]})" : 'COUNT(*)'
      send_result_set(client, final_rows, [col_name])
    end

    def resolve_aggregate_column(client, columns, result)
      agg_col = result[:aggregate_column]
      return nil unless agg_col

      col_idx = columns.index(agg_col)
      if col_idx.nil?
        send_err_packet(client, 1, "Unknown column '#{agg_col}' in 'field list'", 1054)
      end
      col_idx
    end

    AGGREGATE_FUNCS = {
      count: ->(rows, _vals) { rows.size },
      sum:   ->(_rows, vals) { vals.empty? ? nil : vals.sum },
      avg:   ->(_rows, vals) { vals.empty? ? nil : vals.sum.to_f / vals.size },
      min:   ->(_rows, vals) { vals.min },
      max:   ->(_rows, vals) { vals.max }
    }.freeze

    def calculate_aggregate_value(agg_func, rows, values)
      AGGREGATE_FUNCS[agg_func]&.call(rows, values)
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
