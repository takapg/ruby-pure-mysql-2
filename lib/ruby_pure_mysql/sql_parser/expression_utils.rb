# frozen_string_literal: true

module RubyPureMysql
  # 式のトークナイズや引数の分割などの補助ロジックを提供するモジュール
  module ExpressionUtils
    MD_OPERATORS = %w[* /].freeze
    def tokenize_math(col)
      tokens = []
      i = 0
      while i < col.length
        char = col[i]
        case
        when char.match?(/\s/)
          i += 1
        when char == '('
          start = i
          i = consume_parentheses(col, i)
          tokens << col[start...i]
        when char.match?(/[a-zA-Z_]/)
          res = consume_identifier_or_function(col, i)
          return :error if res == :error

          tokens << res[:token]
          i = res[:next_i]
        when char.match?(%r{[-+*\/]})
          res = consume_operator(col, i, tokens)
          return :error if res == :error

          tokens << res[:token]
          i = res[:next_i]
        when char.match?(/[\d.]/)
          start = i
          i = consume_number(col, i)
          tokens << col[start...i]
        else
          return :error
        end
      end

      processed = []
      tokens.each do |t|
        res = process_math_token(t)
        return :error if res == :error

        processed << res
      end
      processed
    end

    def consume_parentheses(col, i)
      depth = 1
      i += 1
      while i < col.length && depth.positive?
        depth += 1 if col[i] == '('
        depth -= 1 if col[i] == ')'
        i += 1
      end
      i
    end

    def consume_identifier_or_function(col, i)
      start = i
      while i < col.length && col[i].match?(/[a-zA-Z0-9_]/)
        i += 1
      end
      token = col[start...i]
      return { token: token, next_i: i } if token.casecmp?('NULL')

      if i < col.length && col[i] == '('
        i += 1
        depth = 1
        while i < col.length && depth.positive?
          depth += 1 if col[i] == '('
          depth -= 1 if col[i] == ')'
          i += 1
        end
        return { token: col[start...i], next_i: i }
      end

      :error
    end

    def consume_operator(col, i, tokens)
      char = col[i]
      unless %w[- +].include?(char) && (tokens.empty? || operator?(tokens.last))
        return { token: char, next_i: i + 1 }
      end

      start = i
      i += 1
      i = skip_whitespace(col, i)
      return :error if i >= col.length

      if col[i] == '('
        i = consume_parentheses(col, i)
      elsif col[i].match?(/[a-zA-Z_]/)
        res = consume_identifier_or_function(col, i)
        return :error if res == :error

        i = res[:next_i]
      elsif col[i].match?(/[\d.]/)
        i = consume_number(col, i)
      else
        return :error
      end
      { token: col[start...i], next_i: i }
    end

    def consume_number(col, i)
      while i < col.length && col[i].match?(/[\d.]/)
        i += 1
      end
      i
    end

    def skip_whitespace(col, i)
      while i < col.length && col[i].match?(/\s/)
        i += 1
      end
      i
    end

    def split_args(args_str)
      state = { args: [], buf: +'', depth: 0 }
      args_str.each_char { |char| update_state(state, char) }
      state[:args] << state[:buf].strip unless state[:buf].strip.empty?
      state[:args]
    end

    private

    def process_math_token(token)
      return token if operator?(token)
      return nil if token.casecmp?('NULL')

      token_s = token.strip
      if token_s.start_with?('-', '+') && token_s.length > 1
        return handle_unary_token(token_s)
      end

      evaluate_inner_token(token_s)
    end

    def handle_unary_token(token_s)
      op = token_s[0]
      inner = token_s[1..].strip
      val = evaluate_inner_token(inner)
      return :error if val == :error

      return nil if val.nil?

      op == '-' ? -to_float_value(val) : to_float_value(val)
    end

    def evaluate_inner_token(token)
      return nil if token.casecmp?('NULL')

      if parenthesized?(token) || function_call?(token)
        val = evaluate_expression(parenthesized?(token) ? token[1...-1] : token)
        return :error if val == :error

        return nil if val.nil?

        return to_float_value(val)
      end

      return token.to_f if token.match?(/\A[-+]?\d*\.?\d+\z/)

      :error
    end

    def operator?(token)
      token.match?(%r{[+*/-]}) && token.length == 1
    end

    def parenthesized?(token)
      token.start_with?('(') && token.end_with?(')')
    end

    def function_call?(token)
      token.match?(/\A\w+\(.*\)\z/)
    end

    def to_float_value(val)
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
      left, op, right = tokens[index - 1], tokens[index], tokens[index + 1]

      if left.nil? || right.nil?
        tokens[index - 1] = nil
        tokens.slice!(index, 2)
        return :ok
      end

      return :div_by_zero if op == '/' && right.zero?

      tokens[index - 1] = op == '*' ? left * right : left / right
      tokens.slice!(index, 2)
      :ok
    end

    def apply_addition_subtraction(tokens)
      result = tokens[0]
      i = 1
      while i < tokens.size
        op = tokens[i]
        val = tokens[i + 1]
        result = (result.nil? || val.nil?) ? nil : (op == '+' ? result + val : result - val)
        i += 2
      end
      result
    end
  end
end
