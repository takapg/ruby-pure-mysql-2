# frozen_string_literal: true

require_relative 'aggregate_utils'
require_relative 'filter_utils'
require_relative 'column_utils'
require_relative 'join_utils'
require_relative 'projection_utils'
require_relative 'having_utils'
require_relative 'sort_utils'

module RubyPureMysql
  # テーブル操作の補助メソッドをまとめたモジュール
  module TableHandlerUtils
    include AggregateUtils
    include FilterUtils
    include ColumnUtils
    include JoinUtils
    include ProjectionUtils
    include HavingUtils
    include SortUtils

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
      when 'LIKE' then match_pattern?(val, target_value, :like)
      when 'REGEXP', 'RLIKE' then match_pattern?(val, target_value, :regexp)
      when 'IN' then val.nil? ? false : target_value.include?(val)
      when 'BETWEEN', 'NOT BETWEEN' then match_between?(val, operator, target_value)
      else
        val.public_send(operator == '=' ? :== : operator.to_sym, target_value)
      end
    end

    def match_pattern?(val, target, type)
      return target.match?(val.to_s) if target.is_a?(Regexp)

      (type == :like ? build_like_regex(target) : Regexp.new(target.to_s, Regexp::IGNORECASE)).match?(val.to_s)
    end

    def match_between?(val, operator, target)
      operator == 'BETWEEN' ? val.between?(*target) : !val.between?(*target)
    end

    def get_group_column_indices(client, columns, group_by_str, table_map = {})
      group_by_str.split(',').map do |col_name|
        name = col_name.strip
        idx = get_column_index(client, columns, name, table_map)
        return nil unless idx

        idx
      end
    end

    def apply_distinct(rows)
      return rows unless rows

      rows.uniq { |row| row.map { |v| v&.to_s } }
    end
  end
end
