# frozen_string_literal: true

module RubyPureMysql
  # トークンの消費ロジックを提供するモジュール
  module ExpressionTokenConsumer
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

      return consume_function_call(col, start, idx) if idx < col.length && col[idx] == '('

      :error
    end

    def consume_function_call(col, start, idx)
      idx += 1
      depth = 1
      while idx < col.length && depth.positive?
        depth += 1 if col[idx] == '('
        depth -= 1 if col[idx] == ')'
        idx += 1
      end
      { token: col[start...idx], next_i: idx }
    end

    def consume_operator(col, idx, tokens)
      char = col[idx]
      return { token: char, next_i: idx + 1 } unless unary_operator?(char, tokens)

      start = idx
      idx = consume_unary_operand(col, idx + 1)
      return :error if idx.nil?

      { token: col[start...idx], next_i: idx }
    end

    def unary_operator?(char, tokens)
      %w[- +].include?(char) && (tokens.empty? || operator?(tokens.last))
    end

    def consume_unary_operand(col, idx)
      idx = skip_whitespace(col, idx)
      return nil if idx >= col.length

      case col[idx]
      when '(' then consume_parentheses(col, idx)
      when /[a-zA-Z_]/
        res = consume_identifier_or_function(col, idx)
        res == :error ? :error : res[:next_i]
      when /[\d.]/ then consume_number(col, idx)
      end
    end

    def consume_number(col, idx)
      idx += 1 while idx < col.length && col[idx].match?(/[\d.]/)
      idx
    end

    def skip_whitespace(col, idx)
      idx += 1 while idx < col.length && col[idx].match?(/\s/)
      idx
    end
  end

  # 式のトークナイズ処理を提供するモジュール
  module ExpressionTokenizer
    include ExpressionTokenConsumer

    def tokenize_math(col)
      tokens = []
      idx = 0
      while idx < col.length
        res = tokenize_char(col, idx, tokens)
        return :error if res == :error

        idx, token = res
        tokens << token if token
      end
      process_tokens(tokens)
    end

    def tokenize_char(col, idx, tokens)
      char = col[idx]
      case char
      when /\s/ then [idx + 1, nil]
      when '(' then handle_paren(col, idx)
      when /[a-zA-Z_]/ then handle_ident(col, idx)
      when %r{[-+*/]} then handle_op(col, idx, tokens)
      when /[\d.]/ then handle_num(col, idx)
      when /['"]/ then handle_string(col, idx)
      else :error
      end
    end

    def handle_paren(col, idx)
      start = idx
      end_idx = consume_parentheses(col, idx)
      [end_idx, col[start...end_idx]]
    end

    def handle_ident(col, idx)
      res = consume_identifier_or_function(col, idx)
      return :error if res == :error

      [res[:next_i], res[:token]]
    end

    def handle_op(col, idx, tokens)
      res = consume_operator(col, idx, tokens)
      return :error if res == :error

      [res[:next_i], res[:token]]
    end

    def handle_num(col, idx)
      start = idx
      end_idx = consume_number(col, idx)
      [end_idx, col[start...end_idx]]
    end

    def handle_string(col, idx)
      quote = col[idx]
      start = idx
      idx += 1
      idx += 1 while idx < col.length && (col[idx] != quote || col[idx - 1] == '\\')
      idx += 1 if idx < col.length
      [idx, col[start...idx]]
    end

    def process_tokens(tokens)
      processed = []
      tokens.each do |t|
        res = process_math_token(t)
        return :error if res == :error

        processed << res
      end
      processed
    end
  end

  # 式の評価ロジックを提供するモジュール
  module ExpressionEvaluator
    def split_args(args_str)
      state = { args: [], buf: +'', depth: 0, in_quote: nil }
      args_str.each_char { |char| update_state(state, char) }
      state[:args] << state[:buf].strip unless state[:buf].strip.empty?
      state[:args]
    end

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
      return evaluate_complex_token(token) if parenthesized?(token) || function_call?(token)
      return token.to_f if token.match?(/\A[-+]?\d*\.?\d+\z/)

      :error
    end

    def evaluate_complex_token(token)
      inner = parenthesized?(token) ? token[1...-1] : token
      val = evaluate_expression(inner)
      return :error if val == :error

      val.nil? ? nil : to_float_value(val)
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
      update_quote_and_depth(state, char)
      handle_buffer(state, char)
    end

    def update_quote_and_depth(state, char)
      if state[:in_quote]
        state[:in_quote] = nil if char == state[:in_quote] && state[:buf][-1] != '\\'
      elsif ["'", '"'].include?(char)
        state[:in_quote] = char
      else
        state[:depth] = adjust_depth(char, state[:depth])
      end
    end

    def handle_buffer(state, char)
      if comma_at_root?(char, state[:depth]) && state[:in_quote].nil?
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
  end

  # 算術演算の計算ロジックを提供するモジュール
  module ExpressionCalculator
    MD_OPERATORS = %w[* /].freeze

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
      return handle_missing_operand(tokens, index) if left.nil? || right.nil?
      return :div_by_zero if op == '/' && right.zero?

      tokens[index - 1] = op == '*' ? left * right : left / right
      tokens.slice!(index, 2)
      :ok
    end

    def handle_missing_operand(tokens, index)
      tokens[index - 1] = nil
      tokens.slice!(index, 2)
      :ok
    end

    def apply_addition_subtraction(tokens)
      result = tokens[0]
      idx = 1
      while idx < tokens.size
        op = tokens[idx]
        val = tokens[idx + 1]
        result = calculate_sum_diff(result, op, val)
        idx += 2
      end
      result
    end

    def calculate_sum_diff(result, operator, value)
      return nil if result.nil? || value.nil?

      operator == '+' ? result + value : result - value
    end
  end

  # 式のトークナイズや引数の分割などの補助ロジックを提供するモジュール
  module ExpressionUtils
    include ExpressionTokenizer
    include ExpressionEvaluator
    include ExpressionCalculator
  end
end
