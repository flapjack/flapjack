When /^I run "([^"]*)" with the following arguments:$/ do |script, table|
  @arguments = []
  table.hashes.each do |attrs|
    @arguments << attrs["argument"]
  end

  command = "bin/#{script} #{@arguments.join(' ')}"

  @output = `#{command}`
  $?.exitstatus.should == 0
end

Then /^I should see a batch of checks in the output$/ do
  @data["batches"].should_not be_nil
  @data["batches"].size.should > 0

  @data["batches"].each do |batch|
    batch["checks"].should_not be_nil
    batch["checks"].size.should > 0

    batch["checks"].each do |check|
      check["id"].should_not be_nil
      check["command"].should_not be_nil
    end
  end
end

Then /^I should see a batch of checks with relationships in the output$/ do
  @data["batches"].should_not be_nil
  @data["batches"].size.should > 0

  @data["batches"].each do |batch|
    batch["checks"].should_not be_nil
    batch["checks"].size.should > 0

    batch["checks"].each do |check|
      check.key?("parent_id").should be_true
      check.key?("child_id").should be_true
    end
  end
end

Given /^no file exists at "([^"]*)"$/ do |filename|
  FileUtils.rm_f(filename).should be_true
end

Then /^I should see valid JSON in "([^"]*)"$/ do |filename|
  lambda {
    file = File.new(filename, 'r')
    parser = Yajl::Parser.new
    @data = parser.parse(file)
  }.should_not raise_error
end

Given /^I run the importer$/ do
  pending # express the regexp above with the code you wish you had
end

Given /^the necessary checks and relationships are created$/ do
  pending # express the regexp above with the code you wish you had
end

Then /^the latest batch of checks should be in the work queue$/ do
  pending # express the regexp above with the code you wish you had
end

Then /^I should see "([^"]*)" in the output$/ do |regex|
  @output.should =~ /#{regex}/i
end

Given /^beanstalkd is running$/ do
  system("which beanstalkd > /dev/null 2>&1").should be_true

  @pipe = IO.popen("beanstalkd")

  # So beanstalkd has a moment to catch its breath.
  sleep 0.5

  at_exit do
    Process.kill("KILL", @pipe.pid)
  end
end

Given /^there are no jobs on the "([^"]*)" beanstalkd queue$/ do |queue_name|
  @queue = Beanstalk::Connection.new('localhost:11300', queue_name)
  100.times { @queue.put('foo') }
  until @queue.stats["current-jobs-ready"] == 0
    job = @queue.reserve
    job.delete
  end
end

Then /^there should be several jobs on the "([^"]*)" beanstalkd queue$/ do |queue_name|
  @queue = Beanstalk::Connection.new('localhost:11300', queue_name)
  @queue.stats["current-jobs-ready"].should > 0
end


Then /^I should see a valid JSON batch in "([^"]*)"$/ do |filename|
  lambda {
    file = File.new(filename, 'r')
    parser = Yajl::Parser.new
    @data = parser.parse(file)
  }.should_not raise_error

  @data["checks"].size.should > 0
  @data["checks"].each do |check|
    %w(id command interval).each do |attr|
      check[attr].should_not be_nil
    end
  end
end
