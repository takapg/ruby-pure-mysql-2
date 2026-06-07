# frozen_string_literal: true

module RubyPureMysql
  module BuiltinBasicFunctions
    def handle_basic_builtin(name, args)
      case name
      when 'coalesce' then handle_coalesce(args)
      when 'ifnull' then handle_ifnull(args)
      when 'if' then handle_if(args)
      when 'nullif' then handle_nullif(args)
      when 'isnull' then handle_isnull(args)
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

    def handle_if(args)
      return :error unless args.size == 3

      mysql_truthy?(args[0]) ? args[1] : args[2]
    end

    def mysql_truthy?(val)
      return false if val.nil?
      return val if val.is_a?(TrueClass) || val.is_a?(FalseClass)

      numeric_val = val.is_a?(Numeric) ? val : val.to_s.to_f
      numeric_val != 0
    end

    def handle_nullif(args)
      return :error unless args.size == 2

      args[0] == args[1] ? nil : args[0]
    end

    def handle_isnull(args)
      return :error unless args.size == 1

      args[0].nil? ? 1 : 0
    end
  end
end
