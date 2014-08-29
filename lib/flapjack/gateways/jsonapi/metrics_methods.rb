#!/usr/bin/env ruby

require 'sinatra/base'

require 'flapjack/data/check'

module Flapjack

  module Gateways

    class JSONAPI < Sinatra::Base

      module MetricsMethods

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

          def processed_events
            # TODO(@auxesis): potentially provide 5m,10m,30m metrics?
            counters = Hash[Flapjack.redis.hgetall('event_counters').map {|k,v| [k,v.to_i] }]
            { 'all_time' => counters }
          end

          def check_freshness
            Flapjack::Data::Check.split_by_freshness( [0, 60, 300, 900, 3600], :counts => true)
          end

          def failing_checks
            Flapjack::Data::Check.intersect(:state => Flapjack::Data::CheckState.failing_states)
          end

          def checks
            {
              'all'     => Flapjack::Data::Check.count,
              'failing' => failing_checks.count,
            }
          end

          def filter_query(query)
            case
            when query == 'all', query.empty?
              'all'
            else
              filter = query.split(',')
              filter.find {|q| q == 'all'} ? 'all' : filter
            end
          end
        end

        def self.registered(app)
          app.helpers Flapjack::Gateways::JSONAPI::Helpers
          app.helpers Flapjack::Gateways::JSONAPI::MetricsMethods::Helpers

          app.get %r{^/metrics} do
            filter = params[:filter] ? filter_query(params[:filter]) : 'all'

            keys = %w(fqdn pid total_keys processed_events event_queue_length check_freshness checks)
            keys = keys.find_all {|m| filter.include?(m) } unless filter == 'all'

            metrics = {}
            keys.each do |key|
              metrics[key] = self.send(key.to_sym)
            end

            return metrics.to_json
          end
        end

      end

    end

  end

end
