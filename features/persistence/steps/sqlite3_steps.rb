Given /^I set up the Sqlite3 backend with the following options:$/ do |table|
  @backend_options = table.hashes.first
  @backend = Flapjack::Persistence::Sqlite3.new(@backend_options)
end

Given /^the following checks exist:$/ do |table|
  if @backend.class == Flapjack::Persistence::Couch

    table.hashes.each do |attrs|
      check = Flapjack::Persistence::Couch::Document.new(attrs.symbolize_keys)
      check.save.should be_true
    end

  else

    @db = SQLite3::Database.new(@backend_options[:database]) 
    table.hashes.each do |attrs|
      @keys = [] ; @values = []
      attrs.each_pair do |k,v|
        @keys << k
        @values << v
      end
  
      keys   = "(\"" + @keys.join(%(", ")) + "\")"
      values = "(\"" + @values.join(%(", ")) + "\")"
  
      @db.execute(%(INSERT INTO "checks" #{keys} VALUES #{values}))
    end

  end
end

Then /^the following results should save:$/ do |table|
  table.hashes.each do |attrs|
    result = Flapjack::Transport::Result.new(:result => attrs.symbolize_keys)
    @backend.save(result).should be_true
  end
end

Then /^the check with id "([^\"]*)" on the Sqlite3 backend should have a status of "([^\"]*)"$/ do |id, status|
  @db.execute(%(SELECT status FROM "checks" WHERE id = '#{id}')).first.first.should == status
end

Given /^the following related checks exist:$/ do |table|
  if @backend.class == Flapjack::Persistence::Couch

    table.hashes.each do |attrs|

    end

  else
    table.hashes.each do |attrs|
      @keys = [] ; @values = []
      attrs.each_pair do |k,v|
        @keys << k
        @values << v
      end
  
      keys   = "(\"" + @keys.join(%(", ")) + "\")"
      values = "(\"" + @values.join(%(", ")) + "\")"
  
      @db.execute(%(INSERT INTO "related_checks" #{keys} VALUES #{values}))
    end
  end
end

Then /^the following result should not have a failing parent:$/ do |table|
  table.hashes.each do |attrs|
    result = Flapjack::Transport::Result.new(:result => attrs.symbolize_keys)
    @backend.any_parents_failed?(result).should be_false
  end
end

Then /^the following result should have a failing parent:$/ do |table|
  table.hashes.each do |attrs|
    result = Flapjack::Transport::Result.new(:result => attrs.symbolize_keys)
    @backend.any_parents_failed?(result).should be_true
  end
end

Then /^the following event should save:$/ do |table|
  table.hashes.each do |attrs|
    result = Flapjack::Transport::Result.new(:result => attrs.symbolize_keys)
    @backend.create_event(result).should be_true
  end
end

Then /^the check with id "([^\"]*)" on the Sqlite3 backend should have an event created$/ do |id|
  # test event is actually created
  @db.execute(%(SELECT count(*) FROM "events" WHERE check_id = #{id})).first.first.to_i.should == 1
end

