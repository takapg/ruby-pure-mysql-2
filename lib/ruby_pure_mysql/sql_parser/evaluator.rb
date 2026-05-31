# frozen_string_literal: true

module RubyPureMysql
  # SQLクエリの式を評価するモジュール
  module Evaluator
    def evaluate_expression(col)
      col = col.strip
      return nil if col.casecmp?('NULL')
      return evaluate_system_variable(col) if col.start_with?('@@')
      return evaluate_string_literal(col) if col.match?(/\A(['"])(.*?)\1\z/)
      return evaluate_math(col) if /\A\s*[-+]?(\d+\.?\d*|\.\d+)(\s*[\+\-\*\/]\s*[-+]?(\d+\.?\d*|\.\d+))*\s*\z/.match?(col)

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
      content.gsub(/\\([nrtt'\"\\])/) do |match|
        case $1
        when 'n' then "\n"
        when 'r' then "\r"
        when 't' then "\t"
        else $1
        end
      end
    end

    def evaluate_math(col)
      has_float = col.include?('.')
      # 数値（符号付き）と演算子に分割
      tokens = col.scan(/[-+]?\d*\.?\d+|[\+\-\*\/]/)
      
      # 数値文字列を Float に変換し、演算子はそのまま保持
      tokens = tokens.map { |t| t.match?(/[\+\-\*\/]/) && t.length == 1 ? t : t.to_f }

      # 1. 乗算と除算を優先的に処理
      i = 1
      while i < tokens.size
        if tokens[i] == '*' || tokens[i] == '/'
          op = tokens[i]
          left = tokens[i - 1]
          right = tokens[i + 1]
          res = op == '*' ? left * right : left / right
          tokens[i - 1] = res
          tokens.slice!(i, 2)
        else
          i += 1
        end
      end

      # 2. 加算と減算を処理
      result = tokens[0]
      i = 1
      while i < tokens.size
        op = tokens[i]
        right = tokens[i + 1]
        result = op == '+' ? result + right : result - right
        i += 2
      end

      result == result.to_i && !has_float ? result.to_i : result
    end

    private
  end
end
