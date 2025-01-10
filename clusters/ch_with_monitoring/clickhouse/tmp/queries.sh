#!/bin/bash

while true
do
    clickhouse-client -q "select count()
        from (select number as id from numbers(10000000, 100)) t1
        left join (select number as id from numbers(10000000)) t2 using (id)"
    sleep 1
done
