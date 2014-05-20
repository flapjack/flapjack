#!/usr/bin/env ruby

require 'sinatra/base'

require 'flapjack/data/contact'

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
            redis.dbsize
          end

          def event_queue_length
            redis.llen('events')
          end

          def processed_events
            # TODO(@auxesis): potentially provide 5m,10m,30m metrics?
            counters = Hash[redis.hgetall('event_counters').map {|k,v| [k,v.to_i] }]
            { 'all_time' => counters }
          end

          def check_freshness
            freshnesses = [0, 60, 300, 900, 3600]
            options     = {
              :redis => redis,
              :counts => true
            }

            Flapjack::Data::EntityCheck.find_all_split_by_freshness(freshnesses, options)
          end

          def entities
            {
              'all'     => Flapjack::Data::Entity.find_all_with_checks(:redis => redis).length,
              'failing' => Flapjack::Data::Entity.find_all_with_failing_checks(:redis => redis).length,
            }
          end

          def checks
            {
              'all'     => Flapjack::Data::EntityCheck.count_all(:redis => redis),
              'failing' => Flapjack::Data::EntityCheck.count_all_failing(:redis => redis),
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
            filter = filter_query(params[:filter])

            keys = %w(fqdn pid total_keys processed_events event_queue_length check_freshness entities checks)
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
