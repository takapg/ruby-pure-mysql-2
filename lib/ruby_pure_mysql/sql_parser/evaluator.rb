# frozen_string_literal: true

module RubyPureMysql
  # SQLクエリの式を評価するモジュール
  module Evaluator
    def evaluate_expression(col)
      col = col.strip
      return nil if col.casecmp?('NULL')
      return evaluate_system_variable(col) if col.start_with?('@@')
      return evaluate_string_literal(col) if col.match?(/\A(['"])(.*?)\1\z/)
      if %r{\A\s*[-+]?(\d+\.?\d*|\.\d+)(\s*[+\-*/]\s*[-+]?(\d+\.?\d*|\.\d+))*\s*\z}.match?(col)
        return evaluate_math(col)
      end

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
      result = apply_addition_subtraction(tokens)

      result == result.to_i && !has_float ? result.to_i : result
    end

    private

    def tokenize_math(col)
      col.scan(%r{[-+]?\d*\.?\d+|[+\-*/]}).map do |t|
        t.match?(/[+\-*/]/) && t.length == 1 ? t : t.to_f
      end
    end

    def apply_multiplication_division(tokens)
      i = 1
      while i < tokens.size
        if %w[* /].include?(tokens[i])
          op = tokens[i]
          res = op == '*' ? tokens[i - 1] * tokens[i + 1] : tokens[i - 1] / tokens[i + 1]
          tokens[i - 1] = res
          tokens.slice!(i, 2)
        else
          i += 1
        end
      end
      tokens
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
