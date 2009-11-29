#!/usr/bin/env ruby 

require 'rubygems'
require 'fileutils'
require 'spec/rake/spectask'

# integration tests for cli utils
begin 
  require 'cucumber/rake/task'

  Cucumber::Rake::Task.new do |task|
    task.cucumber_opts = "--require features/"
  end
rescue LoadError
end

Spec::Rake::SpecTask.new do |t|
  t.spec_opts = ["--options", "spec/spec.opts"]
end


desc "generate list of files for gemspec"
task "gengemfiles" do 
  executables = `git ls-files bin/*`.split.map {|bin| bin.gsub(/^bin\//, '')}             
  files = `git ls-files`.split.delete_if {|file| file =~ /^(spec\/|\.gitignore)/}
  puts
  puts "Copy and paste into flapjack.gemspec:"
  puts
  puts "    s.executables = #{executables.inspect}"
  puts "    s.files = #{files.inspect}"
  puts
  puts
end

desc "build gem"
task :build do 
  system("gem build flapjack.gemspec")
  
  FileUtils.mkdir_p('pkg')
  puts
  puts "Flapjack gems:"
  Dir.glob("flapjack-*.gem").each do |gem|
    dest = File.join('pkg', gem)
    FileUtils.mv gem, dest
    puts "  " + dest
  end
end


desc "display FIXMEs in the codebase"
task :fixmes do 
  output = `grep -nR FIXME lib/* spec/* bin/`
  output.split("\n").each do |line|
    parts = line.split(':')
    puts "#{parts[0].strip} +#{parts[1].strip}"
    puts "  - #{parts[3].strip}"
  end
end

