# Метрики и мониторинг, логирование

Профилирование может быть настроено как на уровне системы (вспомогательных вещей, ресурсов, потраченных на текущий запрос), так и на уровне  запроса в целом.

## Текстовый лог запроса

Логи клика могут быть достаточно сложными для понимания. Многие системы предлагают дополнительно парсить эти логи и выводитть их в качетсве каких то системных табличек или представлений. Здесь мы можем использовать system.error (будет отражать последнее состояние по текущим ошибкам напрямую из логов), также можем воспользоваться логами по запросу - system.query_log, а также логами по сессии.

На примере тестового датасета youtube:  
text_log сервера, в логе файлом или в логе таблицей, содержит по индентификатору запроса много полезной информации. Эту информацию мы можем выцепить из лога, написав в 5-10 строк какой нибудь парсер с использованием регулярок.
При использовании стандартного клиента, можно получить текстовый лог для конкретного запроса прямо в консоль клиента. в clickhouse-client: `SET send_logs_level='trace'; запрос`  

Пример парсера на питоне: (18 32 - 20 30)

Обычно используют либо МТ, либо FileLog движок, который позволяет подцепляться к логам данных, причем вне нашей системы, и их также разбирать. При этом здесь есть небольшой нюанс что логи нужно выполнять в определенном формате

У ДБивера был конкретный патч с неприятный нюансом. Там JDBC драйвер: оказалось что этот драйвер не имеет настройки session_id. А клик по session_id смотрит наше подключение и по ней понимает, может ли применить эту настройку. То есть настройка применяется, но так как она обновляется при буквально следующем же запросе - он эту настройку не видит!
```sql
SET send_logs_level='trace';
select 1;
/*
Query id: 9e5b2dcb-8988-496a-bc65-2d9dbb7803d2

[168909852ede] 2024.12.23 14:34:33.088020 [ 64 ] {9e5b2dcb-8988-496a-bc65-2d9dbb7803d2} <Debug> executeQuery: (from 127.0.0.1:43758) select 1; (stage: Complete)
[168909852ede] 2024.12.23 14:34:33.094094 [ 64 ] {9e5b2dcb-8988-496a-bc65-2d9dbb7803d2} <Trace> Planner: Query to stage Complete
[168909852ede] 2024.12.23 14:34:33.094518 [ 64 ] {9e5b2dcb-8988-496a-bc65-2d9dbb7803d2} <Trace> Planner: Query from stage FetchColumns to stage Complete
   ┌─1─┐
1. │ 1 │
   └───┘
[168909852ede] 2024.12.23 14:34:33.096329 [ 64 ] {9e5b2dcb-8988-496a-bc65-2d9dbb7803d2} <Debug> executeQuery: Read 1 rows, 1.00 B in 0.008413 sec., 118.86366337810531 rows/sec., 118.86 B/sec.
[168909852ede] 2024.12.23 14:34:33.096538 [ 64 ] {9e5b2dcb-8988-496a-bc65-2d9dbb7803d2} <Debug> TCPHandler: Processed in 0.010029958 sec.

1 row in set. Elapsed: 0.010 sec. 
*/
```
Увеличив уровень лога, мы можем увидеть информацию по стопам нашего запроса. Например `[168909852ede] 2024.12.23 14:34:33.094518 [ 64 ] {9e5b2dcb-8988-496a-bc65-2d9dbb7803d2} <Trace> Planner: Query from stage FetchColumns to stage Complete`:
- <Trace> - уровень, на котором мы выпустили соответствующий лог
- Planner - запуск планнера
- Query to stage Complete - взятие в работу нашего текущего запроса + статус
- Query from stage FetchColumns to stage Complete - указание что мы хотим вытащить из конкретной колонки + статус

`[168909852ede] 2024.12.23 14:34:33.096329 [ 64 ] {9e5b2dcb-8988-496a-bc65-2d9dbb7803d2} <Debug> executeQuery: Read 1 rows, 1.00 B in 0.008413 sec., 118.86366337810531 rows/sec., 118.86 B/sec.` - текущая скорость, загрузка. То есть некоторая статистическая информация, которая поможет нам.

Что мы хотим здесь получить с точки зрения оптимизации. Оптимизировать можно огромное количество различных вещей. Тут нам  дается много информации о том, как это сделать - и это все еще не explain план запроса! Ну и читаем последовательно, а не снизу вверх, как план запроса.

Бывает удобно указать `format Null` для запроса, если нас не интересует результат, а только причины почему запрос выполняется долго. Таким образом результат просто не выведется - просто увидим как запрос выполнился и какие задачи были поставлены для его выполнения
```sql
select 1 format Null
/*
[168909852ede] 2024.12.23 14:41:17.788282 [ 64 ] {1b604fed-da64-4eef-9106-5153171fba93} <Debug> executeQuery: (from 127.0.0.1:43758) select 1 format Null (stage: Complete)
[168909852ede] 2024.12.23 14:41:17.790744 [ 64 ] {1b604fed-da64-4eef-9106-5153171fba93} <Trace> Planner: Query to stage Complete
[168909852ede] 2024.12.23 14:41:17.791198 [ 64 ] {1b604fed-da64-4eef-9106-5153171fba93} <Trace> Planner: Query from stage FetchColumns to stage Complete
[168909852ede] 2024.12.23 14:41:17.794612 [ 64 ] {1b604fed-da64-4eef-9106-5153171fba93} <Debug> executeQuery: Read 1 rows, 1.00 B in 0.006473 sec., 154.4878727019929 rows/sec., 154.49 B/sec.
[168909852ede] 2024.12.23 14:41:17.794935 [ 64 ] {1b604fed-da64-4eef-9106-5153171fba93} <Debug> TCPHandler: Processed in 0.008908584 sec.
Ok.
*/
```

