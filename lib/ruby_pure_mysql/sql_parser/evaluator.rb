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
      # .5 -> 0.5, 1. -> 1.0 に変換し、演算子で分割して計算することで eval を回避します
      has_float = col.include?('.')
      normalized = col.gsub(/(?<!\d)\./, '0.').gsub(/\.(?!\d)/, '.0')
      tokens = normalized.gsub(/([+-])/, ' \1 ').split

      total = 0.0
      current_op = 1
      tokens.each do |token|
        case token
        when '+' then current_op = 1
        when '-' then current_op = -1
        else total += current_op * token.to_f
        end
      end

      (total == total.to_i && !has_float) ? total.to_i : total
    end
  end
end
