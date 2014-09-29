#!/usr/bin/env ruby

require 'sinatra/base'

require 'flapjack/data/contact'
require 'flapjack/data/check'

module Flapjack

  module Gateways

    class JSONAPI < Sinatra::Base

      module SearchMethods

        module Helpers
        end

        def self.registered(app)
          app.helpers Flapjack::Gateways::JSONAPI::Helpers
          # app.helpers Flapjack::Gateways::JSONAPI::SearchMethods::Helpers

          app.get %r{^/search/(contacts/checks)$} do

            query = params[:q]

            case params[:captures][0]
            when 'contacts'
              # contacts = Flapjack::Data::Contact.

              contacts_ids = contacts.map(&:id)
              linked_medium_ids = Flapjack::Data::Contact.associated_ids_for_media(contacts_ids)
              linked_pagerduty_credentials_ids = Flapjack::Data::Contact.associated_ids_for_pagerduty_credentials(contacts_ids)
              linked_notification_rule_ids = Flapjack::Data::Contact.associated_ids_for_notification_rules(contacts_ids)

              contacts_json = contacts.collect {|contact|
                contact.as_json(:medium_ids => linked_medium_ids[contact.id],
                  :pagerduty_credentials_ids => linked_pagerduty_credentials_ids[contact.id],
                  :notification_rule_ids => linked_notification_rule_ids[contact.id]).to_json
              }.join(", ")

              '{"contacts":[' + contacts_json + ']}'

            when 'checks'
              # checks = Flapjack::Data::Check

              checks_json = checks.collect {|check| check.to_json}.join(",")

              '{"checks":[' + checks_json + ']}'

            end

          end

        end

      end

    end

  end

end
