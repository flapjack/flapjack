#!/usr/bin/env ruby

require 'sinatra/base'

require 'flapjack/data/contact'
require 'flapjack/data/notification_rule'

module Flapjack

  module Gateways

    class JSONAPI < Sinatra::Base

      module NotificationRuleMethods

        # module Helpers
        # end

        def self.registered(app)
          app.helpers Flapjack::Gateways::JSONAPI::Helpers
          # app.helpers Flapjack::Gateways::JSONAPI::NotificationRuleMethods::Helpers

          # Creates a notification rule or rules for a contact
          app.post '/contacts/:contact_id/notification_rules' do
            notification_rules_data = wrapped_params('notification_rules')

            notification_rules_err = nil
            notification_rule_ids = nil
            notification_rules = nil

            Flapjack::Data::Contact.send(:lock, Flapjack::Data::NotificationRule) do
              contact = Flapjack::Data::Contact.find_by_id(params[:contact_id])

              if contact.nil?
                notification_rules_err = "Contact with id '#{params[:contact_id]}' could not be loaded"
              else
                notification_rules = notification_rules_data.collect do |notification_rule_data|
                  Flapjack::Data::NotificationRule.new(:id => notification_rule_data['id'],
                    :time_restrictions => notification_rule_data['time_restrictions'])
                end

                if invalid = notification_rules.detect {|nr| nr.invalid? }
                  notification_rules_err = "Notification rule validation failed, " + invalid.errors.full_messages.join(', ')
                else
                  notification_rule_ids = notification_rules.collect {|nr|
                    nr.save
                    contact.notification_rules << nr
                    nr.id
                  }
                end

              end
            end

            if notification_rules_err
              halt err(403, notification_rules_err)
            end

            status 201
            response.headers['Location'] = "#{base_url}/notification_rules/#{notification_rule_ids.join(',')}"
            notification_rule_ids.to_json
          end

          app.get %r{^/notification_rules(?:/)?([^/]+)?$} do
            requested_notification_rules = if params[:captures] && params[:captures][0]
              params[:captures][0].split(',').uniq
            else
              nil
            end

            notification_rules = if requested_notification_rules
              Flapjack::Data::NotificationRule.find_by_ids!(requested_notification_rules)
            else
              Flapjack::Data::NotificationRule.all
            end

            notification_rule_ids = notification_rules.map(&:id)
            linked_contact_ids = Flapjack::Data::NotificationRule.associated_ids_for_contact(notification_rule_ids)
            linked_notification_rule_states_ids = Flapjack::Data::NotificationRule.associated_ids_for_states(notification_rule_ids)

            notification_rules_json = notification_rules.collect {|notification_rule|
              notification_rule.as_json(:contact_id => linked_contact_ids[notification_rule.id],
                                        :states_ids => linked_notification_rule_states_ids[notification_rule.id]).to_json
            }.join(",")

            '{"notification_rules":[' + notification_rules_json + ']}'
          end

          # NB notification rules can't add/remove NotitifcationRuleStates, they're
          # created with the default set and possess them for as long as they exist
          app.patch '/notification_rules/:id' do
            Flapjack::Data::NotificationRule.find_by_ids!(params[:id].split(',')).each do |notification_rule|
              apply_json_patch('notification_rules') do |op, property, linked, value|
                case op
                when 'replace'
                  if ['time_restrictions'].include?(property)
                    notification_rule.send("#{property}=".to_sym, value)
                  end
                when 'add'
                  case linked
                  when 'checks'
                    check = Flapjack::Data::Check.find_by_id(value)
                    notification_rule.checks << check unless check.nil?
                  when 'tags'
                    tag = Flapjack::Data::Tag.find_by_id(value)
                    notification_rule.tags << tag unless tag.nil?
                  end
                when 'remove'
                  case linked
                  when 'checks'
                    check = Flapjack::Data::Check.find_by_id(value)
                    notification_rule.delete(check) unless check.nil?
                  when 'tags'
                    tag = Flapjack::Data::Tag.find_by_id(value)
                    notification_rule.delete(tag) unless tag.nil?
                  end
                end
              end
              notification_rule.save # no-op if the record hasn't changed
            end

            status 204
          end

          app.delete '/notification_rules/:id' do
            Flapjack::Data::NotificationRule.find_by_ids!(params[:id].split(',')).map(&:destroy)

            status 204
          end

        end

      end

    end

  end

end
