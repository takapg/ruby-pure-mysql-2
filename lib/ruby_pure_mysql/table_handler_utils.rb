# frozen_string_literal: true

module RubyPureMysql
  # テーブル操作の補助メソッドをまとめたモジュール
  module TableHandlerUtils
    def validate_table(client, table_name)
      columns = @storage_engine.get_columns(table_name)
      unless columns
        send_err_packet(client, 1, "Table '#{table_name}' doesn't exist", 1146)
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

    def find_matching_indices(client, rows, table_columns, where_clauses)
      return (0...rows.size).to_a unless where_clauses

      compiled_clauses = compile_where_clauses(client, table_columns, where_clauses)
      return nil unless compiled_clauses

      rows.each_with_index.select do |row, _idx|
        compiled_clauses.all? do |c|
          target = c[:regex] || c[:value]
          apply_filter(row[c[:col_idx]], c[:operator], target)
        end
      end.map(&:last)
    end

    def apply_filter(val, operator, target_value)
      return false if val.nil?

      if operator == 'LIKE'
        compiled_regex = target_value.is_a?(Regexp) ? target_value : build_like_regex(target_value)
        compiled_regex.match?(val.to_s)
      else
        method = operator == '=' ? :== : operator.to_sym
        val.public_send(method, target_value)
      end
    end

    def build_like_regex(target_value)
      escaped = Regexp.escape(target_value.to_s)
      pattern = escaped.gsub('%', '.*').tr('_', '.')
      Regexp.new("\\A#{pattern}\\z", Regexp::IGNORECASE)
    end

    def apply_order_by(client, order_by, table_columns, rows)
      col_idx = get_column_index(client, table_columns, order_by[:column])
      return nil unless col_idx

      sort_rows(rows, col_idx, order_by[:direction])
    end

    def sort_rows(rows, col_idx, direction)
      sorted_rows = rows.sort_by do |row|
        val = row[col_idx]
        [val.nil? ? 0 : 1, val]
      end
      direction.to_s.upcase.strip == 'DESC' ? sorted_rows.reverse : sorted_rows
    end

    def apply_offset_and_limit(rows, result)
      rows = rows.drop(result[:offset] || 0)
      result[:limit] ? rows.first(result[:limit]) : rows
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

    def get_group_column_index(client, columns, group_col)
      idx = columns.index(group_col)
      send_err_packet(client, 1, "Unknown column '#{group_col}' in 'group clause'", 1054) unless idx
      idx
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
    private

    def compile_where_clauses(client, table_columns, where_clauses)
      where_clauses.map do |clause|
        col_idx = table_columns.index(clause[:column])
        unless col_idx
          send_err_packet(client, 1, "Unknown column '#{clause[:column]}'", 1054)
          return nil
        end
        regex = clause[:operator] == 'LIKE' ? build_like_regex(clause[:value]) : nil
        { col_idx: col_idx, operator: clause[:operator], value: clause[:value], regex: regex }
      end
    end
  end
end
