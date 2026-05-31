# frozen_string_literal: true

module RubyPureMysql
  # 式のトークナイズや引数の分割などの補助ロジックを提供するモジュール
  module ExpressionUtils
    MD_OPERATORS = %w[* /].freeze
    def tokenize_math(col)
      tokens = []
      idx = 0
      while idx < col.length
        char = col[idx]
        case
        when char.match?(/\s/)
          idx += 1
        when char == '('
          start = idx
          idx = consume_parentheses(col, idx)
          tokens << col[start...idx]
        when char.match?(/[a-zA-Z_]/)
          res = consume_identifier_or_function(col, idx)
          return :error if res == :error

          tokens << res[:token]
          idx = res[:next_i]
        when char.match?(%r{[-+*/]})
          res = consume_operator(col, idx, tokens)
          return :error if res == :error

          tokens << res[:token]
          idx = res[:next_i]
        when char.match?(/[\d.]/)
          start = idx
          idx = consume_number(col, idx)
          tokens << col[start...idx]
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

    def consume_parentheses(col, idx)
      depth = 1
      idx += 1
      while idx < col.length && depth.positive?
        depth += 1 if col[idx] == '('
        depth -= 1 if col[idx] == ')'
        idx += 1
      end
      idx
    end

    def consume_identifier_or_function(col, idx)
      start = idx
      idx += 1 while idx < col.length && col[idx].match?(/[a-zA-Z0-9_]/)
      token = col[start...idx]
      return { token: token, next_i: idx } if token.casecmp?('NULL')

      if idx < col.length && col[idx] == '('
        idx += 1
        depth = 1
        while idx < col.length && depth.positive?
          depth += 1 if col[idx] == '('
          depth -= 1 if col[idx] == ')'
          idx += 1
        end
        return { token: col[start...idx], next_i: idx }
      end

      :error
    end

    def consume_operator(col, idx, tokens)
      char = col[idx]
      return { token: char, next_i: idx + 1 } unless %w[- +].include?(char) && (tokens.empty? || operator?(tokens.last))

      start = idx
      idx += 1
      idx = skip_whitespace(col, idx)
      return :error if idx >= col.length

      case col[idx]
      when '('
        idx = consume_parentheses(col, idx)
      when /[a-zA-Z_]/
        res = consume_identifier_or_function(col, idx)
        return :error if res == :error

        idx = res[:next_i]
      when /[\d.]/
        idx = consume_number(col, idx)
      else
        return :error
      end
      { token: col[start...idx], next_i: idx }
    end

    def consume_number(col, idx)
      idx += 1 while idx < col.length && col[idx].match?(/[\d.]/)
      idx
    end

    def skip_whitespace(col, idx)
      idx += 1 while idx < col.length && col[idx].match?(/\s/)
      idx
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
      return handle_unary_token(token_s) if token_s.start_with?('-', '+') && token_s.length > 1

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
      left = tokens[index - 1]
      op = tokens[index]
      right = tokens[index + 1]

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
      idx = 1
      while idx < tokens.size
        op = tokens[idx]
        val = tokens[idx + 1]
        if result.nil? || val.nil?
          result = nil
        else
          result = op == '+' ? result + val : result - val
        end
        idx += 2
      end
      result
    end
  end
end
