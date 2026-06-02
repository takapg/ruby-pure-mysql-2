# frozen_string_literal: true

require 'json'
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

    def find_matching_indices(client, rows, table_columns, where_clauses, table_map = {}, table_name = nil)
      return (0...rows.size).to_a if where_clauses.nil? || where_clauses.empty?

      groups = normalize_where_groups(where_clauses)
      compiled_groups = compile_groups(client, table_columns, groups, table_map)
      if compiled_groups.nil?
        send_err_packet(client, 1, 'Unknown column in WHERE clause', 1054)
        return nil
      end

      if table_name
        candidate_indices = try_index_lookup(client, table_name, table_columns, where_clauses, table_map)
        if candidate_indices
          return candidate_indices.select { |idx| row_matches_compiled_groups?(rows[idx], compiled_groups) }
        end
      end

      rows.each_index.select { |idx| row_matches_compiled_groups?(rows[idx], compiled_groups) }
    end

    def apply_distinct(rows)
      return rows if rows.nil? || rows.empty?

      base_types = determine_base_types(rows)

      rows.uniq do |row|
        row.each_with_index.map { |val, i| normalize_value_by_type(val, base_types[i]) }
      end
    end

    def normalize_where_groups(where_clauses)
      return [] if where_clauses.nil? || where_clauses.empty?

      where_clauses.first.is_a?(Hash) ? [where_clauses] : where_clauses
    end

    def compile_groups(client, table_columns, groups, table_map)
      return nil if groups.nil?

      compiled = groups.map { |group| compile_where_clauses(client, table_columns, group, table_map) }
      compiled.any?(&:nil?) ? nil : compiled
    end

    def normalize_value_by_type(val, type)
      return nil if val.nil?
      return val if type.nil?

      case type
      when :integer then cast_to_numeric(val, :to_i)
      when :float   then cast_to_numeric(val, :to_f)
      when :string  then val.to_s
      else val
      end
    end

    def cast_to_numeric(val, method)
      return nil if val.nil?

      val.is_a?(Numeric) ? val.send(method) : val.to_s.send(method)
    end

    def determine_base_types(rows)
      return [] if rows.nil? || rows.empty?

      num_cols = rows.first.size
      (0...num_cols).map do |col_idx|
        first_val = rows.find { |row| !row[col_idx].nil? }&.[](col_idx)
        map_value_to_type(first_val)
      end
    end

    private

    def try_index_lookup(client, table_name, table_columns, where_clauses, table_map)
      return nil unless @index_definitions && @index_definitions[table_name]

      groups = normalize_where_groups(where_clauses)
      return nil if groups.size > 1

      group = groups.first
      @index_definitions[table_name].each do |idx_name, cols|
        index_values = []
        all_match = true
        cols.each do |col_idx|
          clause = group.find { |c| get_column_index(client, table_columns, c[:column], table_map) == col_idx }
          if clause && clause[:operator] == '='
            index_values << clause[:value]
          else
            all_match = false
            break
          end
        end

        if all_match
          key = index_values.to_json
          return @index_data[table_name][idx_name][key] if @index_data[table_name] && @index_data[table_name][idx_name] && @index_data[table_name][idx_name].key?(key)
        end

        first_col_idx = cols[0]
        first_clause = group.find { |c| get_column_index(client, table_columns, c[:column], table_map) == first_col_idx }
        if first_clause && first_clause[:operator] == '='
          val0 = first_clause[:value]
          candidates = []
          if @index_data[table_name] && @index_data[table_name][idx_name]
            @index_data[table_name][idx_name].each do |key, row_indices|
              parsed_key = JSON.parse(key)
              candidates.concat(row_indices) if parsed_key[0] == val0
            end
          end
          return candidates unless candidates.empty?
        end
      end
      nil
    end

    def map_value_to_type(val)
      case val
      when Integer then :integer
      when Float   then :float
      when String  then :string
      end
    end
  end
end
