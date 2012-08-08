# a bit hacky

if defined?(::Cucumber)
  ActionMailer::Base.raise_delivery_errors = true
  ActionMailer::Base.delivery_method = :test
else
  ActionMailer::Base.raise_delivery_errors = true
  ActionMailer::Base.delivery_method = :smtp
  ActionMailer::Base.smtp_settings = { :address => "127.0.0.1",
                                       :port => 25,
                                       :enable_starttls_auto => false }
end
