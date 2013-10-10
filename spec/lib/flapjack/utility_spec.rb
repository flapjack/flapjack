
require 'spec_helper'
require 'flapjack/utility'

describe Flapjack::Utility do

  context "relative time ago" do

    # ported from sinatra_more tests for the method
    include Flapjack::Utility

    let(:time) { Time.new }

    it 'displays now as a minute ago' do
      'about a minute'.should == relative_time_ago(time, time - 60)
    end
    it "displays a few minutes ago" do
      '4 minutes'.should == relative_time_ago(time, time - (4 * 60))
    end
    it "displays an hour ago" do
      'about 1 hour'.should == relative_time_ago(time, time - (65 * 60))
    end
    it "displays a few hours ago" do
      'about 3 hours'.should == relative_time_ago(time, time - (185 * 60))
    end
    it "displays a day ago" do
      '1 day'.should == relative_time_ago(time, time - (24 * 60 * 60))
    end
    it "displays about 2 days ago" do
      'about 2 days'.should == relative_time_ago(time, time - (2 * 24 * 60 * 60) + (5 * 60))
    end
    it "displays a few days ago" do
      '5 days'.should == relative_time_ago(time, time - (5 * 24 * 60 * 60) - (5 * 60))
    end
    it "displays a month ago" do
      'about 1 month'.should == relative_time_ago(time, time - (32 * 24 * 60 * 60) - (5 * 60))
    end
    it "displays a few months ago" do
      '6 months'.should == relative_time_ago(time, time - (180 * 24 * 60 * 60) - (5 * 60))
    end
    it "displays a year ago" do
      'about 1 year'.should == relative_time_ago(time, time - (365 * 24 * 60 * 60) - (5 * 60))
    end
    it "displays a few years ago" do
      'over 7 years'.should == relative_time_ago(time, time - (2800 * 24 * 60 * 60) + (5 * 60))
    end

  end

end

