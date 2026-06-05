# frozen_string_literal: true

module RubyPureMysql
  # インデックスルックアップのための低レベルヘルパーメソッドを提供するモジュール
  module IndexLookupHelpers
    def find_start_index(sorted_keys, val, operator)
      case operator
      when '=', '>=' then bsearch_index_or_size(sorted_keys) { |k| nil_safe_cmp(k[0], val) >= 0 }
      when '>' then bsearch_index_or_size(sorted_keys) { |k| nil_safe_cmp(k[0], val).positive? }
      when 'IS NOT NULL' then bsearch_index_or_size(sorted_keys) { |k| !k[0].nil? }
      else 0
      end
    end

    def find_end_index(sorted_keys, val, operator)
      case operator
      when '=', '<=' then bsearch_index_or_size(sorted_keys) { |k| nil_safe_cmp(k[0], val).positive? }
      when '<' then bsearch_index_or_size(sorted_keys) { |k| nil_safe_cmp(k[0], val) >= 0 }
      when 'IS NULL' then bsearch_index_or_size(sorted_keys) { |k| !k[0].nil? }
      else sorted_keys.size
      end
    end

    # MySQL 8.0 の比較演算仕様に準拠し、いずれかが NULL の場合は
    # IS NULL / IS NOT NULL 以外では常に false (UNKNOWN) を返す
    def safe_compare(val, operator, target)
      case operator
      when 'IS NULL' then val.nil?
      when 'IS NOT NULL' then !val.nil?
      when '<=>' then handle_null_safe_compare(val, target, operator)
      else handle_standard_safe_compare(val, target, operator)
      end
    rescue StandardError
      false
    end

    def handle_null_safe_compare(val, target, operator)
      return true if val.nil? && target.nil?
      return false if val.nil? || target.nil?

      matches_operator?(val, operator, target)
    end

    def handle_standard_safe_compare(val, target, operator)
      return false if val.nil? || target.nil?

      matches_operator?(val, operator, target)
    end

    # MySQL 8.0 のソート順に準拠し、NULL を最小値として扱う
    def nil_safe_cmp(val1, val2)
      return 0 if val1.nil? && val2.nil?

      return -1 if val1.nil?
      return 1 if val2.nil?

      (val1 <=> val2) || 0
    end

    private

    def bsearch_index_or_size(sorted_keys, ...)
      sorted_keys.bsearch_index(...) || sorted_keys.size
    end

    def matches_operator?(val, operator, target)
      case operator
      when '=', '<=>' then val == target
      when '>'  then val > target
      when '<'  then val < target
      when '>=' then val >= target
      when '<=' then val <= target
      else false
      end
    end
  end
end
