When /^I create the following checks:$/ do |table|
  table.hashes.each do |attrs|
    @backend.save_check(attrs.symbolize_keys).should be_true
  end
end

Then /^looking up the following checks should return documents:$/ do |table|
  table.hashes.each do |attrs|
    @backend.get_check(attrs['id']).should_not be_nil
  end
end

When /^I update the following checks:$/ do |table|
  table.hashes.each do |attrs|
    @backend.save_check(attrs.symbolize_keys).should be_true
  end
end

Then /^the updates should succeed$/ do
  # matches on "should be_true" above
end

When /^I delete the check with id "([^\"]*)"$/ do |id|
  @backend.delete_check(id).should be_true
end

Then /^the check with id "([^\"]*)" should not exist$/ do |id|
  @backend.get_check(id).should be_nil
end

When /^I get all checks$/ do
  @checks = @backend.all_checks
end

Then /^I should have at least (\d+) checks$/ do |n|
  @checks.size.should >= n.to_i
end

Given /^the following checks exist:$/ do |table|
  table.hashes.each do |attrs|
    @backend.save_check(attrs.symbolize_keys)
  end
end

Then /^the following results should save:$/ do |table|
  table.hashes.each do |attrs|
    @backend.save_check(attrs.symbolize_keys).should be_true
  end
end

Given /^the following related checks exist:$/ do |table|
  table.hashes.each do |attrs|
    @backend.save_check_relationship(attrs).should be_true
  end
end

Then /^the following result should not have a failing parent:$/ do |table|
  table.hashes.each do |attrs|
    @backend.any_parents_failed?(attrs['check_id']).should be_false
  end
end

Then /^the following result should have a failing parent:$/ do |table|
  table.hashes.each do |attrs|
    @backend.any_parents_failed?(attrs['check_id']).should be_true
  end
end

Then /^the following event should save:$/ do |table|
  table.hashes.each do |attrs|
    result = Flapjack::Transport::Result.new(:result => attrs.symbolize_keys)
    @backend.create_event(result).should be_true
  end
end


When /^I get all check relationships$/ do
  @relationships = @backend.all_check_relationships
end

Then /^I should have at least (\d+) check relationships$/ do |n|
  @relationships.size.should >= n.to_i
end

Given /^the following events exist:$/ do |table|
  table.hashes.each do |attrs|
    result = Flapjack::Transport::Result.new(:result => attrs.symbolize_keys)
    @backend.create_event(result).should be_true
  end
end

When /^I get all events$/ do
  @events = @backend.all_events
end

Then /^I should have at least (\d+) events$/ do |n|
  @events.size.should >= n.to_i
end

When /^I get all events for check "([^\"]*)"$/ do |id|
  @events = @backend.all_events_for(id) 
end
