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
        if char =~ /\s/
          i += 1
        elsif char == '('
          start = i
          depth = 1
          i += 1
          while i < col.length && depth > 0
            depth += 1 if col[i] == '('
            depth -= 1 if col[i] == ')'
            i += 1
          end
          tokens << col[start...i]
        elsif char =~ /[a-zA-Z_]/
          start = i
          while i < col.length && col[i] =~ /[a-zA-Z0-9_]/
            i += 1
          end
          token = col[start...i]
          if token.casecmp?('NULL')
            tokens << token
          elsif i < col.length && col[i] == '('
            i += 1
            depth = 1
            while i < col.length && depth > 0
              depth += 1 if col[i] == '('
              depth -= 1 if col[i] == ')'
              i += 1
            end
            tokens << col[start...i]
          else
            return :error
          end
        elsif char =~ /[-+*/]/
          if (char == '-' || char == '+') && (tokens.empty? || operator?(tokens.last))
            start = i
            i += 1
            while i < col.length && col[i] =~ /\s/
              i += 1
            end
            if i < col.length
              if col[i] == '('
                depth = 1
                i += 1
                while i < col.length && depth > 0
                  depth += 1 if col[i] == '('
                  depth -= 1 if col[i] == ')'
                  i += 1
                end
              elsif col[i] =~ /[a-zA-Z_]/
                while i < col.length && col[i] =~ /[a-zA-Z0-9_]/
                  i += 1
                end
                if i < col.length && col[i] == '('
                  i += 1
                  depth = 1
                  while i < col.length && depth > 0
                    depth += 1 if col[i] == '('
                    depth -= 1 if col[i] == ')'
                    i += 1
                  end
                end
              elsif col[i] =~ /[\d.]/
                while i < col.length && col[i] =~ /[\d.]/
                  i += 1
                end
              else
                return :error
              end
            else
              return :error
            end
            tokens << col[start...i]
          else
            tokens << char
            i += 1
          end
        elsif char =~ /[\d.]/
          start = i
          while i < col.length && col[i] =~ /[\d.]/
            i += 1
          end
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
      if token_s.start_with?('-') && token_s.length > 1
        inner = token_s[1..-1].strip
        val = evaluate_inner_token(inner)
        return :error if val == :error
        return val.nil? ? nil : -to_float_value(val)
      elsif token_s.start_with?('+') && token_s.length > 1
        inner = token_s[1..-1].strip
        val = evaluate_inner_token(inner)
        return :error if val == :error
        return val.nil? ? nil : to_float_value(val)
      end

      evaluate_inner_token(token_s)
    end

    def evaluate_inner_token(token)
      return nil if token.casecmp?('NULL')

      if parenthesized?(token) || function_call?(token)
        val = evaluate_expression(parenthesized?(token) ? token[1...-1] : token)
        return :error if val == :error
        return val.nil? ? nil : to_float_value(val)
      end

      return token.to_f if token =~ /\A[-+]?\d*\.?\d+\z/

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
      right = tokens[index + 1]

      if left.nil? || right.nil?
        tokens[index - 1] = nil
        tokens.slice!(index, 2)
        return :ok
      end

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
        val = tokens[i + 1]
        if result.nil? || val.nil?
          result = nil
        else
          result = op == '+' ? result + val : result - val
        end
        i += 2
      end
      result
    end
  end
end
