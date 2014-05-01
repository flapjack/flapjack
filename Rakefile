task :default => :build

task :slate do
  require 'pathname'
  root   = Pathname.new(__FILE__).parent
  source = root.join('..', 'slate', 'build').expand_path
  dest   = root.join('docs', 'jsonapi')

  if source.exist?
    puts "Copying slate documentation from #{source} to #{dest}"
    FileUtils.cp_r source, dest
  else
    puts <<-ERROR.gsub(/^ {6}/, '')
      Error: Expected to find slate documentation at #{source}

      Please ensure you have:

       - A checkout of Flapjack's slate documentation at #{source.parent}
         (Grab the repo from https://github.com/flpjck/slate)
       - Built a standalone local copy of the slate documentation with a `rake build`.

    ERROR
    exit 1
  end

end


desc "take site live"
task :deploy do
  system("rsync -auv -e ssh _site/* p:/srv/www/flapjack-project.com/root/")
end

desc "build site"
task :build => [:slate] do
  system('jekyll build')
end

