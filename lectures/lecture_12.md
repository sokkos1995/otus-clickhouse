# сессия Q&A

Первые 53 минуты - эифрлоу и клик, можно скипать

54:00 - про low cardinality, materialized, 

```sql
create table test (
    a String,
    b LowCardinality(String)  -- сжимаем по принципу обычного словарного кодирования (максимально близкий аналог енуму)
)
engine=Memory;

create table test2 (
    id String,
    mdate Date MATERIALIZED today()  -- передаем выражение (можно от других столбцов, можно вычислять, типа toStartOfMonth())
)
engine=Memory;
insert into test2 (id) values ('a');
select id, mdate from test2;
-- при вставке для каждой строки выполнится определенное выражение
-- важный комментарий - в материализованную колонку вставлять нельзя!
-- при этом по умолчанию в селект звездочку материализованные колонки не включаются!
-- для этого есть опция:
set asterisk_include_materialized_columns=1;
-- алиасы тоже по умолчанию не включаются
alter table test2 add column myAlias String ALIAS concat(id, '-a');
select *, myAlias from test2;
-- еще есть дефолт - объявляется как материалайзд, но с отличием
-- в дефолт не хранится никаких данных и туда можно писать!
create table test3 (
    id String,
    mdate Date DEFAULT today()  
)
engine=Memory;
insert into test3 (id) values ('a');
alter table test3 modify column mdate default today() - 20;
--  в некоторых версиях значение менялось
-- классически отличия такие - в дефолт можно вставлять, в материалайзд нет. Еще дефолт может менять значение при альтер тейбл

-- еще есть кодеки сжатия
alter table test3 add column str String codec(ZSTD);
-- delta - для таймсерии (особенно при правильной вставке, когда изменение идет достаточно плавно - хранить эффективно так как хранится разница)
-- ZSTD - чтобы у нас быстрее осуществлялась вставка (дешевый алгоритм на сжатие, но менее эффективный по хранению. Не рекомендуется - в клике достаточно эффективный кодек по умолчанию. Нужно понимать что мы хотим - выиграть на скорости вставки, место на диске (в gzip можно указать уровень сжатия) )
-- лучше оставаться на дефолтных кодеках сжатия!
-- за разжатие мы платим процессором (использованием проца)

-- налл типов стараемся избегать!

-- по order by:
create table timeseries (
    date Date MATERIALIZED toDate(timestamp),
    timestamp DateTime,
    metric String,
    value UInt64
)
Engine=MergeTree
order by () 
-- общая рекомендация - собирать ключ в порядке возрастания кардинальности
```

