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
    end

    def determine_default_indexes(columns)
      return {} unless columns.is_a?(Array)

      pk_indices = find_table_constraint_pk(columns) || find_column_attribute_pks(columns)
      pk_indices.empty? ? {} : { 'PRIMARY' => pk_indices }
    end

    def duplicate_primary_key?(table_name, values)
      pk_indices = @primary_keys[table_name]
      return false unless pk_indices

      pk_values = values.values_at(*pk_indices)
      !!@index_data[table_name]['PRIMARY']&.key?(pk_values)
    end

    private

    def find_table_constraint_pk(columns)
      constraint = columns.find { |col| col.is_a?(Hash) && col[:primary_key] && col.key?(:columns) }
      (constraint && constraint[:columns].is_a?(Array)) ? constraint[:columns] : nil
    end

    def find_column_attribute_pks(columns)
      columns.each_index.select { |i| columns[i].is_a?(Hash) && columns[i][:primary_key] }
    end
  end
end
