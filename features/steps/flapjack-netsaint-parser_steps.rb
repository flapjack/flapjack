Given /^NetSaint configuration is at "([^"]*)"$/ do |path|
  require 'pathname'
  root  = Pathname.new(path)
  files = []
  files << root.join('commands.cfg')
  files << root.join('netsaint.cfg')
  files << root.join('resource.cfg')

  expect(File.directory?(root)).to be true
  files.each do |filename|
    expect(File.exists?(filename)).to be true
  end
end

Then /^I should see a valid JSON output$/ do
  expect {
    @data = Flapjack.load_json(@output)
  }.not_to raise_error
end

Then /^show me the output$/ do
  puts @output
end

Then /^I should see a list of (\w+)$/ do |type|
  expect(@data[type]).not_to be_nil
  expect(@data[type].size).to be > 0
end

Then /^I should see the following attributes for every (\w+):$/ do |type, table|
  type += 's'
  values = table.hashes.find_all {|h| !h.key?("nillable?") }.map {|h| h["attribute"] }
  @data[type].each_pair do |name, items|
    items.each do |item|
      values.each do |attr|
        expect(item[attr]).not_to be_nil
      end
    end
  end

  nils = table.hashes.find_all {|h| h.key?("nillable?") }.map {|h| h["attribute"] }
  @data[type].each_pair do |name, items|
    items.each do |item|
      nils.each do |attr|
        expect(item.member?(attr)).to be true
      end
    end
  end
end

