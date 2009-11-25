#!/usr/bin/env ruby 

require File.join(File.dirname(__FILE__), '..', 'lib', 'flapjack', 'inifile')
require File.join(File.dirname(__FILE__), 'helpers')

describe "inifile reader" do 

  it "should turn sections into keys" do 
    example = "[forks]\nhello = world\n[spoons]\nfoo = bar\n[splades]\nbar = baz"
    ini = Flapjack::Inifile.new(example)
    ini.keys.sort.should == %w{forks splades spoons}
  end

  it "should nest parameters under a section" do
    example = "[forks]\nhello = world\n[spoons]\nfoo = bar\n[splades]\nbar = baz"
    ini = Flapjack::Inifile.new(example)
    ini['forks']['hello'].should == "world"
    ini['spoons']['foo'].should == "bar"
    ini['splades']['bar'].should == "baz"
  end

  it "should read a file" do 
    filename = File.join(File.dirname(__FILE__), 'simple.ini')
    ini = Flapjack::Inifile.read(filename)
    ini['forks']['hello'].should == "world"
    ini['spoons']['foo'].should == "bar"
    ini['splades']['bar'].should == "baz"
  end

  it "should ignore commented lines" do 
    example = "[forks]\nhello = world\n[spoons]\nfoo = bar\n# comment goes here\n[splades]\nbar = baz"
    ini = Flapjack::Inifile.new(example)
    ini['spoons'].keys.include?(/#/).should be_false
    ini['spoons'].keys.include?(/comment goes here/).should be_false
    ini['spoons'].values.include?(/#/).should be_false
    ini['spoons'].values.include?(/comment goes here/).should be_false
  end

  it "should ignore blank lines" do 
    example = "\n\n\n\n\n\n\n[spoons]\n\n\n\n[of]\n[doom]"
    ini = Flapjack::Inifile.new(example)
    ini.keys.sort.should == %w(doom of spoons)
  end

  it "should ignore mid-line comments" do 
    example = "[forks] ; a comment \nhello = world ; another comment\n\n"
    ini = Flapjack::Inifile.new(example)
    ini.keys.include?("forks").should be_true
    ini['forks']['hello'].should == 'world'
  end

  it "should append re-opened sections" do 
    example = "[forks]\nhello = world\n[forks]\nfoo = bar\n\n[forks]\nbar = baz"
    ini = Flapjack::Inifile.new(example)
    ini.keys.include?("forks").should be_true
    ini["forks"].keys.sort.should == %w(bar foo hello)
  end


end
