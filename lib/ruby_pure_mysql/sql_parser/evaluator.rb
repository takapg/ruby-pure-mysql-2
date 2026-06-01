# frozen_string_literal: true

module RubyPureMysql
  # SQLクエリの式を評価するモジュール
  module Evaluator
    include ExpressionUtils

    def evaluate_expression(col)
      col = col.strip
      return nil if col.casecmp?('NULL')

      # 外側の括弧が式全体を囲んでいる場合は剥離して再帰的に評価する
      while fully_parenthesized?(col)
        col = col[1...-1].strip
      end

      return evaluate_system_variable(col) if col.start_with?('@@')
      return evaluate_function(col) if single_function_call?(col)

      evaluate_math(col)
    end

    def fully_parenthesized?(col)
      return false unless col.start_with?('(') && col.end_with?(')')

      depth = 0
      quote = nil
      col.each_char.with_index do |char, i|
        if quote
          if char == quote && (i == 0 || col[i - 1] != '\\')
            quote = nil
          end
        elsif ["'", '"'].include?(char)
          quote = char
        elsif char == '('
          depth += 1
        elsif char == ')'
          depth -= 1
          return false if depth == 0 && i < col.length - 1
        end
      end
      depth == 0
    end

    def evaluate_system_variable(col)
      {
        '@@version_comment' => 'ruby-pure-mysql-2',
        '@@max_allowed_packet' => 67_108_864
      }.fetch(col.downcase, :error)
    end

    def evaluate_function(col)
      match = col.match(/\A(\w+)\s*\((.*)\)\z/)
      return :error unless match

      args = evaluate_function_args(match[2])
      return :error if args == :error

      call_builtin_function(match[1].downcase, args)
    end

    def call_builtin_function(name, args)
      case name
      when 'now' then Time.now.strftime('%Y-%m-%d %H:%M:%S')
      when 'user' then 'root@localhost'
      when 'version' then 'Hi-MySQL-8.0'
      when 'concat' then args.join
      else :error
      end
    end

    def evaluate_math(col)
      has_float = col.match?(/\d+\.\d+|\d+\.|\.\d+|[eE][+-]?\d+/)
      has_div = col.include?('/')
      result = process_math_tokens(col)
      return result if result == :error || result.nil?

      # MySQL 8.0: 除算結果は常に浮動小数点数となる。
      # 結果が整数で、かつ浮動小数点リテラルが含まれず、除算も行われていない場合のみ Integer を返す。
      if result.is_a?(Numeric) && result == result.to_i && !has_float && !has_div
        result.to_i
      else
        result
      end
    end

    def process_math_tokens(col)
      tokens = tokenize_math(col)
      return :error if tokens == :error

      # 優先順位: 乗除算 -> 加減算 -> 文字列結合
      tokens = apply_multiplication_division(tokens)
      return :error if tokens == :error
      return nil if tokens.nil?

      tokens = apply_addition_subtraction(tokens)
      return :error if tokens == :error

      apply_string_concatenation(tokens)
    end

    private

    def single_function_call?(col)
      return false unless col.match?(/\A\w+\s*\(.*\)\z/)

      depth = 0
      first_paren_idx = col.index('(')
      return false if first_paren_idx.nil?

      col[first_paren_idx..].each_char do |char|
        depth += 1 if char == '('
        depth -= 1 if char == ')'
        return false if depth.negative?
      end
      depth.zero?
    end

    def evaluate_function_args(args_str)
      return [] if args_str.strip.empty?

      split_args(args_str).map do |arg|
        val = evaluate_expression(arg)
        return :error if val == :error

        val
      end
    end
  end
end
