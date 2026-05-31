# frozen_string_literal: true

module RubyPureMysql
  # SQLクエリの式を評価するモジュール
  module Evaluator
    MATH_OPERATORS = ['+', '-', '*', '/'].freeze
    MD_OPERATORS = ['*', '/'].freeze
    ESCAPE_MAP = { 'n' => "\n", 'r' => "\r", 't' => "\t" }.freeze

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
        char = Regexp.last_match(1)
        char == quote || char == '\\' ? char : ESCAPE_MAP.fetch(char, m)
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
      col.scan(%r{([-+]?\d+)|([+\-*/])}).map do |m|
        val = m.compact.first
        MATH_OPERATORS.include?(val) ? val : val.to_i
      end
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
      left = tokens[index - 1]
      right = tokens[index + 1]

      res = case op
            when '*' then left * right
            when '/' then right == 0 ? nil : left.to_f.fdiv(right.to_f)
            end

      tokens[index - 1] = res
      tokens.slice!(index, 2)
    end

    def process_addition_subtraction(tokens)
      res = tokens[0]
      i = 1
      while i < tokens.size
        op = tokens[i]
        right = tokens[i + 1]
        res = (res.nil? || right.nil?) ? nil : (op == '+' ? res + right : res - right)
        i += 2
      end
      res
    end

    def finalize_math_result(res, _col)
      return nil if res.nil?

      res
    end
  end
end
