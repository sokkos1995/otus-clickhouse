# Шардирование и распределенные запросы

## Шардирование

Шардирование - расширение
доступного места под данные, за счет
разселения данных на несколько
экземпляров приложения с
независмым хранением. Как правило за счет размещения
экземпляров приложения на разные
сервера.

Engine=Distributed
Виртуальная таблица выступающая в роли «агрегирующего прокси»: - Принимает запросы
- Повторяет запросы в таблицы с данными согласно топологии кластера
- Объединяет результаты с шардов
- Возвращает результат объединения
Создается:
CREATE TABLE имя таблицы ( колонки ) Engine=Distributed( аргументы)

Engine=Distributed аргументы
Distributed( cluster_name, database, table, sharding_key )
cluster_name - топология описаная в конфигурации в секции <remote_servers>каксекция<cluster_name>, можно выбрать любое имя, можно описывать несколько топологийииспользовать с разными Distributed-таблицами
database, table - таблица, в которую будет повторен запрос в одну реплику каждогошардаsharding_key - необязательный для SELECT-запросов к таблице параметр, можнонеуказывать, необходим для INSERT-запросов. Должен быть числовымтипом, можноиспользовать хеширующие функции от других колонок. Нарезает данные нашардыпономеру шарда получаемого как остаток от деления ключа шардирования наколичествошардов

Engine=Distributed описание топологии кластера
Выполняется через конфигурационный файл:
<remote_servers>
<cluster_name>
<shard>
<replica> <host>ch-server-1.zone</host> <port>9000</port> </replica>
... replica 2 ...
... replica 3 ... </shard>
... one more shard ...
... more shards ... </cluster_name>
... more clusters ... </remote_servers>
на серверах с Distributed-таблицами

Доступы
Если Distributed-таблица расположена не на том же сервере (на отдельном), чтоитаблицасданными, дублировать пользователей на сервера с данными не обязательно. Distributed-таблица породит запросы в реплики с пользователем default, илисуказаным<user>пользователь</user> в секции <replica>...</replica> конфигурации кластера. Однако для row-policy всё ещё необходимо наличие пользователя, он передаетсякакinitital_user на реплики и проверяется по row-policy (подробнее в модуле «Управлениересурсами», лекции «RBAC контроль доступа, квоты и ограничения»).

Удаление и добавление шардов/реплик
Достигается редактированием конфигурационного файла. На всех серверах с Distributed-таблицами. В конфугирационный файл добавляются/удаляются готовые к эскплуатациисервераснужным набором таблиц, подготовленные заранее. Важно, чтобы до раскатки конфигурации, были заранее созданы целевые таблицы, ккоторым будет обращаться Distributed-таблица, ClickHouse не создаст их самостоятельно.В противном случае будет получен DB::Exception: нет таблицы на remote репликаназапроскDistributed таблице.

Замена отказавшей реплики
1) в system.replicas живой реплики подсмотреть имя мертвой реплики и списоктаблиц2) запрос SYSTEM DROP REPLICA ‘отказавшая реплика’ FROM table таблица, длякаждойтаблицы
3) введение в эксплуатацию новой реплики на замену старой, создание на нейвсехтаблиц.4) дождаться репликации таблиц
5) заменить реплику в remote_servers

## Распределенныезапросы

GLOBAL IN/JOIN
Запрос вида
SELECT ... FROM distributed_table WHERE IN ( SELECT ... )
Будет передан на каждый шард как
SELECT ... FROM local_table WHERE IN ( SELECT ... )
Где local_table это таблица заданная в аргументах distributed_table. Таким образом, например при выполнении на кластере из 100 шардов, подзапрос( SELECT ... ) будет выполнен 100 раз. Модификатор GLOBAL меняет это поведение
GLOBAL IN ( подзапрос ) сначала выполнит подзапрос, потом передаст егорезультатнавсешарды как временную таблицу переиспользуемую для основного запроса. Аналогично работает с JOIN.

