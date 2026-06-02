# frozen_string_literal: true

require 'json'
require 'fileutils'

module RubyPureMysql
  # JSONファイルを用いたデータの永続化ロジックを提供するモジュール
  module StoragePersistence
    def setup_persistence
      FileUtils.mkdir_p(File.join(@db_dir, 'data'))
      load_tables
      load_all_data
    end

    def load_tables
      path = File.join(@db_dir, 'tables.json')
      return unless File.exist?(path)

      parse_tables_json(File.read(path))
    rescue JSON::ParserError
      @tables = {}
      @index_definitions = {}
    end

    def parse_tables_json(json_str)
      data = JSON.parse(json_str)
      if data.is_a?(Hash) && data.key?('tables')
        @tables = data['tables']
        @index_definitions = data['indexes'] || {}
      else
        @tables = data
        @index_definitions = {}
      end
    end

    def save_tables
      File.write(File.join(@db_dir, 'tables.json'), JSON.dump({ tables: @tables, indexes: @index_definitions }))
    end

    def load_all_data
      @tables.each_key { |name| @data[name] = load_data(name) }
    end

    def load_data(name)
      path = data_file_path(name)
      return [] unless File.exist?(path)

      parse_data_json(name, File.read(path))
    rescue JSON::ParserError
      []
    end

    def parse_data_json(name, json_str)
      data = JSON.parse(json_str)
      return handle_simple_data(name, data) unless data.is_a?(Hash) && data.key?('rows')

      restore_indexes(name, data['indexes'] || {})
      data['rows'] || []
    end

    def save_data(name)
      File.write(data_file_path(name), JSON.dump({ rows: @data[name], indexes: @index_data[name] }))
    end

    def data_file_path(name)
      File.join(@db_dir, 'data', "#{File.basename(name)}.json")
    end

    def persist_table_creation(name)
      save_tables
      save_data(name)
    end

    def persist_table_deletion(name)
      save_tables
      FileUtils.rm_f(data_file_path(name))
    end

    private

    def convert_to_index_hash(val)
      case val
      when Hash
        val.each_with_object({}) { |(k, v), h| h[safe_json_parse(k)] = convert_to_index_hash(v) }
      when Array
        val.to_h { |row| [row, true] }
      else
        val
      end
    end

    def handle_simple_data(name, data)
      @index_data[name] = {}
      data
    end

    def safe_json_parse(val)
      JSON.parse(val)
    rescue StandardError
      val
    end

    def restore_indexes(name, indexes)
      @index_data[name] = indexes.transform_values do |idx_val|
        idx_val.is_a?(Hash) ? convert_to_index_hash(idx_val) : {}
      end
    end
  end
end
