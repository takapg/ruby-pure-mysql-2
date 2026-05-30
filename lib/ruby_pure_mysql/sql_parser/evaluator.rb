# frozen_string_literal: true

module RubyPureMysql
  # SQLクエリの式を評価するモジュール
  module Evaluator
    def evaluate_expression(col)
      col = col.strip
      return nil if col.casecmp?('NULL')
      return evaluate_system_variable(col) if col.start_with?('@@')
      return evaluate_string_literal(col) if col.match?(/\A(['"])(.*?)\1\z/)
      return evaluate_math(col) if %r{\A-?\d+(?:\.\d+)?(\s*[+\-*/]\s*-?\d+(?:\.\d+)?)*\z}.match?(col)

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
      tokens = col.scan(%r{-?\d+(?:\.\d+)?|[+\-*/]})
      return :error if tokens.empty?

      # 1. 乗除算を先に処理
      stack = []
      i = 0
      while i < tokens.size
        t = tokens[i]
        if t == '*' || t == '/'
          left = stack.pop.to_f
          right = tokens[i + 1].to_f
          return nil if t == '/' && right.zero?

          stack << (t == '*' ? left * right : left / right)
          i += 1
        else
          stack << t
        end
        i += 1
      end

      # 2. 加減算を処理
      res = stack[0].to_f
      i = 1
      while i < stack.size
        op = stack[i]
        val = stack[i + 1].to_f
        res = (op == '+' ? res + val : res - val)
        i += 2
      end

      (res % 1).zero? ? res.to_i : res
    end
  end
end
