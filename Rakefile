#!/usr/bin/env ruby 

require 'rubygems'
require 'fileutils'
require 'spec/rake/spectask'


Spec::Rake::SpecTask.new do |t|
  t.spec_opts = ["--options", "spec/spec.opts"]
end


desc "freeze deps"
task :deps do 

  deps = {'beanstalk-client' => ">= 1.0.2",
          'log4r' => ">= 1.0.5",
          'xmpp4r-simple' => ">= 0.8.8",
          'mailfactory' => ">= 1.4.0"}

  puts "\ninstalling dependencies. this will take a few minutes."

  deps.each_pair do |dep, version|
    puts "\ninstalling #{dep} (#{version})"
    system("gem install #{dep} --version '#{version}' -i gems --no-rdoc --no-ri")
  end

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


if require 'yard'
  
  YARD::Rake::YardocTask.new do |t|
    t.files   = ['lib/**/*.rb']
    t.options = ['--output-dir=doc/', '--readme=README.md']
  end
  
end
