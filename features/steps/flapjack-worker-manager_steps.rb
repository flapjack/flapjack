__DIR__ = File.expand_path(File.join(File.dirname(__FILE__), '..', '..'))

Given /^the (.+) is on my path$/ do |command|
  @bin_path = File.join(__DIR__, 'bin')
  # (and is executable)
  silent_system("test -x #{@bin_path}/#{command}").should be_true
end

Given /^the "([^\"]*)" directory exists and is writable$/ do |directory|
  File.exists?(directory).should be_true
  File.writable?(directory).should be_true
end

When /^I run "([^\"]*)"$/ do |cmd|
  @root = Pathname.new(File.dirname(__FILE__)).parent.parent.expand_path
  bin_path = @root.join('bin')
  command = "#{bin_path}/#{cmd}"

  @output = `#{command}`
  $?.exitstatus.should == 0
end

Then /^(\d+) instances of "([^\"]*)" should be running$/ do |number, command|
  sleep 0.5 # this truly is a dodgy hack.
            # sometimes the the worker manager can take a while to fork
  output = `ps -eo cmd |grep ^#{command} |grep -v grep`
  output.split.size.should >= number.to_i
end

Given /^there are (\d+) instances of the flapjack\-worker running$/ do |number|
  command = "#{@bin_path}/flapjack-worker-manager start --workers=5"
  silent_system(command).should be_true
end

Given /^there are no instances of flapjack\-worker running$/ do
  command = "#{@bin_path}/flapjack-worker-manager stop"
  silent_system(command)

  sleep 0.5 # again, waiting for the worker manager

  output = `ps -eo cmd |grep ^flapjack-worker |grep -v grep`
  output.split("\n").size.should == 0
end

Given /^beanstalkd is running on localhost$/ do
  output = `ps -eo cmd |grep beanstalkd |grep -v grep`
  output.split("\n").size.should == 1
end
