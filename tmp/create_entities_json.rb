#!/usr/bin/env ruby


require 'yajl'

entities = []

contacts = ['0362', '0363', '0364']

entity = { :id          => '10001',
           :name        => 'clientx-app-01',
           :contacts    => contacts }

entities.push(entity)

contacts = ['0362']

entity = { :id          => '10002',
           :name        => 'clientx-app-02',
           :contacts    => contacts }

entities.push(entity)

contacts = ['0363', '0364']

entity = { :id          => '10003',
           :name        => 'clienty-app-01',
           :contacts    => contacts }

entities.push(entity)

puts Yajl::Encoder.encode(entities)

