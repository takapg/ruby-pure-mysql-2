# frozen_string_literal: true

module RubyPureMysql
  # インメモリでテーブル定義を管理するストレージエンジン
  class StorageEngine
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

    def update_rows(table_name, indices, col_idx, new_value)
      @tables_mutex.synchronize do
        return false unless @data.key?(table_name)

        indices.each { |idx| @data[table_name][idx][col_idx] = new_value }
        true
      end
    end

    def delete_rows(table_name, indices)
      @tables_mutex.synchronize do
        return false unless @data.key?(table_name)

        # インデックスの大きい順に削除しないとインデックスがずれるため reverse_each
        indices.sort.reverse_each { |idx| @data[table_name].delete_at(idx) }
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
  end
end
