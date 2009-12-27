#!/usr/bin/env ruby 

require File.join(File.dirname(__FILE__), '..', '..', 'lib', 'flapjack', 'persistence', 'sqlite3')
require File.join(File.dirname(__FILE__), '..', '..', 'lib', 'flapjack', 'transports', 'result')
require File.join(File.dirname(__FILE__), '..', 'helpers')

describe "sqlite3 persistence backend" do 

  it "should query its parent's statuses" do
    backend_options = { :database => "/tmp/flapjack.db", 
                        :auto_migrate => true,
                        :log => MockLogger.new }

    # setup adapter
    backend = Flapjack::Persistence::Sqlite3.new(backend_options)

    # check is failing
    db = SQLite3::Database.new(backend_options[:database]) 
    db.execute(%(INSERT INTO "checks" ("id", "command", "status", "enabled", "name") VALUES (1, 'exit 2', 2, 't', 'failing parent')))

    # create check that is passing, but has a failing parent
    db.execute(%(INSERT INTO "checks" ("id", "command", "status", "enabled", "name") VALUES (2, 'exit 0', 0, 't', 'passing child')))
    db.execute(%(INSERT INTO "related_checks" ("id", "parent_id", "child_id") VALUES (1, 1, 2)))

    # test that failing parent check doesn't fail
    raw_result = {:check_id => 1, :retval => 2}
    result = Flapjack::Transport::Result.new(:result => raw_result)

    backend.any_parents_failed?(result).should be_false

    # test that passing child check does fail
    raw_result = {:check_id => 2, :retval => 0}
    result = Flapjack::Transport::Result.new(:result => raw_result)
    backend.any_parents_failed?(result).should be_true
  end

  it "should persist a result" do 
    backend_options = { :database => "/tmp/flapjack.db", 
                        :auto_migrate => true,
                        :log => MockLogger.new }
    
    # setup adapter
    backend = Flapjack::Persistence::Sqlite3.new(backend_options)

    # save check
    db = SQLite3::Database.new(backend_options[:database]) 
    db.execute(%(INSERT INTO "checks" ("id", "command", "status", "enabled", "name") VALUES (3, 'exit 2', 0, 't', 'failing parent')))
    
    # test persistence
    raw_result = {:check_id => 3, :retval => 2}
    result = Flapjack::Transport::Result.new(:result => raw_result)

    backend.save(result).should be_true
   
    # verify it was updated
    db.execute(%(SELECT status FROM "checks" WHERE id = '3')).first.first.to_i.should == 2
  end

  it "should create an event" do 
    backend_options = { :database => "/tmp/flapjack.db", 
                        :auto_migrate => true,
                        :log => MockLogger.new }

    # setup adapter
    backend = Flapjack::Persistence::Sqlite3.new(backend_options)

    # create a check to attach event to
    db = SQLite3::Database.new(backend_options[:database]) 
    db.execute(%(INSERT INTO "checks" ("id", "command", "status", "enabled", "name") VALUES (4, 'exit 2', 2, 't', 'failing parent')))
    
    # test event is created
    raw_result = {:check_id => 4, :retval => 2}
    result = Flapjack::Transport::Result.new(:result => raw_result)

    backend.create_event(result).should be_true

    # test event is actually created
    db.execute(%(SELECT count(*) FROM "events" WHERE check_id = 4)).first.first.to_i.should == 1
  end

end

