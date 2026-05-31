# frozen_string_literal: true

module RubyPureMysql
  # SQLクエリの式を評価するモジュール
  module Evaluator
    include ExpressionUtils

    def evaluate_expression(col)
      col = col.strip
      return nil if col.casecmp?('NULL')
      return evaluate_system_variable(col) if col.start_with?('@@')
      return evaluate_string_literal(col) if col.match?(/\A(['"])(.*?)\1\z/)
      return evaluate_function(col) if single_function_call?(col)

      evaluate_math(col)
    end

    def evaluate_system_variable(col)
      {
        '@@version_comment' => 'ruby-pure-mysql-2',
        '@@max_allowed_packet' => 67_108_864
      }.fetch(col.downcase, :error)
    end

    def evaluate_function(col)
      match = col.match(/\A(\w+)\((.*)\)\z/)
      return :error unless match

      args = evaluate_function_args(match[2])
      return :error if args == :error

      case match[1].downcase
      when 'now' then Time.now.strftime('%Y-%m-%d %H:%M:%S')
      when 'user' then 'root@localhost'
      when 'version' then 'Hi-MySQL-8.0'
      when 'concat' then args.map(&:to_s).join
      else :error
      end
    end

    def evaluate_math(col)
      has_float = col.include?('.')
      tokens = tokenize_math(col)
      return :error if tokens == :error

      tokens = apply_multiplication_division(tokens)
      return nil if tokens.nil?

      result = apply_addition_subtraction(tokens)
      return :error if result == :error

      return nil if result.nil?

      result == result.to_i && !has_float ? result.to_i : result
    end

    private

    def single_function_call?(col)
      return false unless col.match?(/\A\w+\(.*\)\z/)

      depth = 0
      col[0...-1].each_char do |char|
        depth += 1 if char == '('
        depth -= 1 if char == ')'
        return false if depth.zero? && char == ')'
      end
      depth == 1
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
