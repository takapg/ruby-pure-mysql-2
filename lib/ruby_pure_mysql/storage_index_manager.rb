# frozen_string_literal: true

module RubyPureMysql
  # インデックス管理ロジックを提供するモジュール
  # rubocop:disable Naming/PredicateMethod
  module StorageIndexManager
    def refresh_index_entries(table_name, target_indices, update_map, merged_criteria)
      old_values_map = target_indices.to_h { |idx| [idx, @data[table_name][idx].dup] }

      return false unless perform_update_rows?(@data[table_name], @tables[table_name], update_map, merged_criteria)

      affected_indexes = collect_affected_indexes(table_name, target_indices, old_values_map, update_map.keys)
      save_data(table_name)
      affected_indexes.uniq
    end

    def remove_index_entries(table_name, indices)
      indices.reverse_each do |idx|
        remove_from_index(table_name, idx, @data[table_name][idx])
        @data[table_name].delete_at(idx)
      end
      save_data(table_name)
      true
    end

    def update_indexes(table_name, values)
      return unless @index_definitions[table_name]

      row_idx = @data[table_name].size - 1
      @index_definitions[table_name].each do |idx_name, cols|
        add_to_index(table_name, idx_name, cols, values, row_idx)
      end
    end

    private

    def collect_affected_indexes(table_name, target_indices, old_values_map, updated_cols)
      target_indices.flat_map do |idx|
        update_row_indexes(table_name, idx, old_values_map[idx], @data[table_name][idx], updated_cols)
      end
    end

    def update_row_indexes(table_name, row_idx, old_values, new_values, updated_cols)
      return [] unless @index_definitions[table_name]

      updated_indexes = []
      @index_definitions[table_name].each do |idx_name, cols|
        next unless cols.intersect?(updated_cols)

        remove_entry_from_index_table(table_name, idx_name, cols, row_idx, old_values)
        add_to_index(table_name, idx_name, cols, new_values, row_idx)
        updated_indexes << idx_name
      end
      updated_indexes
    end

    def remove_from_index(table_name, row_idx, values)
      return unless @index_definitions[table_name]

      @index_definitions[table_name].each do |idx_name, cols|
        remove_entry_from_index_table(table_name, idx_name, cols, row_idx, values)
      end
    end

    def add_to_index(table_name, idx_name, cols, values, row_idx)
      key = values.values_at(*cols)
      (@index_data[table_name][idx_name] ||= {})[key] ||= {}
      @index_data[table_name][idx_name][key][row_idx] = true
    end

    def remove_entry_from_index_table(table_name, idx_name, cols, row_idx, values)
      key = values.values_at(*cols)
      idx_table = @index_data[table_name][idx_name]
      return unless idx_table&.key?(key)

      cleanup_index_entry(idx_table, key, row_idx)
    end

    def cleanup_index_entry(idx_table, key, row_idx)
      entry = idx_table[key]
      return unless entry

      entry.delete(row_idx)
      idx_table.delete(key) if entry.empty?
    end
  end
  # rubocop:enable Naming/PredicateMethod
end
