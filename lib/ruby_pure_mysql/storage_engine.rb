# frozen_string_literal: true

require 'json'
require 'fileutils'
require_relative 'table_handler_utils'

module RubyPureMysql
  # インメモリでテーブル定義を管理するストレージエンジン
  class StorageEngine
    include TableHandlerUtils
    include SortUtils

    def initialize
      @tables = {}
      @data = {}
      @tables_mutex = Mutex.new
      @db_dir = 'db'
      setup_persistence
    end

    def create_table(name, columns)
      @tables_mutex.synchronize do
        return false if @tables.key?(name)

        @tables[name] = columns
        @data[name] = []
        persist_table_creation(name)
        true
      end
    end

    def drop_table(name)
      @tables_mutex.synchronize do
        return false unless @tables.key?(name)

        @tables.delete(name)
        @data.delete(name)
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
        save_data(table_name)
        true
      end
    end

    def update_rows_with_where(table_name, criteria, update_map)
      @tables_mutex.synchronize do
        return false unless @data.key?(table_name)

        return false unless perform_update_rows?(@data[table_name], @tables[table_name], update_map, criteria)

        save_data(table_name)
        true
      end
    end

    def delete_rows_with_where(table_name, criteria)
      @tables_mutex.synchronize do
        return false unless @data.key?(table_name)

        indices = collect_indices_to_delete(@data[table_name], @tables[table_name], criteria)
        return false if indices.nil?

        indices.reverse_each { |idx| @data[table_name].delete_at(idx) }
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

    def setup_persistence
      FileUtils.mkdir_p(File.join(@db_dir, 'data'))
      load_tables
      load_all_data
    end

    def load_tables
      path = File.join(@db_dir, 'tables.json')
      @tables = JSON.parse(File.read(path)) if File.exist?(path)
    end

    def save_tables
      File.write(File.join(@db_dir, 'tables.json'), JSON.dump(@tables))
    end

    def load_all_data
      @tables.keys.each { |name| @data[name] = load_data(name) }
    end

    def load_data(name)
      path = data_file_path(name)
      File.exist?(path) ? JSON.parse(File.read(path)) : []
    end

    def save_data(name)
      File.write(data_file_path(name), JSON.dump(@data[name]))
    end

    def data_file_path(name)
      File.join(@db_dir, 'data', "#{name}.json")
    end

    def persist_table_creation(name)
      save_tables
      save_data(name)
    end

    def persist_table_deletion(name)
      save_tables
      FileUtils.rm_f(data_file_path(name))
    end

    def perform_update_rows?(rows, columns, update_map, criteria)
      return true if criteria[:limit]&.zero?

      target_indices = get_target_indices(rows, columns, criteria)
      return false if target_indices.nil?

      target_indices.each { |i| update_row(rows[i], update_map) }
      true
    end

    def update_row(row, update_map)
      update_map.each { |idx, val| row[idx] = val }
    end

    def collect_indices_to_delete(rows, columns, criteria)
      return [] if criteria[:limit]&.zero?

      get_target_indices(rows, columns, criteria)
    end

    def get_target_indices(rows, columns, criteria)
      indices = find_matching_indices(criteria[:client], rows, columns, criteria[:where], criteria[:table_map] || {})
      return nil if indices.nil?

      indices = sort_indices(rows, indices, columns, criteria)
      criteria[:limit] ? indices.first(criteria[:limit]) : indices
    end

    def sort_indices(rows, indices, columns, criteria)
      return indices unless criteria[:order]

      sort_conditions = resolve_sort_conditions(criteria[:client], columns, criteria[:order])
      indices.sort { |i, j| compare_rows(rows[i], rows[j], sort_conditions) }
    end
  end
end
