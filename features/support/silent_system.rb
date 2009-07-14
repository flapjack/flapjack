def silent_system(cmd)
  silent_cmd = cmd + " 2>&1 > /dev/null"
  system(silent_cmd)
end
