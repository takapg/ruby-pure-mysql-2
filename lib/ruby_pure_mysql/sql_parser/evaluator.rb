# frozen_string_literal: true

module RubyPureMysql
  # SQLクエリの式を評価するモジュール
  module Evaluator
    MATH_OPERATORS = ['+', '-', '*', '/'].freeze
    MD_OPERATORS = ['*', '/'].freeze

    def evaluate_expression(col)
      col = col.strip
      return nil if col.casecmp?('NULL')
      return evaluate_system_variable(col) if col.start_with?('@@')
      return evaluate_string_literal(col) if col.match?(/\A(['"])(?:(?!\1).|\\.)*\1\z/m)
      return evaluate_math(col) if %r{\A\s*[-+]?\d+(\s*[+\-*/]\s*[-+]?\d+)*\s*\z}.match?(col)

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
      match = col.match(/\A(['"])(.*)\1\z/m)
      return :error unless match

      quote = match[1]
      content = match[2]

      content.gsub(/\\(.)/) do |m|
        case $1
        when quote, '\\' then $1
        when 'n' then "\n"
        when 'r' then "\r"
        when 't' then "\t"
        else m
        end
      end
    end

    def evaluate_math(col)
      tokens = tokenize_math(col)
      tokens = process_multiplication_division(tokens)
      res = process_addition_subtraction(tokens)

      finalize_math_result(res, col)
    rescue StandardError
      :error
    end

    private

    def tokenize_math(col)
      tokens = col.scan(%r{([-+]?\d+)|([+\-*/])}).map { |m| m.compact.first }
      tokens.map { |t| MATH_OPERATORS.include?(t) ? t : t.to_f }
    end

    def process_multiplication_division(tokens)
      i = 1
      while i < tokens.size
        if MD_OPERATORS.include?(tokens[i])
          apply_md_op(tokens, i)
        else
          i += 1
        end
      end
      tokens
    end

    def apply_md_op(tokens, index)
      op = tokens[index]
      res = op == '*' ? tokens[index - 1] * tokens[index + 1] : tokens[index - 1] / tokens[index + 1]
      tokens[index - 1] = res
      tokens.slice!(index, 2)
    end

    def process_addition_subtraction(tokens)
      res = tokens[0]
      i = 1
      while i < tokens.size
        op = tokens[i]
        res = op == '+' ? res + tokens[i + 1] : res - tokens[i + 1]
        i += 2
      end
      res
    end

    def finalize_math_result(res, col)
      if col.include?('/')
        res.to_f
      else
        res == res.to_i ? res.to_i : res
      end
    end
  end
end
