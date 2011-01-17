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
  @root = Pathname.new(File.dirname(__FILE__)).parent.parent.expand_path
  bin_path = @root.join('bin')
  command = "#{bin_path}/flapjack-worker"

  @worker = IO.popen(command, 'r')

  at_exit do
    Process.kill("KILL", @worker.pid)
  end
end

Then /^I should see "([^"]*)" in the "([^"]*)" output$/ do |string, command|
  instance_variable_name = "@" + command.split("-")[1]
  pipe = instance_variable_get(instance_variable_name)
  pipe.should_not be_nil

  @output = []
  line    = ""
  while data = IO.select([pipe], nil, nil, 1) do
    next if data.empty?
    char = pipe.read(1)
    break if char.nil?

    line << char
    if line[-1] == ?\n
      @output << line
      line = ""
    end
  end
  @output.grep(/#{string}/).size.should > 0
end

Then /^I should not see "([^"]*)" in the "([^"]*)" output$/ do |string, command|
  instance_variable_name = "@" + command.split("-")[1]
  pipe = instance_variable_get(instance_variable_name)
  pipe.should_not be_nil

  @output = []
  line    = ""
  while data = IO.select([pipe], nil, nil, 1) do
    next if data.empty?
    char = pipe.read(1)
    break if char.nil?

    line << char
    if line[-1] == ?\n
      @output << line
      line = ""
    end
  end
  @output.grep(/#{string}/).size.should == 0
end
