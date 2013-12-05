require 'spec_helper'
require 'flapjack/data/notification'

describe Flapjack::Data::Notification, :redis => true, :logger => true do

  let(:event)   { double(Flapjack::Data::Event) }

  let(:check)       { double(Flapjack::Data::Check) }
  let(:check_state) { double(Flapjack::Data::CheckState) }

  let(:contact) { double(Flapjack::Data::Contact) }

  let(:timezone) { double('timezone') }

  it "generates a notification for an event"

  it "generates messages for contacts" do
    notification = Flapjack::Data::Notification.new(
      :state_duration    => 16,
      :severity          => 'critical',
      :type              => 'problem',
      :time              => Time.now,
      :duration          => nil,
      :tags              => Set.new
    )
    notification.save.should be_true
    notification.should_receive(:check).and_return(check)

    check.should_receive(:id).twice.and_return('abcde')

    state = double(Flapjack::Data::CheckState)
    state.should_receive(:state).exactly(4).times.and_return('critical')

    notification.should_receive(:state).exactly(8).times.and_return(state)

    alerting_checks_1 = double('alerting_checks_1')
    alerting_checks_1.should_receive(:exists?).with('abcde').and_return(false)
    alerting_checks_1.should_receive(:<<).with(check)
    alerting_checks_1.should_receive(:count).and_return(1)

    alerting_checks_2 = double('alerting_checks_1')
    alerting_checks_2.should_receive(:exists?).with('abcde').and_return(false)
    alerting_checks_2.should_receive(:<<).with(check)
    alerting_checks_2.should_receive(:count).and_return(1)

    medium_1 = double(Flapjack::Data::Medium)
    medium_1.should_receive(:type).and_return('email')
    medium_1.should_receive(:alerting_checks).exactly(3).times.and_return(alerting_checks_1)
    medium_1.should_receive(:clean_alerting_checks).and_return(0)
    medium_1.should_receive(:rollup_threshold).exactly(3).times.and_return(10)

    medium_2 = double(Flapjack::Data::Medium)
    medium_2.should_receive(:type).and_return('sms')
    medium_2.should_receive(:alerting_checks).exactly(3).times.and_return(alerting_checks_2)
    medium_2.should_receive(:clean_alerting_checks).and_return(0)
    medium_2.should_receive(:rollup_threshold).exactly(3).times.and_return(10)

    alert_1 = double(Flapjack::Data::Alert)
    alert_1.should_receive(:save).and_return(true)
    alert_2 = double(Flapjack::Data::Alert)
    alert_2.should_receive(:save).and_return(true)

    Flapjack::Data::Alert.should_receive(:new).
      with(:rollup => nil, :acknowledgement_duration => nil,
        :state => "critical", :state_duration => 16,
        :notification_type => 'problem').and_return(alert_1)

    Flapjack::Data::Alert.should_receive(:new).
      with(:rollup => nil, :acknowledgement_duration => nil,
        :state => "critical", :state_duration => 16,
        :notification_type => 'problem').and_return(alert_2)

    medium_alerts_1 = double('medium_alerts_1')
    medium_alerts_1.should_receive(:<<).with(alert_1)
    medium_1.should_receive(:alerts).and_return(medium_alerts_1)

    medium_alerts_2 = double('medium_alerts_1')
    medium_alerts_2.should_receive(:<<).with(alert_2)
    medium_2.should_receive(:alerts).and_return(medium_alerts_2)

    check_alerts = double('check_alerts_1')
    check_alerts.should_receive(:<<).with(alert_1)
    check_alerts.should_receive(:<<).with(alert_2)
    check.should_receive(:alerts).twice.and_return(check_alerts)

    contact.should_receive(:id).and_return('23')
    contact.should_receive(:notification_rules).and_return([])
    all_media = double('all_media', :all => [medium_1, medium_2], :empty? => false)
    all_media.should_receive(:each).and_yield(medium_1).
                                    and_yield(medium_2).
                                    and_return([alert_1, alert_2])
    contact.should_receive(:media).and_return(all_media)

    alerts = notification.alerts([contact], :default_timezone => timezone,
      :logger => @logger)
    alerts.should_not be_nil
    alerts.should have(2).items
    alerts.should == [alert_1, alert_2]
  end

end
