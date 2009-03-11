#!/usr/bin/env ruby

require 'bin/common'
require 'net/smtp'
require 'mailfactory'

class Mailer

  def notify!(opts={})
    raise unless (opts[:who] && opts[:result])

    mail = MailFactory.new
    mail.to = opts[:who].email
    mail.from = "notifications@flapjack-project.com"
    mail.subject = "Check: #{opts[:result].id}, Status: #{opts[:result].status}"
    mail.text = <<-DESC
      Check #{opts[:result].id} returned the status "#{opts[:result].status}".
      
      Here was the output: 
        #{opts[:result].output}

      You can respond to this issue at:
        http://localhost:4000/issue/#{opts[:result].object_id * -1}
    DESC

    Net::SMTP.start('localhost') do |smtp|
      smtp.sendmail(mail.to_s, mail.from, mail.to)
    end
  end

end

