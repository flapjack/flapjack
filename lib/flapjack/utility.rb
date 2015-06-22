#!/usr/bin/env ruby

module Flapjack
  module Utility

    def time_period_in_words(period)
      return "0 seconds" unless period.is_a?(Integer) && period > 0
      period_mm, period_ss  = period.divmod(60)
      period_hh, period_mm  = period_mm.divmod(60)
      period_dd, period_hh  = period_hh.divmod(24)
      ["#{period_dd} day#{plural_s(period_dd)}",
       "#{period_hh} hour#{plural_s(period_hh)}",
       "#{period_mm} minute#{plural_s(period_mm)}",
       "#{period_ss} second#{plural_s(period_ss)}"].reject {|s| s =~ /^0 /}.join(', ')
    end

    # Returns relative time in words referencing the given date
    # relative_time_ago(Time.now, Time.now - 1) => 'about a minute ago'
    def relative_time_ago(from_time, to_time)
      distance_in_minutes = (((from_time.to_time - to_time.to_time).abs)/60).round
      case distance_in_minutes
      when 0..1 then 'about a minute'
      when 2..44 then "#{distance_in_minutes} minutes"
      when 45..89 then 'about 1 hour'
      when 90..1439 then "about #{(distance_in_minutes.to_f / 60.0).round} hours"
      when 1440..2439 then '1 day'
      when 2440..2879 then 'about 2 days'
      when 2880..43199 then "#{(distance_in_minutes / 1440).round} days"
      when 43200..86399 then 'about 1 month'
      when 86400..525599 then "#{(distance_in_minutes / 43200).round} months"
      when 525600..1051199 then 'about 1 year'
      else "over #{(distance_in_minutes / 525600).round} years"
      end
    end

    # returns a string showing the local timezone we're running in
    # eg "CST (UTC+09:30)"
    def local_timezone
      tzname = Time.new.zone
      q, r = Time.new.utc_offset.divmod(3600)
      sign = (q < 0) ? '-' : '+'
      tzoffset = sign + "%02d" % q.abs.to_s + ':' + r.to_f.div(60).to_s
      "#{tzname} (UTC#{tzoffset})"
    end

    def remove_utc_offset(time)
      Time.utc(time.year, time.month, time.day, time.hour, time.min, time.sec)
    end

    def stringify(obj)
      return obj.inject({}){|memo,(k,v)| memo[k.to_s] =  stringify(v); memo} if obj.is_a?(Hash)
      return obj.inject([]){|memo,v    | memo         << stringify(v); memo} if obj.is_a?(Array)
      obj
    end

    def symbolize(obj)
      return obj.inject({}){|memo,(k,v)| memo[k.to_sym] =  symbolize(v); memo} if obj.is_a? Hash
      return obj.inject([]){|memo,v    | memo           << symbolize(v); memo} if obj.is_a? Array
      obj
    end

    # The passed block will be provided each value from the args
    # and must return array pairs [key, value] representing members of
    # the hash this method returns. Keys should be unique -- if they're
    # not, the earlier pair for that key will be overwritten.
    def hashify(*args, &block)
      key_value_pairs = args.map {|a| yield(a) }

      # if using Ruby 1.9,
      #   Hash[ key_value_pairs ]
      # is all that's needed, but for Ruby 1.8 compatability, these must
      # be flattened and the resulting array unpacked. flatten(1) only
      # flattens the arrays constructed in the block, it won't mess up
      # any values (or keys) that are themselves arrays/hashes.
      Hash[ *( key_value_pairs.flatten(1) )]
    end

    # copied from ActiveSupport
    def truncate(str, length, options = {})
      text = str.dup
      options[:omission] ||= "..."

      length_with_room_for_omission = length - options[:omission].length
      stop = options[:separator] ?
        (text.rindex(options[:separator], length_with_room_for_omission) || length_with_room_for_omission) : length_with_room_for_omission

      (text.length > length ? text[0...stop] + options[:omission] : text).to_s
    end

    def load_template(template_config, message_type, message_filetype,
                      default_template_path)
      template_file = if template_config.nil? || !template_config.has_key?("#{message_type}.#{message_filetype}")
        # we ship UTF-8 templates with the gem
        template_path = File.join(default_template_path, "#{message_type}.#{message_filetype}.erb")
        File.open(template_path, "r:UTF-8", &:read)
      else
         # respects Encoding.default_external (UTF-8 or ENV['LANG'])
        template_path = template_config["#{message_type}.#{message_filetype}"]
        File.read(template_path)
      end
      [ERB.new(template_file, nil, '-'), template_file]
    end

    private

    def plural_s(value)
      (value == 1) ? '' : 's'
    end

  end
end
