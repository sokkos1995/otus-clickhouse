drop database if exists streams;
drop database if exists raw;
drop database if exists parsed;
drop database if exists to_kafka;

create database streams;
create database raw;
create database parsed;
create database to_kafka;

CREATE TABLE streams.sensor_data
(
    `message` String
)
ENGINE = Kafka
SETTINGS kafka_broker_list = 'kafka1:9092',
         kafka_topic_list = 'sensor_data',
         kafka_format = 'JSONAsString',
         kafka_group_name = 'ch_consumer'
;

create table if not exists raw.sensor_data_raw
(
    message          String,
    _topic           LowCardinality(String),
    _offset          UInt64,
    _timestamp_ms    DateTime64,
    _partition       UInt8,
    _row_created     DateTime64(3) default now64() comment 'Дата и время записи в БД'
)
engine = MergeTree 
ORDER BY _timestamp_ms
comment 'Сырые данные из кафки, обогащенные метаданными';

CREATE MATERIALIZED VIEW streams.sensor_data_raw_mv
    TO raw.sensor_data_raw
AS
SELECT message,
       _topic,
       _offset,
       _timestamp_ms,
       _partition,
       now64() AS _row_created
FROM streams.sensor_data;

CREATE TABLE parsed.sensor_data (
    sensor_id   UInt32,
    temperature Float,
    humidity    Float,
    `timestamp` UInt64
)
ENGINE = MergeTree()
ORDER BY sensor_id
comment 'Распаршенные данные из кафки';

CREATE MATERIALIZED VIEW raw.sensor_data_raw_mv
    TO parsed.sensor_data
AS
SELECT JSONExtractInt(message, 'sensor_id') AS sensor_id,
       JSONExtractFloat(message, 'temperature') AS temperature,
       JSONExtractFloat(message, 'humidity') AS humidity,
       JSONExtractInt(message, 'timestamp') AS timestamp
FROM raw.sensor_data_raw;

CREATE TABLE to_kafka.sensor_data_queue (
    sensor_id   UInt32,
    temperature Float,
    humidity    Float,
    `timestamp` UInt64
)
ENGINE = Kafka('kafka1:9092', 'sensor_data_from_ch', 'clickhouse_out', 'JSONEachRow') settings kafka_thread_per_consumer = 0, kafka_num_consumers = 1
comment 'очередь к кафку';

CREATE MATERIALIZED VIEW parsed.sensor_data_mv 
    TO to_kafka.sensor_data_queue
AS
SELECT sensor_id, temperature, humidity, timestamp
FROM parsed.sensor_data
FORMAT JsonEachRow;