#!/usr/bin/env ruby 

require File.join(File.dirname(__FILE__), '..', '..', 'lib', 'flapjack', 'applications', 'notifier')
require File.join(File.dirname(__FILE__), '..', '..', 'lib', 'flapjack', 'persistence', 'couch')
require File.join(File.dirname(__FILE__), '..', '..', 'lib', 'flapjack', 'transports', 'result')
require File.join(File.dirname(__FILE__), '..', 'helpers')

describe "couchdb persistence backend" do 

  it "should query its parent's statuses" do
    backend_options = { :host => "localhost", 
                        :port => "5984",
                        :database => "flapjack_production",
                        :log => MockLogger.new }

    # setup adapter
    backend = Flapjack::Persistence::Couch.new(backend_options)

    # check is failing
    parent = Flapjack::Persistence::Couch::Document.new(:command => "exit 1", :name => "failing parent")
    parent.save.should be_true

    # check is passing, but has a failing parent
    child = Flapjack::Persistence::Couch::Document.new(:command => "exit 0", :name => "passing child", 
                                                       :parent_checks => [parent.id])
    child.save.should be_true

    # test that failing parent check doesn't fail
    raw_result = {:check_id => parent.id, :retval => 2}
    result = Flapjack::Transport::Result.new(:result => raw_result)

    backend.any_parents_failed?(result).should be_false

    parent.status = 2
    parent.save.should be_true
    
    # test that passing child check does fail
    raw_result = {:check_id => child.id, :retval => 0}
    result = Flapjack::Transport::Result.new(:result => raw_result)
    backend.any_parents_failed?(result).should be_true
  end

end
