#!/usr/bin/env ruby

require 'sinatra/base'

require 'flapjack/data/check'
require 'flapjack/data/report'

module Flapjack
  module Gateways
    class JSONAPI < Sinatra::Base
      module Methods
        module Reports

          # module Helpers
          # end

          def self.registered(app)
            app.helpers Flapjack::Gateways::JSONAPI::Helpers::Headers
            app.helpers Flapjack::Gateways::JSONAPI::Helpers::Miscellaneous
            app.helpers Flapjack::Gateways::JSONAPI::Helpers::Resources
            # app.helpers Flapjack::Gateways::JSONAPI::Methods::Reports::Helpers

            # FIXME swagger docs for reports

            # app.get %r{^/(outage|(?:un)?scheduled_maintenance|downtime)_reports/(?:(checks)(?:/(.+))?|(tags)/(.+))$} do
            app.get %r{^/(outage|downtime)_reports/(?:(checks)(?:/(.+))?|(tags)/(.+))$} do
              report_type = params[:captures][0]

              resource = params[:captures][1] || params[:captures][3]

              resource_id = params[:captures][1].nil? ? params[:captures][4] :
                                                        params[:captures][2]
              initial_scope = case resource
              when 'checks'
                resource_id.nil? ? Flapjack::Data::Check : nil
              when 'tags'
                Flapjack::Data::Tag.find_by_id!(resource_id).checks
              end

              args = {:start_time => validate_and_parsetime(params[:start_time]),
                      :end_time   => validate_and_parsetime(params[:end_time])}

              checks, links, meta = if 'tags'.eql?(resource) || resource_id.nil?
                scoped = resource_filter_sort(initial_scope,
                 :filter => params[:filter], :sort => params[:sort])
                paginate_get(scoped, :page => params[:page],
                  :per_page => params[:per_page])
              else
                [Flapjack::Data::Check.intersect(:id => resource_id), {}, {}]
              end

              halt(404) if initial_scope.nil? && checks.empty?

              links[:self] = request_url

              rd = []

              checks.each do |check|
                r, stats = Flapjack::Data::Report.send(report_type.to_sym, check, args)
                rd << r.merge(:type => "#{report_type}_report")
                unless stats.nil? || stats.empty?
                  meta[:statistics] ||= {}
                  meta[:statistics][check.id] = stats
                end
              end

              # unwrap, if single check requested
              rd = rd.first unless 'tags'.eql?(resource) || resource_id.nil?

              status 200
              json_data = {:links => links, :data => rd}
              json_data.update(:meta => meta) unless meta.nil? || meta.empty?
              Flapjack.dump_json(json_data)
            end

          end
        end
      end
    end
  end
end
