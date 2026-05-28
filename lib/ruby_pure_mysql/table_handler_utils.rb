# frozen_string_literal: true

require_relative 'aggregate_utils'
require_relative 'filter_utils'

module RubyPureMysql
  # テーブル操作の補助メソッドをまとめたモジュール
  module TableHandlerUtils
    class HavingError < StandardError; end

    include AggregateUtils
    include FilterUtils

    def validate_table(client, table_name)
      columns = @storage_engine.get_columns(table_name)
      unless columns
        send_err_packet(client, 1, "Table '#{table_name}' doesn't exist", 1146)
        return nil
      end
      columns
    end

    def get_column_index(client, columns, column_name, table_map = {})
      if column_name.include?('.')
        table, col = column_name.split('.')
        unless table_map && table_map.key?(table)
          send_err_packet(client, 1, "Unknown table '#{table}'", 1146)
          return nil
        end

        offset = 0
        table_map.each do |t, cols|
          break if t == table
          offset += cols.size
        end

        col_idx = table_map[table].index(col)
        unless col_idx
          send_err_packet(client, 1, "Unknown column '#{col}' in table '#{table}'", 1054)
          return nil
        end
        return offset + col_idx
      end

      # テーブル指定がない場合、table_map があればそこから解決を試みる（結合クエリでの曖昧さ回避）
      if table_map && !table_map.empty?
        table_map.each do |t, cols|
          if (idx = cols.index(column_name))
            offset = 0
            table_map.each do |t2, cols2|
              break if t2 == t
              offset += cols2.size
            end
            return offset + idx
          end
        end
      end

      # 最終手段として全カラムリストから検索
      idx = columns.index(column_name)
      unless idx
        send_err_packet(client, 1, "Unknown column '#{column_name}'", 1054)
        return nil
      end
      idx
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

    def perform_inner_join(client, rows1, cols1, rows2, cols2, on_condition, table_map)
      left_expr, right_expr = on_condition.split('=').map(&:strip)
      
      all_cols = cols1 + cols2
      left_idx = get_column_index(client, all_cols, left_expr, table_map)
      right_idx = get_column_index(client, all_cols, right_expr, table_map)

      return [[], all_cols] if left_idx.nil? || right_idx.nil?

      joined_rows = []
      rows1.each do |r1|
        rows2.each do |r2|
          row = r1 + r2
          # nil == nil の結合（ゴーストマッチ）を防ぐため、値が nil でないことを確認する
          next if row[left_idx].nil? || row[right_idx].nil?
          joined_rows << row if row[left_idx] == row[right_idx]
        end
      end
      [joined_rows, all_cols]
    end

    def apply_offset_and_limit(rows, result)
      rows = rows.drop(result[:offset] || 0)
      result[:limit] ? rows.first(result[:limit]) : rows
    end

    def project_rows(client, rows, columns, selected_columns, table_map = {})
      if selected_columns && !selected_columns.include?('*')
        return nil unless validate_selected_columns?(client, columns, selected_columns, table_map)

        selected_indices = selected_columns.map { |col| get_column_index(client, columns, col, table_map) }
        return nil if selected_indices.any?(&:nil?)

        projected_rows = rows.map { |row| selected_indices.map { |idx| row[idx] } }
        [projected_rows, selected_columns]
      else
        [rows, columns]
      end
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
