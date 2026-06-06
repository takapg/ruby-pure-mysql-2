# frozen_string_literal: true

module RubyPureMysql
  # 式解析の共通ユーティリティ
  module ExpressionCommon
    include BuiltinFunctions

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
      (token.match?(%r{[+*/%-]}) && token.length == 1) || token == '||' || %w[= <=> != <> < > <= >=].include?(token)
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

  end
end
