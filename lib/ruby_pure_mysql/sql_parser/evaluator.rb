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
      return evaluate_function(col) if col.match?(/\A\w+\(.*\)\z/)
      return evaluate_math(col) if %r{\A\s*[-+]?(\d+\.?\d*|\.\d+|\w+\(.*\))(\s*[+*/-]\s*[-+]?(\d+\.?\d*|\.\d+|\w+\(.*\)))*\s*\z}.match?(col)

      :error
    end

    def evaluate_system_variable(col)
      case col.downcase
      when '@@version_comment' then 'ruby-pure-mysql-2'
      when '@@max_allowed_packet' then 67_108_864
      else :error
      end
    end

    def evaluate_function(col)
      match = col.match(/\A(\w+)\((.*)\)\z/)
      name = match[1].downcase
      args_str = match[2]

      args = args_str.empty? ? [] : split_args(args_str).map { |a| evaluate_expression(a) }

      case name
      when 'now' then Time.now.strftime('%Y-%m-%d %H:%M:%S')
      when 'user' then 'root@localhost'
      when 'version' then 'Hi-MySQL-8.0'
      else :error
      end
    end

    def evaluate_string_literal(col)
      content = col.match(/\A(['"])(.*?)\1\z/)[2]
      content.gsub(/\\([nrt'"\\])/) do
        case Regexp.last_match(1)
        when 'n' then "\n"
        when 'r' then "\r"
        when 't' then "\t"
        else Regexp.last_match(1)
        end
      end
    end

    def evaluate_math(col)
      has_float = col.include?('.')
      tokens = tokenize_math(col)
      tokens = apply_multiplication_division(tokens)
      return nil if tokens.nil?

      result = apply_addition_subtraction(tokens)

      result == result.to_i && !has_float ? result.to_i : result
    end

    private

    def tokenize_math(col)
      col.scan(%r{[-+]?\d*\.?\d+|\w+\(.*\)|[+*/-]}).map do |t|
        if t.match?(%r{[+*/-]}) && t.length == 1
          t
        elsif t.match?(/\A\w+\(.*\)\z/)
          val = evaluate_expression(t)
          val.is_a?(Numeric) ? val.to_f : val.to_s.to_f
        else
          t.to_f
        end
      end
    end

    def split_args(args_str)
      args = []
      buf = +''
      depth = 0
      args_str.each_char do |char|
        depth += 1 if char == '('
        depth -= 1 if char == ')' && depth.positive?
        if char == ',' && depth.zero?
          args << buf.strip
          buf = +''
        else
          buf << char
        end
      end
      args << buf.strip unless buf.strip.empty?
      args
    end

    def apply_multiplication_division(tokens)
      index = 1
      while index < tokens.size
        if MD_OPERATORS.include?(tokens[index])
          return nil if process_md_op!(tokens, index) == :div_by_zero
        else
          index += 1
        end
      end
      tokens
    end

    def process_md_op!(tokens, index)
      left = tokens[index - 1]
      right = tokens[index + 1]
      return :div_by_zero if tokens[index] == '/' && right.zero?

      tokens[index - 1] = tokens[index] == '*' ? left * right : left / right
      tokens.slice!(index, 2)
      :ok
    end

    def apply_addition_subtraction(tokens)
      result = tokens[0]
      i = 1
      while i < tokens.size
        op = tokens[i]
        result = op == '+' ? result + tokens[i + 1] : result - tokens[i + 1]
        i += 2
      end
      result
    end
  end
end