По оптимизации джоинов - есть [такая](https://raw.githubusercontent.com/ClickHouse/clickhouse-presentations/master/2024-meetup-stockholm-2/Robert_Schulze_Joins.pdf) статья, актуальна для версии 24.11+

### На примере тестового датасета youtube (из презы)

```bash
sudo apt-get install clickhouse-client
clickhouse-client --help  # и затем смотрим параметры подключения
```

Так выглядит полный лог уровня trace по запросу с count() за конкретный upload_date, являющийся основным ключом. (это по презе, но по практике было с другой таблицей)
```sql
-- создаем таблицу
DESCRIBE s3(
    'https://clickhouse-public-datasets.s3.amazonaws.com/youtube/original/files/*.zst',
    'JSONLines'
);
CREATE TABLE youtube
(
    `id` String,
    `fetch_date` DateTime,
    `upload_date_str` String,
    `upload_date` Date,
    `title` String,
    `uploader_id` String,
    `uploader` String,
    `uploader_sub_count` Int64,
    `is_age_limit` Bool,
    `view_count` Int64,
    `like_count` Int64,
    `dislike_count` Int64,
    `is_crawlable` Bool,
    `has_subtitles` Bool,
    `is_ads_enabled` Bool,
    `is_comments_enabled` Bool,
    `description` String,
    `rich_metadata` Array(Tuple(call String, content String, subtitle String, title String, url String)),
    `super_titles` Array(Tuple(text String, url String)),
    `uploader_badges` String,
    `video_badges` String
)
ENGINE = MergeTree
ORDER BY (uploader, upload_date);
INSERT INTO youtube
SETTINGS input_format_null_as_default = 1
SELECT
    id,
    parseDateTimeBestEffortUSOrZero(toString(fetch_date)) AS fetch_date,
    upload_date AS upload_date_str,
    toDate(parseDateTimeBestEffortUSOrZero(upload_date::String)) AS upload_date,
    ifNull(title, '') AS title,
    uploader_id,
    ifNull(uploader, '') AS uploader,
    uploader_sub_count,
    is_age_limit,
    view_count,
    like_count,
    dislike_count,
    is_crawlable,
    has_subtitles,
    is_ads_enabled,
    is_comments_enabled,
    ifNull(description, '') AS description,
    rich_metadata,
    super_titles,
    ifNull(uploader_badges, '') AS uploader_badges,
    ifNull(video_badges, '') AS video_badges
FROM s3(
    'https://clickhouse-public-datasets.s3.amazonaws.com/youtube/original/files/*.zst',
    'JSONLines'
);

select count()
from youtube
where upload_date = '2011-05-06'
format Null;
/*
[168909852ede] 2024.12.23 15:18:16.380353 [ 66 ] {9e56d960-dfd5-4902-a021-a75b21b8da2a} <Debug> executeQuery: (from 127.0.0.1:44070) select count() from system.youtube where upload_date = '2011-05-06' format Null; (stage: Complete)
[168909852ede] 2024.12.23 15:18:16.412086 [ 66 ] {9e56d960-dfd5-4902-a021-a75b21b8da2a} <Trace> Planner: Query to stage Complete
[168909852ede] 2024.12.23 15:18:16.420095 [ 66 ] {9e56d960-dfd5-4902-a021-a75b21b8da2a} <Trace> Planner: Query from stage FetchColumns to stage Complete
[168909852ede] 2024.12.23 15:18:16.459735 [ 66 ] {9e56d960-dfd5-4902-a021-a75b21b8da2a} <Trace> QueryPlanOptimizePrewhere: The min valid primary key position for moving to the tail of PREWHERE is -1
[168909852ede] 2024.12.23 15:18:16.465030 [ 66 ] {9e56d960-dfd5-4902-a021-a75b21b8da2a} <Trace> IInterpreterUnionOrSelectQuery: The new analyzer is enabled, but the old interpreter is used. It can be a bug, please report it. Will disable 'allow_experimental_analyzer' setting (for query: SELECT min(uploader), max(uploader), count() SETTINGS aggregate_functions_null_for_empty = false, transform_null_in = false, legacy_column_name_of_tuple_literal = false)
[168909852ede] 2024.12.23 15:18:16.470348 [ 66 ] {9e56d960-dfd5-4902-a021-a75b21b8da2a} <Debug> system.youtube (556c1f5b-7889-4212-bf3c-c0e7cec93011) (SelectExecutor): Key condition: (column 1 in [15100, 15100])
[168909852ede] 2024.12.23 15:18:16.471160 [ 66 ] {9e56d960-dfd5-4902-a021-a75b21b8da2a} <Trace> system.youtube (556c1f5b-7889-4212-bf3c-c0e7cec93011) (SelectExecutor): Filtering marks by primary and secondary keys
[168909852ede] 2024.12.23 15:18:16.473808 [ 888 ] {9e56d960-dfd5-4902-a021-a75b21b8da2a} <Trace> system.youtube (556c1f5b-7889-4212-bf3c-c0e7cec93011) (SelectExecutor): Used generic exclusion search with exact ranges over index for part all_2_2_0 with 57 steps
[168909852ede] 2024.12.23 15:18:16.481784 [ 888 ] {9e56d960-dfd5-4902-a021-a75b21b8da2a} <Trace> system.youtube (556c1f5b-7889-4212-bf3c-c0e7cec93011) (SelectExecutor): Used generic exclusion search with exact ranges over index for part all_3_3_0 with 56 steps
[168909852ede] 2024.12.23 15:18:16.473799 [ 881 ] {9e56d960-dfd5-4902-a021-a75b21b8da2a} <Trace> system.youtube (556c1f5b-7889-4212-bf3c-c0e7cec93011) (SelectExecutor): Used generic exclusion search with exact ranges over index for part all_1_1_0 with 57 steps
[168909852ede] 2024.12.23 15:18:16.486461 [ 800 ] {9e56d960-dfd5-4902-a021-a75b21b8da2a} <Trace> system.youtube (556c1f5b-7889-4212-bf3c-c0e7cec93011) (SelectExecutor): Used generic exclusion search with exact ranges over index for part all_4_4_0 with 50 steps
[168909852ede] 2024.12.23 15:18:16.489958 [ 888 ] {9e56d960-dfd5-4902-a021-a75b21b8da2a} <Trace> system.youtube (556c1f5b-7889-4212-bf3c-c0e7cec93011) (SelectExecutor): Used generic exclusion search with exact ranges over index for part all_6_6_0 with 55 steps
[168909852ede] 2024.12.23 15:18:16.491744 [ 888 ] {9e56d960-dfd5-4902-a021-a75b21b8da2a} <Trace> system.youtube (556c1f5b-7889-4212-bf3c-c0e7cec93011) (SelectExecutor): Used generic exclusion search with exact ranges over index for part all_7_7_0 with 51 steps
[168909852ede] 2024.12.23 15:18:16.492758 [ 800 ] {9e56d960-dfd5-4902-a021-a75b21b8da2a} <Trace> system.youtube (556c1f5b-7889-4212-bf3c-c0e7cec93011) (SelectExecutor): Used generic exclusion search with exact ranges over index for part all_8_8_0 with 57 steps
[168909852ede] 2024.12.23 15:18:16.492996 [ 715 ] {9e56d960-dfd5-4902-a021-a75b21b8da2a} <Trace> system.youtube (556c1f5b-7889-4212-bf3c-c0e7cec93011) (SelectExecutor): Used generic exclusion search with exact ranges over index for part all_5_5_0 with 58 steps
[168909852ede] 2024.12.23 15:18:16.495244 [ 800 ] {9e56d960-dfd5-4902-a021-a75b21b8da2a} <Trace> system.youtube (556c1f5b-7889-4212-bf3c-c0e7cec93011) (SelectExecutor): Used generic exclusion search with exact ranges over index for part all_9_9_0 with 57 steps
[168909852ede] 2024.12.23 15:18:16.495516 [ 800 ] {9e56d960-dfd5-4902-a021-a75b21b8da2a} <Trace> system.youtube (556c1f5b-7889-4212-bf3c-c0e7cec93011) (SelectExecutor): Used generic exclusion search with exact ranges over index for part all_11_11_0 with 54 steps
[168909852ede] 2024.12.23 15:18:16.496041 [ 800 ] {9e56d960-dfd5-4902-a021-a75b21b8da2a} <Trace> system.youtube (556c1f5b-7889-4212-bf3c-c0e7cec93011) (SelectExecutor): Used generic exclusion search with exact ranges over index for part all_12_12_0 with 57 steps
[168909852ede] 2024.12.23 15:18:16.496847 [ 888 ] {9e56d960-dfd5-4902-a021-a75b21b8da2a} <Trace> system.youtube (556c1f5b-7889-4212-bf3c-c0e7cec93011) (SelectExecutor): Used generic exclusion search with exact ranges over index for part all_10_10_0 with 56 steps
[168909852ede] 2024.12.23 15:18:16.498237 [ 66 ] {9e56d960-dfd5-4902-a021-a75b21b8da2a} <Debug> system.youtube (556c1f5b-7889-4212-bf3c-c0e7cec93011) (SelectExecutor): Selected 12/12 parts by partition key, 12 parts by primary key, 560/560 marks by primary key, 560 marks to read from 12 ranges
[168909852ede] 2024.12.23 15:18:16.498420 [ 66 ] {9e56d960-dfd5-4902-a021-a75b21b8da2a} <Trace> system.youtube (556c1f5b-7889-4212-bf3c-c0e7cec93011) (SelectExecutor): Spreading mark ranges among streams (default reading)
[168909852ede] 2024.12.23 15:18:16.502187 [ 66 ] {9e56d960-dfd5-4902-a021-a75b21b8da2a} <Debug> system.youtube (556c1f5b-7889-4212-bf3c-c0e7cec93011) (SelectExecutor): Reading approx. 4547424 rows with 4 streams
[168909852ede] 2024.12.23 15:18:16.504098 [ 66 ] {9e56d960-dfd5-4902-a021-a75b21b8da2a} <Trace> Aggregator: Compile expression count()() 0 
[168909852ede] 2024.12.23 15:18:16.882106 [ 723 ] {9e56d960-dfd5-4902-a021-a75b21b8da2a} <Trace> AggregatingTransform: Aggregating
[168909852ede] 2024.12.23 15:18:16.883179 [ 723 ] {9e56d960-dfd5-4902-a021-a75b21b8da2a} <Trace> Aggregator: Aggregation method: without_key
[168909852ede] 2024.12.23 15:18:18.646048 [ 723 ] {9e56d960-dfd5-4902-a021-a75b21b8da2a} <Trace> AggregatingTransform: Aggregating
[168909852ede] 2024.12.23 15:18:18.646335 [ 723 ] {9e56d960-dfd5-4902-a021-a75b21b8da2a} <Trace> Aggregator: Aggregation method: without_key
[168909852ede] 2024.12.23 15:18:21.154286 [ 723 ] {9e56d960-dfd5-4902-a021-a75b21b8da2a} <Trace> AggregatingTransform: Aggregating
[168909852ede] 2024.12.23 15:18:21.154486 [ 723 ] {9e56d960-dfd5-4902-a021-a75b21b8da2a} <Trace> Aggregator: Aggregation method: without_key
[168909852ede] 2024.12.23 15:18:21.295783 [ 723 ] {9e56d960-dfd5-4902-a021-a75b21b8da2a} <Trace> AggregatingTransform: Aggregated. 49 to 1 rows (from 0.00 B) in 4.574649293 sec. (10.711 rows/sec., 0.00 B/sec.)
[168909852ede] 2024.12.23 15:18:21.296025 [ 723 ] {9e56d960-dfd5-4902-a021-a75b21b8da2a} <Trace> Aggregator: Aggregation method: without_key
[168909852ede] 2024.12.23 15:18:21.296077 [ 723 ] {9e56d960-dfd5-4902-a021-a75b21b8da2a} <Trace> AggregatingTransform: Aggregated. 0 to 1 rows (from 0.00 B) in 4.574968793 sec. (0.000 rows/sec., 0.00 B/sec.)
[168909852ede] 2024.12.23 15:18:21.296169 [ 723 ] {9e56d960-dfd5-4902-a021-a75b21b8da2a} <Trace> AggregatingTransform: Aggregated. 152 to 1 rows (from 0.00 B) in 4.575083544 sec. (33.223 rows/sec., 0.00 B/sec.)
[168909852ede] 2024.12.23 15:18:21.296274 [ 723 ] {9e56d960-dfd5-4902-a021-a75b21b8da2a} <Trace> AggregatingTransform: Aggregated. 115 to 1 rows (from 0.00 B) in 4.575176169 sec. (25.136 rows/sec., 0.00 B/sec.)
[168909852ede] 2024.12.23 15:18:21.296311 [ 723 ] {9e56d960-dfd5-4902-a021-a75b21b8da2a} <Trace> Aggregator: Merging aggregated data
[168909852ede] 2024.12.23 15:18:21.297696 [ 723 ] {9e56d960-dfd5-4902-a021-a75b21b8da2a} <Trace> HashTablesStatistics: Statistics updated for key=11602579768081011284: new sum_of_sizes=4, median_size=1
[168909852ede] 2024.12.23 15:18:21.328777 [ 66 ] {9e56d960-dfd5-4902-a021-a75b21b8da2a} <Debug> executeQuery: Read 4547424 rows, 8.67 MiB in 4.948468 sec., 918955.9273698445 rows/sec., 1.75 MiB/sec.
[168909852ede] 2024.12.23 15:18:21.341315 [ 66 ] {9e56d960-dfd5-4902-a021-a75b21b8da2a} <Debug> MemoryTracker: Peak memory usage (for query): 964.81 KiB.
[168909852ede] 2024.12.23 15:18:21.341457 [ 66 ] {9e56d960-dfd5-4902-a021-a75b21b8da2a} <Debug> TCPHandler: Processed in 4.968015045 sec.
Ok.

0 rows in set. Elapsed: 4.952 sec. Processed 4.55 million rows, 9.09 MB (918.24 thousand rows/s., 1.84 MB/s.)
Peak memory usage: 964.81 KiB.
*/
```

Начальная стадия запроса: 
- принят на исполнение запрос
- оптимизатор запроса сдвинул выражение для основного ключа в PREWHERE
- проверены права доступа
- определили какие будем читать колонки

Работа с индексом: 
- преобразовано выражение из WHERE (PREWHERE) к выражению поиска по индексу
- используем стандартный алгоритм поиска по индексу для единственного подходящегоpart 
- отсеяли один диапазон в 393 засечки
- начали читать в 4 потока выбранные по индексу диапазоны (один найденный диапазон)

Выборка и аггрегация данных
- читаем диапазон в 4 потока
- аггрегируем полученные в каждом потоке данные
- выводим итоговые счетчики сколько потратили памяти и как быстро выполнили запрос

### На примере тестового датасета trips (из лекции)

```sql
CREATE TABLE trips (
    trip_id             UInt32,
    pickup_datetime     DateTime,
    dropoff_datetime    DateTime,
    pickup_longitude    Nullable(Float64),
    pickup_latitude     Nullable(Float64),
    dropoff_longitude   Nullable(Float64),
    dropoff_latitude    Nullable(Float64),
    passenger_count     UInt8,
    trip_distance       Float32,
    fare_amount         Float32,
    extra               Float32,
    tip_amount          Float32,
    tolls_amount        Float32,
    total_amount        Float32,
    payment_type        Enum('CSH' = 1, 'CRE' = 2, 'NOC' = 3, 'DIS' = 4, 'UNK' = 5),
    pickup_ntaname      LowCardinality(String),
    dropoff_ntaname     LowCardinality(String)
)
ENGINE = MergeTree
PRIMARY KEY (pickup_datetime, dropoff_datetime);

INSERT INTO trips
SELECT
    trip_id,
    pickup_datetime,
    dropoff_datetime,
    pickup_longitude,
    pickup_latitude,
    dropoff_longitude,
    dropoff_latitude,
    passenger_count,
    trip_distance,
    fare_amount,
    extra,
    tip_amount,
    tolls_amount,
    total_amount,
    payment_type,
    pickup_ntaname,
    dropoff_ntaname
FROM gcs(
    'https://storage.googleapis.com/clickhouse-public-datasets/nyc-taxi/trips_{0..2}.gz',
    'TabSeparatedWithNames'
);

select count() from trips where toDate(pickup_datetime) = '2015-07-01';
/*
[168909852ede] 2024.12.23 15:33:53.645138 [ 64 ] {4d2c16fc-87f3-423e-b4ce-b4e201a46c4c} <Debug> executeQuery: (from 127.0.0.1:43758) select count() from trips where toDate(pickup_datetime) = '2015-07-01'; (stage: Complete)
[168909852ede] 2024.12.23 15:33:53.646076 [ 64 ] {4d2c16fc-87f3-423e-b4ce-b4e201a46c4c} <Trace> Planner: Query to stage Complete
[168909852ede] 2024.12.23 15:33:53.646293 [ 64 ] {4d2c16fc-87f3-423e-b4ce-b4e201a46c4c} <Trace> Planner: Query from stage FetchColumns to stage Complete
[168909852ede] 2024.12.23 15:33:53.648318 [ 64 ] {4d2c16fc-87f3-423e-b4ce-b4e201a46c4c} <Trace> QueryPlanOptimizePrewhere: The min valid primary key position for moving to the tail of PREWHERE is 0
[168909852ede] 2024.12.23 15:33:53.648537 [ 64 ] {4d2c16fc-87f3-423e-b4ce-b4e201a46c4c} <Trace> IInterpreterUnionOrSelectQuery: The new analyzer is enabled, but the old interpreter is used. It can be a bug, please report it. Will disable 'allow_experimental_analyzer' setting (for query: SELECT min(pickup_datetime), max(pickup_datetime), count() SETTINGS aggregate_functions_null_for_empty = false, transform_null_in = false, legacy_column_name_of_tuple_literal = false)
[168909852ede] 2024.12.23 15:33:53.649344 [ 64 ] {4d2c16fc-87f3-423e-b4ce-b4e201a46c4c} <Debug> default.trips (aa2ba48c-0e91-439e-83e0-0390a77b51aa) (SelectExecutor): Key condition: (toDate(column 0) in [16617, 16617])
[168909852ede] 2024.12.23 15:33:53.649439 [ 64 ] {4d2c16fc-87f3-423e-b4ce-b4e201a46c4c} <Trace> default.trips (aa2ba48c-0e91-439e-83e0-0390a77b51aa) (SelectExecutor): Filtering marks by primary and secondary keys
[168909852ede] 2024.12.23 15:33:53.650467 [ 735 ] {4d2c16fc-87f3-423e-b4ce-b4e201a46c4c} <Trace> default.trips (aa2ba48c-0e91-439e-83e0-0390a77b51aa) (SelectExecutor): Used generic exclusion search with exact ranges over index for part all_1_1_0 with 20 steps
[168909852ede] 2024.12.23 15:33:53.650623 [ 721 ] {4d2c16fc-87f3-423e-b4ce-b4e201a46c4c} <Trace> default.trips (aa2ba48c-0e91-439e-83e0-0390a77b51aa) (SelectExecutor): Used generic exclusion search with exact ranges over index for part all_3_3_0 with 1 steps
[168909852ede] 2024.12.23 15:33:53.650761 [ 832 ] {4d2c16fc-87f3-423e-b4ce-b4e201a46c4c} <Trace> default.trips (aa2ba48c-0e91-439e-83e0-0390a77b51aa) (SelectExecutor): Used generic exclusion search with exact ranges over index for part all_2_2_0 with 1 steps
[168909852ede] 2024.12.23 15:33:53.651601 [ 64 ] {4d2c16fc-87f3-423e-b4ce-b4e201a46c4c} <Debug> default.trips (aa2ba48c-0e91-439e-83e0-0390a77b51aa) (SelectExecutor): Selected 3/3 parts by partition key, 1 parts by primary key, 3/367 marks by primary key, 1 marks to read from 1 ranges
[168909852ede] 2024.12.23 15:33:53.651631 [ 64 ] {4d2c16fc-87f3-423e-b4ce-b4e201a46c4c} <Trace> default.trips (aa2ba48c-0e91-439e-83e0-0390a77b51aa) (SelectExecutor): Spreading mark ranges among streams (default reading)
[168909852ede] 2024.12.23 15:33:53.651705 [ 64 ] {4d2c16fc-87f3-423e-b4ce-b4e201a46c4c} <Trace> default.trips (aa2ba48c-0e91-439e-83e0-0390a77b51aa) (SelectExecutor): Reading 1 ranges in order from part all_1_1_0, approx. 8192 rows starting from 16384
[168909852ede] 2024.12.23 15:33:53.653202 [ 843 ] {4d2c16fc-87f3-423e-b4ce-b4e201a46c4c} <Trace> AggregatingTransform: Aggregating
[168909852ede] 2024.12.23 15:33:53.653302 [ 843 ] {4d2c16fc-87f3-423e-b4ce-b4e201a46c4c} <Trace> Aggregator: Aggregation method: without_key
[168909852ede] 2024.12.23 15:33:53.653939 [ 843 ] {4d2c16fc-87f3-423e-b4ce-b4e201a46c4c} <Trace> AggregatingTransform: Aggregated. 1 to 1 rows (from 16.00 B) in 0.001523916 sec. (656.204 rows/sec., 10.25 KiB/sec.)
[168909852ede] 2024.12.23 15:33:53.664563 [ 860 ] {4d2c16fc-87f3-423e-b4ce-b4e201a46c4c} <Trace> AggregatingTransform: Aggregating
[168909852ede] 2024.12.23 15:33:53.664669 [ 860 ] {4d2c16fc-87f3-423e-b4ce-b4e201a46c4c} <Trace> Aggregator: Aggregation method: without_key
[168909852ede] 2024.12.23 15:33:53.664979 [ 860 ] {4d2c16fc-87f3-423e-b4ce-b4e201a46c4c} <Trace> AggregatingTransform: Aggregated. 2844 to 1 rows (from 0.00 B) in 0.012987917 sec. (218972.758 rows/sec., 0.00 B/sec.)
[168909852ede] 2024.12.23 15:33:53.665003 [ 860 ] {4d2c16fc-87f3-423e-b4ce-b4e201a46c4c} <Trace> Aggregator: Merging aggregated data
[168909852ede] 2024.12.23 15:33:53.665058 [ 860 ] {4d2c16fc-87f3-423e-b4ce-b4e201a46c4c} <Trace> HashTablesStatistics: Statistics updated for key=15437283326351392866: new sum_of_sizes=2, median_size=1
   ┌─count()─┐
1. │   19228 │
   └─────────┘
[168909852ede] 2024.12.23 15:33:53.670260 [ 64 ] {4d2c16fc-87f3-423e-b4ce-b4e201a46c4c} <Debug> executeQuery: Read 8193 rows, 32.02 KiB in 0.025166 sec., 325558.2929349122 rows/sec., 1.24 MiB/sec.
[168909852ede] 2024.12.23 15:33:53.671003 [ 64 ] {4d2c16fc-87f3-423e-b4ce-b4e201a46c4c} <Debug> MemoryTracker: Peak memory usage (for query): 465.81 KiB.
[168909852ede] 2024.12.23 15:33:53.671650 [ 64 ] {4d2c16fc-87f3-423e-b4ce-b4e201a46c4c} <Debug> TCPHandler: Processed in 0.027072125 sec.

1 row in set. Elapsed: 0.025 sec. Processed 8.19 thousand rows, 32.78 KB (328.77 thousand rows/s., 1.32 MB/s.)
Peak memory usage: 465.81 KiB.
*/
```
- executeQuery - запускает выполнение запроса (здесь выведется сам запрос)
- QueryPlanOptimizePrewhere - идет оптимизация prewhere, здесь у клика есть некоторая особенность. Это дополнительный синтаксис предикатов, но в целом, если следить за статистикой - этот prewhere сильно не меняет нашу работу и чаще всего мы получаем тот же самый запрос поскольку оптимизатор вывенет в prewhere что нибудь (`The min valid primary key position for moving to the tail of PREWHERE is 0`)
- дальше идет поиск по нашему ключу (`<Debug> default.trips (aa2ba48c-0e91-439e-83e0-0390a77b51aa) (SelectExecutor): Key condition: (toDate(column 0) in [16617, 16617])`) - значение '2015-07-01' было преобразовано в числовое 16617
- дальше идет фильтрация по ключам `(SelectExecutor): Filtering marks by primary and secondary keys` (в нашем случае ничего не меняло)
- дальше указывается, на какие парты обращает внимание ( `(SelectExecutor): Used generic exclusion search with exact ranges over index for part all_1_1_0 with 20 steps` )
- в итоге мы выбралди следующие парты и засечки `(SelectExecutor): Selected 3/3 parts by partition key, 1 parts by primary key, 3/367 marks by primary key, 1 marks to read from 1 ranges`
- разделяем на потоки и читаем `(SelectExecutor): Spreading mark ranges among streams (default reading)`, количество потоков выбирается исходя из количества ядер.
- затем, после того как мы выбрали всю информацию - пошли в работу агрегаторы `AggregatingTransform: Aggregating`
- в конечном итоге сделан мердж `Aggregator: Merging aggregated data`

### На что обращать внимание?

- **метки времени** - у каждой строки лога есть метка времени, это позволяет выяснить сколько ClickHouse затратил времени на какую операцию, например, в текущем примере:
1. с 13:51:38.649646 по 13:51:38.651022, т.е. 0.001376 сек мы занимались только интерпретацией запроса. когда это происходит слишком долго, значит запрос тяжелый для парсера и следует переписать длинные выражения `WHERE column IN (.....)` в _external_data передаваемый с запросом, или использовать временные таблицы. 
2. с 13:51:38.651022 по 13:51:38.654973, т.е. 0.003951 сек происходил поиск по индексу, если индексы слишком тяжелые (например вторичные set(0) ), стоит пересмотреть имеющиеся индексы 
3. аналогично со стадией аггрегации запроса
- **использование индексов** - обратная история к п.2., когда индексов нет совсем или они не отсеивают достаточно узкие диапазоны строка «Selected 1/1 parts by partition key, 1 parts by primary key, 393/393 marks by primary key, 393 marks to read from 1 ranges» или её отсутствие если индекса нет, позволит выявить фуллскан-обращения к таблице. Но индексы это не панацея! Плюс если индекс не используется - то лучше его удалить.
- **медленные реплики** - в строке лога есть индентификатор хостнейма «[3cfe83966013]» в текущем примере, это хостнейм докер-контейнера. при обращении к Distributed-таблицам, будет приноситься лог с реплик, можно сравнивать метки времени с разных реплик. Не забываем что в любом случае имеет место передача данных по сети и сетка - не самое хорошее место для большого объема информации.

По оптимизации. 

Мы можем оптимизировать 2 штуки - хранение данных и работу с данными. 
- С точки зрения хранения данных в кликхаусе все более-менее хорошо - с точки зрения распределить на отдельные шарды, сжать данными, подключить сжатие на уровне колонок.
- с точки зхрения работы с данными - основные моменты это джоины (мы должны подставлять минимально возможное количество строк) и подзапросы. В in стараемя очень большие значения не включать. При необходимости создать витрину - лучше предподготовить данные на уровне временных таблиц (помним про уровень сессии!) либо буферных таблиц.

## Встроенный профайлер

Представляет собой встроенный сэмплирующий профайлер который внутри ClickHouse снимает трейсы со всех тредов запросов. Под семплированием понимается запуск профайлера раз в N период времени. Периоды времени задаются через settings default-пользователя:
```sql
SET query_profiler_cpu_time_period_ns = 1000000; /* каждые N наносекунд процессорного времени*/
SET query_profiler_real_time_period_ns = 1000000; /* каждые N наносекунд реального времени*/
-- (+ memory_profiler в новых версиях, см. memory_profiler_% в system.settings)
```
Работа профайлера требует объявления секции <trace_log> в конфигурации (по умолчанию она не объявлена). В system.trace_log сохраняются трейсы снимаемые профайлером. Для сбора и чтения trace_log должен быть установлен пакет clickhouse-common-static-dbg  
Внимание! Снятие трейсов - CPU-интенсивная операция; частый профайлинг, даже на дефолтных настройках на нагруженном прод-инстансе, приведет к большому потреблению CPU и как следствие деградации скорости запросов.
```sql
select * from system.trace_log limit 1\G;
/*
Row 1:
──────
hostname:                bee87d3f7fba
event_date:              2024-12-23
event_time:              2024-12-23 18:41:33
event_time_microseconds: 2024-12-23 18:41:33.334961
timestamp_ns:            1734979293334961469
revision:                54493
trace_type:              Memory
thread_id:               710
query_id:                
trace:                   [195946224,195946076,195689804,195681360,196194028,273559168,248412560,248413304,273544304,273543236,273502508,273570456,274805128,273774556,276179724,282052216,281295424,281294584,281292516,279019184,278976212,278974740,260293384,196922356,196601436,196628060,281473711445540,281473710753324]
size:                    4728259
ptr:                     0
event:                   
increment:               0

1 row in set. Elapsed: 0.021 sec. 
*/
```

Есть полезный материал от Миловидова, ссылка на [презу](https://presentations.clickhouse.com/yatalks_2019_moscow/)

Как читать trace_log
1) Включить набор необходимых фукнций `SET allow_introspection_functions = 1`
2) Распарсить колонку trace функциями `demangle(addressToSymbol(trace))` для каждого trace в колонке trace, (там массив на каждый тред по трейсу), например так:
```sql
SET allow_introspection_functions = 1;
-- так мы можем посмотреть операции, которые были здесь заиспользованы и увидеть логи выполнения текущих операций
select arrayStringConcat(arrayMap(x -> demangle(addressToSymbol(x)), trace), '\n')
from system.trace_log
limit 1\G;
/*
Row 1:
──────
arrayStringConcat(arrayMap(lambda(tuple(x), demangle(addressToSymbol(x))), trace), '\n'): MemoryTracker::allocImpl(long, bool, MemoryTracker*, double)
MemoryTracker::allocImpl(long, bool, MemoryTracker*, double)
CurrentMemoryTracker::alloc(long)
Allocator<false, false>::alloc(unsigned long, unsigned long)
DB::Memory<Allocator<false, false>>::alloc(unsigned long)
void std::__1::__function::__policy_invoker<void (DB::ISerialization::SubstreamPath const&)>::__call_impl<std::__1::__function::__default_alloc_func<DB::MergeTreeDataPartWriterCompact::addStreams(DB::NameAndTypePair const&, COW<DB::IColumn>::immutable_ptr<DB::IColumn> const&, std::__1::shared_ptr<DB::IAST> const&)::$_0, void (DB::ISerialization::SubstreamPath const&)>>(std::__1::__function::__policy_storage const*, DB::ISerialization::SubstreamPath const&)
DB::ISerialization::enumerateStreams(DB::ISerialization::EnumerateStreamsSettings&, std::__1::function<void (DB::ISerialization::SubstreamPath const&)> const&, DB::ISerialization::SubstreamData const&) const
DB::ISerialization::enumerateStreams(std::__1::function<void (DB::ISerialization::SubstreamPath const&)> const&, std::__1::shared_ptr<DB::IDataType const> const&, COW<DB::IColumn>::immutable_ptr<DB::IColumn> const&) const
DB::MergeTreeDataPartWriterCompact::addStreams(DB::NameAndTypePair const&, COW<DB::IColumn>::immutable_ptr<DB::IColumn> const&, std::__1::shared_ptr<DB::IAST> const&)
DB::MergeTreeDataPartWriterCompact::MergeTreeDataPartWriterCompact(std::__1::basic_string<char, std::__1::char_traits<char>, std::__1::allocator<char>> const&, std::__1::basic_string<char, std::__1::char_traits<char>, std::__1::allocator<char>> const&, std::__1::unordered_map<std::__1::basic_string<char, std::__1::char_traits<char>, std::__1::allocator<char>>, std::__1::shared_ptr<DB::ISerialization const>, std::__1::hash<std::__1::basic_string<char, std::__1::char_traits<char>, std::__1::allocator<char>>>, std::__1::equal_to<std::__1::basic_string<char, std::__1::char_traits<char>, std::__1::allocator<char>>>, std::__1::allocator<std::__1::pair<std::__1::basic_string<char, std::__1::char_traits<char>, std::__1::allocator<char>> const, std::__1::shared_ptr<DB::ISerialization const>>>> const&, std::__1::shared_ptr<DB::IDataPartStorage>, DB::MergeTreeIndexGranularityInfo const&, std::__1::shared_ptr<DB::MergeTreeSettings const> const&, DB::NamesAndTypesList const&, std::__1::shared_ptr<DB::StorageInMemoryMetadata const> const&, std::__1::shared_ptr<DB::VirtualColumnsDescription const> const&, std::__1::vector<std::__1::shared_ptr<DB::IMergeTreeIndex const>, std::__1::allocator<std::__1::shared_ptr<DB::IMergeTreeIndex const>>> const&, std::__1::vector<std::__1::shared_ptr<DB::ColumnPartStatistics>, std::__1::allocator<std::__1::shared_ptr<DB::ColumnPartStatistics>>> const&, std::__1::basic_string<char, std::__1::char_traits<char>, std::__1::allocator<char>> const&, std::__1::shared_ptr<DB::ICompressionCodec> const&, DB::MergeTreeWriterSettings const&, DB::MergeTreeIndexGranularity const&)
DB::createMergeTreeDataPartCompactWriter(std::__1::basic_string<char, std::__1::char_traits<char>, std::__1::allocator<char>> const&, std::__1::basic_string<char, std::__1::char_traits<char>, std::__1::allocator<char>> const&, std::__1::unordered_map<std::__1::basic_string<char, std::__1::char_traits<char>, std::__1::allocator<char>>, std::__1::shared_ptr<DB::ISerialization const>, std::__1::hash<std::__1::basic_string<char, std::__1::char_traits<char>, std::__1::allocator<char>>>, std::__1::equal_to<std::__1::basic_string<char, std::__1::char_traits<char>, std::__1::allocator<char>>>, std::__1::allocator<std::__1::pair<std::__1::basic_string<char, std::__1::char_traits<char>, std::__1::allocator<char>> const, std::__1::shared_ptr<DB::ISerialization const>>>> const&, std::__1::shared_ptr<DB::IDataPartStorage>, DB::MergeTreeIndexGranularityInfo const&, std::__1::shared_ptr<DB::MergeTreeSettings const> const&, DB::NamesAndTypesList const&, std::__1::unordered_map<std::__1::basic_string<char, std::__1::char_traits<char>, std::__1::allocator<char>>, unsigned long, std::__1::hash<std::__1::basic_string<char, std::__1::char_traits<char>, std::__1::allocator<char>>>, std::__1::equal_to<std::__1::basic_string<char, std::__1::char_traits<char>, std::__1::allocator<char>>>, std::__1::allocator<std::__1::pair<std::__1::basic_string<char, std::__1::char_traits<char>, std::__1::allocator<char>> const, unsigned long>>> const&, std::__1::shared_ptr<DB::StorageInMemoryMetadata const> const&, std::__1::shared_ptr<DB::VirtualColumnsDescription const> const&, std::__1::vector<std::__1::shared_ptr<DB::IMergeTreeIndex const>, std::__1::allocator<std::__1::shared_ptr<DB::IMergeTreeIndex const>>> const&, std::__1::vector<std::__1::shared_ptr<DB::ColumnPartStatistics>, std::__1::allocator<std::__1::shared_ptr<DB::ColumnPartStatistics>>> const&, std::__1::basic_string<char, std::__1::char_traits<char>, std::__1::allocator<char>> const&, std::__1::shared_ptr<DB::ICompressionCodec> const&, DB::MergeTreeWriterSettings const&, DB::MergeTreeIndexGranularity const&)
DB::createMergeTreeDataPartWriter(DB::MergeTreeDataPartType, std::__1::basic_string<char, std::__1::char_traits<char>, std::__1::allocator<char>> const&, std::__1::basic_string<char, std::__1::char_traits<char>, std::__1::allocator<char>> const&, std::__1::unordered_map<std::__1::basic_string<char, std::__1::char_traits<char>, std::__1::allocator<char>>, std::__1::shared_ptr<DB::ISerialization const>, std::__1::hash<std::__1::basic_string<char, std::__1::char_traits<char>, std::__1::allocator<char>>>, std::__1::equal_to<std::__1::basic_string<char, std::__1::char_traits<char>, std::__1::allocator<char>>>, std::__1::allocator<std::__1::pair<std::__1::basic_string<char, std::__1::char_traits<char>, std::__1::allocator<char>> const, std::__1::shared_ptr<DB::ISerialization const>>>> const&, std::__1::shared_ptr<DB::IDataPartStorage>, DB::MergeTreeIndexGranularityInfo const&, std::__1::shared_ptr<DB::MergeTreeSettings const> const&, DB::NamesAndTypesList const&, std::__1::unordered_map<std::__1::basic_string<char, std::__1::char_traits<char>, std::__1::allocator<char>>, unsigned long, std::__1::hash<std::__1::basic_string<char, std::__1::char_traits<char>, std::__1::allocator<char>>>, std::__1::equal_to<std::__1::basic_string<char, std::__1::char_traits<char>, std::__1::allocator<char>>>, std::__1::allocator<std::__1::pair<std::__1::basic_string<char, std::__1::char_traits<char>, std::__1::allocator<char>> const, unsigned long>>> const&, std::__1::shared_ptr<DB::StorageInMemoryMetadata const> const&, std::__1::shared_ptr<DB::VirtualColumnsDescription const> const&, std::__1::vector<std::__1::shared_ptr<DB::IMergeTreeIndex const>, std::__1::allocator<std::__1::shared_ptr<DB::IMergeTreeIndex const>>> const&, std::__1::vector<std::__1::shared_ptr<DB::ColumnPartStatistics>, std::__1::allocator<std::__1::shared_ptr<DB::ColumnPartStatistics>>> const&, std::__1::basic_string<char, std::__1::char_traits<char>, std::__1::allocator<char>> const&, std::__1::shared_ptr<DB::ICompressionCodec> const&, DB::MergeTreeWriterSettings const&, DB::MergeTreeIndexGranularity const&)
DB::MergedBlockOutputStream::MergedBlockOutputStream(std::__1::shared_ptr<DB::IMergeTreeDataPart> const&, std::__1::shared_ptr<DB::StorageInMemoryMetadata const> const&, DB::NamesAndTypesList const&, std::__1::vector<std::__1::shared_ptr<DB::IMergeTreeIndex const>, std::__1::allocator<std::__1::shared_ptr<DB::IMergeTreeIndex const>>> const&, std::__1::vector<std::__1::shared_ptr<DB::ColumnPartStatistics>, std::__1::allocator<std::__1::shared_ptr<DB::ColumnPartStatistics>>> const&, std::__1::shared_ptr<DB::ICompressionCodec>, DB::TransactionID, bool, bool, DB::WriteSettings const&, DB::MergeTreeIndexGranularity const&)
DB::MergeTreeDataWriter::writeTempPartImpl(DB::BlockWithPartition&, std::__1::shared_ptr<DB::StorageInMemoryMetadata const> const&, std::__1::shared_ptr<DB::Context const>, long, bool)
DB::MergeTreeSink::consume(DB::Chunk&)
DB::SinkToStorage::onConsume(DB::Chunk)
void std::__1::__function::__policy_invoker<void ()>::__call_impl<std::__1::__function::__default_alloc_func<DB::ExceptionKeepingTransform::work()::$_1, void ()>>(std::__1::__function::__policy_storage const*)
DB::runStep(std::__1::function<void ()>, DB::ThreadStatus*, std::__1::atomic<unsigned long>*)
DB::ExceptionKeepingTransform::work()
DB::ExecutionThreadContext::executeTask()
DB::PipelineExecutor::executeStepImpl(unsigned long, std::__1::atomic<bool>*)
DB::PipelineExecutor::executeStep(std::__1::atomic<bool>*)
DB::SystemLog<DB::AsynchronousMetricLogElement>::savingThreadFunction()
void std::__1::__function::__policy_invoker<void ()>::__call_impl<std::__1::__function::__default_alloc_func<ThreadFromGlobalPoolImpl<true, true>::ThreadFromGlobalPoolImpl<DB::SystemLogBase<DB::AsynchronousMetricLogElement>::startup()::'lambda'()>(DB::SystemLogBase<DB::AsynchronousMetricLogElement>::startup()::'lambda'()&&)::'lambda'(), void ()>>(std::__1::__function::__policy_storage const*)
ThreadPoolImpl<std::__1::thread>::ThreadFromThreadPool::worker()
void* std::__1::__thread_proxy[abi:v15007]<std::__1::tuple<std::__1::unique_ptr<std::__1::__thread_struct, std::__1::default_delete<std::__1::__thread_struct>>, void (ThreadPoolImpl<std::__1::thread>::ThreadFromThreadPool::*)(), ThreadPoolImpl<std::__1::thread>::ThreadFromThreadPool*>>(void*)
start_thread


1 row in set. Elapsed: 0.015 sec. 
*/
```

