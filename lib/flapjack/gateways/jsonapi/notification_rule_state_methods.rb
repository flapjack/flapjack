#!/usr/bin/env ruby

require 'sinatra/base'

require 'flapjack/data/contact'

module Flapjack

  module Gateways

    class JSONAPI < Sinatra::Base

      module NotificationRuleStateMethods

        module Helpers
        end

        def self.registered(app)
          app.helpers Flapjack::Gateways::JSONAPI::Helpers
          # app.helpers Flapjack::Gateways::JSONAPI::NotificationRuleStateMethods::Helpers

          app.get %r{^/notification_rule_states(?:/)?([^/]+)?$} do
            requested_notification_rule_states = if params[:captures] && params[:captures][0]
              params[:captures][0].split(',').uniq
            else
              nil
            end

            notification_rule_states = if requested_notification_rule_states
              Flapjack::Data::NotificationRuleState.find_by_ids!(requested_notification_rule_states)
            else
              Flapjack::Data::NotificationRuleState.all
            end

            notification_rule_state_ids = notification_rule_states.map(&:id)
            linked_notification_rule_ids = Flapjack::Data::NotificationRuleState.associated_ids_for_notification_rule(notification_rule_state_ids)

            notification_rule_states_json = notification_rule_states.collect {|notification_rule_state|
              notification_rule_state.as_json(:notification_rule_id => linked_notification_rule_ids[notification_rule_state.id]).to_json
            }.join(",")

            '{"notification_rule_states":[' + notification_rule_states_json + ']}'
          end

          app.patch '/notification_rule_states/:id' do
            Flapjack::Data::NotificationRuleState.find_by_ids!(params[:id].split(',')).
              each do |notification_rule_state|

              apply_json_patch('notification_rule_states') do |op, property, linked, value|
                case op
                when 'replace'
                  if ['blackhole'].include?(property)
                    notification_rule_state.send("#{property}=".to_sym, value)
                  end
                when 'add'
                  case linked
                  when 'media'
                    Flapjack::Data::Medium.send(:lock) do
                      medium = Flapjack::Data::Medium.find_by_id(value)
                      unless medium.nil?
                        if existing_medium = notification_rule_state.media.intersect(:type => medium.type).all.first
                          # just dissociate, not delete record
                          notification_rule_state.media.delete(existing_medium)
                        end
                        notification_rule_state.media << medium
                      end
                    end
                  end
                when 'remove'
                  case linked
                  when 'media'
                    medium = Flapjack::Data::Medium.find_by_id(value)
                    notification_rule_state.media.delete(medium) unless medium.nil?
                  end
                end
              end
              notification_rule_state.save # no-op if the record hasn't changed
            end

            status 204
          end

        end

      end

    end

  end

end
