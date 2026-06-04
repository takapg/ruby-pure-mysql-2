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
      else
        handle_complex_builtin(name, args)
      end
    end

    def handle_complex_builtin(name, args)
      case name
      when 'coalesce' then handle_coalesce(args)
      when 'ifnull' then handle_ifnull(args)
      when 'substring', 'substr' then handle_substring(args)
      else :error
      end
    end

    def handle_coalesce(args)
      return :error if args.empty?

      args.find { |arg| !arg.nil? }
    end

    def handle_ifnull(args)
      return :error unless args.size == 2

      args[0].nil? ? args[1] : args[0]
    end

    def handle_substring(args)
      return :error unless [2, 3].include?(args.size)
      return nil if args.any?(&:nil?)

      execute_substring(args[0].to_s, args[1].to_i, args[2]&.to_i)
    end

    def execute_substring(str, pos, len)
      return '' if pos.zero? || (len && len <= 0)

      start = pos.positive? ? pos - 1 : pos
      (len ? str[start, len] : str[start..]) || ''
    end
  end
end
