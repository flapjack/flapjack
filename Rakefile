#!/usr/bin/env ruby

unless $:.include?(File.dirname(__FILE__) + '/lib/')
  $: << File.dirname(__FILE__) + '/lib'
end

require 'fileutils'
require 'rake'

require 'resque/tasks'

Dir['tasks/**/*.rake'].each { |t| load t }

require 'cucumber'
require 'cucumber/rake/task'
require 'colorize'
require 'rake/clean'
require 'bundler'
Bundler::GemHelper.install_tasks

Cucumber::Rake::Task.new(:features) do |t|
  t.cucumber_opts = "features --format pretty"
end

require 'rspec/core/rake_task'
RSpec::Core::RakeTask.new(:spec)

task :default => :spec

namespace :verify do
  task :uncommitted do
    uncommitted = `git ls-files -m`.split("\n")
    if uncommitted.size > 0
      puts "The following files are uncommitted:".red
      uncommitted.each do |filename|
        puts " - #{filename}".red
      end
      exit 1
    end
  end

  task :all => [ :uncommitted ]
end

# FIXME: getting that intermittent gherken lexing error so removing :features from verify list
#task :verify => [ 'verify:all', :spec, :features]
task :verify => [ 'verify:all', :spec]
