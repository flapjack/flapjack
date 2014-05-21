desc 'Generate streams of events in various states'
command :simulate do |simulate|

  simulate.desc 'Generate a stream of failure events'
  simulate.command :fail do |_fail|
    # Because `fail` is a keyword (that you can actually override in a block,
    # but we want to be good Ruby citizens).
    _fail.action do |global_options,options,args|
      puts "fail command ran"
    end
  end

  simulate.desc 'Generate a stream of failure events, and one final recovery'
  simulate.command :fail_and_recover do |fail_and_recover|
    fail_and_recover.action do |global_options,options,args|
      puts "fail_and_recover command ran"
    end
  end

  simulate.desc 'Generate a stream of ok events'
  simulate.command :ok do |ok|
    ok.action do |global_options,options,args|
      puts "ok command ran"
    end
  end

end
