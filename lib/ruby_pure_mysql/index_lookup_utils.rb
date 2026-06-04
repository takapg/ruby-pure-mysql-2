# frozen_string_literal: true

require_relative 'index_lookup_helpers'

module RubyPureMysql
  # インデックスを利用したルックアップロジックを提供するモジュール
  module IndexLookupUtils
    include IndexLookupHelpers

    def try_index_lookup(table_name, _table_columns, where_clauses, lookup_opts)
      return nil unless @index_definitions&.key?(table_name)

      groups = normalize_where_groups(where_clauses)
      return nil if groups.size > 1

      find_best_index_match(table_name, groups.first, lookup_opts)
    end

    def clear_index_cache(table_name, idx_name = nil)
      return unless @index_sorted_keys

      if idx_name
        @index_sorted_keys[table_name]&.delete(idx_name)
      else
        @index_sorted_keys.delete(table_name)
      end
    end

    private

    def find_best_index_match(table_name, group, lookup_opts)
      @index_definitions[table_name].each do |idx_name, cols|
        res = attempt_index_match(table_name, idx_name, cols, group, lookup_opts)
        return res unless res.nil?
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
        clause = find_clause_for_col(col_idx, group, lookup_opts)
        return nil unless clause&.[](:operator) == '='

        clause[:value]
      end
    end

    def lookup_exact(table_name, idx_name, values)
      return [] if values.any?(&:nil?)

      data = @index_data.dig(table_name, idx_name)
      data ? (data[values]&.keys || []) : []
    end

    def lookup_prefix(table_name, idx_name, cols, group, lookup_opts)
      first_clause = find_clause_for_col(cols[0], group, lookup_opts)
      return nil unless valid_prefix_operator?(first_clause)

      data = @index_data.dig(table_name, idx_name)
      return [] unless data

      candidates = extract_range_candidates(table_name, idx_name, data, first_clause)
      filter_index_candidates(cols, group, lookup_opts, candidates).flat_map { |k| data[k].keys }
    end

    def valid_prefix_operator?(clause)
      clause && %w[= > < >= <= IS NULL IS NOT NULL].include?(clause[:operator])
    end

    # インデックスから範囲候補を抽出する。
    # nil_safe_cmp により NULL は先頭に配置されるため、演算子によっては
    # 候補に NULL が含まれるが、後の filter_index_candidates で safe_compare により除外される。
    def extract_range_candidates(table_name, idx_name, data, clause)
      sorted_keys = get_sorted_keys(table_name, idx_name, data)
      start_idx = find_start_index(sorted_keys, clause[:value], clause[:operator])
      end_idx = find_end_index(sorted_keys, clause[:value], clause[:operator])
      sorted_keys[start_idx...end_idx] || []
    end

    def get_sorted_keys(table_name, idx_name, data)
      @index_sorted_keys ||= {}
      @index_sorted_keys[table_name] ||= {}
      @index_sorted_keys[table_name][idx_name] ||= sort_index_keys(data.keys)
    end

    def sort_index_keys(keys)
      keys.sort { |a, b| a.zip(b).map { |x, y| nil_safe_cmp(x, y) }.find { |r| r != 0 } || 0 }
    end

    def find_clause_for_col(col_idx, group, lookup_opts)
      group.find do |c|
        get_column_index(lookup_opts[:client], lookup_opts[:columns], c[:column], lookup_opts[:table_map]) == col_idx
      end
    end

    # 抽出された候補を各カラムの条件で絞り込む。
    # safe_compare を使用することで、比較演算子を用いた検索時に
    # カラム値または検索値が NULL である行が確実に除外されることを保証する。
    def filter_index_candidates(cols, group, lookup_opts, candidates)
      cols.each_with_index do |col_idx, i|
        clause = find_clause_for_col(col_idx, group, lookup_opts)
        next if clause.nil?

        candidates = filter_candidates(candidates, clause[:operator], clause[:value], i)
      end
      candidates
    end

    def filter_candidates(candidates, operator, value, col_pos)
      return candidates unless %w[= > < >= <= IS NULL IS NOT NULL].include?(operator)

      candidates.select do |k|
        val = k[col_pos]
        safe_compare(val, operator, value)
      end
    end
  end
end