distributed_product_mode
Настройка сервера, меняет поведение по умолчанию для IN/JOIN запросов, следующимобразом:
deny - по умолчанию, возвращает DB::EXCEPTION при попытке использоватьGLOBAL- запросы
local - всё ещё запращает GLOBAL, но в подзапросах отправляемых на шардызаменяетdistributed-таблицы на их local-таблицы
global - заменяет IN/JOIN на GLOBAL IN/JOIN
allow - разрешает пользователю выбирать самостоятельно

prefer_global_in_and_join
при использовании distributed_product_mode=global не учитываются таблицысEngineдлядоступа к внешним ресурсам, например Engine=mysql. prefer_global_in_and_join=1 включает такое же поведение для таких Engine. prefer_global_in_and_join=0 по умолчанию, отключено

использование нескольких реплик одного шарда для запросаВключается ручкой max_parallel_replicas>1
Требует наличия ключа семплирования “SAMPLE BY ключ” на MergeTree таблицах. Ускоряет выполнения запроса, разбивая его на N реплик, используя ключ семплированияSAMPLE 1/N OFFSET (N-1)/N
Важно!
Если таблицы не имеют ключа семплирования, будет получен некорректныйрезультат(выборка будет осуществлена по задублированным данным).

## Особенностишардирования

Взаимосвязь с репликацией
Взаимосвязи нет. В описании топологии кластера вы можете назначать сервера репликами, агруппысерверов шардами, но ClickHouse никак не будет проверять что ваша топологиясоответствует заданной при создании таблиц репликации. Набор взаимореплицирумых таблиц шарда, это самостоятельный набор таблиц, никакнезависящий от такого же набора для другого шарда. Для того, чтобы на разных шардах эти наборы были самостоятельными, удобноиспользовать макрос <shard> в *keeper-пути при создании таблицы, для уникализацииэтогопути для шарда.

Очередь Distributed таблиц
Под капотом очень не оптимальный недокументированный одноименныйформатDistributed,на него нарезается приходящая в Engine=Distributed таблицы вставка. Может бытьузкимместом и причиной поддержки топологии кластера в клиентах, с собственнойреализациейшардирования, записью в обход Distributed-таблиц. Отслеживать очередь можно в таблице system.distribution_queue, важно рисоватьметрикина основании этой таблицы.

Не досхлопывать результаты аггрегации с реплик
Некоторые запросы, выполняющие аггрегацию по ключу шардирования, приусловиичтоданные действительно шардированы по этому ключу, не требуют дополнительнойаггрегации. Можно выставить настройку distributed_group_by_no_merge=1, значительноускоривскоростьтаких запросов. Например, uniq() в группировке по ключу, при условии что на разных шардах нетповторяющихся между шардами ключей, даст корректный результат даже припропускеоперации дополнительной аггрегации. Если такие повторения между шардами есть, вернется несколько результатовпокаждомутакому повторению (по результату с шарда).

Решардинг
Его НЕТ. Предлагаемый в документации способ - создание нового кластера и переливкаданныхприпомощи clickhouse-copier, под капотом которого конструктор “INSERT SELECT” запросовизконфига утилиты. Альтернативы:
1)
- копирование таблиц как “CREATE TABLE AS”+”ALTER TABLE ATTACHPARTITIONFROM”- дублирование данных по репликации на новые шарды
- спил лишнего через “ALTER TABLE DELETE WHERE”
- переключение на новые таблицы
2) на скриптах DETACH PART/PARTITION, перенос в новое место, ATTACH3) переливка inplace через INSERT SELECT

А как шардируются в yandex?
- Много маленьких кластеров используя макрос shard, сверху них distributedтаблицы, кластера называются layer. - Общий кластер используя макрос layer, ещё distributed таблицы сверху distributedтаблицуровня layer. - в такой концепции становится применима переливка layer-ов утилитой clickhouse-copier

## Примеры

Distributed и Local таблицы
CREATE TABLE default.events (
date Date MATERIALIZED toDate(timestamp), ts DateTime, event_id UInt64, host IPv4, response_time_ms UInt32, headers Map(String, String), another_column String, one_more_column Array(String)
)
ENGINE=Distributed(cluster_name,default.events
_local)