1:28:00 - по системным таблицам (полезно быть с ними знакомыми)
```sql
-- в привычных базах данных есть information_schema
use INFORMATION_SCHEMA;
show tables;
-- на самом деле они являются вьюхами, которые берут данные из таблиц кликхауса
show create table COLUMNS;
-- сделано для совместимости с мускулом и прочим

-- здесь можно найти текущие настройки сервера
use system;
select * from settings
-- where changed
;

-- настройки для мердж три таблиц можно поменять в xml
-- <merge_tree> ... </merge_tree>
select * from merge_tree_settings;
-- из наиболее часто практикуемых - ограничение скорости репликации
-- (их потом перенесли в настройки пользователя из merge_tree_settings)
SELECT *
FROM merge_tree_settings
WHERE name LIKE '%bandwidth%';
-- max_replicated_fetches_network_bandwidth
-- max_replicated_sends_network_bandwidth
-- достаточно часто используется эта ручка для уменьшения пропускной способности. Дело в том что если между датацентрами ограниченный аплинк, а мы разнесли кликхаус по разных серверам - мы можем, засетапив еще одну реплику, взять и забить весь аплинк. Поэтому максимальную пропускную способность можно ограничить на стороне кликхауса.

-- еще одна полезная настройка
SELECT name, value
FROM merge_tree_settings
WHERE name LIKE '%dedup%';
/*
┌─name──────────────────────────────────────────────────────┬─value──┐
│ non_replicated_deduplication_window                       │ 0      │
│ replicated_deduplication_window                           │ 1000   │
│ replicated_deduplication_window_seconds                   │ 604800 │
│ replicated_deduplication_window_for_async_inserts         │ 10000  │
│ replicated_deduplication_window_seconds_for_async_inserts │ 604800 │
└───────────────────────────────────────────────────────────┴────────┘

5 rows in set. Elapsed: 0.002 sec. 
*/
-- когда мы вставляем инсерт, у нас образуется блок, образуется парт. Кликхаус помнит последние 1000 (раньше 100) хэшсум наших вставленных блоков. Если писатель у нас по какой то причине отвалился и не понял что он вставил (поскольку вставка в клик может быть достаточно увесистая) - при перезаливке, если мы попадем ровно в те же данные, так же отсортированные, когда он снова начнет их нарезать - он увидит что такая уже сумма есть и вставлять их не будет. Это защита от вставки дубликатов 
-- если мы действительно хотим вставлять одни и те же данные - то эту штуку нужно выкрутить.

-- здесь же лежат наши лимиты на максимальную задержку при вставке
SELECT
    name,
    value
FROM merge_tree_settings
WHERE name LIKE '%insert%'
/*
┌─name──────────────────────────────────────────────────────┬─value──┐
│ fsync_after_insert                                        │ 0      │
│ parts_to_delay_insert                                     │ 1000   │
│ inactive_parts_to_delay_insert                            │ 0      │
│ parts_to_throw_insert                                     │ 3000   │
│ inactive_parts_to_throw_insert                            │ 0      │
│ max_delay_to_insert                                       │ 1      │
│ min_delay_to_insert_ms                                    │ 10     │
│ async_insert                                              │ 0      │
│ replicated_deduplication_window_for_async_inserts         │ 10000  │
│ replicated_deduplication_window_seconds_for_async_inserts │ 604800 │
│ in_memory_parts_insert_sync                               │ 0      │
└───────────────────────────────────────────────────────────┴────────┘

11 rows in set. Elapsed: 0.012 sec. 
*/
-- parts_to_delay_insert - опсле того как мы вставим в одну партицию тысячу партишн ключей (когда подробится на много партов), у нас включится задержка связанная с тме что кликхаус не может перемерджить (то есть мы занялиь мелкой вставкой)
-- parts_to_throw_insert - когда мы превысич это значение - у нас выпадет ошибка TOO MANY PARTS и вставляться вообще не будет, пока кликхаус под собой не перемеджит.

-- по таблице system.replicas
SHOW CREATE TABLE system.replicas
FORMAT TSVRaw;
/*
CREATE TABLE system.replicas
(
    `database` String,
    `table` String,
    `engine` String,
    `is_leader` UInt8,
    `can_become_leader` UInt8,
    `is_readonly` UInt8,
    `is_session_expired` UInt8,
    `future_parts` UInt32,
    `parts_to_check` UInt32,
    `zookeeper_name` String,
    `zookeeper_path` String,
    `replica_name` String,
    `replica_path` String,
    `columns_version` Int32,
    `queue_size` UInt32,
    `inserts_in_queue` UInt32,
    `merges_in_queue` UInt32,
    `part_mutations_in_queue` UInt32,
    `queue_oldest_time` DateTime,
    `inserts_oldest_time` DateTime,
    `merges_oldest_time` DateTime,
    `part_mutations_oldest_time` DateTime,
    `oldest_part_to_get` String,
    `oldest_part_to_merge_to` String,
    `oldest_part_to_mutate_to` String,
    `log_max_index` UInt64,
    `log_pointer` UInt64,
    `last_queue_update` DateTime,
    `absolute_delay` UInt64,
    `total_replicas` UInt8,
    `active_replicas` UInt8,
    `lost_part_count` UInt64,
    `last_queue_update_exception` String,
    `zookeeper_exception` String,
    `replica_is_active` Map(String, UInt8)
)
ENGINE = SystemReplicas
COMMENT 'SYSTEM TABLE is built on the fly.'
*/
-- здесь у нас есть absolute_delay (абсолютная задержка), total_replicas (сколько всего реплик у таблицы) и прочую инфу о состоянии репликации таблиц.


-- еще более удобная табличка для анализа состояния репликации - system.replication_queue
show create table system.replication_queue format TSVRaw;
/*
CREATE TABLE system.replication_queue
(
    `database` String,
    `table` String,
    `replica_name` String,
    `position` UInt32,
    `node_name` String,
    `type` String,
    `create_time` DateTime,
    `required_quorum` UInt32,
    `source_replica` String,
    `new_part_name` String,
    `parts_to_merge` Array(String),
    `is_detach` UInt8,
    `is_currently_executing` UInt8,
    `num_tries` UInt32,
    `last_exception` String,
    `last_exception_time` DateTime,
    `last_attempt_time` DateTime,
    `num_postponed` UInt32,
    `postpone_reason` String,
    `last_postpone_time` DateTime,
    `merge_type` String
)
ENGINE = SystemReplicationQueue
COMMENT 'SYSTEM TABLE is built on the fly.'
*/
-- здесь можно посмотреть текущее состояние репликации, какие то ошибки по репликации (num_tries, last_exception)
```

