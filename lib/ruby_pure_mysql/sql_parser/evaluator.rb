# frozen_string_literal: true

module RubyPureMysql
  # SQLクエリの式を評価するモジュール
  module Evaluator
    include ExpressionUtils

    MD_OPERATORS = %w[* /].freeze
    MATH_REGEX = %r{\A\s*[-+]?(\d+\.?\d*|\.\d+|\w+\(.*\))(\s*[+*/-]\s*[-+]?(\d+\.?\d*|\.\d+|\w+\(.*\)))*\s*\z}.freeze

    def evaluate_expression(col)
      col = col.strip
      return nil if col.casecmp?('NULL')
      return evaluate_system_variable(col) if col.start_with?('@@')
      return evaluate_string_literal(col) if col.match?(/\A(['"])(.*?)\1\z/)
      return evaluate_function(col) if col.match?(/\A\w+\(.*\)\z/)
      return evaluate_math(col) if MATH_REGEX.match?(col)

      :error
    end

    def evaluate_system_variable(col)
      {
        '@@version_comment' => 'ruby-pure-mysql-2',
        '@@max_allowed_packet' => 67_108_864
      }.fetch(col.downcase, :error)
    end

    def evaluate_function(col)
      name, _args_str = col.match(/\A(\w+)\((.*)\)\z/).captures
      name = name.downcase

      case name
      when 'now' then Time.now.strftime('%Y-%m-%d %H:%M:%S')
      when 'user' then 'root@localhost'
      when 'version' then 'Hi-MySQL-8.0'
      else :error
      end
    end

    def evaluate_string_literal(col)
      content = col.match(/\A(['"])(.*?)\1\z/)[2]
      content.gsub(/\\([nrt'"\\])/) do
        case Regexp.last_match(1)
        when 'n' then "\n"
        when 'r' then "\r"
        when 't' then "\t"
        else Regexp.last_match(1)
        end
      end
    end

    def evaluate_math(col)
      has_float = col.include?('.')
      tokens = tokenize_math(col)
      tokens = apply_multiplication_division(tokens)
      return nil if tokens.nil?

      result = apply_addition_subtraction(tokens)

      result == result.to_i && !has_float ? result.to_i : result
    end

    private

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
