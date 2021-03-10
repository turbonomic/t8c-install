server = true
bootstrap_expect = 1
bind_addr = "{{GetInterfaceIP \"eth0\"}}"
client_addr = "{{GetInterfaceIP \"eth0\"}}"
data_dir="/opt/consul/data"
disable_update_check = true
ui = true