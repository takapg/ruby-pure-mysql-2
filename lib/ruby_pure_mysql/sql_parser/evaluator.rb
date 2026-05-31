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
      tokens = col.gsub(/\s+/, '').scan(/[-+]?\d+|[\+\-\*\/]/)
      return :error if tokens.empty?

      # First pass: Multiplication and Division
      i = 0
      while i < tokens.size
        if tokens[i] == '*' || tokens[i] == '/'
          op = tokens[i]
          left = tokens[i - 1].to_f
          right = tokens[i + 1].to_f
          return nil if op == '/' && right == 0

          res = op == '*' ? left * right : left / right
          tokens[i - 1] = res
          tokens.delete_at(i)
          tokens.delete_at(i)
          i -= 1
        end
        i += 1
      end

      # Second pass: Addition and Subtraction
      res = tokens[0].to_f
      i = 1
      while i < tokens.size
        op = tokens[i]
        val = tokens[i + 1].to_f
        res = op == '+' ? res + val : res - val
        i += 2
      end

      has_division = col.include?('/')
      return res.to_f if has_division

      res == res.to_i ? res.to_i : res
    end
  end
end
