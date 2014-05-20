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
            rules_data = params[:notification_rules]

            if rules_data.nil? || !rules_data.is_a?(Enumerable)
              halt err(422, "No valid notification rules were submitted")
            end

            contact = find_contact(params[:contact_id])

            errors = []
            rules_data.each do |rule_data|
              errors << Flapjack::Data::NotificationRule.prevalidate_data(symbolize(rule_data), {:logger => logger})
            end
            errors.compact!

            unless errors.nil? || errors.empty?
              halt err(422, *errors)
            end

            rules = []
            errors = []
            rules_data.each do |rule_data|
              rule_data = symbolize(rule_data)
              rule_or_errors = contact.add_notification_rule(rule_data, :logger => logger)
              if rule_or_errors.respond_to?(:critical_media)
                rules << rule_or_errors
              else
                errors << rule_or_errors
              end
            end

            if rules.empty?
              halt err(422, *errors)
            else
              if errors.empty?
                status 201
              else
                logger.warn("Errors during bulk notification rules creation: " + errors.join(', '))
                status 200
              end
            end

            ids = rules.map {|r| r.id}
            location(ids)

            rules_json = rules.map {|r| r.to_json}.join(',')
            '{"notification_rules":[' + rules_json + ']}'
          end

          app.get %r{^/notification_rules(?:/)?([^/]+)?$} do
            requested_notification_rules = if params[:captures] && params[:captures][0]
              params[:captures][0].split(',').uniq
            else
              nil
            end

            notification_rules = if requested_notification_rules
              Flapjack::Data::NotificationRule.find_by_ids(requested_notification_rules, :logger => logger, :redis => redis)
            else
              Flapjack::Data::NotificationRule.all(:redis => redis).reject {|nr| nr.id.nil? || nr.id.empty? }
            end
            notification_rules.compact!

            if requested_notification_rules && notification_rules.empty?
              raise Flapjack::Gateways::JSONAPI::NotificationRulesNotFound.new(requested_notification_rules)
            end

            notification_rules_json = notification_rules.collect {|notification_rule|
              notification_rule.to_jsonapi
            }.join(", ")

            '{"notification_rules":[' + notification_rules_json + ']}'
          end

          app.patch '/notification_rules/:id' do
            params[:id].split(',').collect {|rule_id|
              find_rule(rule_id)
            }.each do |rule|
              apply_json_patch('notification_rules') do |op, property, linked, value|
                case op
                when 'replace'
                  case property
                  when 'entities', 'regex_entities', 'tags', 'regex_tags',
                    'time_restrictions', 'unknown_media', 'warning_media',
                    'critical_media', 'unknown_blackhole', 'warning_blackhole',
                    'critical_blackhole'

                    rule.update({property.to_sym => value}, :logger => logger)
                  end
                end
              end
            end

            status 204
          end

          # Deletes one or more notification rules
          app.delete '/notification_rules/:id' do
            params[:id].split(',').each do |rule_id|
              rule = find_rule(rule_id)
              logger.debug("rule to delete: #{rule.inspect}, contact_id: #{rule.contact_id}")
              contact = find_contact(rule.contact_id)
              contact.delete_notification_rule(rule)
            end

            status 204
          end

        end

      end

    end

  end

end
