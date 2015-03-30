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

          def events
            { 'processed' => processed_events,
              'queue'     => {'length' => event_queue_length}
            }
          end

          def processed_events
            Hash[redis.hgetall('event_counters').map {|k,v| [k,v.to_i] }]
          end

          def processed_events_all_time
            { 'all_time' => processed_events }
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
              'all'     => Flapjack::Data::Entity.all(:redis => redis).length,
              'enabled' => Flapjack::Data::Entity.all(:enabled => true, :redis => redis).length,
              'failing' => Flapjack::Data::Entity.find_all_names_with_failing_checks(:redis => redis).length,
            }
          end

          def checks
            {
              'all'     => Flapjack::Data::EntityCheck.count_current(:redis => redis),
              'failing' => Flapjack::Data::EntityCheck.count_current_failing(:redis => redis),
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

          app.get %r{^/metrics$} do

            filter = params[:filter] ? filter_query(params[:filter]) : 'all'

            keys = %w(fqdn pid total_keys processed_events_all_time event_queue_length check_freshness entities checks)
            keys = keys.find_all {|m| filter.include?(m) } unless filter == 'all'

            metrics = {}
            keys.each do |key|
              metrics[key] = self.send(key.to_sym)
            end

            Flapjack.dump_json(metrics)
          end

          app.get %r{^/metrics/check_freshness$} do
            cf = self.check_freshness
            Flapjack.dump_json({"check_freshness" => {
              "from_0_to_60"     => cf[0],
              "from_60_to_300"   => cf[60],
              "from_300_to_900"  => cf[300],
              "from_900_to_3600" => cf[900],
              "from_3600_to_∞"   => cf[3600]
              }})
          end

          app.get %r{^/metrics/entities$} do
            Flapjack.dump_json({"entities" => entities})
          end

          app.get %r{^/metrics/checks$} do
            Flapjack.dump_json({"checks" => checks})
          end

          app.get %r{^/metrics/events$} do
            Flapjack.dump_json({"events" => events})
          end

        end

      end

    end

  end

end
