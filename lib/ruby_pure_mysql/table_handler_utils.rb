# frozen_string_literal: true

require_relative 'aggregate_utils'
require_relative 'filter_utils'
require_relative 'column_utils'
require_relative 'join_utils'

module RubyPureMysql
  # テーブル操作の補助メソッドをまとめたモジュール
  module TableHandlerUtils
    class HavingError < StandardError; end

    include AggregateUtils
    include FilterUtils
    include ColumnUtils
    include JoinUtils

    def validate_table(client, table_name)
      columns = @storage_engine.get_columns(table_name)
      unless columns
        send_err_packet(client, 1, "Table '#{table_name}' doesn't exist", 1146)
        return nil
      end
      columns
    end

    def find_matching_indices(client, rows, table_columns, where_clauses, table_map = {})
      return (0...rows.size).to_a unless where_clauses

      compiled_clauses = compile_where_clauses(client, table_columns, where_clauses, table_map)
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

    def project_rows(client, rows, columns, selected_columns, table_map = {})
      return [rows, columns] if selected_columns.nil? || selected_columns.include?('*')

      return nil unless validate_selected_columns?(client, columns, selected_columns, table_map)

      indices = selected_columns.map { |col| get_column_index(client, columns, col, table_map) }
      return nil if indices.any?(&:nil?)

      [project_data(rows, indices), project_column_names(selected_columns)]
    end

    def project_data(rows, indices)
      rows.map { |row| indices.map { |idx| row[idx] } }
    end

    def project_column_names(selected_columns)
      selected_columns.map { |col| col.split('.').last }
    end

    def validate_selected_columns?(client, columns, selected_columns, table_map = {})
      selected_columns.all? { |col| !get_column_index(client, columns, col, table_map).nil? }
    end

    def get_group_column_indices(client, columns, group_by_str)
      group_by_str.split(',').map do |col_name|
        name = col_name.strip
        idx = columns.index(name)
        unless idx
          send_err_packet(client, 1, "Unknown column '#{name}' in 'group clause'", 1054)
          return nil
        end
        idx
      end
    end

    def evaluate_having_condition(columns, group_val, group_rows, group_indices, clause)
      val = resolve_having_value(columns, group_val, group_rows, group_indices, clause[:column])
      raise HavingError, 'Unknown column' if val == :no_column

      apply_filter(val, clause[:operator], clause[:value])
    end

    def resolve_having_value(columns, group_val, group_rows, group_indices, col_expr)
      if (m = col_expr.match(AggregateUtils::AGGREGATE_REGEX))
        agg = { type: m[1].downcase.to_sym, column: m[2], index: nil }
        return compute_single_aggregate_value(group_rows, columns, agg)
      end

      col_idx = columns.index(col_expr)
      return :no_column unless col_idx

      group_idx = group_indices.index(col_idx)
      msg = "Column '#{col_expr}' must appear in the GROUP BY clause or be used in an aggregate function"
      raise HavingError, msg if group_idx.nil?

      group_val[group_idx]
    end
  end
end
