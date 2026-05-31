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
      parts = col.scan(/[-+]?\s*(?:\d+\.?\d*|\.\d+)/).map { |p| p.gsub(/\s+/, '') }
      parts.any? { |p| p.include?('.') } ? parts.sum(&:to_f) : parts.sum(&:to_i)
    end
  end
end
