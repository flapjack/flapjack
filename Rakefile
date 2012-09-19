#!/usr/bin/env ruby

unless $:.include?(File.dirname(__FILE__) + '/lib/')
  $: << File.dirname(__FILE__) + '/lib'
end

require 'fileutils'
require 'rake'

require 'resque/tasks'

Dir['tasks/**/*.rake'].each { |t| load t }

#require 'rubygems'
#require 'bundler/setup'
require 'cucumber'
require 'cucumber/rake/task'
require 'colorize'
#require 'pathname'
#$: << Pathname.new(__FILE__).join('lib').expand_path.to_s
#require 'flapjack/version'

Cucumber::Rake::Task.new(:features) do |t|
  t.cucumber_opts = "features --format pretty"
end

desc "build gem"
task :build => :verify do
  build_output = `gem build flapjack.gemspec`
  puts build_output

  gem_filename = build_output[/File: (.*)/,1]
  pkg_path = "pkg"
  FileUtils.mkdir_p(pkg_path)
  FileUtils.mv(gem_filename, pkg_path)

  puts "Gem built in #{pkg_path}/#{gem_filename}".green
end

desc "push gem"
task :push do
  filenames = Dir.glob("pkg/*.gem")
  filenames_with_times = filenames.map do |filename|
    [filename, File.mtime(filename)]
  end

  newest = filenames_with_times.sort_by { |tuple| tuple.last }.last
  newest_filename = newest.first

  command = "gem push #{newest_filename}"
  system(command)
end

desc "clean up various generated files"
task :clean do
  [ "pkg/"].each do |filename|
    puts "Removing #{filename}"
    FileUtils.rm_rf(filename)
  end
end

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

task :verify => 'verify:all'
