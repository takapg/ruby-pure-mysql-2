# frozen_string_literal: true

module RubyPureMysql
  # ストレージエンジンにおける行の更新・削除のためのインデックス計算などの補助ロジックを提供するモジュール
  module StorageQueryUtils
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
      lookup_opts = { table_map: criteria[:table_map] || {}, table_name: criteria[:table_name] }
      indices = find_matching_indices(criteria[:client], rows, columns, criteria[:where], lookup_opts)
      return nil if indices.nil?

      indices = sort_indices(rows, indices, columns, criteria)
      criteria[:limit] ? indices.first(criteria[:limit]) : indices
    end

    def sort_indices(rows, indices, columns, criteria)
      return indices unless criteria[:order]

      sort_conditions = resolve_sort_conditions(criteria[:client], columns, criteria[:order])
      indices.sort { |i, j| compare_rows(rows[i], rows[j], sort_conditions) }
    end

    def determine_default_indexes(columns)
      pk_indices = columns.each_with_index.filter_map { |col, idx| idx if col.is_a?(Hash) && col[:primary_key] }
      pk_indices.empty? ? {} : { 'PRIMARY' => pk_indices }
    end

    def resolve_target_indices(table_name, criteria)
      normalized_criteria = criteria.is_a?(Array) ? { where: criteria } : criteria
      merged_criteria = normalized_criteria.merge(table_name: table_name)
      indices = collect_indices_to_delete(@data[table_name], @tables[table_name], merged_criteria)
      [indices, merged_criteria]
    end
  end
end
