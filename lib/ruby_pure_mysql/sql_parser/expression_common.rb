# frozen_string_literal: true

module RubyPureMysql
  # 式解析の共通ユーティリティ
  module ExpressionCommon
    def format_for_concat(val)
      return '' if val.nil?

      if val.is_a?(Numeric)
        val == val.to_i ? val.to_i.to_s : val.to_s
      else
        val.to_s
      end
    end

    def calculate_sum_diff(left, operator, right)
      return nil if left.nil? || right.nil?

      operator == '+' ? left + right : left - right
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

    def string_literal?(token)
      return false unless token.match?(/\A(['"])(.*)\1\z/m)

      quote = token[0]
      content = token[1...-1]
      cleaned = content.gsub(/\\./, '').then { |c| quote == "'" ? c.gsub("''", '') : c }
      !cleaned.include?(quote)
    end

    def count_backslashes(string, pos)
      count = 0
      while pos >= 0 && string[pos] == '\\'
        count += 1
        pos -= 1
      end
      count
    end

    def calculate_next_state(char, quote, depth, escaped)
      return handle_quote_state(char, quote, depth, escaped) if quote

      handle_bracket_state(char, depth)
    end

    def handle_quote_state(char, quote, depth, escaped)
      [quote == char && !escaped ? nil : quote, depth]
    end

    def handle_bracket_state(char, depth)
      if ["'", '"'].include?(char)
        [char, depth]
      elsif char == '('
        [nil, depth + 1]
      elsif char == ')'
        [nil, depth.positive? ? depth - 1 : 0]
      else
        [nil, depth]
      end
    end

    def operator?(token)
      (token.match?(%r{[+*/%-]}) && token.length == 1) || token == '||'
    end

    def evaluate_system_variable(col)
      {
        '@@version_comment' => 'ruby-pure-mysql-2',
        '@@max_allowed_packet' => 67_108_864
      }.fetch(col.downcase, :error)
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

    def scan_string(scanner)
      quote = scanner.getch
      start_pos = scanner.pos - 1
      until scanner.eos?
        break if string_quote?(scanner, quote)

        scanner.getch
      end
      scanner.getch unless scanner.eos?
      scanner.string[start_pos...scanner.pos]
    end

    def string_quote?(scanner, quote)
      return false unless scanner.peek(1) == quote

      if quote == "'" && scanner.peek(2)&.start_with?("''")
        scanner.getch
        scanner.getch
        return false
      end

      return false if count_backslashes(scanner.string, scanner.pos - 1).odd?

      true
    end

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
      escaped = count_backslashes(scanner.string, scanner.pos - 2).odd?
      calculate_next_state(char, quote, depth, escaped)
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
  end
end
