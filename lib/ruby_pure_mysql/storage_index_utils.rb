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

      pk_indices = []
      columns.each_with_index do |col, idx|
        pk_indices << idx if col.is_a?(Hash) && col[:primary_key]
      end

      pk_indices.empty? ? {} : { 'PRIMARY' => pk_indices }
    end

    def duplicate_primary_key?(table_name, values)
      pk_indices = @primary_keys[table_name]
      return false unless pk_indices

      pk_values = values.values_at(*pk_indices)
      !!@index_data[table_name]['PRIMARY']&.key?(pk_values)
    end
  end
end
