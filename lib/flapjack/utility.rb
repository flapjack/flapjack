#!/usr/bin/env ruby

module Flapjack
  module Utility

    def time_period_in_words(period)
      period_mm, period_ss  = period.divmod(60)
      period_hh, period_mm  = period_mm.divmod(60)
      period_dd, period_hh  = period_hh.divmod(24)
      period_string         = ''
      period_string        += period_dd.to_s + ' days, ' if period_dd > 0
      period_string        += period_hh.to_s + ' hours, ' if period_hh > 0
      period_string        += period_mm.to_s + ' minutes, ' if period_mm > 0
      period_string        += period_ss.to_s + ' seconds' if period_ss > 0
      period_string
    end

    # Returns relative time in words referencing the given date
    # relative_time_ago(Time.now) => 'about a minute ago'
    def relative_time_ago(from_time)
      distance_in_minutes = (((Time.now - from_time.to_time).abs)/60).round
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

  end
end
