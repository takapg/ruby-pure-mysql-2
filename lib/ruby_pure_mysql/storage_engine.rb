# frozen_string_literal: true

require_relative 'table_handler_utils'

module RubyPureMysql
  # インメモリでテーブル定義を管理するストレージエンジン
  class StorageEngine
    include TableHandlerUtils

    def initialize
      @tables = {}
      @data = {}
      @tables_mutex = Mutex.new
    end

    def create_table(name, columns)
      @tables_mutex.synchronize do
        return false if @tables.key?(name)

        @tables[name] = columns
        @data[name] = []
        true
      end
    end

    def drop_table(name)
      @tables_mutex.synchronize do
        return false unless @tables.key?(name)

        @tables.delete(name)
        @data.delete(name)
        true
      end
    end

    def insert(table_name, values)
      @tables_mutex.synchronize do
        columns = @tables[table_name]
        return false unless columns
        return false unless values.size == columns.size

        @data[table_name] << values.dup
        true
      end
    end

    def update_rows_with_where(table_name, criteria, update_map)
      @tables_mutex.synchronize do
        return false unless @data.key?(table_name)

        perform_update_rows(@data[table_name], @tables[table_name], update_map, criteria)
        true
      end
    end

    def delete_rows_with_where(table_name, criteria)
      @tables_mutex.synchronize do
        return false unless @data.key?(table_name)

        indices = collect_indices_to_delete(@data[table_name], @tables[table_name], criteria)
        indices.reverse_each { |idx| @data[table_name].delete_at(idx) }
        true
      end
    end

    def select(table_name)
      @tables_mutex.synchronize do
        @data[table_name] || []
      end
    end

    def get_columns(table_name)
      @tables_mutex.synchronize do
        @tables[table_name]
      end
    end

    def list_tables
      @tables_mutex.synchronize do
        @tables.keys
      end
    end

    private

    def match_row?(row, columns, where_clauses)
      return true if where_clauses.nil? || where_clauses.empty?

      where_clauses.all? { |clause| match_clause?(row, columns, clause) }
    end

    def match_clause?(row, columns, clause)
      c_idx = clause[:col_idx] || columns.index(clause[:column])
      return false unless c_idx

      val = row[c_idx]

      apply_filter(val, clause[:operator], clause[:value])
    end

    def perform_update_rows(rows, columns, update_map, criteria)
      return if criteria[:limit]&.zero?

      target_indices = get_target_indices(rows, columns, criteria)
      target_indices.each { |i| update_row(rows[i], update_map) }
    end

    def update_row(row, update_map)
      update_map.each { |idx, val| row[idx] = val }
    end

    def collect_indices_to_delete(rows, columns, criteria)
      return [] if criteria[:limit]&.zero?

      get_target_indices(rows, columns, criteria)
    end

    def get_target_indices(rows, columns, criteria)
      matching_indices = rows.each_index.select { |i| match_row?(rows[i], columns, criteria[:where]) }

      if criteria[:order] && criteria[:client]
        sort_conditions = resolve_sort_conditions(criteria[:client], columns, criteria[:order])
        matching_indices.sort! { |i, j| compare_rows(rows[i], rows[j], sort_conditions) }
      end

      criteria[:limit] ? matching_indices.first(criteria[:limit]) : matching_indices
    end
  end
end
