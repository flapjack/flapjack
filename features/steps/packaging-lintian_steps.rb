Given /^I am at the project root$/ do
  Dir.pwd.split('/').last.should == "flapjack"
end

Then /^I should see (\d+) lines of output$/ do |number|
  @output.split.size.should == number.to_i
end

Then /^every file in the output should start with "([^\"]*)"$/ do |string|
  @output.split.each do |file|
    `head -n 1 #{file}`.should =~ /^#{string}\s*$/
  end
end
