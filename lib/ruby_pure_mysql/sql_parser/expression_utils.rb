# frozen_string_literal: true

require 'strscan'
require_relative 'expression_common'

module RubyPureMysql
  # 単項演算子のスキャン処理を提供するモジュール
  module ExpressionUnaryScanner
    include ExpressionCommon

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

  # 式のトークナイズ処理を提供するモジュール
  module ExpressionTokenizer
    include ExpressionCommon
    include ExpressionUnaryScanner

    def scan_operator(scanner, tokens)
      char = scanner.getch
      return nil unless char

      return char unless unary_operator?(char, tokens)

      scan_unary_operator_body(scanner)
    end

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

      scan_token_by_type(scanner, tokens)
    end

    def scan_token_by_type(scanner, tokens)
      return scan_paren_token(scanner) if scanner.scan('(')
      return scan_id_token(scanner) if scanner.scan(/[a-zA-Z_]/)
      return '||' if scanner.scan('||')
      return scan_op_token(scanner, tokens) if scanner.scan(%r{[-+*/%]})
      return scanner.matched if scanner.scan(/(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?/)
      return scan_str_token(scanner) if scanner.scan(/['"]/)

      :error
    end

    def scan_paren_token(scanner)
      scanner.pos -= 1
      scan_balanced_parens(scanner)
    end

    def scan_id_token(scanner)
      scanner.pos -= 1
      scan_identifier_or_function(scanner)
    end

    def scan_op_token(scanner, tokens)
      scan_operator_with_char(scanner, tokens, scanner.string[scanner.pos - 1])
    end

    def scan_str_token(scanner)
      scanner.pos -= 1
      scan_string(scanner)
    end

    def scan_operator_with_char(scanner, tokens, char)
      return char unless unary_operator?(char, tokens)

      scan_unary_operator_body(scanner)
    end

    # tokenize_char 内で直接 scan(/\|\|/) を行うように変更したため、
    # このメソッドは不要になりますが、互換性のために残すか削除します。
    def handle_pipe_operator(scanner)
      scanner.scan('||') ? '||' : :error
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

  # 算術演算の計算ロジックを提供するモジュール
  module ExpressionCalculator
    include ExpressionCommon

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

    def to_float_value(val)
      return val.to_f if val.is_a?(Numeric)
      return val if %i[error nil].include?(val)

      return :error if string_operator?(val)
      return evaluate_parenthesized_float(val) if parenthesized_string?(val)

      val.to_s.to_f
    end

    def string_operator?(val)
      val.is_a?(String) && operator?(val)
    end

    def parenthesized_string?(val)
      val.is_a?(String) && val.start_with?('(') && val.end_with?(')')
    end

    def evaluate_parenthesized_float(val)
      evaluated = evaluate_expression(val)
      evaluated == :error ? :error : to_float_value(evaluated)
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
      index = 1
      while index < tokens.size
        op = tokens[index]
        res = ['+', '-'].include?(op) ? process_add_sub_op!(tokens, index) : :skipped
        return res if res == :error

        index += 1 if res == :skipped
      end
      tokens
    end

    def process_add_sub_op!(tokens, index)
      left_raw = tokens[index - 1]
      right_raw = tokens[index + 1]
      return :error if left_raw.nil? || right_raw.nil?

      left = to_float_value(left_raw)
      right = to_float_value(right_raw)
      return :error if left == :error || right == :error

      tokens[index - 1] = calculate_sum_diff(left, tokens[index], right)
      tokens.slice!(index, 2)
      :ok
    end

    def apply_string_concatenation(tokens)
      return nil if tokens.empty?

      index = 1
      while index < tokens.size
        if tokens[index] == '||'
          process_concat_op!(tokens, index)
          next
        end
        index += 1
      end
      tokens[0]
    end

    def process_concat_op!(tokens, index)
      left_raw = tokens[index - 1]
      right_raw = tokens[index + 1]
      return if left_raw.nil? || right_raw.nil?

      tokens[index - 1] = "#{format_for_concat(left_raw)}#{format_for_concat(right_raw)}"
      tokens.slice!(index, 2)
    end
  end

  # 式の評価ロジックを提供するモジュール
  module ExpressionEvaluator
    include ExpressionCommon
    include ExpressionCalculator

    def update_state(state, char)
      update_quote_and_depth(state, char)
      handle_buffer(state, char)
    end

    def update_quote_and_depth(state, char)
      escaped = quote_escaped?(state)
      state[:in_quote], state[:depth] = calculate_next_state(char, state[:in_quote], state[:depth], escaped)
    end

    def quote_escaped?(state)
      count_backslashes(state[:buf], state[:buf].length - 1).odd?
    end

    def handle_buffer(state, char)
      if comma_at_root?(char, state[:depth]) && state[:in_quote].nil?
        state[:args] << state[:buf].strip
        state[:buf] = +''
      else
        state[:buf] << char
      end
    end

    def comma_at_root?(char, depth)
      char == ',' && depth.zero?
    end

    def evaluate_string_literal(col)
      # 強欲マッチに変更し、末尾のクォートまで正しくマッチさせる
      match = col.match(/\A(['"])(.*)\1\z/m)
      return nil unless match

      quote = match[1]
      content = match[2]

      content = content.gsub("''", "'") if quote == "'"
      unescape_string_content(content)
    end

    def split_args(args_str)
      return [] if args_str.nil? || args_str.strip.empty?

      state = { args: [], current_arg: +'', depth: 0, quote: nil }
      args_str.each_char.with_index do |char, i|
        update_split_state(char, i, args_str, state)
      end
      state[:args] << state[:current_arg].strip
      state[:args]
    end

    def update_split_state(char, index, args_str, state)
      return handle_split_quote_state(char, index, args_str, state) if state[:quote]
      return handle_split_quote_start(char, state) if ["'", '"'].include?(char)
      return handle_split_bracket_state(char, state) if ['(', ')'].include?(char)
      return handle_split_comma(state) if char == ',' && state[:depth].zero?

      state[:current_arg] << char
    end

    def handle_split_quote_state(char, index, args_str, state)
      state[:quote] = nil if char == state[:quote] && (index.zero? || args_str[index - 1] != '\\')
      state[:current_arg] << char
    end

    def handle_split_quote_start(char, state)
      state[:quote] = char
      state[:current_arg] << char
    end

    def handle_split_bracket_state(char, state)
      char == '(' ? state[:depth] += 1 : state[:depth] -= 1
      state[:current_arg] << char
    end

    def handle_split_comma(state)
      state[:args] << state[:current_arg].strip
      state[:current_arg] = +''
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

      return evaluate_string_literal_token(token) if string_literal?(token)
      return token.to_f if token.match?(/\A[-+]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?\z/)

      :error
    end

    def evaluate_string_literal_token(token)
      evaluate_string_literal(token)
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

    def parenthesized?(token)
      token.start_with?('(') && token.end_with?(')')
    end

    def function_call?(token)
      token.match?(/\A\w+\(.*\)\z/)
    end
  end

  # 式のトークナイズや引数の分割などの補助ロジックを提供するモジュール
  module ExpressionUtils
    include ExpressionCommon
    include ExpressionTokenizer
    include ExpressionEvaluator
  end
end
