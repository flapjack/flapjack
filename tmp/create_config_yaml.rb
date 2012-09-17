#!/usr/bin/env ruby


require 'yaml'

config = { 'sausage' => true,
           'sauce'   => 'tomato sauce',
           'count'   => 23,
           'foobar'  => 'jkfldjsk',
           'zero_s'  => '0',
           'true_s'  => 'true',
         }


puts config.to_yaml