Что делать с трейсами дальше?
1) Это семплирующий профайлер, если выставить достаточно часто, можно в пределах одного запроса выявить наиболее часто встречающиеся в трейсе строки, это и будет самым долгим местом выполнения запроса. 
2) То же самое по группе однотипных запросов. 
3) Можно матчить query_id и thread_id на query_log и thread_log
4) Можно использовать сторонние инструменты для анализа трейса, например в виде flamegraph: https://github.com/Slach/clickhouse-flamegraph или визуализировать самостоятельно в любом удобном формате (личное предпочтение преподавателя: `cat собранное-из-лога|sort|uniq -c` в bash)

Но тут мы можем только отобразить частоту. Самое частое не всегда самое долгое!

На профилирование будет требоватиься достаточно большое количество системных ресурсов! Клик достаточно ревнивый (как и другие субд) к ресурсам, на которых он находится. Помним что профилирпование - достаточно интенсивная операция. Частое профилирование даже на дефолтных настройках приводит к нагрузке по cpu и деградации скорости запросов. Поэтому такое профилирование стоит либо отключать по умолчанию, либо включать на меньшее количество наносекунд.

Можно отдельно включить профилирование cpu `set enable_cpu_profiler=1;`, можно включить профайлер по памяти `set memory_profiler_step=1024*1024`. Настройки по профайлерам можно найти и в дальнейшем использовать для того, что нам нужно. Чаще всего профилируем cpu на выполнение, память на выполнение и застраченные операции в рамках выполнения того или иного запроса.

