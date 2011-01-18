Given /^beanstalkd is not running$/ do
  if @beanstalk
    Process.kill("KILL", @beanstalk.pid)
  end
end

Then /^I should see "([^"]*)" running$/ do |command|
  instance_variable_name = "@" + command.split("-")[1]
  pipe = instance_variable_get(instance_variable_name)
  pipe.should_not be_nil
  `ps -p #{pipe.pid}`.split("\n").size.should == 2
end

When /^I background run "flapjack-worker"$/ do
  @root    = Pathname.new(File.dirname(__FILE__)).parent.parent.expand_path
  bin_path = @root.join('bin')
  command  = "#{bin_path}/flapjack-worker 2>&1"

  @worker = IO.popen(command, 'r')

  sleep 1

  at_exit do
    Process.kill("KILL", @worker.pid)
  end
end

Then /^I should see "([^"]*)" in the "([^"]*)" output$/ do |string, command|
  instance_variable_name = "@" + command.split("-")[1]
  pipe = instance_variable_get(instance_variable_name)
  pipe.should_not be_nil

  @output = read_until_timeout(pipe)
  @output.grep(/#{string}/).size.should > 0
end

Then /^I should not see "([^"]*)" in the "([^"]*)" output$/ do |string, command|
  instance_variable_name = "@" + command.split("-")[1]
  pipe = instance_variable_get(instance_variable_name)
  pipe.should_not be_nil

  @output = read_until_timeout(pipe, 5)
  @output.grep(/#{string}/).size.should == 0
end

When /^beanstalkd is killed$/ do
  Given "beanstalkd is not running"
end

Then /^show me the output from "([^"]*)"$/ do |command|
  instance_variable_name = "@" + command.split("-")[1]
  pipe = instance_variable_get(instance_variable_name)
  pipe.should_not be_nil

  @output = read_until_timeout(pipe, 5)
  puts @output
end

When /^I sleep "(\d+)" seconds$/ do |time|
  sleep(time.to_i)
end
