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
      case operator
      when 'LIKE' then match_like?(val, target_value)
      when 'REGEXP', 'RLIKE' then match_regexp?(val, target_value)
      when 'IN' then val.nil? ? false : target_value.include?(val)
      when 'BETWEEN', 'NOT BETWEEN' then match_between?(val, operator, target_value)
      else
        method = operator == '=' ? :== : operator.to_sym
        val.public_send(method, target_value)
      end
    end

    def match_like?(val, target_value)
      target_value.is_a?(Regexp) ? target_value.match?(val.to_s) : build_like_regex(target_value).match?(val.to_s)
    end

    def match_regexp?(val, target_value)
      target_value.is_a?(Regexp) ? target_value.match?(val.to_s) : Regexp.new(target_value.to_s, Regexp::IGNORECASE).match?(val.to_s)
    end

    def match_between?(val, operator, target_value)
      operator == 'BETWEEN' ? val.between?(*target_value) : !val.between?(*target_value)
    end

    def apply_order_by(client, order_by, table_columns, rows, selected_columns = nil)
      sort_conditions = order_by.map do |cond|
        idx = resolve_order_by_column_index(client, table_columns, cond[:column], selected_columns)
        if idx.nil?
          send_err_packet(client, 1, "Unknown column '#{cond[:column]}' in 'order clause'", 1054)
          return nil
        end
        { index: idx, direction: cond[:direction] }
      end

      sort_rows(rows, sort_conditions)
    end

    def resolve_order_by_column_index(client, table_columns, col_name, selected_columns)
      name = col_name
      if selected_columns
        alias_info = selected_columns.find { |c| c.is_a?(Hash) && c[:alias]&.casecmp?(name) }
        name = alias_info[:original] if alias_info
      end
      get_column_index(client, table_columns, name)
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
        (val_a <=> val_b) || 0
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
