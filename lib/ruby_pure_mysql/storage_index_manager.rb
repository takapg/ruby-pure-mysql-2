# frozen_string_literal: true

module RubyPureMysql
  # インデックス管理ロジックを提供するモジュール
  # rubocop:disable Naming/PredicateMethod
  module StorageIndexManager
    def refresh_index_entries(table_name, target_indices, update_map, merged_criteria)
      old_values_map = target_indices.to_h { |idx| [idx, @data[table_name][idx].dup] }

      return false unless perform_update_rows?(@data[table_name], @tables[table_name], update_map, merged_criteria)

      updated_cols = update_map.keys
      updated_indexes = []
      target_indices.each do |idx|
        updated_indexes.concat(update_row_indexes(table_name, idx, old_values_map[idx], @data[table_name][idx], updated_cols))
      end
      save_data(table_name)
      Array(updated_indexes).uniq
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

    def update_row_indexes(table_name, row_idx, old_values, new_values, updated_cols)
      return [] unless @index_definitions[table_name]

      touched = []
      @index_definitions[table_name].each do |idx_name, cols|
        # インデックス対象カラムが更新対象に含まれているか確認
        next unless cols.intersect?(updated_cols)

        # 実際にインデックスキーの値が変更されたか確認
        old_key = old_values.values_at(*cols)
        new_key = new_values.values_at(*cols)
        next if old_key == new_key

        remove_entry_from_index_table(table_name, idx_name, cols, row_idx, old_values)
        add_to_index(table_name, idx_name, cols, new_values, row_idx)
        touched << idx_name
      end
      touched
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
