# frozen_string_literal: true

module RubyPureMysql
  # 式のトークナイズや引数の分割などの補助ロジックを提供するモジュール
  module ExpressionUtils
    MD_OPERATORS = %w[* /].freeze
    def tokenize_math(col)
      tokens = []
      col.scan(%r{\((?:[^()]*|\([^()]*\))*\)|[-+]?\d*\.?\d+|\w+\((?:[^()]*|\([^()]*\))*\)|[+*/-]}).each do |t|
        token = process_math_token(t)
        return :error if token == :error

        tokens << token
      end
      tokens
    end

    def split_args(args_str)
      state = { args: [], buf: +'', depth: 0 }
      args_str.each_char { |char| update_state(state, char) }
      state[:args] << state[:buf].strip unless state[:buf].strip.empty?
      state[:args]
    end

    private

    def process_math_token(token)
      return token if token.match?(%r{[+*/-]}) && token.length == 1
      if token.start_with?('(') && token.end_with?(')')
        val = evaluate_expression(token[1...-1])
        return :error if val == :error

        return val.is_a?(Numeric) ? val.to_f : val.to_s.to_f
      end
      return token.to_f unless token.match?(/\A\w+\(.*\)\z/)

      val = evaluate_expression(token)
      return :error if val == :error

      val.is_a?(Numeric) ? val.to_f : val.to_s.to_f
    end

    def update_state(state, char)
      state[:depth] = adjust_depth(char, state[:depth])
      if comma_at_root?(char, state[:depth])
        state[:args] << state[:buf].strip
        state[:buf] = +''
      else
        state[:buf] << char
      end
    end

    def adjust_depth(char, depth)
      return depth + 1 if char == '('
      return depth - 1 if char == ')' && depth.positive?

      depth
    end

    def comma_at_root?(char, depth)
      char == ',' && depth.zero?
    end

    def apply_multiplication_division(tokens)
      index = 1
      while index < tokens.size
        if MD_OPERATORS.include?(tokens[index])
          return nil if process_md_op!(tokens, index) == :div_by_zero
        else
          index += 1
        end
      end
      tokens
    end

    def process_md_op!(tokens, index)
      left = tokens[index - 1]
      right = tokens[index + 1]
      return :div_by_zero if tokens[index] == '/' && right.zero?

      tokens[index - 1] = tokens[index] == '*' ? left * right : left / right
      tokens.slice!(index, 2)
      :ok
    end

    def apply_addition_subtraction(tokens)
      result = tokens[0]
      i = 1
      while i < tokens.size
        op = tokens[i]
        result = op == '+' ? result + tokens[i + 1] : result - tokens[i + 1]
        i += 2
      end
      result
    end
  end
end
