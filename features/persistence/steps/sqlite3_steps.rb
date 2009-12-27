Given /^I set up the Sqlite3 backend with the following options:$/ do |table|
  @backend_options = table.hashes.first
  @backend = Flapjack::Persistence::Sqlite3.new(@backend_options)
end