CREATE TABLE default.events_local (
date Date MATERIALIZEDtoDate(timestamp),ts DateTime, event_id UInt64, host IPv4, response_time_ms UInt32, headers Map(String, String), another_column String, one_more_column Array(String)
)
ENGINE=ReplicatedMergeTree(‘/ch/{database}/{table}/{shard}’,’{replica}’)
PARTITION BY date
ORDER BY (date,event_id)
SAMPLE by event_id

<remote_servers> 2 шарда 2 реплики, 1 шард 4 реплики, 3 шарда3реплики<remote_servers>
<!-- 2 shards 2 replicas -->
<2sh2rep>
<shard>
<replica> <host>ch-server-1.zone</host> <port>9000</port> </replica>
<replica> <host>ch-server-2.zone</host> <port>9000</port> </replica>
</shard>
<shard>
<replica> <host>ch-server-3.zone</host> <port>9000</port> </replica>
<replica> <host>ch-server-4.zone</host> <port>9000</port> </replica>
</shard>
</2sh2rep>

<!-- 1 shards 4 replicas -->
<1sh4rep>
<shard>
<replica> <host>ch-server-1.zone</host> <port>9000</port> </replica>
<replica> <host>ch-server-2.zone</host> <port>9000</port> </replica>
<replica> <host>ch-server-3.zone</host> <port>9000</port> </replica>
<replica> <host>ch-server-4.zone</host> <port>9000</port> </replica>
</shard>
</1sh4rep>

<!-- 3 shards 3 replicas -->
<3sh3rep>
<shard>
<replica> <host>ch-server-1.zone</host> <port>9000</port> </replica>
<replica> <host>ch-server-2.zone</host> <port>9000</port> </replica>
<replica> <host>ch-server-3.zone</host> <port>9000</port> </replica>
</shard>
<shard>
<replica> <host>ch-server-4.zone</host> <port>9000</port> </replica>
<replica> <host>ch-server-5.zone</host> <port>9000</port> </replica>
<replica> <host>ch-server-6.zone</host> <port>9000</port> </replica>
</shard>
<shard>
<replica> <host>ch-server-7.zone</host> <port>9000</port> </replica>
<replica> <host>ch-server-8.zone</host> <port>9000</port> </replica>
<replica> <host>ch-server-9.zone</host> <port>9000</port> </replica>
</shard>
</3sh3rep>
</remote_servers>

bash-скрипт для создания таблиц как на другой реплике
#!/bin/bash
source_replica=один хост
dest_replica=другой хост
for database in $(
clickhouse-client --host “${source_replica}” -q “show databases”
) ; do
clickhouse-client --host “${dest_replica}” -q “create database if not exists ${database}”
for table in $(
clickhouse-client --host “${source_replica}” -d “${database}” -q “show tables”
); do
table_sql=”$(
clickhouse-client --host “${source_replica}” -d “${database}” -q “show create table ${table} format TSVRaw”)”clickhouse-client --host “${dest_replica}” -n -d “${database}” <<<”${table_sql}” done
done

## Homework

1) запустить N экземпляров clickhouse-server
2) описать несколько (2 или более) топологий объединения экземпляров вшардывконфигурации clickhouse на одном из экземпляров. Фактор репликации и количествошардов можно выбрать на свой вкус. 3) предоставить xml-секцию <remote_servers> для проверки текстовымфайлом4) создать DISTRIBUTED-таблицу на каждую из топологий. Можно использоватьсистемнуютаблицу system.one, содержащую одну колонку dummy типа UInt8, в качествелокальнойтаблицы. или 5) предоставить вывод запроса SELECT *,hostName(),_shard_numfromdistributed-tableдля каждой distributed-таблицы, можно добавить group by и limit по вкусу еслитестовыхданных много. или 5) предоставить SELECT * FROM system.clusters; SHOW CREATE TABLE длякаждойDistributed-таблицы. п.5 можно любой из на ваш выбор из «или», можно оба