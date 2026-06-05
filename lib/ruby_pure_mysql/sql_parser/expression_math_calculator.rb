# frozen_string_literal: true

module RubyPureMysql
  # 算術演算の計算ロジックを提供するモジュール
  module ExpressionMathCalculator
    include ExpressionCommon

    MD_OPERATORS = %w[* / %].freeze

    def apply_multiplication_division(tokens)
      index = 1
      while index < tokens.size
        res = process_md_if_operator(tokens, index)
        return nil if res == :div_by_zero
        return :error if res == :error

        index += 1 if res == :ok
      end
      tokens
    end

    def process_md_if_operator(tokens, index)
      if MD_OPERATORS.include?(tokens[index])
        res = process_md_op!(tokens, index)
        return res == :ok ? :performed : res
      end
      :ok
    end

    def process_md_op!(tokens, index)
      left, operator, right = resolve_operands(tokens, index)
      return handle_missing_operand(tokens, index) if operator.nil?

      status = check_md_status(left, right, operator)
      return status unless status == :ok

      update_tokens_with_result!(tokens, index, calculate_md(left, right, operator))
    end

    def check_md_status(left, right, operator)
      return :error if left == :error || right == :error
      return :div_by_zero if %w[/ %].include?(operator) && right&.zero?

      :ok
    end

    def resolve_numeric_value(val)
      return nil if val.nil? || val == :nil || (val.is_a?(String) && val.casecmp?('NULL'))
      return val if val.is_a?(Numeric) || val == :error
      return :error if string_operator?(val)
      return evaluate_parenthesized_numeric(val) if parenthesized_string?(val)

      parse_string_to_numeric(val.to_s.strip)
    end

    def parse_string_to_numeric(str)
      return 0 if str.empty?
      return str.to_i if str.match?(/\A-?\d+\z/)

      f_val = str.to_f
      f_val == f_val.to_i ? f_val.to_i : f_val
    end

    def string_operator?(val)
      val.is_a?(String) && operator?(val)
    end

    def parenthesized_string?(val)
      val.is_a?(String) && val.start_with?('(') && val.end_with?(')')
    end

    def evaluate_parenthesized_numeric(val)
      evaluated = evaluate_expression(val)
      evaluated == :error ? :error : resolve_numeric_value(evaluated)
    end

    def calculate_md(left, right, operator)
      return nil if left.nil? || right.nil?

      case operator
      when '*' then left * right
      when '/' then left.to_f / right
      when '%' then left % right
      end
    end

    def handle_missing_operand(tokens, index)
      update_tokens_with_result!(tokens, index, nil)
    end

    def update_tokens_with_result!(tokens, index, result)
      tokens[index - 1] = result
      tokens.slice!(index, 2)
      :ok
    end

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

      # <=> (NULL-safe equal) の場合は nil が許容されるため、
      # ここで nil チェックによる早期リターンを行わず calculate_comparison に委ねる
      result = calculate_comparison(left, right, operator)
      update_tokens_with_result!(tokens, index, result)
      :ok
    end

    def calculate_comparison(left, right, operator)
      op_str = operator.to_s
      # <=> (NULL-safe equal) は NULL 同士の比較を許容するため、nil チェックより前に評価する
      if op_str == '<=>'
        return 1 if left.nil? && right.nil?
        return 0 if left.nil? || right.nil?
        return (left == right) ? 1 : 0
      end

      # MySQLの仕様: <=> 以外の比較演算子で片方が NULL の場合は結果も NULL (nil)
      return nil if left.nil? || right.nil?

      case operator
      when '='
        left == right ? 1 : 0
      when '!=', '<>'
        left != right ? 1 : 0
      when '<'
        left < right ? 1 : 0
      when '>'
        left > right ? 1 : 0
      when '<='
        left <= right ? 1 : 0
      when '>='
        left >= right ? 1 : 0
      else
        0
      end
    end

    def apply_addition_subtraction(tokens)
      index = 1
      while index < tokens.size
        op = tokens[index]
        res = ['+', '-'].include?(op) ? process_add_sub_op!(tokens, index) : :skipped
        return res if res == :error

        index += 1 if res == :skipped
      end
      tokens
    end

    def process_add_sub_op!(tokens, index)
      left, operator, right = resolve_operands(tokens, index)
      return handle_missing_operand(tokens, index) if operator.nil?
      return :error if left == :error || right == :error

      update_tokens_with_result!(tokens, index, calculate_sum_diff(left, operator, right))
    end

    private

    def resolve_operands(tokens, index)
      return [nil, nil, nil] if index <= 0 || index >= tokens.size - 1

      left_raw = tokens[index - 1]
      right_raw = tokens[index + 1]

      [resolve_numeric_value(left_raw), tokens[index], resolve_numeric_value(right_raw)]
    end
  end
end
