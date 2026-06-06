# frozen_string_literal: true

module RubyPureMysql
  # フィルタ評価のための比較および正規化ヘルパーを提供するモジュール
  module FilterComparisonUtils
    def handle_in_operator(val, target_value)
      return target_value.include?(val) unless val.is_a?(Numeric)

      target_value.any? do |t|
        cast_to_numeric_for_comparison(t).is_a?(Numeric) && cast_to_numeric_for_comparison(t) == val
      end
    end

    def handle_between_operator?(val, operator, target_value)
      if val.is_a?(Numeric)
        normalized_target = target_value.map { |t| cast_to_numeric_for_comparison(t) }
        return false if normalized_target.any? { |t| !t.is_a?(Numeric) }

        begin
          return match_between?(val, operator, normalized_target)
        rescue StandardError
          return false
        end
      end
      match_between?(val, operator, target_value)
    end

    def normalize_for_distinct(value)
      value.nil? ? :null : value.to_s
    end

    def normalize_for_comparison(val1, val2)
      return [val1, val2] if val1.nil? || val2.nil?
      return [val1, val2] unless val1.is_a?(Numeric) || val2.is_a?(Numeric)

      n1 = cast_to_numeric_for_comparison(val1)
      n2 = cast_to_numeric_for_comparison(val2)
      n1.is_a?(Numeric) && n2.is_a?(Numeric) ? [n1, n2] : [val1, val2]
    end

    def cast_to_numeric_for_comparison(val)
      return val if val.is_a?(Numeric)
      return nil if val.nil?

      val.to_s.to_f
    end

    def handle_null_safe_equal(val, target)
      return 1 if val.nil? && target.nil?
      return 0 if val.nil? || target.nil?

      compare_equality?(val, '=', target) ? 1 : 0
    end
  end
end
