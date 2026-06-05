# frozen_string_literal: true

module RubyPureMysql
  # 比較演算の計算ロジックを提供するモジュール
  module ExpressionComparisonCalculator
    include ExpressionCommon

    COMPARISON_OPS = {
      '='  => ->(l, r) { l == r ? 1 : 0 },
      '!=' => ->(l, r) { l == r ? 0 : 1 },
      '<>' => ->(l, r) { l == r ? 0 : 1 },
      '<'  => ->(l, r) { l < r ? 1 : 0 },
      '>'  => ->(l, r) { l > r ? 1 : 0 },
      '<=' => ->(l, r) { l <= r ? 1 : 0 },
      '>=' => ->(l, r) { l >= r ? 1 : 0 }
    }.freeze

    def apply_comparisons(tokens)
      index = 1
      while index < tokens.size
        res = process_comparison_if_operator(tokens, index)
        return :error if res == :error

        index += 1 if res == :ok
      end
      tokens
    end

    def process_comparison_if_operator(tokens, index)
      op = tokens[index]
      if %w[= <=> != <> < > <= >=].include?(op.to_s)
        res = process_comparison_op!(tokens, index)
        return res == :ok ? :performed : res
      end
      :ok
    end

    def process_comparison_op!(tokens, index)
      left, operator, right = resolve_operands(tokens, index)
      return handle_missing_operand(tokens, index) if operator.nil?

      return :error if left == :error || right == :error

      result = calculate_comparison(left, right, operator)
      result = 0 if operator.to_s == '<=>' && result.nil?

      update_tokens_with_result!(tokens, index, result)
      :ok
    end

    def calculate_comparison(left, right, operator)
      op_str = operator.to_s

      return calculate_null_safe_equal(left, right) if op_str == '<=>'

      return nil if left.nil? || right.nil?

      calculate_standard_comparison(left, right, operator)
    end

    private

    def calculate_null_safe_equal(left, right)
      return 1 if left.nil? && right.nil?
      return 0 if left.nil? || right.nil?

      left == right ? 1 : 0
    end

    def calculate_standard_comparison(left, right, operator)
      op = COMPARISON_OPS[operator.to_s]
      op ? op.call(left, right) : 0
    end
  end
end
