def silent_system(cmd)
  #silent_cmd = cmd + " 2>&1 > /dev/null"
  @output = `#{cmd}`
end
