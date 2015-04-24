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
              filter.include?('all') ? 'all' : filter
            end
          end

          def self.registered(app)
            app.helpers Flapjack::Gateways::JSONAPI::Helpers::Headers
            app.helpers Flapjack::Gateways::JSONAPI::Helpers::Miscellaneous
            app.helpers Flapjack::Gateways::JSONAPI::Helpers::Resources
            app.helpers Flapjack::Gateways::JSONAPI::Methods::Metrics::Helpers

            app.get %r{^/metrics$} do
              filter = params[:filter] ? filter_query(params[:filter]) : 'all'

              keys = [:fqdn, :pid, :total_keys, :processed_events_all_time,
                      :event_queue_length, :check_freshness, :checks]
              keys = keys.select {|m| filter.include?(m.to_s)} unless 'all'.eql?(filter)

              metrics = Hash[ *(keys.collect{|key| [key, self.send(key)]}) ]
              Flapjack.dump_json(metrics)
            end

            [:check_freshness, :checks, :event_queue, :processed_events].each do |metric|
              app.get %r{^/metrics/#{metric.to_s}$} do
                Flapjack.dump_json(metric => self.send(:metric))
              end
            end
          end

        end
      end
    end
  end
end
