#!/usr/bin/env ruby

class CheckTemplate
  include DataMapper::Resource

  has n, :checks

  property :id,      Serial
  property :command, Text, :nullable => false
  property :name,    String, :nullable => false
  property :params,  Yaml

  validates_is_unique :command, :name

  def name_for_select
    cmd = (self.command.size > 30 ? "#{self.command[0..50]}..." : self.command)
    "#{self.name} (#{cmd})"
  end

end
