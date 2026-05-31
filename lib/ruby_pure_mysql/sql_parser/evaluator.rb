# frozen_string_literal: true

module RubyPureMysql
  # SQLクエリの式を評価するモジュール
  module Evaluator
    def evaluate_expression(col)
      col = col.strip
      return nil if col.casecmp?('NULL')
      return evaluate_system_variable(col) if col.start_with?('@@')
      return evaluate_string_literal(col) if col.match?(/\A(['"])(.*)\1\z/m)
      return evaluate_math(col) if /\A\s*[-+]?\d+(\s*[\+\-\*\/]\s*[-+]?\d+)*\s*\z/.match?(col)

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
      content.gsub("\\#{quote}", quote)
    end

    def evaluate_math(col)
      # 整数除算を避けるため、数値を Float に変換して評価する
      safe_expr = col.gsub(/\d+/) { |m| "#{m}.to_f" }
      res = eval(safe_expr)

      # 除算が含まれる場合は Float を返し、それ以外は整数値なら Integer に変換する
      if col.include?('/')
        res.to_f
      else
        res == res.to_i ? res.to_i : res
      end
    rescue StandardError
      :error
    end
  end
end
