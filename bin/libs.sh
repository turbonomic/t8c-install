#!/bin/bash

# Library functions to be used in other scripts.

log_msg () {
    local msg=${@};
    echo "$msg"
    echo $msg | logger
}


configure_buffer_pool() {
    local MYSQL_CONF=${1}
	TOTAL_MEM_BYTES=$(cat /proc/meminfo  | grep MemTotal | awk  '{print $2*1024}')
    GB_BYTES=$((1024*1024*1024))
    DB_MEM_PCT_FOR_BUFFER_POOL=75

	if [ $TOTAL_MEM_BYTES -le $((32*GB_BYTES)) ];then
		MEM_FOR_DB=$((4 * GB_BYTES))
	elif [ $TOTAL_MEM_BYTES -le $((64*GB_BYTES)) ];then
		MEM_FOR_DB=$((8*GB_BYTES))
    else
		MEM_FOR_DB=$((12*GB_BYTES)) # 12GB
    fi

    BUFFER_POOL_SIZE_MB=$(( (MEM_FOR_DB * DB_MEM_PCT_FOR_BUFFER_POOL) / (100*1024*1024) ))
	log_msg "Total Memory: $(( (TOTAL_MEM_BYTES)/(1024*1024) )) MB"
	log_msg "Changing Innodb buffer pool size to: ${BUFFER_POOL_SIZE_MB} MB"

	sudo sed -i 's/innodb_buffer_pool_size.*/innodb_buffer_pool_size = '$BUFFER_POOL_SIZE_MB'M/' $MYSQL_CONF
}
