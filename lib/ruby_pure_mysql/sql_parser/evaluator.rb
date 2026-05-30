# frozen_string_literal: true

module RubyPureMysql
  # SQLクエリの式を評価するモジュール
  module Evaluator
    MD_OPERATORS = %w[* /].freeze
    def evaluate_expression(col)
      col = col.strip
      return nil if col.casecmp?('NULL')
      return evaluate_system_variable(col) if col.start_with?('@@')
      return evaluate_string_literal(col) if col.match?(/\A(['"])(.*?)\1\z/)
      return evaluate_math(col) if %r{\A\s*[-+]?\d*\.?\d+(\s*[+*/-]\s*[-+]?\d*\.?\d+)*\s*\z}.match?(col)

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
      tokens = col.split(/([+*/-])/).map(&:strip).reject(&:empty?)
      return :error if tokens.empty?

      # 単項演算子（符号）を数値に統合
      i = 0
      while i < tokens.size
        if (tokens[i] == '-' || tokens[i] == '+') && (i == 0 || %w[+*/-].include?(tokens[i - 1]))
          if tokens[i + 1] && tokens[i + 1] =~ /\A\d*\.?\d+\z/
            tokens[i + 1] = tokens[i] + tokens[i + 1]
            tokens.delete_at(i)
            i -= 1
          end
        end
        i += 1
      end

      tokens = process_multiplication_division(tokens)
      return nil if tokens.nil?

      res = process_addition_subtraction(tokens)
      (res % 1).zero? ? res.to_i : res
    end

    private

    def process_multiplication_division(tokens)
      index = 0
      while index < tokens.size
        if MD_OPERATORS.include?(tokens[index])
          return nil if (result = execute_md_op(tokens, index)).nil?

          update_tokens_md(tokens, index, result)
          index -= 1
        end
        index += 1
      end
      tokens
    end

    def execute_md_op(tokens, index)
      op = tokens[index]
      left = tokens[index - 1].to_f
      right = tokens[index + 1].to_f
      return nil if op == '/' && right.zero?

      op == '*' ? left * right : left / right
    end

    def update_tokens_md(tokens, index, result)
      tokens[index - 1] = result
      tokens.delete_at(index)
      tokens.delete_at(index)
    end

    def process_addition_subtraction(tokens)
      res = tokens[0].to_f
      i = 1
      while i < tokens.size
        op = tokens[i]
        val = tokens[i + 1].to_f
        res = op == '+' ? res + val : res - val
        i += 2
      end
      res
    end
  end
end
