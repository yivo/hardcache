# frozen_string_literal: true
require 'securerandom'
require 'active_support/all'
require 'active_record'
require 'activerecord-traits'

require 'hardcache/extension'
require 'hardcache/version'

ActiveRecord::Base.include(HardCache::Extension)
