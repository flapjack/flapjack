require 'spec_helper'

require 'flapjack/configuration'

describe Flapjack::Configuration, :logger => true do

  let(:configuration) { Flapjack::Configuration.new }

  # NOTE For readability, config files are defined at the bottom of this spec

  context "single config file" do

    before(:each) do
      allow(Dir).to receive(:glob).and_return(%w(dummy_file))
      expect(File).to receive(:read).and_return(toml_data)
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
        expect(configuration.all[:processor][:enabled]).to be_a(TrueClass)
      end

      it "loads data accessible by string" do
        expect(configuration.all['processor']['enabled']).to be_a(TrueClass)
      end

      it "loads nested data" do
        expect(
          configuration.all[:gateways][:sms_twilio][:logger][:syslog_errors]
        ).to be_a(TrueClass)
      end
    end

    describe "reload configuration data" do

      it "reloads config data" do
        allow(File).to receive(:read).and_return(reloaded_toml_data)

        expect(configuration.for_redis[:host]).to eq('192.168.0.1')
        expect(configuration.for_redis[:port]).to eq(9999)
        expect(configuration.for_redis[:db]).to eq(11)

        configuration.reload

        expect(configuration.for_redis['host']).to eq('192.168.0.2')
        expect(configuration.for_redis['port']).to eq(8888)
        expect(configuration.for_redis['db']).to eq(12)

        expect(configuration.all['processor']).to be_nil
      end
    end
  end

  context "multiple config files" do

    it "loads config data from files" do
      expect(Dir).to receive(:glob).and_return(%w(1 2 3))
      expect(File).to receive(:read).thrice.and_return(
        base_toml_data,
        redis_toml_data,
        gateways_sms_toml_data
        )

      configuration.load('dummy_pattern')

      expect(configuration.all[:gateways][:sms][:enabled]).to be_a(FalseClass)
      expect(configuration.for_redis[:host]).to eq('192.168.0.1')
    end

    it "fails to load config from clashing files" do
      expect(Dir).to receive(:glob).and_return(%w(1 2 3))
      expect(File).to receive(:read).thrice.and_return(
        base_toml_data,
        redis_toml_data,
        clashing_redis_toml_data
        )

      configuration.load('dummy_pattern')

      expect(configuration.all).to be_nil
    end
  end

  let(:toml_data) {
    <<-TOML_DATA
[logger]
  level = "INFO"
  syslog_errors = true
[redis]
  host = "192.168.0.1"
  port = 9999
  db = 11
[processor]
  enabled = true
  queue = "events"
  notifier_queue = "notifications"
  archive_events = true
  events_archive_maxage = 10800
  new_check_scheduled_maintenance_duration = "100 years"
  new_check_scheduled_maintenance_ignore_regex = "bypass_ncsm$"
  [processor.logger]
    level = "INFO"
    syslog_errors = true
[notifier]
  enabled = true
  queue = "notifications"
  email_queue = "email_notifications"
  sms_queue = "sms_notifications"
  sms_twilio_queue = "sms_twilio_notifications"
  sns_queue = "sns_notifications"
  jabber_queue = "jabber_notifications"
  pagerduty_queue = "pagerduty_notifications"
  default_contact_timezone = "UTC"
  [notifier.logger]
    level = "INFO"
    syslog_errors = true
[nagios-receiver]
  fifo = "/var/cache/nagios3/event_stream.fifo"
[nsca-receiver]
  fifo = "/var/lib/nagios3/rw/nagios.cmd"
[gateways]
  # Generates email notifications
  [gateways.email]
    enabled = false
    queue = "email_notifications"
    [gateways.email.logger]
      level = "INFO"
      syslog_errors = true
    [gateways.email.smtp_config]
      host = "127.0.0.1"
      port = 1025
      starttls = false
  [gateways.sms]
    enabled = false
    queue = "sms_notifications"
    endpoint = "https://www.messagenet.com.au/dotnet/Lodge.asmx/LodgeSMSMessage"
    username = "ermahgerd"
    password = "xxxx"
    [gateways.sms.logger]
      level = "INFO"
      syslog_errors = true
  [gateways.sms_twilio]
    enabled = false
    queue = "sms_twilio_notifications"
    account_sid = "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
    auth_token = "yyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyy"
    from = "+1xxxxxxxxxx"
    [gateways.sms_twilio.logger]
      level = "INFO"
      syslog_errors = true
  [gateways.sns]
    enabled = false
    queue = "sns_notifications"
    access_key = "AKIAIOSFODNN7EXAMPLE"
    secret_key = "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
  [gateways.jabber]
    enabled = false
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
      syslog_errors = true
  [gateways.pagerduty]
    enabled = false
    # the redis queue this pikelet will look for notifications on
    queue = "pagerduty_notifications"
    [gateways.pagerduty.logger]
      level = "INFO"
      syslog_errors = true
  [gateways.web]
    enabled = true
    port = 3080
    timeout = 300
    # Seconds between auto_refresh of entities/checks pages.  Set to 0 to disable
    auto_refresh = 120
    access_log = "/var/log/flapjack/web_access.log"
    [gateways.web.logger]
      level = "INFO"
      syslog_errors = true
  [gateways.jsonapi]
    enabled = true
    port = 3081
    timeout = 300
    access_log = "/var/log/flapjack/jsonapi_access.log"
    base_url = "http://localhost:3081/"
    [gateways.jsonapi.logger]
      level = "INFO"
      syslog_errors = true
  [gateways.oobetet]
    enabled = false
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
      syslog_errors = true
  TOML_DATA
  }

  let(:reloaded_toml_data) {
    <<-NEW_TOML_DATA
daemonize = false
[logger]
  level = "DEBUG"
  syslog_errors = false
[redis]
  host = "192.168.0.2"
  port = 8888
  db = 12
NEW_TOML_DATA
  }

  let(:base_toml_data) {
    <<-BASE_TOML_DATA
daemonize = true
[logger]
  level = "INFO"
  syslog_errors = true
BASE_TOML_DATA
  }

  let(:redis_toml_data) {
    <<-REDIS_TOML_DATA
[redis]
  host = "192.168.0.1"
  port = 9999
  db = 11
REDIS_TOML_DATA
  }

  let(:clashing_redis_toml_data) {
    <<-REDIS_TOML_DATA
[redis]
  host = "192.168.0.2"
  port = 8888
  db = 22
REDIS_TOML_DATA
  }

  let(:gateways_sms_toml_data) {
    <<-GATEWAYS_SMS_TOML_DATA
[gateways.sms]
  enabled = false
  queue = "sms_notifications"
  endpoint = "https://www.messagenet.com.au/dotnet/Lodge.asmx/LodgeSMSMessage"
  username = "ermahgerd"
  password = "xxxx"
  [gateways.sms.logger]
    level = "INFO"
    syslog_errors = true
GATEWAYS_SMS_TOML_DATA
  }
end