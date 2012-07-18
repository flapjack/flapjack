#!/usr/bin/env ruby

out = ""
(1..20).to_a.each { |clientid|
  (1..100).to_a.each { |id|
    out += "define host {\n"
    out += "  use            linux-server\n"
    out += "  host_name      client#{clientid}-localhost-test-#{id}\n"
    out += "  alias          client#{clientid}-localhost-test-#{id}\n"
    out += "  address        127.0.0.1\n"
    out += "  hostgroups     fakes\n"
    out += "}\n\n"
  }
}

puts out
