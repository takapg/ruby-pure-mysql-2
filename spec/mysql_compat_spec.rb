# frozen_string_literal: true

require 'spec_helper'
require_relative 'support/shared_mysql_examples'

RSpec.describe 'MySQL Protocol Compatibility' do
  context 'with Real MySQL (Port 3306)' do
    it_behaves_like 'a MySQL-compatible server', 3306
  end

  context 'with Ruby-Pure-MySQL (Port 3307)' do
    it_behaves_like 'a MySQL-compatible server', 3307
  end
end
