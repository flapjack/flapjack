#!/usr/bin/env ruby

unless $:.include?(File.dirname(__FILE__) + '/lib/')
  $: << File.dirname(__FILE__) + '/lib'
end

require 'fileutils'
require 'rake'

Dir['tasks/**/*.rake'].each { |t| load t }

require 'cucumber'
require 'cucumber/rake/task'
require 'rake/clean'
require 'bundler'
Bundler::GemHelper.install_tasks

require 'pact/tasks'

Cucumber::Rake::Task.new(:features) do |t|
  #t.cucumber_opts = 'features --format pretty'
  t.cucumber_opts = '--format progress'
end

require 'rspec/core/rake_task'
RSpec::Core::RakeTask.new(:spec)

task :default => :tests

namespace :verify do

  task :uncommitted do

    def red(text)
      "\e[0;31;49m#{text}\e[0m"
    end

    uncommitted = `git ls-files -m`.split("\n")
    if uncommitted.size > 0
      puts red('The following files are uncommitted:')
      uncommitted.each do |filename|
        puts red(" - #{filename}")
      end
      exit 1
    end
  end

  task :all => [ :uncommitted ]
end

task :verify => [ 'verify:all', :spec, :features]
task :tests  => [ :spec, :features]
