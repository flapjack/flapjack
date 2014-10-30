#!/usr/bin/env ruby

require 'sinatra/base'

require 'flapjack/data/check'

require 'flapjack/gateways/jsonapi/check_presenter'

module Flapjack

  module Gateways

    class JSONAPI < Sinatra::Base

      module ReportMethods

        module Helpers

          def load_api_data(check_ids, &block)
            checks = if check_ids.nil?
              # TODO paginate
              Flapjack::Data::Check.all
            elsif !check_ids.empty?
              Flapjack::Data::Check.find_by_ids!(*check_ids)
            else
              []
            end

            report_data = []
            check_data = []

            checks.each do |check|
              report_data << yield(Flapjack::Gateways::JSONAPI::CheckPresenter.new(check)).
                merge('links'  => {
                  'check'  => [check.id],
                })

              check_data << check.as_json
            end

            [report_data, check_data]
          end

        end

        def self.registered(app)
          app.helpers Flapjack::Gateways::JSONAPI::Helpers
          app.helpers Flapjack::Gateways::JSONAPI::ReportMethods::Helpers

          app.get %r{^/(status|outage|(?:un)?scheduled_maintenance|downtime)_report/checks(?:/([^/]+))?$} do

            action = params[:captures][0]
            action_pres = case action
            when 'status', 'downtime'
              action
            else
              "#{action}s"
            end

            args = []
            unless 'status'.eql?(action)
              start_time = validate_and_parsetime(params[:start_time])
              start_time = start_time.to_i unless start_time.nil?
              end_time = validate_and_parsetime(params[:end_time])
              end_time = end_time.to_i unless end_time.nil?
              args += [start_time, end_time]
            end

            check_ids = params[:captures][1].nil? ? nil : params[:captures][1].split(',')
            report_data, check_data = load_api_data(check_ids) {|presenter|
              presenter.send(action_pres.to_sym, *args)
            }

            "{\"#{action}_reports\":" + Flapjack.dump_json(report_data) + "," +
             "\"linked\":{\"checks\":" + Flapjack.dump_json(check_data) + "}}"
          end

        end

      end

    end

  end

end
