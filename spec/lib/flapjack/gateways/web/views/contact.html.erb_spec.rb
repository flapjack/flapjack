require 'spec_helper'

describe 'web/views/contact.html.erb', :erb_view => true do

  it "should escape unsafe check characters in URI parameters" do
    @contact = double('contact')

    @contact.should_receive(:name).twice.and_return('Aeschylus')

    no_notification_rules = double('no_notification_rules', :all => [])
    @contact.should_receive(:notification_rules).and_return(no_notification_rules)

    @contact_media = []

    entity_check = double('entity_check')
    entity_check.should_receive(:name).exactly(3).times.and_return('Disk / Utilisation')
    entity_checks_all = double('all_checks', :all => [entity_check])

    entity = double('entity')
    entity.should_receive(:name).exactly(3).times.and_return('abc-xyz-01')
    entity.should_receive(:checks).and_return(entity_checks_all)

    all_entities = double('all_entities', :all => [entity])
    @contact.should_receive(:entities).and_return(all_entities)

    page = render_erb('contact.html.erb', binding)
    page.should match(%r{\?entity=abc-xyz-01&amp;check=Disk%20%2F%20Utilisation})
  end

end
