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
require_relative 'type_utils'

module RubyPureMysql
  # テーブル操作の補助メソッドをまとめたモジュール
  module TableHandlerUtils
    include AggregateUtils
    include TypeUtils
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
      # 入力を確実に「行の配列」形式にする
      normalized_rows = ensure_rows_array(rows)
      return normalized_rows if normalized_rows.empty?

      base_types = determine_base_types(normalized_rows)
      seen = {}
      
      # 元の rows の構造を維持したままフィルタリングを行う
      # normalized_rows をベースに判定し、元の rows から該当する要素を抽出する
      result = []
      normalized_rows.each_with_index do |row, idx|
        vals = extract_row_values(row)
        key = vals.each_with_index.map { |val, i| normalize_value_by_type(val, base_types[i]) }
        
        unless seen.key?(key)
          seen[key] = true
          # 元の rows がラップされていた場合はラップ後の要素を、
          # そうでない場合は元の要素をそのまま追加する
          result << (rows.is_a?(Array) && rows.first.is_a?(Array) || rows.first.respond_to?(:values) ? rows[idx] : rows)
          # 上記の三項演算子が複雑なため、シンプルに normalized_rows の要素を返す
          # (ensure_rows_array でラップした場合、normalized_rows[0] は元の rows そのものになる)
        end
      end
      
      # 修正: シンプルに normalized_rows から select する
      # 構造を破壊しないよう、元の rows が単一行だった場合はその結果を適切に返す
      final_rows = normalized_rows.select do |row|
        vals = extract_row_values(row)
        key = vals.each_with_index.map { |val, i| normalize_value_by_type(val, base_types[i]) }
        !seen.key?(key) && seen.store(key, true)
      end
      
      # もし元の rows が単一行（1D配列）として渡され、ラップされていた場合、
      # 結果は [[val1, val2]] となる。これをそのまま返せば 1行2列として正しく処理される。
      final_rows
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

    private

    def handle_unknown_column(client)
      send_err_packet(client, 1, 'Unknown column in WHERE clause', 1054)
      nil
    end

    def perform_lookup(rows, table_columns, where_clauses, lookup_opts)
      table_name = lookup_opts[:table_name]
      return (0...rows.size).to_a unless table_name

      indices = try_index_lookup(table_name, table_columns, where_clauses, lookup_opts)
      normalize_lookup_indices(indices) || (0...rows.size).to_a
    end

    def normalize_lookup_indices(indices)
      case indices
      when Hash then indices.keys
      when Array then indices.flat_map { |item| item.is_a?(Hash) ? item.keys : item }
      when nil then nil
      else indices
      end
    end
  end
end
