# frozen_string_literal: true

module RubyPureMysql
  # インデックス管理ロジックを提供するモジュール
  module StorageIndexManager
    def update_rows_indexes(table_name, target_indices, update_map, merged_criteria)
      old_values_map = target_indices.to_h { |idx| [idx, @data[table_name][idx].dup] }

      return false unless perform_update_rows?(@data[table_name], @tables[table_name], update_map, merged_criteria)

      target_indices.each { |idx| update_row_indexes(table_name, idx, old_values_map[idx], @data[table_name][idx]) }
      save_data(table_name)
      true
    end

    def delete_rows_indexes(table_name, indices)
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

    def update_row_indexes(table_name, row_idx, old_values, new_values)
      remove_from_index(table_name, row_idx, old_values)
      @index_definitions[table_name].each do |idx_name, cols|
        add_to_index(table_name, idx_name, cols, new_values, row_idx)
      end
    end

    def remove_from_index(table_name, row_idx, values)
      return unless @index_definitions[table_name]

      @index_definitions[table_name].each do |idx_name, cols|
        remove_entry_from_index_table(table_name, idx_name, cols, row_idx, values)
      end
    end

    def add_to_index(table_name, idx_name, cols, values, row_idx)
      key = values.values_at(*cols)
      val0 = key[0]
      (@index_data[table_name][idx_name] ||= {})[val0] ||= {}
      (@index_data[table_name][idx_name][val0][key] ||= {})[row_idx] = true
    end

    def remove_entry_from_index_table(table_name, idx_name, cols, row_idx, values)
      key = values.values_at(*cols)
      val0 = key[0]
      idx_table = @index_data[table_name][idx_name]
      return unless idx_table&.dig(val0, key)

      cleanup_index_entry(idx_table, val0, key, row_idx)
    end

    def cleanup_index_entry(idx_table, val0, key, row_idx)
      idx_table[val0][key].delete(row_idx)
      idx_table[val0].delete(key) if idx_table[val0][key].empty?
      idx_table.delete(val0) if idx_table[val0].empty?
    end
  end
end
