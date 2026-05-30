# frozen_string_literal: true

module RubyPureMysql
  # SQLクエリの式を評価するモジュール
  module Evaluator
    def evaluate_expression(col)
      col = col.strip
      return nil if col.casecmp?('NULL')
      return evaluate_system_variable(col) if col.start_with?('@@')
      return evaluate_string_literal(col) if col.match?(/\A(['"])(.*?)\1\z/)
      return evaluate_math(col) if %r{\A-?\d+(?:\.\d+)?(\s*[+*/-]\s*-?\d+(?:\.\d+)?)*\z}.match?(col)

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

      # 数値トークンをあらかじめ Float に変換して精度を保証する
      processed_tokens = tokens.map { |t| t.match?(/\A[+*\/-]\z/) ? t : t.to_f }

      # 1. 乗除算を先に処理
      pass1 = []
      i = 0
      while i < processed_tokens.size
        t = processed_tokens[i]
        if t == '*' || t == '/'
          left = pass1.pop
          right = processed_tokens[i + 1]
          return nil if t == '/' && right == 0.0

          pass1 << (t == '*' ? left * right : left / right)
          i += 2
        else
          pass1 << t
          i += 1
        end
      end

      # 2. 加減算を処理
      res = pass1.shift
      while pass1.any?
        op = pass1.shift
        val = pass1.shift
        res = (op == '+' ? res + val : res - val)
      end

      # 計算結果が整数と等しい場合は整数型で返し、それ以外は Float で返す
      res == res.to_i ? res.to_i : res
    end
  end
end
