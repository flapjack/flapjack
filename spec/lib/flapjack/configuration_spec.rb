require 'spec_helper'

require 'flapjack/configuration'

describe Flapjack::Configuration do
  
  let(:configuration) { Flapjack::Configuration.new }  

  before(:each) do
    allow(File).to receive(:file?).and_return(true)
    allow(File).to receive(:read).and_return(toml_data) 
    configuration.load('dummy_path')
  end   
  
  describe "redis configuration data" do 
    it "loads data accessible by symbol" do        
      expect(configuration.for_redis[:host]).to eq('192.168.0.1') 
      expect(configuration.for_redis[:port]).to eq(9999) 
      expect(configuration.for_redis[:db]).to eq(11)  
    end
    
    it "loads data accessible by string" do        
      expect(configuration.for_redis['host']).to eq('192.168.0.1') 
      expect(configuration.for_redis['port']).to eq(9999) 
      expect(configuration.for_redis['db']).to eq(11)  
    end    
  end  
  
  describe "all configuration data" do   
    it "loads data accessible by symbol" do 
      expect(configuration.all[:processor][:enabled]).to eq('yes')  
    end
    
    it "loads data accessible by string" do 
      expect(configuration.all['processor']['enabled']).to eq('yes')  
    end
    
    it "loads array data" do
      expect(configuration.all[:processor][:new_check_scheduled_maintenance_ignore_tags]).to be_an(Array)    
    end
    
    it "loads nested data" do
      expect(configuration.all[:gateways][:sms_twilio][:logger][:syslog_errors]).to eq('yes')  
    end     
  end

  let(:toml_data) {
    <<-TOML_DATA 
pid_dir = "/var/run/flapjack/"
log_dir = "/var/log/flapjack/"
daemonize = "yes"
[logger]
  level = "INFO"
  syslog_errors = "yes"
[redis]
  host = "192.168.0.1"
  port = 9999
  db = 11
[processor]
  enabled = "yes"
  queue = "events"
  notifier_queue = "notifications"
  archive_events = true
  events_archive_maxage = 10800
  new_check_scheduled_maintenance_duration = "100 years"
  new_check_scheduled_maintenance_ignore_tags = ["bypass_ncsm"]
  [processor.logger]
    level = "INFO"
    syslog_errors = "yes"
[notifier]
  enabled = "yes"
  queue = "notifications"
  email_queue = "email_notifications"
  sms_queue = "sms_notifications"
  sms_twilio_queue = "sms_twilio_notifications"
  sns_queue = "sns_notifications"
  jabber_queue = "jabber_notifications"
  pagerduty_queue = "pagerduty_notifications"
  notification_log_file = "/var/log/flapjack/notification.log"
  default_contact_timezone = "UTC"
  [notifier.logger]
    level = "INFO"
    syslog_errors = "yes"
[nagios-receiver]
  fifo = "/var/cache/nagios3/event_stream.fifo"
  pid_dir = "/var/run/flapjack/"
  log_dir = "/var/log/flapjack/"
[nsca-receiver]
  fifo = "/var/lib/nagios3/rw/nagios.cmd"
  pid_dir = "/var/run/flapjack/"
  log_dir = "/var/log/flapjack/"
[gateways]
  # Generates email notifications
  [gateways.email]
    enabled = "no"
    queue = "email_notifications"
    [gateways.email.logger]
      level = "INFO"
      syslog_errors = "yes"
    [gateways.email.smtp_config]
      host = "127.0.0.1"
      port = 1025
      starttls = false
  [gateways.sms]
    enabled = "no"
    queue = "sms_notifications"
    endpoint = "https://www.messagenet.com.au/dotnet/Lodge.asmx/LodgeSMSMessage"
    username = "ermahgerd"
    password = "xxxx"
    [gateways.sms.logger]
      level = "INFO"
      syslog_errors = "yes"
  [gateways.sms_twilio]
    enabled = "no"
    queue = "sms_twilio_notifications"
    account_sid = "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
    auth_token = "yyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyy"
    from = "+1xxxxxxxxxx"
    [gateways.sms_twilio.logger]
      level = "INFO"
      syslog_errors = "yes"
  [gateways.sns]
    enabled = "no"
    queue = "sns_notifications"
    access_key = "AKIAIOSFODNN7EXAMPLE"
    secret_key = "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
  [gateways.jabber]
    enabled = "no"
    queue = "jabber_notifications"
    server = "jabber.example.com"
    port = 5222
    jabberid = "flapjack@jabber.example.com"
    password = "good-password"
    alias = "flapjack"
    identifiers = ["@flapjack"]
    rooms = [
      "gimp@conference.jabber.example.com",
      "log@conference.jabber.example.com"
    ]
    [gateways.jabber.logger]
      level = "INFO"
      syslog_errors = "yes"
  [gateways.pagerduty]
    enabled = "no"
    # the redis queue this pikelet will look for notifications on
    queue = "pagerduty_notifications"
    [gateways.pagerduty.logger]
      level = "INFO"
      syslog_errors = "yes"
  [gateways.web]
    enabled = "yes"
    port = 3080
    timeout = 300
    # Seconds between auto_refresh of entities/checks pages.  Set to 0 to disable
    auto_refresh = 120
    access_log = "/var/log/flapjack/web_access.log"
    api_url = "http://localhost:3081/"
    [gateways.web.logger]
      level = "INFO"
      syslog_errors = "yes"
  [gateways.jsonapi]
    enabled = "yes"
    port = 3081
    timeout = 300
    access_log = "/var/log/flapjack/jsonapi_access.log"
    base_url = "http://localhost:3081/"
    [gateways.jsonapi.logger]
      level = "INFO"
      syslog_errors = "yes"
  [gateways.oobetet]
    enabled = "no"
    server = "jabber.example.com"
    port = 5222
    jabberid = "flapjacktest@jabber.example.com"
    password = "nuther-good-password"
    alias = "flapjacktest"
    watched_check = "PING"
    pagerduty_contact = 11111111111111111111111111111111
    rooms = [
      "flapjacktest@conference.jabber.example.com",
      "gimp@conference.jabber.example.com",
      "log@conference.jabber.example.com"
    ]  
    [gateways.oobetet.logger]
      level = "INFO"
      syslog_errors = "yes"
  TOML_DATA
  }
end  