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

    def update(table_name, col_idx, where_col_idx, new_value, where_value)
      @tables_mutex.synchronize do
        return false unless @data.key?(table_name)

        @data[table_name].each do |row|
          row[col_idx] = new_value if where_col_idx.nil? || row[where_col_idx] == where_value
        end
        true
      end
    end

    def delete(table_name, where_col_idx, where_value)
      @tables_mutex.synchronize do
        return false unless @data.key?(table_name)

        if where_col_idx.nil?
          @data[table_name].clear
        else
          @data[table_name].reject! { |row| row[where_col_idx] == where_value }
        end
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
  end
end
