task :default => :build

desc "take site live"
task :deploy do
  system("rsync -auv -e ssh _site/* p:/srv/www/flapjack-project.com/root/")
end

desc "build site"
task :build do
  system('jekyll')
end

