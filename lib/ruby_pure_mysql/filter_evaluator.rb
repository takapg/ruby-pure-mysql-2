# frozen_string_literal: true

require_relative 'filter_comparison_utils'

module RubyPureMysql
  # フィルタリング条件の評価ロジックを提供するモジュール
  module FilterEvaluator
    include FilterComparisonUtils

    def apply_filter(val, operator, target_value, regex = nil)
      return evaluate_null_guards?(val, operator) if null_operator?(operator)
      return false if val.nil? && operator != '<=>'

      if regex.is_a?(Regexp)
        res = regex.match?(val.to_s)
        return operator.start_with?('NOT ') ? !res : res
      end

      res = compare_value(val, operator, target_value)
      [true, 1].include?(res)
    rescue StandardError
      false
    end

    def null_operator?(operator)
      ['IS NULL', 'IS NOT NULL'].include?(operator)
    end

    def evaluate_null_guards?(val, operator)
      operator == 'IS NULL' ? val.nil? : !val.nil?
    end

    def compare_value(val, operator, target_value)
      case operator
      when 'LIKE', 'NOT LIKE' then handle_like_operator(val, target_value, operator)
      when 'REGEXP', 'RLIKE', 'NOT REGEXP', 'NOT RLIKE' then handle_regexp_operator(val, target_value, operator)
      when 'IN', 'NOT IN' then handle_in_operator_with_negation(val, target_value, operator)
      when '<=>' then handle_null_safe_equal(val, target_value)
      when 'BETWEEN', 'NOT BETWEEN' then handle_between_operator?(val, operator, target_value)
      when '=', '!=', '<>' then compare_equality?(val, operator, target_value)
      else compare_generic_operator(val, operator, target_value)
      end
    end

    def match_pattern?(val, target, type)
      return target.match?(val.to_s) if target.is_a?(Regexp)

      (type == :like ? build_like_regex(target) : Regexp.new(target.to_s, Regexp::IGNORECASE)).match?(val.to_s)
    end

    def match_between?(val, operator, target)
      operator == 'BETWEEN' ? val.between?(*target) : !val.between?(*target)
    end

    def row_matches_compiled_groups?(row, compiled_groups)
      compiled_groups.any? do |group|
        group.all? do |c|
          apply_filter(row[c[:col_idx]], c[:operator], c[:value], c[:regex])
        end
      end
    end

    private

    def handle_like_operator(val, target, operator)
      res = match_pattern?(val, target, :like)
      operator == 'LIKE' ? res : !res
    end

    def handle_regexp_operator(val, target, operator)
      res = match_pattern?(val, target, :regexp)
      operator.start_with?('NOT') ? !res : res
    end

    def handle_in_operator_with_negation(val, target, operator)
      res = handle_in_operator(val, target)
      operator == 'IN' ? res : !res
    end

    def compare_equality?(val, operator, target_value)
      v1, v2 = normalize_for_comparison(val, target_value)
      operator == '=' ? v1 == v2 : v1 != v2
    end

    def compare_generic_operator(val, operator, target_value)
      v1, v2 = normalize_for_comparison(val, target_value)
      begin
        v1.public_send(operator.to_sym, v2)
      rescue StandardError
        false
      end
    end
  end
end
