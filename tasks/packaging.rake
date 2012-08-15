require 'rdoc/task'
Rake::RDocTask.new do |rdoc|
  version = File.exist?('VERSION') ? File.read('VERSION') : ""

  rdoc.rdoc_dir = 'rdoc'
  rdoc.title = "flapjack #{version}"
  rdoc.rdoc_files.include('README*')
  rdoc.rdoc_files.include('lib/**/*.rb')
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

begin
  require 'jeweler'
  Jeweler::Tasks.new do |gem|
    gem.name = "flapjack"
    gem.summary = %Q{a scalable and distributed monitoring system}
    gem.description = %Q{Flapjack is highly scalable and distributed monitoring system. It understands the Nagios plugin format, and can easily be scaled from 1 server to 1000.}
    gem.email = "lindsay@holmwood.id.au"
    gem.homepage = "http://flapjack-project.com/"
    gem.authors = ["Lindsay Holmwood"]
    gem.has_rdoc = false

    gem.add_dependency('daemons', '= 1.0.10')
    gem.add_dependency('beanstalk-client', '= 1.0.2')
    gem.add_dependency('log4r', '= 1.1.5')
    gem.add_dependency('xmpp4r', '= 0.5')
    gem.add_dependency('tmail', '= 1.2.3.1')
    gem.add_dependency('yajl-ruby', '= 0.6.4')
    gem.add_dependency('sqlite3-ruby', '= 1.2.5')

    # Don't release unsanitised NetSaint config into gem.
    gem.files.exclude('features/support/data/etc/netsaint')
  end
  Jeweler::GemcutterTasks.new
rescue LoadError
  puts "Jeweler (or a dependency) not available. Install it with: gem install jeweler"
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
