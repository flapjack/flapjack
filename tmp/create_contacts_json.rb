#!/usr/bin/env ruby


require 'yajl'

contacts = []

media = { :sms   => '+61414669790',
          :email => 'jesse@va.com.au' }

contact = { :id         => '0362',
            :first_name => 'Jesse',
            :last_name  => 'Reynolds',
            :email      => 'jesse@va.com.au',
            :media      => media }

contacts.push(contact)

media = { :sms   => '+61414111111' }

contact = { :id         => '0363',
            :first_name => 'Tom',
            :last_name  => 'Alphabet',
            :email      => 'tom@alphabet.com',
            :media      => media }

contacts.push(contact)

media = { :email => '+61414222222' }

contact = { :id         => '0364',
            :first_name => 'Jane',
            :last_name  => 'Alphabet',
            :email      => 'jane@alphabet.com',
            :media      => media }

contacts.push(contact)

puts Yajl::Encoder.encode(contacts)

