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

            Flapjack::Data::Contact.lock(Flapjack::Data::NotificationRule,
              Flapjack::Data::Medium, Flapjack::Data::NotificationRuleState,
              Flapjack::Data::CheckState) do

              contact = Flapjack::Data::Contact.find_by_id(params[:contact_id])

              if contact.nil?
                notification_rules_err = "Contact with id '#{params[:contact_id]}' could not be loaded"
              else
                notification_rules = notification_rules_data.collect do |notification_rule_data|
                  Flapjack::Data::NotificationRule.new(:id => notification_rule_data['id'],
                    :time_restrictions => notification_rule_data['time_restrictions'],
                    :is_specific => false)
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

            halt err(403, notification_rules_err) unless notification_rules_err.nil?

            status 201
            response.headers['Location'] = "#{base_url}/notification_rules/#{notification_rule_ids.join(',')}"
            Flapjack.dump_json(notification_rule_ids)
          end

          app.get %r{^/notification_rules(?:/)?([^/]+)?$} do
            requested_notification_rules = if params[:captures] && params[:captures][0]
              params[:captures][0].split(',').uniq
            else
              nil
            end

            notification_rules = if requested_notification_rules
              Flapjack::Data::NotificationRule.find_by_ids!(*requested_notification_rules)
            else
              Flapjack::Data::NotificationRule.all
            end

            notification_rule_ids = notification_rules.map(&:id)
            linked_contact_ids = Flapjack::Data::NotificationRule.associated_ids_for_contact(*notification_rule_ids)
            linked_tag_ids = Flapjack::Data::NotificationRule.associated_ids_for_tags(*notification_rule_ids)
            linked_notification_rule_states_ids = Flapjack::Data::NotificationRule.associated_ids_for_states(*notification_rule_ids)

            notification_rules_as_json = notification_rules.collect {|notification_rule|
              notification_rule.as_json(:contact_ids => [linked_contact_ids[notification_rule.id]],
                                        :tag_ids => linked_tag_ids,
                                        :notification_rule_state_ids => linked_notification_rule_states_ids[notification_rule.id])
            }

            Flapjack.dump_json(:notification_rules => notification_rules_as_json)
          end

          # NB notification rules can't add/remove NotitifcationRuleStates, they're
          # created with the default set and possess them for as long as they exist
          app.patch '/notification_rules/:id' do
            Flapjack::Data::NotificationRule.find_by_ids!(*params[:id].split(',')).each do |notification_rule|
              apply_json_patch('notification_rules') do |op, property, linked, value|
                case op
                when 'replace'
                  if ['time_restrictions'].include?(property)
                    notification_rule.send("#{property}=".to_sym, value)
                  end
                when 'add'
                  case linked
                  when 'tags'
                    Flapjack::Data::NotificationRule.lock(Flapjack::Data::Tag) do
                      tag = Flapjack::Data::Tag.intersect(:name => value).all.first
                      if tag.nil?
                        tag = Flapjack::Data::Tag.new(:name => value)
                        tag.save
                      end
                        # TODO association callbacks, which would lock around things
                      notification_rule.tags << tag
                      notification_rule.is_specific = true
                      notification_rule.save
                    end
                  end
                when 'remove'
                  case linked
                  when 'tags'
                    Flapjack::Data::NotificationRule.lock(Flapjack::Data::Tag) do
                      tag = notification_rule.tags.intersect(:name => value).all.first
                      unless tag.nil?
                        notification_rule.tags.delete(tag)
                        if tag.notification_rules.empty? && tag.checks.empty?
                          tag.destroy
                        end
                        if notification_rule.tags.empty?
                          notification_rule.is_specific = false
                          notification_rule.save
                        end
                      end
                    end
                  end
                end
              end
              notification_rule.save # no-op if the record hasn't changed
            end

            status 204
          end

          app.delete '/notification_rules/:id' do
            notification_rule_ids = params[:id].split(',')
            notification_rules = Flapjack::Data::NotificationRule.intersect(:id => notification_rule_ids)
            missing_ids = notification_rule_ids - notification_rules.ids

            unless missing_ids.empty?
              raise Sandstorm::Records::Errors::RecordsNotFound.new(Flapjack::Data::NotificationRule, missing_ids)
            end

            notification_rules.destroy_all
            status 204
          end

        end

      end

    end

  end

end
