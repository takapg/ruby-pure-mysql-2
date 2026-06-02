# frozen_string_literal: true

module RubyPureMysql
  # インデックスを利用したルックアップロジックを提供するモジュール
  module IndexLookupUtils
    def try_index_lookup(table_name, _table_columns, where_clauses, lookup_opts)
      return nil unless @index_definitions&.key?(table_name)

      groups = normalize_where_groups(where_clauses)
      return nil if groups.size > 1

      find_best_index_match(table_name, groups.first, lookup_opts)
    end

    private

    def find_best_index_match(table_name, group, lookup_opts)
      @index_definitions[table_name].each do |idx_name, cols|
        res = attempt_index_match(table_name, idx_name, cols, group, lookup_opts)
        return res if res
      end
      nil
    end

    def attempt_index_match(table_name, idx_name, cols, group, lookup_opts)
      values = collect_exact_values(cols, group, lookup_opts)
      return lookup_exact(table_name, idx_name, values) if values

      lookup_prefix(table_name, idx_name, cols, group, lookup_opts)
    end

    def collect_exact_values(cols, group, lookup_opts)
      cols.map do |col_idx|
        clause = group.find do |c|
          get_column_index(lookup_opts[:client], lookup_opts[:columns], c[:column], lookup_opts[:table_map]) == col_idx
        end
        return nil unless clause && clause[:operator] == '='

        clause[:value]
      end
    end

    def lookup_exact(table_name, idx_name, values)
      data = @index_data.dig(table_name, idx_name)
      return [] unless data

      data[values]&.keys || []
    end

    def lookup_prefix(table_name, idx_name, cols, group, lookup_opts)
      first_clause = group.find { |c| get_column_index(lookup_opts[:client], lookup_opts[:columns], c[:column], lookup_opts[:table_map]) == cols[0] }
      return nil unless first_clause && %w[= > < >= <=].include?(first_clause[:operator])

      data = @index_data.dig(table_name, idx_name)
      return [] unless data

      candidates = data.keys
      cols.each_with_index do |col_idx, i|
        clause = group.find { |c| get_column_index(lookup_opts[:client], lookup_opts[:columns], c[:column], lookup_opts[:table_map]) == col_idx }
        break if clause.nil?

        op, val = clause[:operator], clause[:value]
        if op == '='
          candidates = candidates.select { |k| !k[i].nil? && !val.nil? && k[i] == val }
        elsif %w[> < >= <=].include?(op)
          candidates = candidates.select { |k| !k[i].nil? && !val.nil? && k[i].send(op.to_sym, val) }
          break
        else
          break
        end
      end
      candidates.flat_map { |k| data[k].keys }
    end
  end
end
