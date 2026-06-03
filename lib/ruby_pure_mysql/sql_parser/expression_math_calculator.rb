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
      left_raw, operator, right_raw = tokens[(index - 1)..(index + 1)]
      return handle_missing_operand(tokens, index) if left_raw.nil? || right_raw.nil?

      left, right = resolve_md_operands(left_raw, right_raw)
      status = check_md_status(left, right, operator)
      return status unless status == :ok

      tokens[index - 1] = calculate_md(left, right, operator)
      tokens.slice!(index, 2)
      :ok
    end

    def check_md_status(left, right, operator)
      return :error if left == :error || right == :error
      return :div_by_zero if %w[/ %].include?(operator) && right&.zero?

      :ok
    end

    def resolve_md_operands(left, right)
      [resolve_numeric_value(left), resolve_numeric_value(right)]
    end

    def resolve_numeric_value(val)
      return nil if val.nil? || val == :nil
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
      tokens[index - 1] = nil
      tokens.slice!(index, 2)
      :ok
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
      left_raw = tokens[index - 1]
      right_raw = tokens[index + 1]
      return handle_missing_operand(tokens, index) if left_raw.nil? || right_raw.nil?

      left = resolve_numeric_value(left_raw)
      right = resolve_numeric_value(right_raw)
      return :error if left == :error || right == :error

      tokens[index - 1] = calculate_sum_diff(left, tokens[index], right)
      tokens.slice!(index, 2)
      :ok
    end
  end
end
