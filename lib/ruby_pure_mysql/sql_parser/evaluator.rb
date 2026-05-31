# frozen_string_literal: true

module RubyPureMysql
  # SQLクエリの式を評価するモジュール
  module Evaluator
    def evaluate_expression(col)
      col = col.strip
      return nil if col.casecmp?('NULL')
      return evaluate_system_variable(col) if col.start_with?('@@')
      return evaluate_string_literal(col) if col.match?(/\A(['"])(.*?)\1\z/)
      return evaluate_math(col) if /\A\s*[-+]?(\d+\.?\d*|\.\d+)(\s*[+-]\s*[-+]?(\d+\.?\d*|\.\d+))*\s*\z/.match?(col)

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
      has_float = col.include?('.')
      tokens = col.gsub(/([+-])/, ' \1 ').split

      total = calculate_tokens(tokens)
      total == total.to_i && !has_float ? total.to_i : total
    end

    private

    def calculate_tokens(tokens)
      tokens.reduce([0.0, 1]) do |(sum, op), token|
        case token
        when '+' then [sum, op]
        when '-' then [sum, op * -1]
        else [sum + (op * token.to_f), 1]
        end
      end.first
    end
  end
end
