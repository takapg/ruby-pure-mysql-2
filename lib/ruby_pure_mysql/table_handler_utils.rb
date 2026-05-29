# frozen_string_literal: true

require_relative 'aggregate_utils'
require_relative 'filter_utils'
require_relative 'column_utils'
require_relative 'join_utils'
require_relative 'projection_utils'
require_relative 'having_utils'

module RubyPureMysql
  # テーブル操作の補助メソッドをまとめたモジュール
  module TableHandlerUtils
    include AggregateUtils
    include FilterUtils
    include ColumnUtils
    include JoinUtils
    include ProjectionUtils
    include HavingUtils

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
      return val.nil? if operator == 'IS NULL'
      return !val.nil? if operator == 'IS NOT NULL'
      return false if val.nil?

      compare_value(val, operator, target_value)
    rescue StandardError
      false
    end

    def compare_value(val, operator, target_value)
      if operator == 'LIKE'
        regex = target_value.is_a?(Regexp) ? target_value : build_like_regex(target_value)
        regex.match?(val.to_s)
      elsif operator == 'IN'
        val.nil? ? false : target_value.include?(val)
      else
        method = operator == '=' ? :== : operator.to_sym
        val.public_send(method, target_value)
      end
    end

    def apply_order_by(client, order_by, table_columns, rows)
      sort_conditions = order_by.filter_map do |cond|
        idx = get_column_index(client, table_columns, cond[:column])
        { index: idx, direction: cond[:direction] } if idx
      end
      return nil if sort_conditions.empty?

      sort_rows(rows, sort_conditions)
    end

    def sort_rows(rows, sort_conditions)
      rows.sort do |a, b|
        comparison = 0
        sort_conditions.each do |cond|
          res = compare_values(a, b, cond)
          comparison = res * (cond[:direction] == :DESC ? -1 : 1)
          break if comparison != 0
        end
        comparison
      end
    end

    def compare_values(row_a, row_b, cond)
      val_a = row_a[cond[:index]]
      val_b = row_b[cond[:index]]

      res = (val_a.nil? ? 0 : 1) <=> (val_b.nil? ? 0 : 1)
      return res unless res.zero?

      begin
        val_a <=> val_b
      rescue StandardError
        0
      end
    end

    def get_group_column_indices(client, columns, group_by_str, table_map = {})
      group_by_str.split(',').map do |col_name|
        name = col_name.strip
        idx = get_column_index(client, columns, name, table_map)
        return nil unless idx

        idx
      end
    end
  end
end
