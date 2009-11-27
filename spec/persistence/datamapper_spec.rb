#!/usr/bin/env ruby 

require File.join(File.dirname(__FILE__), '..', '..', 'lib', 'flapjack', 'applications', 'notifier')
require File.join(File.dirname(__FILE__), '..', '..', 'lib', 'flapjack', 'persistence', 'data_mapper')
require File.join(File.dirname(__FILE__), '..', '..', 'lib', 'flapjack', 'transports', 'result')
require File.join(File.dirname(__FILE__), '..', 'helpers')
require 'tmpdir'

describe "datamapper persistence backend" do 

  it "should query its parent's statuses" do
    backend_options = { :uri => "sqlite3://#{Dir.mktmpdir}/flapjack.db", :log => MockLogger.new }
    DataMapper.setup(:default, backend_options[:uri])
    DataMapper.auto_migrate!

    bad = Check.new(:command => "exit 1", :name => "bad")
    bad.save.should be_true

    good = Check.new(:command => "exit 0", :name => "good")
    good.save.should be_true

    relation = RelatedCheck.new(:parent_check => bad, :child_check => good)
    relation.save.should be_true

    # the bad check doesn't have failing parents
    raw_result = {:check_id => bad.id, :retval => 2}
    result = Flapjack::Transport::Result.new(:result => raw_result)

    backend = Flapjack::Persistence::DataMapper.new(backend_options)
    backend.any_parents_failed?(result).should be_false

    bad.status = 2
    bad.save
    
    # the good check has a failing parent (bad)
    raw_result = {:check_id => good.id, :retval => 0}
    result = Flapjack::Transport::Result.new(:result => raw_result)
    backend.any_parents_failed?(result).should be_true
  end

  it "should persist a result" do 
    backend_options = { :uri => "sqlite3://#{Dir.mktmpdir}/flapjack.db", :log => MockLogger.new }
    DataMapper.setup(:default, backend_options[:uri])
    DataMapper.auto_migrate!
    
    backend = Flapjack::Persistence::DataMapper.new(backend_options)

    check = Check.new(:command => "exit 0", :name => "good")
    check.save.should be_true

    raw_result = {:check_id => check.id, :retval => 2}
    result = Flapjack::Transport::Result.new(:result => raw_result)

    backend.save(result).should be_true
  end

  it "should create an event" do 
    backend_options = { :uri => "sqlite3://#{Dir.mktmpdir}/flapjack.db", :log => MockLogger.new }
    DataMapper.setup(:default, backend_options[:uri])
    DataMapper.auto_migrate!
    
    backend = Flapjack::Persistence::DataMapper.new(backend_options)

    check = Check.new(:command => "exit 0", :name => "good")
    check.save.should be_true

    raw_result = {:check_id => check.id, :retval => 2}
    result = Flapjack::Transport::Result.new(:result => raw_result)

    backend.create_event(result).should be_true
  end

end

