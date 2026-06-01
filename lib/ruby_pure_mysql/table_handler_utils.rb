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
      return (0...rows.size).to_a if where_clauses.nil? || where_clauses.empty?

      # where_clauses がフラットな条件配列 [{...}] の場合は、グループの配列 [[{...}]] に変換する
      groups = where_clauses.first.is_a?(Hash) ? [where_clauses] : where_clauses

      compiled_groups = groups.map do |group|
        compile_where_clauses(client, table_columns, group, table_map)
      end
      return nil if compiled_groups.any? { |g| g.nil? }

      rows.each_with_index.select do |row, _idx|
        compiled_groups.any? do |group|
          group.all? do |c|
            apply_filter(row[c[:col_idx]], c[:operator], c[:value], c[:regex])
          end
        end
      end.map(&:last)
    end

    def apply_filter(val, operator, target_value, regex = nil)
      return val.nil? if operator == 'IS NULL'
      return !val.nil? if operator == 'IS NOT NULL'
      return false if val.nil? && operator != 'IS NULL'

      # regex が提供されている場合は優先的に使用 (LIKE, REGEXP用)
      return regex.match?(val.to_s) if regex.is_a?(Regexp)

      compare_value(val, operator, target_value)
    rescue StandardError
      false
    end

    def compare_value(val, operator, target_value)
      case operator
      when 'LIKE' then match_pattern?(val, target_value, :like)
      when 'REGEXP', 'RLIKE' then match_pattern?(val, target_value, :regexp)
      when 'IN'
        return target_value.include?(val) unless val.is_a?(Numeric)
        target_value.any? { |t| cast_to_numeric(t).is_a?(Numeric) && cast_to_numeric(t) == val }
      when 'BETWEEN', 'NOT BETWEEN'
        if val.is_a?(Numeric)
          normalized_target = target_value.map { |t| cast_to_numeric(t) }
          return false if normalized_target.any? { |t| !t.is_a?(Numeric) }
          begin
            return match_between?(val, operator, normalized_target)
          rescue StandardError
            return false
          end
        end
        match_between?(val, operator, target_value)
      when '='
        v1, v2 = normalize_for_comparison(val, target_value)
        v1 == v2
      when '!=', '<>'
        v1, v2 = normalize_for_comparison(val, target_value)
        v1 != v2
      else
        v1, v2 = normalize_for_comparison(val, target_value)
        begin
          v1.public_send(operator.to_sym, v2)
        rescue StandardError
          false
        end
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

      rows.uniq { |row| row.map { |val| normalize_for_distinct(val) } }
    end

    private

    def normalize_for_distinct(value)
      value.nil? ? :null : value.to_s
    end

    def normalize_for_comparison(v1, v2)
      return [v1, v2] if v1.nil? || v2.nil?
      return [v1, v2] unless (v1.is_a?(Numeric) || v2.is_a?(Numeric))

      n1 = cast_to_numeric(v1)
      n2 = cast_to_numeric(v2)
      (n1.is_a?(Numeric) && n2.is_a?(Numeric)) ? [n1, n2] : [v1, v2]
    end

    def cast_to_numeric(val)
      return val if val.is_a?(Numeric)
      return nil if val.nil?
      Float(val) rescue val
    end
  end
end
