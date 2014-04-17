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

          # get one or more notification rules
          app.get '/notification_rules/:id' do
            rules_json = params[:id].split(',').collect {|rule_id|
              find_rule(rule_id).to_jsonapi
            }.join(', ')

            '{"notification_rules":[' + rules_json + ']}'
          end

          app.patch '/notification_rules/:id' do

            params[:id].split(',').collect {|notification_rule_id|
              find_rule(notification_rule_id)
            }.each do |notification_rule|
              apply_json_patch('notification_rules') do |op, property, linked, value|
                case op
                when 'replace'
                  case property
                  when ''
                  end
                end
              end
            end

          end

          # # Updates one or more notification rules
          # app.put '/notification_rules/:id' do
          #   rules_data = params[:notification_rules]

          #   if rules_data.nil? || !rules_data.is_a?(Enumerable)
          #     halt err(422, "No valid notification rules were submitted")
          #   end

          #   rule_ids       = params[:id].split(',')
          #   rules_data_ids = rules_data.collect {|rd| rd['id'].to_s }

          #   unless (rule_ids & rules_data_ids) == rule_ids
          #     halt err(422, "Rule id parameters do not match rule update data ids")
          #   end

          #   # pre-retrieve rule objects, errors before data is changed if any
          #   # are not found
          #   rules      = rule_ids.collect {|rule_id| find_rule(rule_id) }
          #   rules_json = rules.inject([]) {|memo, rule|
          #     if rule_data = rules_data.detect {|rd| rd['id'].to_s == rule.id}
          #       rule.update(symbolize(rule_data), :logger => logger)
          #       memo << rule.to_json
          #     end
          #     memo
          #   }.join(', ')

          #   '{"notification_rules":[' + rules_json + ']}'
          # end

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
