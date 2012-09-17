#!/usr/bin/env ruby

unless $:.include?(File.dirname(__FILE__) + '/lib/')
  $: << File.dirname(__FILE__) + '/lib'
end

require 'fileutils'
require 'rake'

require 'resque/tasks'

Dir['tasks/**/*.rake'].each { |t| load t }

# desc "dump out statements to create sqlite3 schema"
# task :dm_debug do
#   require 'lib/flapjack/persistence/data_mapper'
#
#   DataMapper.logger.set_log(STDOUT, :debug)
#   DataMapper.setup(:default, "sqlite3:///tmp/sqlite3.db")
#   DataMapper.auto_migrate!
# end
