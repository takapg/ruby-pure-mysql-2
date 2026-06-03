# frozen_string_literal: true

require_relative 'table_handler_utils'
require_relative 'storage_persistence'
require_relative 'storage_query_utils'
require_relative 'storage_index_manager'
require_relative 'storage_index_utils'

module RubyPureMysql
  # インメモリでテーブル定義を管理するストレージエンジン
  class StorageEngine
    include TableHandlerUtils
    include SortUtils
    include StoragePersistence
    include StorageQueryUtils
    include StorageIndexManager
    include StorageIndexUtils

    def initialize
      init_storage_state
      setup_persistence
      rebuild_all_unique_indexes
    end

    def create_table(name, columns, indexes = {})
      @tables_mutex.synchronize do
        return false if @tables.key?(name)

        @tables[name] = columns
        @data[name] = []
        setup_table_indexes(name, columns, indexes)
        persist_table_creation(name)
        true
      end
    end

    def drop_table(name)
      @tables_mutex.synchronize do
        return false unless @tables.key?(name)

        delete_table_state(name)
        persist_table_deletion(name)
        true
      end
    end

    def delete_table_state(name)
      @tables.delete(name)
      @data.delete(name)
      @index_definitions.delete(name)
      @index_data.delete(name)
      @primary_keys.delete(name)
      clear_index_cache(name)
    end

    def insert(table_name, values)
      @tables_mutex.synchronize do
        columns = @tables[table_name]
        return false unless columns && values.size == columns.size

        return :duplicate_pk if duplicate_unique_key?(table_name, values)

        @data[table_name] << values.dup
        update_indexes(table_name, values)
        clear_index_cache(table_name)
        save_data(table_name)
        true
      end
    end

    def update_rows_with_where(table_name, criteria, update_map)
      @tables_mutex.synchronize do
        return false unless @data.key?(table_name)

        indices, merged_criteria = resolve_target_indices(table_name, criteria)
        return false if indices.nil?

        affected_indexes = refresh_index_entries(table_name, indices, update_map, merged_criteria)
        return false if affected_indexes == false

        affected_indexes.each { |idx_name| clear_index_cache(table_name, idx_name) }
        true
      end
    end

    def delete_rows_with_where(table_name, criteria)
      @tables_mutex.synchronize do
        return false unless @data.key?(table_name)

        indices, _merged_criteria = resolve_target_indices(table_name, criteria)
        return false if indices.nil?

        remove_index_entries(table_name, indices)
        clear_index_cache(table_name)
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
        cols = @tables[table_name] || []
        cols.map { |c| c.is_a?(Hash) ? c[:name] : c }
      end
    end

    def list_tables
      @tables_mutex.synchronize do
        @tables.keys
      end
    end

    private

    def init_storage_state
      @tables = {}
      @data = {}
      @index_definitions = {}
      @index_data = {}
      @primary_keys = {}
      @index_sorted_keys = {}
      @unique_indexes = {}
      @tables_mutex = Mutex.new
      @db_dir = 'db'
    end

    private(*StoragePersistence.instance_methods(false))
    private(*StorageQueryUtils.instance_methods(false))
  end
end
