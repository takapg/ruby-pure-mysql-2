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

      @tables = JSON.parse(File.read(path))
    rescue JSON::ParserError
      @tables = {}
    end

    def save_tables
      File.write(File.join(@db_dir, 'tables.json'), JSON.dump(@tables))
    end

    def load_all_data
      @tables.each_key { |name| @data[name] = load_data(name) }
    end

    def load_data(name)
      path = data_file_path(name)
      return [] unless File.exist?(path)

      JSON.parse(File.read(path))
    rescue JSON::ParserError
      []
    end

    def save_data(name)
      File.write(data_file_path(name), JSON.dump(@data[name]))
    end

    def data_file_path(name)
      File.join(@db_dir, 'data', "#{name}.json")
    end

    def persist_table_creation(name)
      save_tables
      save_data(name)
    end

    def persist_table_deletion(name)
      save_tables
      FileUtils.rm_f(data_file_path(name))
    end
  end
end
