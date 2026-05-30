# frozen_string_literal: true

module RubyPureMysql
  # SQLクエリの式を評価するモジュール
  module Evaluator
    MD_OPERATORS = %w[* /].freeze
    def evaluate_expression(col)
      col = col.strip
      return nil if col.casecmp?('NULL')
      return evaluate_system_variable(col) if col.start_with?('@@')
      return evaluate_string_literal(col) if col.match?(/\A(['"])(.*?)\1\z/)
      return evaluate_math(col) if %r{\A\d+(\s*[+*/-]\s*\d+)*\z}.match?(col)

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
      tokens = col.scan(%r{\d+|[+*/-]})
      return :error if tokens.empty?

      tokens = process_multiplication_division(tokens)
      return nil if tokens.nil?

      res = process_addition_subtraction(tokens)
      (res % 1).zero? ? res.to_i : res
    end

    private

    def process_multiplication_division(tokens)
      i = 0
      while i < tokens.size
        if MD_OPERATORS.include?(tokens[i])
          result = execute_md_op(tokens, i)
          return nil if result.nil?

          update_tokens_md(tokens, i, result)
          i -= 1
        end
        i += 1
      end
      tokens
    end

    def execute_md_op(tokens, i)
      op = tokens[i]
      left = tokens[i - 1].to_f
      right = tokens[i + 1].to_f
      return nil if op == '/' && right.zero?

      op == '*' ? left * right : left / right
    end

    def update_tokens_md(tokens, i, result)
      tokens[i - 1] = result
      tokens.delete_at(i)
      tokens.delete_at(i)
    end

    def process_addition_subtraction(tokens)
      res = tokens[0].to_f
      i = 1
      while i < tokens.size
        op = tokens[i]
        val = tokens[i + 1].to_f
        res = op == '+' ? res + val : res - val
        i += 2
      end
      res
    end
  end
end
