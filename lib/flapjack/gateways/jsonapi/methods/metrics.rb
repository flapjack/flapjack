#!/usr/bin/env ruby

require 'sinatra/base'

require 'flapjack/data/check'

module Flapjack
  module Gateways
    class JSONAPI < Sinatra::Base
      module Methods
        module Metrics

          module Helpers

            def fqdn
              `/bin/hostname -f`.chomp
            end

            def pid
              Process.pid
            end

            def total_keys
              Flapjack.redis.dbsize
            end

            def event_queue_length
              Flapjack.redis.llen('events')
            end

            def event_queue
              {:length => event_queue_length}
            end

            def processed_events
              Hash[Flapjack.redis.hgetall('event_counters').map {|k,v| [k,v.to_i] }]
            end

            def processed_events_all_time
              {:all_time => processed_events}
            end

            def check_freshness
              Flapjack::Data::Check.split_by_freshness([0, 60, 300, 900, 3600], :counts => true)
            end

            def checks
              {
                :all     => Flapjack::Data::Check.count,
                :failing => Flapjack::Data::Check.intersect(:failing => true).count
              }
            end

            def filter_query(query)
              return 'all' if ['all', ''].include?(query)
              filter = query.split(',')
              filter.find {|q| q == 'all'} ? 'all' : filter
            end
          end

          def self.registered(app)
            app.helpers Flapjack::Gateways::JSONAPI::Helpers::Headers
            app.helpers Flapjack::Gateways::JSONAPI::Helpers::Miscellaneous
            app.helpers Flapjack::Gateways::JSONAPI::Helpers::Resources
            app.helpers Flapjack::Gateways::JSONAPI::Methods::Metrics::Helpers

            app.get %r{^/metrics$} do
              filter = params[:filter] ? filter_query(params[:filter]) : 'all'

              keys = %w(fqdn pid total_keys processed_events_all_time event_queue_length check_freshness checks)
              keys = keys.find_all {|m| filter.include?(m) } unless filter == 'all'

              metrics = keys.each_with_object({}) do |key, memo|
                memo[key.to_sym] = self.send(key.to_sym)
              end

              Flapjack.dump_json(metrics)
            end

            app.get %r{^/metrics/check_freshness$} do
              Flapjack.dump_json(:check_freshness => check_freshness)
            end

            app.get %r{^/metrics/checks$} do
              Flapjack.dump_json(:checks => checks)
            end

            app.get %r{^/metrics/event_queue$} do
              Flapjack.dump_json(:event_queue => event_queue)
            end

            app.get %r{^/metrics/processed_events$} do
              Flapjack.dump_json(:processed_events => processed_events)
            end

          end

        end
      end
    end
  end
end
