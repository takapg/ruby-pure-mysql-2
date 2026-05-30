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

    def update_rows_with_where(table_name, where_clauses, update_map, limit: nil)
      @tables_mutex.synchronize do
        return false unless @data.key?(table_name)

        apply_update(table_name, where_clauses, update_map, limit)
        true
      end
    end

    def delete_rows_with_where(table_name, where_clauses, limit: nil)
      @tables_mutex.synchronize do
        return false unless @data.key?(table_name)

        apply_delete(table_name, where_clauses, limit)
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

    def apply_update(table_name, where_clauses, update_map, limit)
      return if limit == 0

      columns = @tables[table_name]
      updated_count = 0
      @data[table_name].each do |row|
        next unless match_row?(row, columns, where_clauses)

        update_map.each { |idx, val| row[idx] = val }
        updated_count += 1
        break if limit && updated_count >= limit
      end
    end

    def apply_delete(table_name, where_clauses, limit)
      return if limit == 0

      columns = @tables[table_name]
      rows = @data[table_name]
      
      # 削除対象となる行オブジェクトを収集する
      to_delete = []
      rows.each do |row|
        if match_row?(row, columns, where_clauses)
          to_delete << row
          break if limit && to_delete.size >= limit
        end
      end

      # 元の配列から削除対象の行を除外して更新する
      @data[table_name] = rows - to_delete
    end

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
