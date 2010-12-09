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
