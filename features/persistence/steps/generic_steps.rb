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

