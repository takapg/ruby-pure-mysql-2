# frozen_string_literal: true

module RubyPureMysql
  # SQLクエリの式を評価するモジュール
  module Evaluator
    def evaluate_expression(col)
      col = col.strip
      return nil if col.casecmp?('NULL')
      return evaluate_system_variable(col) if col.start_with?('@@')
      return evaluate_string_literal(col) if col.match?(/\A(['"])(.*?)\1\z/)
      return evaluate_math(col) if %r{\A\d+(\s*[+\-*/]\s*\d+)*\z}.match?(col)

      :error
    end

    def evaluate_system_variable(col)
      case col.downcase
      when '@@version_comment' then 'ruby-pure-mysql-2'
      when '@@max_allowed_packet' then 67_108_864
      else :error
      end
    end

    def evaluate_string_literal(col)
      col.match(/\A(['"])(.*?)\1\z/)[2]
    end

    def evaluate_math(col)
      tokens = col.scan(%r{\d+|[+\-*/]})
      return :error if tokens.empty?

      stack = process_multiplication_division(tokens)
      return nil if stack.nil?

      res = process_addition_subtraction(stack)
      (res % 1).zero? ? res.to_i : res
    end

    private

    def process_multiplication_division(tokens)
      stack = []
      i = 0
      while i < tokens.size
        i = process_token(stack, tokens, i)
        return nil if i == :error
      end
      stack
    end

    def process_token(stack, tokens, i)
      t = tokens[i]
      return handle_mul_div(stack, tokens, i) if ['*', '/'].include?(t)

      stack << t
      i + 1
    end

    def handle_mul_div(stack, tokens, i)
      op = tokens[i]
      left = stack.pop.to_f
      right = tokens[i + 1].to_f
      return :error if op == '/' && right.zero?

      stack << (op == '*' ? left * right : left / right)
      i + 2
    end

    def process_addition_subtraction(stack)
      res = stack[0].to_f
      i = 1
      while i < stack.size
        op = stack[i]
        val = stack[i + 1].to_f
        res = op == '+' ? res + val : res - val
        i += 2
      end
      res
    end
  end
end
