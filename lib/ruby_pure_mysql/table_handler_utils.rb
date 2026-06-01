# frozen_string_literal: true

require_relative 'aggregate_utils'
require_relative 'filter_utils'
require_relative 'column_utils'
require_relative 'join_utils'
require_relative 'projection_utils'
require_relative 'having_utils'
require_relative 'sort_utils'
require_relative 'filter_evaluator'

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
    include FilterEvaluator

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

      groups = normalize_where_groups(where_clauses)
      compiled_groups = compile_groups(client, table_columns, groups, table_map)
      return nil if compiled_groups.nil?

      rows.each_index.select { |idx| row_matches_compiled_groups?(rows[idx], compiled_groups) }
    end

    private

    def normalize_for_distinct(val)
      return nil if val.nil?

      if val.is_a?(Numeric) || (val.is_a?(String) && val.match?(/\A-?\d+(\.\d+)?\z/))
        val.to_f.to_s
      else
        val
      end
    end

    def normalize_where_groups(where_clauses)
      where_clauses.first.is_a?(Hash) ? [where_clauses] : where_clauses
    end

    def compile_groups(client, table_columns, groups, table_map)
      compiled = groups.map { |group| compile_where_clauses(client, table_columns, group, table_map) }
      compiled.any?(&:nil?) ? nil : compiled
    end

    public

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
  end
end
