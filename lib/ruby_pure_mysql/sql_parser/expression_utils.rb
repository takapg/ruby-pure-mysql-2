# frozen_string_literal: true

require 'strscan'

module RubyPureMysql
  # 文字列スキャンに関する補助ロジックを提供するモジュール
  module ExpressionStringUtils
    def scan_string(scanner)
      quote = scanner.getch
      start_pos = scanner.pos - 1
      until scanner.eos?
        break if scanner.peek(1) == quote && count_backslashes(scanner).even?

        scanner.getch
      end
      scanner.getch unless scanner.eos?
      scanner.string[start_pos...scanner.pos]
    end

    def count_backslashes(scanner)
      count = 0
      pos = scanner.pos - 1
      while pos >= 0 && scanner.string[pos] == '\\'
        count += 1
        pos -= 1
      end
      count
    end
  end

  # 単項演算子の処理を支援するモジュール
  module ExpressionUnaryHandler
    def scan_unary_operator_body(scanner)
      start_pos = scanner.pos - 1
      return scanner.string[start_pos...scanner.pos] if scan_unary_operand(scanner)

      :error
    end

    def unary_operator?(char, tokens)
      %w[- +].include?(char) && (tokens.empty? || operator?(tokens.last))
    end

    def scan_unary_operand(scanner)
      scanner.skip(/\s+/)
      return false if scanner.eos?

      consume_unary_token(scanner)
    end

    def consume_unary_token(scanner)
      case scanner.peek(1)
      when '(' then consume_unary_parens?(scanner)
      when /[a-zA-Z_]/ then consume_unary_id_func?(scanner)
      when /[\d.]/ then consume_unary_numeric?(scanner)
      when /['"]/ then consume_unary_string?(scanner)
      when /[-+]/ then scan_recursive_unary(scanner)
      else false
      end
    end

    def consume_unary_parens?(scanner)
      scan_balanced_parens(scanner)
      true
    end

    def consume_unary_id_func?(scanner)
      scan_identifier_or_function(scanner)
      true
    end

    def consume_unary_numeric?(scanner)
      scanner.scan(/[\d.]+/)
      true
    end

    def consume_unary_string?(scanner)
      scan_string(scanner)
      true
    end

    def scan_recursive_unary(scanner)
      scanner.getch
      scan_unary_operand(scanner)
    end
  end

  # トークンの消費ロジックを提供するモジュール
  module ExpressionTokenConsumer
    include ExpressionStringUtils
    include ExpressionUnaryHandler

    def scan_balanced_parens(scanner)
      start_pos = scanner.pos
      depth = 0
      quote = nil
      until scanner.eos?
        char = scanner.getch
        quote, depth = update_balanced_state(char, quote, depth, scanner)
        break if depth.zero? && char == ')'
      end
      return :error if depth != 0

      scanner.string[start_pos...scanner.pos]
    end

    def update_balanced_state(char, quote, depth, scanner)
      return [quote == char && count_backslashes(scanner).even? ? nil : quote, depth] if quote

      if ["'", '"'].include?(char)
        [char, depth]
      elsif char == '('
        [nil, depth + 1]
      elsif char == ')'
        [nil, depth - 1]
      else
        [nil, depth]
      end
    end

    def scan_identifier_or_function(scanner)
      token = scanner.scan(/[a-zA-Z0-9_]+/)
      return nil unless token

      return token if token.casecmp?('NULL')

      return scan_function_body(scanner, token) if scanner.peek(1) == '('

      token
    end

    def scan_function_body(scanner, token)
      start_pos = scanner.pos - token.length
      res = scan_balanced_parens(scanner)
      return :error if res == :error

      scanner.string[start_pos...scanner.pos]
    end

    def scan_operator(scanner, tokens)
      char = scanner.getch
      return nil unless char

      return char unless unary_operator?(char, tokens)

      scan_unary_operator_body(scanner)
    end
  end

  # 式のトークナイズ処理を提供するモジュール
  module ExpressionTokenizer
    include ExpressionTokenConsumer

    def tokenize_math(col)
      scanner = StringScanner.new(col)
      tokens = []
      until scanner.eos?
        token = tokenize_char(scanner, tokens)
        return :error if token == :error

        tokens << token if token
      end
      process_tokens(tokens)
    end

    def tokenize_char(scanner, tokens)
      return nil if scanner.scan(/\s+/)

      case scanner.peek(1)
      when '(' then scan_balanced_parens(scanner)
      when /[a-zA-Z_]/ then scan_identifier_or_function(scanner)
      when %r{[-+*/%]} then scan_operator(scanner, tokens)
      when /[\d.]/ then scanner.scan(/[\d.]+/)
      when /['"]/ then scan_string(scanner)
      else :error
      end
    end

    def process_tokens(tokens)
      processed = []
      tokens.each do |t|
        res = process_math_token(t)
        return :error if res == :error

        processed << res
      end
      processed
    end
  end

  # 式の状態管理を支援するモジュール
  module ExpressionStateHelper
    def update_state(state, char)
      update_quote_and_depth(state, char)
      handle_buffer(state, char)
    end

    def update_quote_and_depth(state, char)
      if state[:in_quote]
        state[:in_quote] = nil if char == state[:in_quote] && !quote_escaped?(state)
      elsif ["'", '"'].include?(char)
        state[:in_quote] = char
      else
        state[:depth] = adjust_depth(char, state[:depth])
      end
    end

    def quote_escaped?(state)
      bs_count = 0
      pos = state[:buf].length - 1
      while pos >= 0 && state[:buf][pos] == '\\'
        bs_count += 1
        pos -= 1
      end
      bs_count.odd?
    end

    def handle_buffer(state, char)
      if comma_at_root?(char, state[:depth]) && state[:in_quote].nil?
        state[:args] << state[:buf].strip
        state[:buf] = +''
      else
        state[:buf] << char
      end
    end

    def adjust_depth(char, depth)
      return depth + 1 if char == '('
      return depth - 1 if char == ')' && depth.positive?

      depth
    end

    def comma_at_root?(char, depth)
      char == ',' && depth.zero?
    end
  end

  # 式の評価ロジックを提供するモジュール
  module ExpressionEvaluator
    include ExpressionStateHelper

    def evaluate_string_literal(col)
      match = col.match(/\A(['"])(.*?)\1\z/)
      return nil unless match

      quote = match[1]
      content = match[2]

      content = content.gsub("''", "'") if quote == "'"
      unescape_string_content(content)
    end

    def unescape_string_content(content)
      content.gsub(/\\([nrt'"\\])/) do
        case Regexp.last_match(1)
        when 'n' then "\n"
        when 'r' then "\r"
        when 't' then "\t"
        else Regexp.last_match(1)
        end
      end
    end

    def split_args(args_str)
      state = { args: [], buf: +'', depth: 0, in_quote: nil }
      args_str.each_char { |char| update_state(state, char) }
      return :error if state[:in_quote]

      state[:args] << state[:buf].strip unless state[:buf].strip.empty?
      state[:args]
    end

    def process_math_token(token)
      return token if operator?(token)
      return nil if token.casecmp?('NULL')

      token_s = token.strip
      return handle_unary_token(token_s) if token_s.start_with?('-', '+') && token_s.length > 1

      evaluate_inner_token(token_s)
    end

    def handle_unary_token(token_s)
      op = token_s[0]
      inner = token_s[1..].strip
      val = evaluate_inner_token(inner)
      return :error if val == :error

      return nil if val.nil?

      float_val = to_float_value(val)
      return :error if float_val == :error

      op == '-' ? -float_val : float_val
    end

    def evaluate_inner_token(token)
      return nil if token.casecmp?('NULL')
      return evaluate_complex_token(token) if parenthesized?(token) || function_call?(token)
      return evaluate_string_literal(token) if token.match?(/\A(['"])(.*?)\1\z/)
      return token.to_f if token.match?(/\A[-+]?\d*\.?\d+\z/)

      :error
    end

    def evaluate_complex_token(token)
      return evaluate_parenthesized(token) if parenthesized?(token)
      return evaluate_function_token(token) if function_call?(token)

      :error
    end

    def evaluate_parenthesized(token)
      val = evaluate_expression(token[1...-1])
      return :error if val == :error

      val
    end

    def evaluate_function_token(token)
      val = evaluate_function(token)
      return :error if val == :error

      val
    end

    def operator?(token)
      token.match?(%r{[+*/%-]}) && token.length == 1
    end

    def parenthesized?(token)
      token.start_with?('(') && token.end_with?(')')
    end

    def function_call?(token)
      token.match?(/\A\w+\(.*\)\z/)
    end

    def to_float_value(val)
      return val.to_f if val.is_a?(Numeric)
      return :error if val == :error
      return nil if val.nil?

      val.to_s.to_f
    end
  end

  # 算術演算の計算ロジックを提供するモジュール
  module ExpressionCalculator
    MD_OPERATORS = %w[* / %].freeze

    def apply_multiplication_division(tokens)
      index = 1
      while index < tokens.size
        res = process_md_if_operator(tokens, index)
        return nil if res == :div_by_zero
        return :error if res == :error

        index += 1 if res == :ok
      end
      tokens
    end

    def process_md_if_operator(tokens, index)
      if MD_OPERATORS.include?(tokens[index])
        res = process_md_op!(tokens, index)
        return res == :ok ? :performed : res
      end
      :ok
    end

    def process_md_op!(tokens, index)
      left_raw, operator, right_raw = tokens[(index - 1)..(index + 1)]
      return handle_missing_operand(tokens, index) if left_raw.nil? || right_raw.nil?

      left, right = resolve_md_operands(left_raw, right_raw)
      return :error if left == :error || right == :error
      return :div_by_zero if %w[/ %].include?(operator) && right.zero?

      tokens[index - 1] = calculate_md(left, right, operator)
      tokens.slice!(index, 2)
      :ok
    end

    def resolve_md_operands(left, right)
      [to_float_value(left), to_float_value(right)]
    end

    def calculate_md(left, right, operator)
      return nil if left.nil? || right.nil?

      case operator
      when '*' then left * right
      when '/' then left / right
      when '%' then left % right
      end
    end

    def handle_missing_operand(tokens, index)
      tokens[index - 1] = nil
      tokens.slice!(index, 2)
      :ok
    end

    def apply_addition_subtraction(tokens)
      result = tokens[0]
      idx = 1
      while idx < tokens.size
        op = tokens[idx]
        val = tokens[idx + 1]
        result = calculate_sum_diff(result, op, val)
        return :error if result == :error

        idx += 2
      end
      result
    end

    def calculate_sum_diff(result, operator, value)
      return nil if result.nil? || value.nil?

      left = to_float_value(result)
      right = to_float_value(value)
      return :error if left == :error || right == :error

      operator == '+' ? left + right : left - right
    end
  end

  # 式のトークナイズや引数の分割などの補助ロジックを提供するモジュール
  module ExpressionUtils
    include ExpressionTokenizer
    include ExpressionEvaluator
    include ExpressionCalculator
  end
end
