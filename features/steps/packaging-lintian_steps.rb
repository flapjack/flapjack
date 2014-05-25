Then /^I should see (\d+) lines of output$/ do |number|
  expect(@output.split.size).to eq(number.to_i)
end

Then /^every file in the output should start with "([^\"]*)"$/ do |string|
  @output.split.each do |file|
    expect(`head -n 1 #{file}`).to match(/^#{string}\s*$/)
  end
end

When /^I run `([^"]*)`$/ do |cmd|
  @cmd = cmd
  @output = `#{cmd} 2>&1`
  @exit_status = $?.exitstatus
  puts "output: #{@output}" if @debug
  puts "exit_status: #{@exit_status}" if @debug
end

Then /^the exit status should( not)? be (\d+)$/ do |negativity, number|
  expect(@exit_status).send(negativity ? :not_to : :to, eq(number.to_i))
end

Then /^the output should( not)? contain "([^"]*)"$/ do |negativity, matcher|
  expect(@output).send(negativity ? :not_to : :to, include(matcher))
end
