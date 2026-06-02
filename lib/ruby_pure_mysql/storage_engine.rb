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
      @primary_keys = {}
      @tables_mutex = Mutex.new
      @db_dir = 'db'
      setup_persistence
    end

    def create_table(name, columns, indexes = {})
      @tables_mutex.synchronize do
        return false if @tables.key?(name)

        column_names = columns.map { |c| c.is_a?(Hash) ? c[:name] : c }
        @tables[name] = column_names
        @data[name] = []

        final_indexes = indexes.empty? ? determine_default_indexes(columns) : indexes
        @index_definitions[name] = final_indexes
        @index_data[name] = {}
        @primary_keys[name] = final_indexes['PRIMARY'] if final_indexes.key?('PRIMARY')

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
        @primary_keys.delete(name)
        persist_table_deletion(name)
        true
      end
    end

    def insert(table_name, values)
      @tables_mutex.synchronize do
        columns = @tables[table_name]
        return false unless columns && values.size == columns.size

        return :duplicate_pk if duplicate_primary_key?(table_name, values)

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

    def duplicate_primary_key?(table_name, values)
      pk_indices = @primary_keys[table_name]
      return false unless pk_indices

      pk_values = values.values_at(*pk_indices)
      !!@index_data[table_name]['PRIMARY']&.key?(pk_values)
    end

    def determine_default_indexes(columns)
      pk_idx = columns.find_index { |col| col.is_a?(Hash) && col[:primary_key] }
      pk_idx ? { 'PRIMARY' => [pk_idx] } : {}
    end

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
