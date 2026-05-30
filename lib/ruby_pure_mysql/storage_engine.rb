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

    def update_rows_with_where(table_name, where_clauses, update_map)
      @tables_mutex.synchronize do
        return false unless @data.key?(table_name)

        columns = @tables[table_name]
        @data[table_name].each do |row|
          if match_row?(row, columns, where_clauses)
            update_map.each { |idx, val| row[idx] = val }
          end
        end
        true
      end
    end

    def delete_rows_with_where(table_name, where_clauses)
      @tables_mutex.synchronize do
        return false unless @data.key?(table_name)

        columns = @tables[table_name]
        @data[table_name].reject! { |row| match_row?(row, columns, where_clauses) }
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
  end
end
