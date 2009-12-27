Given /^I set up the Sqlite3 backend with the following options:$/ do |table|
  @backend_options = table.hashes.first
  @backend = Flapjack::Persistence::Sqlite3.new(@backend_options)
end

Then /^the check with id "([^\"]*)" on the Sqlite3 backend should have an event created$/ do |id|
  @backend.all_events_for(id).size.should > 0
end

Then /^the check with id "([^\"]*)" on the Sqlite3 backend should have a status of "([^\"]*)"$/ do |id, status|
  @backend.get_check(id)["status"].should == status
end

