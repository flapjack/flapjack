require 'redis'
require 'oj'

namespace :benchmarks do

  # add lib to the default include path
  unless $:.include?(File.dirname(__FILE__) + '/../lib/')
    $: << File.dirname(__FILE__) + '/../lib'
  end

  require 'flapjack/configuration'
  require 'flapjack/data/event'
  require 'flapjack/data/entity_check'
  require 'flapjack/version'

  FLAPJACK_ENV = ENV['FLAPJACK_ENV'] || 'test'
  config_file = File.join('tasks', 'support', 'flapjack_config_benchmark.yaml')

  config = Flapjack::Configuration.new
  config.load( config_file )

  @config_env = config.all
  @redis_config = config.for_redis

  if @config_env.nil? || @config_env.empty?
    puts "No config data for environment '#{FLAPJACK_ENV}' found in '#{config_file}'"
    exit(false)
  end

  redis = Redis.new(@redis_config)

  desc "nukes the redis db, generates the events, runs and shuts down flapjack, generates perftools reports"
  task :run => [:reset_redis, :benchmark, :run_flapjack, :reports] do
    puts Oj.dump(@benchmark_data, :indent => 2)
  end

  desc "reset the redis database"
  task :reset_redis do
    raise "I'm not going to let you reset your production redis db, sorry about that." if FLAPJACK_ENV.downcase == "production"
    puts "db size before: #{redis.dbsize}"
    redis.flushdb
    puts "db size after: #{redis.dbsize}"
  end

  desc "starts flapjack"
  task :run_flapjack do
    puts "Discovering path to perftools"
    perftools = `gem which perftools | tail -1`
    if system("if [ ! -d 'artifacts' ] ; then mkdir artifacts ; fi")
      puts "we now have an artifacts dir"
    else
      raise "Problem creating artifacts: #{$?}"
    end
    time_flapjack_start = Time.now.to_f
    puts "Starting flapjack..."
    if system({"FLAPJACK_ENV" => FLAPJACK_ENV,
               "CPUPROFILE"   => "artifacts/flapjack-perftools-cpuprofile",
               "RUBYOPT"      => "-r#{perftools}"},
              "bin/flapjack start --no-daemonize --config tasks/support/flapjack_config_benchmark.yaml")
      puts "Flapjack run completed successfully"
    else
      raise "Problem starting flapjack: #{$?}"
    end
    @timer_flapjack = Time.now.to_f - time_flapjack_start
  end

  desc "generates perftools reports"
  task :reports do
    @benchmark_data = { 'events_created'   => @events_created,
                        'flapjack_runtime' => @timer_flapjack,
                        'processing_rate'  => @events_created.to_f / @timer_flapjack }.merge(@benchmark_parameters)
    bytes_written = IO.write('artifacts/benchmark_data.json', Oj.dump(@benchmark_data, :indent => 2))
    puts "benchmark data written to artifacts/benchmark_data.json (#{bytes_written} bytes)"

    if system("pprof.rb --text artifacts/flapjack-perftools-cpuprofile > artifacts/flapjack-perftools-cpuprofile.txt")
      puts "Generated perftools.rb text report at artifacts/flapjack-perftools-cpuprofile.txt"
      system("head -24 artifacts/flapjack-perftools-cpuprofile.txt")
    else
      raise "Problem generating perftools.rb text report: #{$?}"
    end
    if system("pprof.rb --pdf artifacts/flapjack-perftools-cpuprofile > artifacts/flapjack-perftools-cpuprofile.pdf")
      puts "Generated perftools.rb pdf report at artifacts/flapjack-perftools-cpuprofile.pdf"
    else
      raise "Problem generating perftools.rb pdf report: #{$?}"
    end
  end


  desc "run benchmark - simulate a stream of events from the check execution system"
  # Assumptions:
  # - time to failure varies evenly between 1 hour and 1 month
  # - time to recovery varies evenly between 10 seconds and 1 week
  task :benchmark do

    num_checks_per_entity = (ENV['CHECKS_PER_ENTITY'] || 5).to_i
    num_entities          = (ENV['ENTITIES'] || 100).to_i
    interval              = (ENV['INTERVAL'] || 60).to_i
    hours                 = (ENV['HOURS'] || 1).to_f
    seed                  = (ENV['SEED'] || 42).to_i

    puts "Behaviour can be modified by setting any combination of the following environment variables: "
    puts "CHECKS_PER_ENTITY - #{num_checks_per_entity}"
    puts "ENTITIES          - #{num_entities}"
    puts "INTERVAL          - #{interval}"
    puts "HOURS             - #{hours}"
    puts "SEED              - #{seed}"
    puts "FLAPJACK_ENV      - #{FLAPJACK_ENV}"

    raise "INTERVAL must be less than (or equal to) 3600 seconds (1 hour)" unless interval <= 3600

    cycles_per_hour   = (60.0 * 60) / interval
    cycles_per_day    = (60.0 * 60 * 24) / interval
    cycles_per_week   = (60.0 * 60 * 24 * 7) / interval
    cycles_per_month  = (60.0 * 60 * 24 * 7 * 30) / interval
    cycles            = (hours * cycles_per_hour).to_i
    failure_prob_min  = 1.0 / cycles_per_month
    failure_prob_max  = 1.0 / cycles_per_hour
    recovery_prob_min = 1.0 / cycles_per_week
    recovery_prob_max = 1.0
    initial_ok_prob   = 1
    num_checks = num_checks_per_entity * num_entities

    prng = Random.new(seed)

    ok = 0
    critical = 0
    check_id = 1
    entities = (1..num_entities).to_a.inject({}) {|memo, id|
      checks = (1..num_checks_per_entity).to_a.inject({}) {|memo_check, id_check|
        memo_check[check_id] = {:name => "Check Type #{id_check}",
                                :state => ( prng.rand < initial_ok_prob ? 'OK' : 'CRITICAL' ),
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
    #puts "ok: #{ok * 100.0 / num_checks}% (#{ok}), critical: #{100.0 * critical / num_checks}% (#{critical})"

    events_created  = 0
    ok_to_critical  = 0
    critical_to_ok  = 0
    ok_events       = 0
    critical_events = 0
    state_changes   = 0
    (0..cycles).to_a.each {|i|
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

      #puts "ok: #{100.0 * ok / num_checks}% (#{ok}), critical: #{100.0 * critical / num_checks}% (#{critical}), changed: #{100.0 * changes / num_checks}% (#{changes})"

    }
    puts "created #{events_created} events:"
    puts "  OK:             #{ok_events} (#{ (100.0 * ok_events / events_created).round(1)}%)"
    puts "  CRITICAL:       #{critical_events} (#{ (100.0 * critical_events / events_created).round(1)}%)"
    puts "containing #{state_changes} state changes (#{ (100.0 * state_changes / events_created).round(1)}%):"
    puts "  OK -> CRITICAL: #{ok_to_critical} (#{ (100.0 * ok_to_critical / events_created).round(1)}%)"
    puts "  CRITICAL -> OK: #{critical_to_ok} (#{ (100.0 * critical_to_ok / events_created).round(1)}%)"

    @events_created = events_created
    @benchmark_parameters = { 'events_created'    => events_created,
                              'ok_to_critical'    => ok_to_critical,
                              'critical_to_ok'    => critical_to_ok,
                              'checks_per_entity' => num_checks_per_entity,
                              'entities'          => num_entities,
                              'interval'          => interval,
                              'hours'             => hours,
                              'cycles'            => cycles,
                              'failure_prob_min'  => failure_prob_min,
                              'failure_prob_max'  => failure_prob_max,
                              'recovery_prob_min' => recovery_prob_min,
                              'recovery_prob_max' => recovery_prob_max,
                              'initial_ok_prob'   => initial_ok_prob,
                              'seed'              => seed,
                              'flapjack_env'      => FLAPJACK_ENV,
                              'version'           => Flapjack::VERSION,
                              'git_last_commit'   => `git rev-parse HEAD`.chomp,
                              'git_version'       => `git describe --long --dirty --abbrev=10 --tags`.chomp,
                              'git_branch'        => `git status --porcelain -b | head -1 | cut -d ' ' -f 2`.chomp,
                              'ruby_build'        => `ruby --version`.chomp,
                              'hostname'          => `hostname -f`.chomp,
                              'uname'             => `uname -a`.chomp }
  end

end