## План запроса

Тут икспэин не настолько же полноценен, насколько он полноценен в базах вроде постгреса. Тем не менее мы можем получить полезную информацию для нашего плана запроса. Читаем снизу вверху - как и в постгресе.

Синтаксис `EXPLAIN [AST | SYNTAX | PLAN | PIPELINE] [setting = value, ...] SELECT ... [FORMAT...]`
Пример:
- EXPLAIN AST - EXPLAIN возвращает разбор синтаксиса запроса на выполняемые действия (Abstract SyntaxTree)
- EXPLAIN SYNTAX - Обрабатывает запрос встроенным оптмизиатором ClickHouse. Самый частый кейс - сдвигает выражение по ПК в PREWHERE. 
- EXPLAIN ESTIMATE - Показывает сколько будет прочитано строк, гранул, партов. К сожалению не показывает ожидаемоевремя.
- EXPLAIN PLAN - То же, что и AST без указания аргументов. Через аргументы можно достать информациюобиспользовании индексов

```sql
select count() from trips where toDate(pickup_datetime) = '2015-07-01';

explain 
select count() from trips where toDate(pickup_datetime) = '2015-07-01';
/*
   ┌─explain────────────────────────────────────────────────────────────┐
1. │ Expression ((Project names + Projection))                          │
2. │   AggregatingProjection                                            │
3. │     Expression (Before GROUP BY)                                   │
4. │       Filter ((WHERE + Change column names to column identifiers)) │
5. │         ReadFromMergeTree (default.trips)                          │
6. │     ReadFromPreparedSource (Optimized trivial count)               │
   └────────────────────────────────────────────────────────────────────┘

6 rows in set. Elapsed: 0.006 sec. 
*/

explain ast
select count() from trips where toDate(pickup_datetime) = '2015-07-01';
/*
    ┌─explain─────────────────────────────────────┐
 1. │ SelectWithUnionQuery (children 1)           │
 2. │  ExpressionList (children 1)                │
 3. │   SelectQuery (children 3)                  │
 4. │    ExpressionList (children 1)              │
 5. │     Function count (children 1)             │
 6. │      ExpressionList                         │
 7. │    TablesInSelectQuery (children 1)         │
 8. │     TablesInSelectQueryElement (children 1) │
 9. │      TableExpression (children 1)           │
10. │       TableIdentifier trips                 │
11. │    Function equals (children 1)             │
12. │     ExpressionList (children 2)             │
13. │      Function toDate (children 1)           │
14. │       ExpressionList (children 1)           │
15. │        Identifier pickup_datetime           │
16. │      Literal '2015-07-01'                   │
    └─────────────────────────────────────────────┘

16 rows in set. Elapsed: 0.007 sec. 
*/
```

В целом по оптимизации:
- работа с индексами
- изменение структуры данных (изменение объема данных, который мы используем)
- переписывание запросов для испорльзования меньшего объема данных
- можем также посмотреть некоторые тяжелые запросы и так называемый анализ соединений

## Домашнее задание

1) Выполнить запрос с WHERE не использующим ПК. Выполнить запрос с WHERE использующим ПК. Сравнить text_log запросов, предоставить строки лога относящиеся к пробегу основного индекса. 
2) Показать тот же индекс через EXPLAIN