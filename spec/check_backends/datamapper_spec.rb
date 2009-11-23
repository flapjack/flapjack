#!/usr/bin/env ruby 

require File.join(File.dirname(__FILE__), '..', '..', 'lib', 'flapjack', 'applications', 'notifier')
require File.join(File.dirname(__FILE__), '..', '..', 'lib', 'flapjack', 'check_backends', 'datamapper')
require File.join(File.dirname(__FILE__), '..', '..', 'lib', 'flapjack', 'queue_backends', 'result')
require File.join(File.dirname(__FILE__), '..', 'helpers')
require 'tmpdir'

describe "datamapper check backend" do 

  it "should query its parent's statuses" do
    backend_options = { :uri => "sqlite3://#{Dir.mktmpdir}/flapjack.db", :log => MockLogger.new }
    DataMapper.setup(:default, backend_options[:uri])
    DataMapper.auto_migrate!

    backend = Flapjack::CheckBackends::Datamapper.new(backend_options)

    bad = Check.new(:command => "exit 1", :name => "bad")
    bad.save.should be_true

    good = Check.new(:command => "exit 0", :name => "good")
    good.save.should be_true

    relation = RelatedCheck.new(:parent_check => bad, :child_check => good)
    relation.save.should be_true

    # the bad check doesn't have failing parents
    result_job = OpenStruct.new(:body => {:id => bad.id, :retval => 2}.to_yaml)
    result = Flapjack::QueueBackends::Result.new(:job => result_job)
    backend.any_parents_failed?(result).should be_false

    bad.status = 2
    bad.save
    
    # the good check has a failing parent (bad)
    result_job = OpenStruct.new(:body => {:id => good.id}.to_yaml)
    result = Flapjack::QueueBackends::Result.new(:job => result_job)
    backend.any_parents_failed?(result).should be_true
  end

  it "should persist a result" do 
    backend_options = { :uri => "sqlite3://#{Dir.mktmpdir}/flapjack.db", :log => MockLogger.new }
    DataMapper.setup(:default, backend_options[:uri])
    DataMapper.auto_migrate!
    
    backend = Flapjack::CheckBackends::Datamapper.new(backend_options)

    check = Check.new(:command => "exit 0", :name => "good")
    check.save.should be_true

    result_job = OpenStruct.new(:body => {:id => check.id, :retval => 2}.to_yaml)
    result = Flapjack::QueueBackends::Result.new(:job => result_job)

    backend.save(result).should be_true
  end

  it "should create an event" do 
    backend_options = { :uri => "sqlite3://#{Dir.mktmpdir}/flapjack.db", :log => MockLogger.new }
    DataMapper.setup(:default, backend_options[:uri])
    DataMapper.auto_migrate!
    
    backend = Flapjack::CheckBackends::Datamapper.new(backend_options)

    check = Check.new(:command => "exit 0", :name => "good")
    check.save.should be_true

    result_job = OpenStruct.new(:body => {:id => check.id, :retval => 2}.to_yaml)
    result = Flapjack::QueueBackends::Result.new(:job => result_job)

    backend.create_event(result).should be_true
  end

end

