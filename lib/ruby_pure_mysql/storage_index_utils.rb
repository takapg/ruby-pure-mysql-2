# frozen_string_literal: true

module RubyPureMysql
  # ストレージエンジンのインデックス構築と検証を支援するユーティリティ
  module StorageIndexUtils
    def setup_table_indexes(name, columns, indexes)
      final_indexes = (indexes || {}).dup
      final_indexes.merge!(determine_default_indexes(columns)) { |_, old, _| old }
      @index_definitions[name] = final_indexes
      @index_data[name] = {}
      @primary_keys[name] = final_indexes['PRIMARY']

      @unique_indexes ||= {}
      @unique_indexes[name] = final_indexes.keys.select { |idx_name| unique_index?(idx_name) }
    end

    def determine_default_indexes(columns)
      return {} unless columns.is_a?(Array)

      indexes = {}
      pk_indices = find_table_constraint_pk(columns) || find_column_attribute_pks(columns)
      indexes['PRIMARY'] = pk_indices unless pk_indices.empty?

      add_unique_indexes(indexes, columns)
      indexes
    end

    def duplicate_unique_key?(table_name, values)
      unique_idxs = @unique_indexes[table_name]
      return false unless unique_idxs

      unique_idxs.any? do |idx_name|
        col_indices = @index_definitions[table_name][idx_name]
        val = values.values_at(*col_indices)
        @index_data[table_name][idx_name]&.key?(val)
      end
    end

    def rebuild_all_unique_indexes
      @unique_indexes ||= {}
      @index_definitions.each do |table_name, indexes|
        @unique_indexes[table_name] = indexes.keys.select { |idx_name| unique_index?(idx_name) }
      end
    end

    private

    def unique_index?(idx_name)
      idx_name == 'PRIMARY' || idx_name.start_with?('unique_')
    end

    def add_unique_indexes(indexes, columns)
      columns.each_with_index do |col, idx|
        indexes["unique_#{col[:name]}"] = [idx] if col.is_a?(Hash) && col[:unique] && !col[:primary_key]
      end
    end

    def find_table_constraint_pk(columns)
      constraint = columns.find { |col| col.is_a?(Hash) && col[:primary_key] && col.key?(:columns) }
      constraint && constraint[:columns].is_a?(Array) ? constraint[:columns] : nil
    end

    def find_column_attribute_pks(columns)
      columns.each_index.select { |i| columns[i].is_a?(Hash) && columns[i][:primary_key] }
    end
  end
end
