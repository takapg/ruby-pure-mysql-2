# frozen_string_literal: true

require_relative 'table_handler_utils'
require_relative 'storage_persistence'
require_relative 'storage_query_utils'

module RubyPureMysql
  # インメモリでテーブル定義を管理するストレージエンジン
  class StorageEngine
    include TableHandlerUtils
    include SortUtils
    include StoragePersistence
    include StorageQueryUtils

    def initialize
      @tables = {}
      @data = {}
      @index_definitions = {}
      @index_data = {}
      @tables_mutex = Mutex.new
      @db_dir = 'db'
      setup_persistence
    end

    def create_table(name, columns, indexes = {})
      @tables_mutex.synchronize do
        return false if @tables.key?(name)

        @tables[name] = columns
        @data[name] = []
        @index_definitions[name] = indexes
        @index_data[name] = {}
        persist_table_creation(name)
        true
      end
    end

    def drop_table(name)
      @tables_mutex.synchronize do
        return false unless @tables.key?(name)

        @tables.delete(name)
        @data.delete(name)
        @index_definitions.delete(name)
        @index_data.delete(name)
        persist_table_deletion(name)
        true
      end
    end

    def insert(table_name, values)
      @tables_mutex.synchronize do
        columns = @tables[table_name]
        return false unless columns
        return false unless values.size == columns.size

        @data[table_name] << values.dup
        update_indexes(table_name, values)
        save_data(table_name)
        true
      end
    end

    def update_rows_with_where(table_name, criteria, update_map)
      @tables_mutex.synchronize do
        return false unless @data.key?(table_name)

        merged_criteria = criteria.merge(table_name: table_name)
        target_indices = collect_indices_to_delete(@data[table_name], @tables[table_name], merged_criteria)
        return false if target_indices.nil?

        old_values_map = {}
        target_indices.each { |idx| old_values_map[idx] = @data[table_name][idx].dup }

        return false unless perform_update_rows?(@data[table_name], @tables[table_name], update_map, merged_criteria)

        target_indices.each do |idx|
          update_row_indexes(table_name, idx, old_values_map[idx], @data[table_name][idx])
        end

        save_data(table_name)
        true
      end
    end

    def delete_rows_with_where(table_name, criteria)
      @tables_mutex.synchronize do
        return false unless @data.key?(table_name)

        merged_criteria = criteria.merge(table_name: table_name)
        indices = collect_indices_to_delete(@data[table_name], @tables[table_name], merged_criteria)
        return false if indices.nil?

        indices.reverse_each do |idx|
          remove_from_index(table_name, idx, @data[table_name][idx])
          @data[table_name].delete_at(idx)
        end
        save_data(table_name)
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

    def remove_from_index(table_name, row_idx, values)
      return unless @index_definitions[table_name]

      @index_definitions[table_name].each do |idx_name, cols|
        key = values.values_at(*cols)
        val0 = key[0]
        idx_table = @index_data[table_name][idx_name]
        next unless idx_table && idx_table[val0] && idx_table[val0][key]

        idx_table[val0][key].delete(row_idx)
        idx_table[val0].delete(key) if idx_table[val0][key].empty?
        idx_table.delete(val0) if idx_table[val0].empty?
      end
    end

    def update_row_indexes(table_name, row_idx, old_values, new_values)
      remove_from_index(table_name, row_idx, old_values)
      @index_definitions[table_name].each do |idx_name, cols|
        add_to_index(table_name, idx_name, cols, new_values, row_idx)
      end
    end

    def update_indexes(table_name, values)
      return unless @index_definitions[table_name]

      row_idx = @data[table_name].size - 1
      @index_definitions[table_name].each do |idx_name, cols|
        add_to_index(table_name, idx_name, cols, values, row_idx)
      end
    end

    def add_to_index(table_name, idx_name, cols, values, row_idx)
      key = values.values_at(*cols)
      val0 = key[0]
      (@index_data[table_name][idx_name] ||= {})[val0] ||= {}
      (@index_data[table_name][idx_name][val0][key] ||= {})[row_idx] = true
    end

    private(*StoragePersistence.instance_methods(false))
    private(*StorageQueryUtils.instance_methods(false))
  end
end
