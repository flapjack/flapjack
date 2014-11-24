#!/usr/bin/env ruby

require 'sinatra/base'

require 'flapjack/data/check'

require 'flapjack/gateways/jsonapi/helpers/check_presenter'

module Flapjack
  module Gateways
    class JSONAPI < Sinatra::Base
      module Methods
        module Reports

          module Helpers

            def report_data(check_ids, options = {}, &block)
              checks, meta = if check_ids.nil?
                paginate_get(Flapjack::Data::Check.sort(:name),
                  :total => Flapjack::Data::Check.count, :page => options[:page],
                  :per_page => options[:per_page])
              elsif !check_ids.empty?
                [Flapjack::Data::Check.find_by_ids!(*check_ids), {}]
              else
                [[], {}]
              end

              rd = checks.each_with_object([]) do |check, memo|
                memo << yield(Flapjack::Gateways::JSONAPI::Helpers::CheckPresenter.new(check)).
                  merge('links'  => {'check'  => [check.id]})
              end

              [rd, meta]
            end

          end

          def self.registered(app)
            app.helpers Flapjack::Gateways::JSONAPI::Helpers::Headers
            app.helpers Flapjack::Gateways::JSONAPI::Helpers::Miscellaneous
            app.helpers Flapjack::Gateways::JSONAPI::Helpers::Resources
            app.helpers Flapjack::Gateways::JSONAPI::Methods::Reports::Helpers

            app.get %r{^/(status|outage|(?:un)?scheduled_maintenance|downtime)_report(?:/([^/]+))?$} do
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
              rd, meta = report_data(check_ids, :page => params[:page],
                                     :per_page => params[:per_page]) {|presenter|
                presenter.send(action_pres.to_sym, *args)
              }

              status 200
              Flapjack.dump_json({"#{action}_reports".to_sym => rd}.merge(meta))
            end

          end
        end
      end
    end
  end
end
