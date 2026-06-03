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
      first_clause = find_clause_for_col(cols[0], group, lookup_opts)
      return nil unless first_clause && %w[= > < >= <=].include?(first_clause[:operator])

      data = @index_data.dig(table_name, idx_name)
      return [] unless data

      # インデックスキーをソートしてバイナリサーチを可能にする
      # 本来はストレージエンジン側でソート済みリストを維持すべきだが、ここではルックアップ時にソートする
      sorted_keys = data.keys.sort do |a, b|
        res = 0
        a.size.times do |i|
          cmp = nil_safe_cmp(a[i], b[i])
          if cmp != 0
            res = cmp
            break
          end
        end
        res
      end

      # 先頭カラムの条件に基づいて範囲を絞り込む
      val = first_clause[:value]
      op = first_clause[:operator]
      start_idx = 0
      end_idx = sorted_keys.size

      case op
      when '='
        start_idx = sorted_keys.bsearch_index { |k| nil_safe_cmp(k[0], val) >= 0 } || sorted_keys.size
        end_idx = sorted_keys.bsearch_index { |k| nil_safe_cmp(k[0], val) > 0 } || sorted_keys.size
      when '>'
        start_idx = sorted_keys.bsearch_index { |k| nil_safe_cmp(k[0], val) > 0 } || sorted_keys.size
      when '>='
        start_idx = sorted_keys.bsearch_index { |k| nil_safe_cmp(k[0], val) >= 0 } || sorted_keys.size
      when '<'
        end_idx = sorted_keys.bsearch_index { |k| nil_safe_cmp(k[0], val) >= 0 } || sorted_keys.size
      when '<='
        end_idx = sorted_keys.bsearch_index { |k| nil_safe_cmp(k[0], val) > 0 } || sorted_keys.size
      end

      candidates = sorted_keys[start_idx...end_idx] || []
      refined_candidates = filter_index_candidates(cols, group, lookup_opts, candidates)
      refined_candidates.flat_map { |k| data[k].keys }
    end

    def find_clause_for_col(col_idx, group, lookup_opts)
      group.find do |c|
        get_column_index(lookup_opts[:client], lookup_opts[:columns], c[:column], lookup_opts[:table_map]) == col_idx
      end
    end

    def filter_index_candidates(cols, group, lookup_opts, candidates)
      cols.each_with_index do |col_idx, i|
        clause = find_clause_for_col(col_idx, group, lookup_opts)
        next if clause.nil?

        candidates = filter_candidates(candidates, clause[:operator], clause[:value], i)
      end
      candidates
    end

    def filter_candidates(candidates, operator, value, col_pos)
      return candidates unless %w[= > < >= <=].include?(operator)

      candidates.select do |k|
        val = k[col_pos]
        operator == '=' ? val == value : safe_compare(val, operator, value)
      end
    end

    def safe_compare(val, operator, target)
      return false if val.nil? || target.nil?

      method = operator == '=' ? :== : operator.to_sym
      val.send(method, target)
    rescue StandardError
      false
    end

    private

    def nil_safe_cmp(a, b)
      return 0 if a.nil? && b.nil?
      return -1 if a.nil?
      return 1 if b.nil?
      a <=> b
    end
  end
end
