# frozen_string_literal: true

module RubyPureMysql
  # クエリ操作に関連するハンドラメソッド
  module QueryHandlers
    def handle_select(client, result)
      columns = validate_table(client, result[:table_name])
      return unless columns

      if result[:group_by]
        handle_group_by_select(client, columns, result)
      elsif result[:aggregate]
        if result[:columns].size > 1
          send_err_packet(client, 1, "Expression #1 of SELECT list is not in GROUP BY clause and contains nonaggregated column", 1055)
          return
        end
        handle_aggregate(client, columns, result)
      else
        handle_standard_select(client, columns, result)
      end
    end

    def handle_group_by_select(client, columns, result)
      rows = fetch_and_filter_rows(client, columns, result)
      return if rows.nil?

      group_col = result[:group_by]
      group_idx = columns.index(group_col)
      unless group_idx
        send_err_packet(client, 1, "Unknown column '#{group_col}' in 'group by clause'", 1054)
        return
      end

      grouped_rows = rows.group_by { |row| row[group_idx] }
      
      final_rows = grouped_rows.map do |key, group|
        agg_val = compute_aggregate_value(client, group, columns, result)
        return if agg_val == :error

        result[:columns].map do |col|
          if col == group_col
            key
          elsif col.match?(/\A(COUNT|SUM|AVG|MIN|MAX)\(/i)
            agg_val
          else
            nil
          end
        end
      end.compact

      final_rows = apply_order_by(client, result[:order], result[:columns], final_rows) if result[:order]
      return if final_rows.nil?

      final_rows = apply_offset_and_limit(final_rows, result)
      send_result_set(client, final_rows, result[:columns])
    end

    def handle_aggregate(client, columns, result)
      rows = fetch_and_filter_rows(client, columns, result.merge(limit: nil, offset: nil, order: nil))
      return if rows.nil?

      res_val = compute_aggregate_value(client, rows, columns, result)
      return if res_val == :error

      res_rows = [[res_val]]
      final_rows = apply_offset_and_limit(res_rows, result)
      send_result_set(client, final_rows, [result[:columns].first])
    end

    def compute_aggregate_value(client, rows, columns, result)
      col_name = result[:aggregate_column]
      return rows.size if col_name == '*'

      col_idx = columns.index(col_name)
      unless col_idx
        send_err_packet(client, 1, "Unknown column '#{col_name}' in 'field list'", 1054)
        return :error
      end

      values = rows.filter_map { |r| r[col_idx] }.map(&:to_f)
      calculate_aggregate_value(values, result[:aggregate])
    end

    def calculate_aggregate_value(values, type)
      return values.size if type == :count
      return nil if values.empty?

      case type
      when :sum then values.sum
      when :avg then values.sum / values.size
      when :min then values.min
      when :max then values.max
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
