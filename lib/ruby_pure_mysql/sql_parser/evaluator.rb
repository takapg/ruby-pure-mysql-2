# frozen_string_literal: true

module RubyPureMysql
  # SQLクエリの式を評価するモジュール
  module Evaluator
    include ExpressionUtils

    def evaluate_expression(col)
      col = col.strip
      return nil if col.casecmp?('NULL')

      # 外側の括弧が式全体を囲んでいる場合は剥離して再帰的に評価する
      col = col[1...-1].strip while fully_parenthesized?(col)

      return evaluate_system_variable(col) if col.start_with?('@@')
      return evaluate_function(col) if single_function_call?(col)

      evaluate_math(col)
    end

    def fully_parenthesized?(col)
      return false unless col.start_with?('(') && col.end_with?(')')

      depth = 0
      quote = nil
      col.each_char.with_index do |char, index|
        quote, depth = update_paren_state(char, index, col, quote, depth)
        return false if depth.zero? && index < col.length - 1 && char == ')'
      end
      depth.zero?
    end

    def update_paren_state(char, index, col, quote, depth)
      return handle_quote_paren_state(char, index, col, quote, depth) if quote

      handle_bracket_paren_state(char, depth)
    end

    def handle_quote_paren_state(char, index, col, quote, depth)
      new_quote = quote == char && (index.zero? || col[index - 1] != '\\') ? nil : quote
      [new_quote, depth]
    end

    def handle_bracket_paren_state(char, depth)
      if ["'", '"'].include?(char)
        [char, depth]
      elsif char == '('
        [nil, depth + 1]
      elsif char == ')'
        [nil, depth.positive? ? depth - 1 : 0]
      else
        [nil, depth]
      end
    end

    def evaluate_function(col)
      match = col.match(/\A(\w+)\s*\((.*)\)\z/)
      return :error unless match

      args = evaluate_function_args(match[2])
      return :error if args == :error

      call_builtin_function(match[1].downcase, args)
    end

    def evaluate_math(col)
      result = process_math_tokens(col)
      return result if result == :error || result.nil?

      result.size == 1 ? result.first : result
    end

    def process_math_tokens(col)
      tokens = tokenize_math(col)
      return :error if tokens == :error

      # 優先順位: 乗除算 -> 加減算 -> 文字列結合
      tokens = apply_multiplication_division(tokens)
      return :error if tokens == :error
      return nil if tokens.nil?

      tokens = apply_addition_subtraction(tokens)
      return :error if tokens == :error

      tokens = apply_comparisons(tokens)
      return :error if tokens == :error

      apply_string_concatenation(tokens)
    end

    private

    def single_function_call?(col)
      return false unless col.match?(/\A\w+\s*\(.*\)\z/)

      depth = 0
      first_paren_idx = col.index('(')
      return false if first_paren_idx.nil?

      col[first_paren_idx..].each_char do |char|
        depth += 1 if char == '('
        depth -= 1 if char == ')'
        return false if depth.negative?
      end
      depth.zero?
    end

    def evaluate_function_args(args_str)
      return [] if args_str.strip.empty?

      split_args(args_str).map do |arg|
        val = evaluate_expression(arg)
        return :error if val == :error

        val
      end
    end
  end
end
