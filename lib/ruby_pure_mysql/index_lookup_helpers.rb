# frozen_string_literal: true

module RubyPureMysql
  # インデックスルックアップのための低レベルヘルパーメソッドを提供するモジュール
  module IndexLookupHelpers
    def find_start_index(sorted_keys, val, operator)
      case operator
      when '=', '>=' then sorted_keys.bsearch_index { |k| nil_safe_cmp(k[0], val) >= 0 } || sorted_keys.size
      when '>' then sorted_keys.bsearch_index { |k| nil_safe_cmp(k[0], val).positive? } || sorted_keys.size
      else 0
      end
    end

    def find_end_index(sorted_keys, val, operator)
      case operator
      when '=', '<=' then sorted_keys.bsearch_index { |k| nil_safe_cmp(k[0], val).positive? } || sorted_keys.size
      when '<' then sorted_keys.bsearch_index { |k| nil_safe_cmp(k[0], val) >= 0 } || sorted_keys.size
      else sorted_keys.size
      end
    end

    def safe_compare(val, operator, target)
      return false if val.nil? || target.nil?

      val.send(operator == '=' ? :== : operator.to_sym, target)
    rescue StandardError
      false
    end

    def nil_safe_cmp(val1, val2)
      return 0 if val1.nil? && val2.nil?

      return -1 if val1.nil?
      return 1 if val2.nil?

      (val1 <=> val2) || 0
    end
  end
end
