require 'redis'

namespace :events do

  # add lib to the default include path
  unless $:.include?(File.dirname(__FILE__) + '/../lib/')
    $: << File.dirname(__FILE__) + '/../lib'
  end

  require 'flapjack/configuration'
  require 'flapjack/data/event'
  require 'flapjack/data/entity_check'

  def get_initial_state(prng, p_initial_state_ok)
    if prng.rand < p_initial_state_ok
      'OK'
    else
      'CRITICAL'
    end
  end

  desc "benchmark event set 1"
  task :benchmark_set_1 do
    num_checks_per_entity = 5
    num_entities = 100
    num_checks = num_checks_per_entity * num_entities
    interval = 60
    cycles_per_hour    = (60 * 60) / interval
    cycles_per_day     = (60 * 60 * 24) / interval
    cycles_per_week    = (60 * 60 * 24 * 7) / interval
    cycles_per_month   = (60 * 60 * 24 * 7 * 30) / interval
    failure_prob_min   = 1.0 / cycles_per_month
    failure_prob_max   = 1.0 / cycles_per_hour
    recovery_prob_min  = 1.0 / cycles_per_week
    recovery_prob_max  = 1.0
    p_initial_state_ok = 1

    prng = Random.new(42)

    FLAPJACK_ENV = ENV['FLAPJACK_ENV'] || 'development'
    config_file = File.join('etc', 'flapjack_config.yaml')

    config = Flapjack::Configuration.new
    config.load( config_file )

    @config_env = config.all
    @redis_config = config.for_redis

    if @config_env.nil? || @config_env.empty?
      puts "No config data for environment '#{FLAPJACK_ENV}' found in '#{config_file}'"
      exit(false)
    end

    redis = Redis.new(@redis_config)

    ok = 0
    critical = 0
    check_id = 1
    entities = (1..num_entities).to_a.inject({}) {|memo, id|
      checks = (1..num_checks_per_entity).to_a.inject({}) {|memo_check, id_check|
        memo_check[check_id] = {:name => "Check Type #{id_check}",
                                :state => ( prng.rand < p_initial_state_ok ? 'OK' : 'CRITICAL' ),
                                :p_failure => prng.rand(failure_prob_min..failure_prob_max),
                                :p_recovery => prng.rand(recovery_prob_min..recovery_prob_max)}
        ok       += 1 if memo_check[check_id][:state] == 'OK'
        critical += 1 if memo_check[check_id][:state] == 'CRITICAL'
        check_id += 1
        memo_check
      }
      memo[id] = checks
      memo
    }
    puts "ok: #{ok * 100.0 / num_checks}% (#{ok}), critical: #{100.0 * critical / num_checks}% (#{critical})"

    events_created  = 0
    ok_to_critical  = 0
    critical_to_ok  = 0
    ok_events       = 0
    critical_events = 0
    state_changes   = 0
    (0..(cycles_per_hour)).to_a.each {|i|
      changes = 0
      ok = 0
      critical = 0
      summary = "You tell me summer's here \nand the time is wrong \n"
      summary << "You tell me winter's here \nAnd your days are getting long"
      entities.each_pair {|entity_id, checks|
        checks.each_pair {|check_id, check|
          changed = false
          previous_state = check[:state]
          case previous_state
          when "OK"
            if prng.rand < check[:p_failure]
              check[:state] = "CRITICAL"
              changed = true
              changes += 1
              ok_to_critical += 1
            end
          when "CRITICAL"
            if prng.rand < check[:p_recovery]
              check[:state] = "OK"
              changed = true
              changes += 1
              critical_to_ok += 1
            end
          end
          ok       += 1 if check[:state] == 'OK'
          critical += 1 if check[:state] == 'CRITICAL'

          Flapjack::Data::Event.add({'entity'  => "entity_#{entity_id}.example.com",
                                     'check'   => check[:name],
                                     'type'    => 'service',
                                     'state'   => check[:state],
                                     'summary' => summary }, :redis => redis)
          events_created += 1
        }
      }
      ok_events       += ok
      critical_events += critical
      state_changes   += changes

      puts "ok: #{100.0 * ok / num_checks}% (#{ok}), critical: #{100.0 * critical / num_checks}% (#{critical}), changed: #{100.0 * changes / num_checks}% (#{changes})"

    }
    puts "created #{events_created} events:"
    puts "  OK:             #{ok_events} (#{ (100.0 * ok_events / events_created).round(2)}%)"
    puts "  CRITICAL:       #{critical_events} (#{ (100.0 * critical_events / events_created).round(2)}%)"
    puts "containing #{state_changes} state changes:"
    puts "  OK -> CRITICAL: #{ok_to_critical}"
    puts "  CRITICAL -> OK: #{critical_to_ok}"

  end

  # FIXME: add arguments, make more flexible
  desc "send events to trigger some notifications"
  task :test_notification do

    FLAPJACK_ENV = ENV['FLAPJACK_ENV'] || 'development'
    config_file = File.join('etc', 'flapjack_config.yaml')

    config = Flapjack::Configuration.new
    config.load( config_file )

    @config_env = config.all
    @redis_config = config.for_redis

    if @config_env.nil? || @config_env.empty?
      puts "No config data for environment '#{FLAPJACK_ENV}' found in '#{config_file}'"
      exit(false)
    end

    redis = Redis.new(@redis_config)

    Flapjack::Data::Event.add({'entity'  => 'clientx-app-01',
                               'check'   => 'ping',
                               'type'    => 'service',
                               'state'   => 'ok',
                               'summary' => 'testing'}, :redis => redis)

    sleep(8)

    Flapjack::Data::Event.add({'entity'  => 'clientx-app-01',
                               'check'   => 'ping',
                               'type'    => 'service',
                               'state'   => 'critical',
                               'summary' => 'testing'}, :redis => redis)

    sleep(8)

    Flapjack::Data::Event.add({'entity'  => 'clientx-app-01',
                               'check'   => 'ping',
                               'type'    => 'service',
                               'state'   => 'ok',
                               'summary' => 'testing'}, :redis => redis)

  end


end
