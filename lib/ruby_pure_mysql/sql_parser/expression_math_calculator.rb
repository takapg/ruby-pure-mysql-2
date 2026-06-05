# frozen_string_literal: true

module RubyPureMysql
  # 算術演算の計算ロジックを提供するモジュール
  module ExpressionMathCalculator
    include ExpressionCommon

    MD_OPERATORS = %w[* / %].freeze

    def apply_unary_operators(tokens)
      (tokens.size - 1).downto(0) do |i|
        if tokens[i] == '-' && (i == 0 || ['+', '-', '*', '/', '%', '('].include?(tokens[i - 1]))
          next_val = resolve_numeric_value(tokens[i + 1])
          if next_val.is_a?(Numeric)
            tokens[i] = -next_val
            tokens.slice!(i + 1)
          elsif next_val == :error
            return :error
          elsif next_val.nil?
            tokens[i] = nil
            tokens.slice!(i + 1)
          end
        elsif tokens[i] == '+' && (i == 0 || ['+', '-', '*', '/', '%', '('].include?(tokens[i - 1]))
          tokens.slice!(i)
        end
      end
      tokens
    end

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
      return handle_missing_operand(tokens, index) if left.nil? || right.nil?

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
      return nil if val.nil? || val == :nil
      return val if val.is_a?(Numeric) || val == :error

      val_s = val.to_s.strip
      return nil if val_s.casecmp?('NULL')

      return :error if string_operator?(val)
      return evaluate_parenthesized_numeric(val) if parenthesized_string?(val)

      parse_string_to_numeric(val_s)
    end

    def parse_string_to_numeric(str)
      return 0 if str.empty?
      return 0 unless str.match?(/\A[-+]?(\d|\.)/)

      (str.include?('.') || str.match?(/[eE]/)) ? str.to_f : str.to_i
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
      return handle_missing_operand(tokens, index) if left.nil? || right.nil?
      return :error if left == :error || right == :error

      update_tokens_with_result!(tokens, index, calculate_sum_diff(left, operator, right))
    end

    private

    def resolve_operands(tokens, index)
      left_raw = tokens[index - 1]
      right_raw = tokens[index + 1]
      return [nil, nil, nil] if left_raw.nil? || right_raw.nil?

      [resolve_numeric_value(left_raw), tokens[index], resolve_numeric_value(right_raw)]
    end
  end
end