1:47:00-1:51:00 немного про дистрибьютед (как данные лежат в файловой систмеме, точнее какие имена у директорий (раньше было по айпи, теперь по днс имени))

К чему может привести высококардинальное поле в ключе партиционирования (например, `PARTITION BY (project,data)`) - приведет к тому, что у нас не будут между собой объединяться куски данных с разным значением ключа партиционирования. если у нас таких project 100500 и в каждом совсем по чуть чуть данных, то у нас данные не будут объединяться в принципе, то есть не будет эффективно строиться вокруг них разряженный индекс, то есть не будут они эффективно сжиматься, то есть скорость выборки будет у нас значительно падать, а зукипер будет переполняться все большим количеством метаинформации (на больших объемах данных это станет проблемой, тк зукипер не масштабирается на запись, только на чтение)
```sql
-- по удалению
create table data2
( 
    project UInt64,
    date Date,
    data String
)
Engine=MergeTree
PARTITION BY (project, data)
order by data;
alter table data2 delete where data like '%7%';
-- Подводный камень удаления наших данных в кликхаусе в том, что поскольку у нас строки расположены гранулами, пойти и отредактироваться какую то гранулу - это значит по факту вмешаться в наш ключик. Посколько мы сортировались по праймари ключу - то нам придется построит весь наш ключ заново. Поэтому в кликхаусе вот такая операция (удалить какуцю то одну строку) - приведет к изменению вообще всех данных! Поэтому чтобы более точечно заниматься удалением - можно удалить в какой то партиции или вообще удалить партицию целиком.
-- поэтому желательно согласовывать - да, мы можем удалять данные, но такие операции не могут делаться чаще чем раз в месяц/день, и такая операция будет стоить столько, сколько будет стоить переписать одну партицию. Также желательно не делать несколько таких операций за раз (не выполнять мутации параллельно) - можно повредить данные.
```

2:00:00 - про добавление реплики в кластер

Кликхаус работает с партами и мартициями на хардлинках. То есть добавить в таблицу те же самые данные будет стоить столько же, сколько прохардлинкать их все (а не скопировать). Поэтому при помощи манипуляций с партициями мы можем быстро перекинуть данные:
```sql
create table orig_replicated as orig engine=ReplicatedMergeTree Order by a;
alter table orig_replicated attach partition 'all' from orig;
exchange tables orig_replicated and orig;
```
Операция происходит на хардлинках, поэтому она происчходит быстро и дешево. При этом, когда мы аттачим партицию в нашу уже реплицируемую таблицу - то она у нас пропишется полностью в зукипере

Роль зукипера - именно в хранении наших партов.
```sql
select *
from system.parts
where table = 'orig'
format Vertical;
-- пока у нас нереплицируемый движок - зукипер нам совершенно не нужен. В тот момент когда мы хотим уже отказоустойчивый сэтап - тогда нам нужно ин формацию о партах хранить в зукипере чтобы в случае создания/добавления еще одной репликиможно было как то синхронизировать информацию о партах. Кроме того, у нас в мерджах используются номера блоков(напр, all_1_1_0)(это является уникальным ключом для парта). Этот уникальный ключ должен быть уникальным в пределах всего репликасета. Поэтому зукипер обеспечивает еще и общий инкремент блоков среди всего репликасета для этой таблицы. Кроме того, в зукипере есть еще наш replication queue. Когда мы говорим `alter table add column` - то это событие добавляется в очередь репликации, реплики перекладывают себе эти события в свои пути для репликации и их выполняют (точнее, инкрементируют счетчик)
-- крому того, зукипер участвует в запросах `on cluster`. В кликхаусе есть такая настройка как distributed_ddl. Мы туда пишем путь в зукипере. Как раз через этот путь в зукипере будут распространяться запросы on cluster
-- еще зукипер можно использовать для подстановок в конфигурации
-- кроме того, clickhouse-copier использует зукипер
```

Кликхаус можно делать на той же машине, что и кликхаус (а можно и отдельно)

