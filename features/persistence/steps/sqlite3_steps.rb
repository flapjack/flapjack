Given /^I set up the Sqlite3 backend with the following options:$/ do |table|
  @backend_options = table.hashes.first
  @backend = Flapjack::Persistence::Sqlite3.new(@backend_options)
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

Then /^the check with id "([^\"]*)" on the Sqlite3 backend should have a status of "([^\"]*)"$/ do |id, status|
  @backend.get_check(id)["status"].should == status
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

Then /^the check with id "([^\"]*)" on the Sqlite3 backend should have an event created$/ do |id|
  @backend.all_events(id).size.should > 0
end

