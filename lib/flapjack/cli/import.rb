#!/usr/bin/env ruby

desc 'Bulk import data from an external source'
command :import do |import|

  import.desc 'Import contacts'
  import.command :contacts do |contacts|
    contacts.action do |global_options,options,args|
      puts "contacts command ran"
    end
  end

  import.desc 'Import entities'
  import.command :entities do |entities|
    entities.action do |global_options,options,args|
      puts "entities command ran"
    end
  end

end
