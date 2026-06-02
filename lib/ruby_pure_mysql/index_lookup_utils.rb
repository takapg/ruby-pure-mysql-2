# frozen_string_literal: true

module RubyPureMysql
  module IndexLookupUtils
    def try_index_lookup(client, table_name, table_columns, where_clauses, table_map)
      return nil unless @index_definitions&.key?(table_name)

      groups = normalize_where_groups(where_clauses)
      return nil if groups.size > 1

      find_best_index_match(client, table_name, table_columns, groups.first, table_map)
    end

    private

    def find_best_index_match(client, table_name, table_columns, group, table_map)
      @index_definitions[table_name].each do |idx_name, cols|
        res = attempt_index_match(client, table_name, idx_name, cols, group, table_columns, table_map)
        return res if res
      end
      nil
    end

    def attempt_index_match(client, table_name, idx_name, cols, group, table_columns, table_map)
      index_values = []
      all_match = true

      cols.each do |col_idx|
        clause = group.find { |c| get_column_index(client, table_columns, c[:column], table_map) == col_idx }
        if clause && clause[:operator] == '='
          index_values << clause[:value]
        else
          all_match = false
          break
        end
      end

      return lookup_exact(table_name, idx_name, index_values) if all_match

      lookup_prefix(client, table_name, idx_name, cols, group, table_columns, table_map)
    end

    def lookup_exact(table_name, idx_name, values)
      key = values.to_json
      data = @index_data.dig(table_name, idx_name)
      data[key] if data&.key?(key)
    end

    def lookup_prefix(client, table_name, idx_name, cols, group, table_columns, table_map)
      first_col_idx = cols[0]
      clause = group.find { |c| get_column_index(client, table_columns, c[:column], table_map) == first_col_idx }
      return nil unless clause && clause[:operator] == '='

      val0 = clause[:value]
      candidates = []
      data = @index_data.dig(table_name, idx_name)
      return nil unless data

      data.each do |key, row_indices|
        candidates.concat(row_indices) if JSON.parse(key)[0] == val0
      end
      candidates.empty? ? nil : candidates
    end
  end
end
