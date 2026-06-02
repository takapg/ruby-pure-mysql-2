# frozen_string_literal: true

require_relative 'table_handler_utils'
require_relative 'storage_persistence'
require_relative 'storage_query_utils'
require_relative 'storage_index_manager'

module RubyPureMysql
  # インメモリでテーブル定義を管理するストレージエンジン
  class StorageEngine
    include TableHandlerUtils
    include SortUtils
    include StoragePersistence
    include StorageQueryUtils
    include StorageIndexManager

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

        indices, merged_criteria = resolve_target_indices(table_name, criteria)
        return false if indices.nil?

        refresh_index_entries(table_name, indices, update_map, merged_criteria)
      end
    end

    def delete_rows_with_where(table_name, criteria)
      @tables_mutex.synchronize do
        return false unless @data.key?(table_name)

        indices, _merged_criteria = resolve_target_indices(table_name, criteria)
        return false if indices.nil?

        remove_index_entries(table_name, indices)
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

    def resolve_target_indices(table_name, criteria)
      normalized_criteria = criteria.is_a?(Array) ? { where: criteria } : criteria
      merged_criteria = normalized_criteria.merge(table_name: table_name)
      indices = collect_indices_to_delete(@data[table_name], @tables[table_name], merged_criteria)
      [indices, merged_criteria]
    end

    private(*StoragePersistence.instance_methods(false))
    private(*StorageQueryUtils.instance_methods(false))
  end
end
