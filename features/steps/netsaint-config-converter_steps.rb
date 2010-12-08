Given /^NetSaint configuration is at "([^"]*)"$/ do |path|
  require 'pathname'
  root  = Pathname.new(path)
  files = []
  files << root.join('commands.cfg')
  files << root.join('netsaint.cfg')
  files << root.join('resource.cfg')

  File.directory?(root).should be_true
  files.each do |filename|
    File.exists?(filename).should be_true
  end
end

Then /^I should see a valid JSON output$/ do
  lambda {
    parser = Yajl::Parser.new
    @data = parser.parse(@output)
  }.should_not raise_error
end

Then /^show me the output$/ do
  puts @output
end

Then /^I should see a list of (\w+)$/ do |type|
  @data[type].should_not be_nil
  @data[type].size.should > 0
end

Then /^I should see the following attributes for every (\w+):$/ do |type, table|
  type += 's'
  values = table.hashes.find_all {|h| !h.key?("nillable?") }.map {|h| h["attribute"] }
  @data[type].each_pair do |name, items|
    items.each do |item|
      values.each do |attr|
        item[attr].should_not be_nil
      end
    end
  end

  nils = table.hashes.find_all {|h| h.key?("nillable?") }.map {|h| h["attribute"] }
  @data[type].each_pair do |name, items|
    items.each do |item|
      nils.each do |attr|
        item.member?(attr).should be_true
      end
    end
  end
end

