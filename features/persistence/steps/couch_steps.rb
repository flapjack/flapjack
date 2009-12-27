Given /^I set up the Couch backend with the following options:$/ do |table|
  @backend_options = table.hashes.first.symbolize_keys
  uri = "/#{@backend_options[:database]}/"
  request  = ::Net::HTTP::Put.new(uri)
  response = ::Net::HTTP.start(@backend_options[:host], @backend_options[:port]) {|http| http.request(request)}
  
  @backend = Flapjack::Persistence::Couch.new(@backend_options)

  uri = "/#{@backend_options[:database]}/_all_docs"
  request = ::Net::HTTP::Get.new(uri)
  response = ::Net::HTTP.start(@backend_options[:host], @backend_options[:port]) {|http| http.request(request)}
  
  parser = Yajl::Parser.new
  doc = parser.parse(response.body)
  doc["rows"].each do |row|
    uri = "/#{@backend_options[:database]}/#{row["id"]}?rev=#{row["value"]["rev"]}"
    request = ::Net::HTTP::Delete.new(uri)
    response = ::Net::HTTP.start(@backend_options[:host], @backend_options[:port]) {|http| http.request(request)}
  end
end

Then /^the check with id "([^\"]*)" on the Couch backend should have a status of "([^\"]*)"$/ do |arg1, arg2|
  pending # express the regexp above with the code you wish you had
end

