# frozen_string_literal: true

require 'json'
require_relative 'index_lookup_utils'
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
    include IndexLookupUtils

    def validate_table(client, table_name)
      columns = @storage_engine.get_columns(table_name)
      unless columns
        send_err_packet(client, 1, "Table '#{table_name}' doesn't exist", 1146)
        return nil
      end
      columns
    end

    def find_matching_indices(client, rows, table_columns, where_clauses, lookup_opts = {})
      table_map = lookup_opts[:table_map] || {}

      return (0...rows.size).to_a if where_clauses.nil? || where_clauses.empty?

      groups = normalize_where_groups(where_clauses)
      compiled_groups = compile_groups(client, table_columns, groups, table_map)
      return handle_unknown_column(client) if compiled_groups.nil?

      full_opts = lookup_opts.merge(client: client, columns: table_columns, table_map: table_map)
      indices = perform_lookup(rows, table_columns, where_clauses, full_opts)

      filter_by_compiled_groups(rows, indices, compiled_groups)
    end

    def filter_by_compiled_groups(rows, indices, compiled_groups)
      indices.select { |idx| row_matches_compiled_groups?(rows[idx], compiled_groups) }
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

    def handle_unknown_column(client)
      send_err_packet(client, 1, 'Unknown column in WHERE clause', 1054)
      nil
    end

    def perform_lookup(rows, table_columns, where_clauses, lookup_opts)
      table_name = lookup_opts[:table_name]
      if table_name
        candidate_indices = try_index_lookup(table_name, table_columns, where_clauses, lookup_opts)
        return candidate_indices.keys if candidate_indices.is_a?(Hash)
        return candidate_indices if candidate_indices
      end

      (0...rows.size).to_a
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
