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

desc "build a tarball suitable for building packages from"
task :tarball do 
  require 'open-uri'
  require 'tmpdir'
  tmpdir = Dir.mktmpdir

  current_commit  = `git log`.first.split[1][0..5]
  release_tarball = "/tmp/flapjack-#{current_commit}.tar.gz"
  flapjack_path   = File.join(tmpdir, "flapjack-#{current_commit}")
  repo_path       = File.expand_path(File.dirname(__FILE__))
  ignores         = %w(.gitignore .git)

  # create new staging directory
  command = "git clone #{repo_path} #{flapjack_path}"
  `#{command}`

  # remove files we don't want to publish
  ignores.each do |filename|
    path = File.join(flapjack_path, filename)
    FileUtils.rm_rf(path)
  end

  deps = { :daemons => {
             :source => "http://rubyforge.org/frs/download.php/34223/daemons-1.0.10.tgz",
             :filename => "daemons-1.0.10.tar.gz"
           },
           :beanstalkd_client => {
             :source => "http://github.com/kr/beanstalk-client-ruby/tarball/v1.0.2",
             :filename => "beanstalkd-client-1.0.2.tar.gz"
           },
           :yajl_ruby => {
             :source => "http://github.com/brianmario/yajl-ruby/tarball/0.6.4",
             :filename => "yajl-ruby-0.6.4.tar.gz"
           },
           :tmail => {
             :source => "http://rubyforge.org/frs/download.php/35297/tmail-1.2.3.1.tgz",
             :filename => "tmail-1.2.3.1.tar.gz"
           },
           :xmpp4r => {
             :source => "http://download.gna.org/xmpp4r/xmpp4r-0.4.tgz",
             :filename => "xmpp4r-0.4.tar.gz"
           },
           :log4r => {
             :source => "http://qa.debian.org/watch/sf.php/log4r/log4r-1.0.5.tgz",
             :filename => "log4r-1.0.5.tar.gz"
           }
  }
  deps.each_pair do |name, details|
    puts "Pulling in #{name} dependency..."
    # save file
    saved_file = "/tmp/#{details[:filename]}"
    File.open(saved_file, 'w') do |f|
      f << open(details[:source]).read 
    end

    `tar zxf #{saved_file} -C #{tmpdir}`
  end

  # build tarball
  under = File.dirname(tmpdir)
  staging = File.join("/tmp", "flapjack-#{current_commit}")
  FileUtils.mv(tmpdir, staging)
  actual = File.basename(staging)
  command = "cd #{under} ; tar czf #{release_tarball} #{actual}"
  system(command)

  puts "Release tarball with deps at #{release_tarball}"
end
