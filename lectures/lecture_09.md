# Другие движки

Engine - это то как структура будет храниться на диске и то, как структура будет храниться и обрабатываться в памяти. И, собственно, как к ней будут строиться запросы различного характера (ддл, дмл).

## Движки TinyLog, Log, StripeLog

Это базовые таблички, которые предназначены когда нам нужно создавать сразу миллион таблиц с небольшими объемами данных для каких то сэмпловых задач (временные, промежуточные данные, которые нам нужно быстро сохранить)

Основные особенности семейства *Log
- Основной сценарий использования - временные, промежуточные данные: пишется в много таблиц, а в таблицах немного записей (до 1 млн), записи читается из таблиц целиком
- Запись блокирует запись и чтение (чтение не блокирует другие чтения, то есть куча пользователей может читать параллельно)
- Мутации не поддерживается.
- Индексы не поддерживается.
- Дозапись в конец файла.
- Не атомарно. Может быть повреждение данных при сбоях во время записи
- Могут хранить данные в HDFS или S3

TinyLog (редко используется)
- Самый простой движок
- Каждый столбец хранится в отдельном файле (как и в Log)
- Не поддерживает многопоточного чтения (в отличие от Log и StripeLog) зато записи при чтении отсортированы в порядке вставки

Log
- Расширяет возможности TinyLog многопоточным чтением. Реализуется с помощье файла засечек Засечки пишутся на каждый блок данных и содержат смещение: в этом смезении мы можем понять, с какого места нужно читать файл, чтобы пропустить заданное количество строк.

StripeLog
- Хранит все столбцы в одном файле (не wide, а compact)
  - data.bin — файл с данными.
  - index.mrk — файл с метками. Метки содержат смещения для каждого столбца каждого вставленного блока данных.
- при INSERT добавляет блок данных в конец файла таблицы, записывая столбцы один за другим.

```sql
DROP TABLE IF EXISTS log_tbl;
DROP TABLE IF EXISTS stripe_log_tbl;
DROP TABLE IF EXISTS tiny_log_tbl;

CREATE TABLE log_tbl (number UInt64) ENGINE = Log;
INSERT INTO log_tbl SELECT number FROM numbers(10);

-- в случае StripeLog сразу создаем как вставку
CREATE TABLE stripe_log_tbl ENGINE = StripeLog AS
	SELECT number AS x FROM numbers(10);

INSERT INTO stripe_log_tbl SELECT number FROM numbers(100);

CREATE TABLE tiny_log_tbl (A UInt8) ENGINE = TinyLog;
INSERT INTO tiny_log_tbl SELECT number FROM numbers(10);

select name, data_paths from system.tables
where name in ('log_tbl', 'stripe_log_tbl', 'tiny_log_tbl')
/*
Row 1:
──────
name:       log_tbl
data_paths: ['/var/lib/clickhouse/store/0e1/0e1ebfcd-2a22-429d-a673-21e75f52008e/']

Row 2:
──────
name:       stripe_log_tbl
data_paths: ['/var/lib/clickhouse/store/b3d/b3d9db7b-2b0e-4a29-bdbe-88086405f45c/']

Row 3:
──────
name:       tiny_log_tbl
data_paths: ['/var/lib/clickhouse/store/cc7/cc76214e-3162-4227-942c-ab8a706ab56e/']
*/

-- Посмотрим на их структуру:
-- $ ls /var/lib/clickhouse/store/0e1/0e1ebfcd-2a22-429d-a673-21e75f52008e/
-- __marks.mrk  number.bin   sizes.json
```

Эти таблицы не реплицируются. Это именно временные таблицы для небольших дел.

Этимология (лог) никак не связана с логами! Для хранения логов лучше всего МТ, особенно когда логи структурированы хоть как то.

## Buffer (16:00)

- предназначен для буферизации данных в памяти
  - для ускорения вставки в другуе! таблицу (то есть мы создаем таблицу Buffer для вставки в МТ)
  - но и сюда рекомендуется также вставлять блоками (хотя бы по 10 записей)
- При чтении из буферной таблицы, чтение происходит также и из целевой таблицы
- при разнице структур столбцов в целевой и буферной таблице будут вставлены только данные совпадаещих столбцов, типы данных у столбцов тоже должны совпадать (иначе INSERT завершится ошибкой)
- Можно указать пустые кавычки вместо целевой таблицы, тогда у вас будет просто буфер с периодической очисткой

```sql
drop table if exists mt_log_table;
drop table if exists buffer_tbl;

create table mt_log_table (
  id UInt64,
  log String
)
ENGINE = MergeTree()
ORDER BY id;

-- создадим буффер с такой же структурой как и у МТ
create table buffer_tbl
(
	id UInt64,
  log String
)
Engine=Buffer(currentDatabase(), mt_log_table,  -- указывает, буффером для чего мы являемся
    /* num_layers= */ 	1,
    /* min_time= */   	10,			
    /* max_time= */   	86400,
    /* min_rows= */   	10000,
    /* max_rows= */    100000,
    /* min_bytes= */  	0, 
    /* max_bytes= */ 	8192,
    /* flush_time= */ 	86400,
    /* flush_rows= */ 	500,
    /* flush_bytes= */	1024
);

-- делаем вставки в буффер
insert into buffer_tbl VALUES (1, 'log 1');
insert into buffer_tbl VALUES (2, 'log 2');
insert into buffer_tbl VALUES (3, 'log 3');
insert into buffer_tbl VALUES (4, 'log 4');
select * from mt_log_table;  -- 0 rows in set. Elapsed: 0.005 sec.
select * from buffer_tbl;  -- 4 rows in set. Elapsed: 0.013 sec. 

insert into mt_log_table VALUES (5, 'log 5');
select * from buffer_tbl;
-- после выставки мы видим эту запись в buffer_tbl! При этом в основной таблице только 1 запись
/*
   ┌─id─┬─log───┐
1. │  1 │ log 1 │
2. │  2 │ log 2 │
3. │  3 │ log 3 │
4. │  4 │ log 4 │
   └────┴───────┘
   ┌─id─┬─log───┐
5. │  5 │ log 5 │
   └────┴───────┘
5 rows in set. Elapsed: 0.008 sec. 
*/

-- забьем буффер данными
insert into buffer_tbl select number, concat('log ',number) from numbers(10000);
-- мы видим что в буффер у нас все не влезло, что то перешло в основную таблицу
select * from mt_log_table;  -- 10001 rows in set
-- при этом в буферной таблице будет 10005 записей
```

Буферизатор - это такой внутренний кэш на стороне кликхауса, чтобы вставлять массово, а не по одной строке. С ним мы уменьшаем количество слияний на стороне МТ (копит операции вставки и скором вставлет). Буффер используют достаточно часто. Досаточно старый движок - когда в клике были проблемы, это достаточно сильно выручало. Сейчас есть более продвинутые механизмы (асинхронная вставка)

Разберем параметры:
- `num_layers—` уровень параллелизма (Кол-во независимых буферов. Рекомендуемое значение — 16)
- Данные сбрасывается из буфера и записывается в таблицу назначения (если выполнены все min-условия или хотя бы одно max-условие)
- `min_time`, `max_time` — условие на время в секундах от момента первой записи в буфер.
- `min_rows`, `max_rows` — условие на количество строк в буфере.
- `min_bytes`, `max_bytes` — условие на количество байт в буфере.
- Условия для сброса данных учитывается отдельно для каждого из буферов

Недостатки:
- FINAL и SAMPLE не учитывает данные в буфере
- блокировка одного из буферов при вставке (может влиять на скорость)чтения
- Сброс данных в порядке, отличном от ставки (негативный эффект на CollapsingMergeTree (нерегулируемый порядок вставки) и реплицируемые таблицы)

Альтернатива движку Buffer: async_insert
- async_insert = 1 – вклечить асинхронные вставки (по умолчание: 0) (можно выставить в сеттинге МТ таблицы). Это некий встроенный буффер, который неявный, никак не определен и работает внутри самого кликхауса.
- async_insert_threads - число потоков для фоновой обработки и вставки данных (по умолчание: 16) (аналог буфферных лэйеров)
- wait_for_async_insert = 0/1 - ожидать или нет записи данных в таблицу (бывают случаи, когда вроде асинхронную вставку включили, но фактически она не идет. Дело обычно в этом или следующем параметре)
- wait_for_async_insert_timeout - время ожидания в секундах, выделяемое для обработки асинхронной вставки. 0 — ожидание отклечено.

Мало включить асинхронную вставку - нужно еще понять что вставка закончилась или где то продолжается и так далее

Сейчас идет плавный переход к асинхронным вставкам, буффер выбирают для прозрачности

```sql
-- Посмотрим сеттинг
select * from system.merge_tree_settings where name like 'async_insert' format Vertical; 
/*
Row 1:
──────
name:        async_insert
value:       0
changed:     0
description: If true, data from INSERT query is stored in queue and later flushed to table in background.
min:         ᴺᵁᴸᴸ
max:         ᴺᵁᴸᴸ
readonly:    0
type:        Bool
is_obsolete: 0

1 row in set. Elapsed: 0.019 sec. 
*/

drop table if exists mt_log_table_async;

create table mt_log_table_async (
  id UInt64,
  log String
)
ENGINE = MergeTree()
ORDER BY id
SETTINGS async_insert = 1;

insert into mt_log_table_async select number, concat('log ',number) from numbers(3);
insert into mt_log_table_async select number*10, concat('log ',number*10) from numbers(3);
insert into mt_log_table_async select number*11, concat('log ',number*11) from numbers(3);

select * from mt_log_table_async;  -- все быстро вставилось
```

## Движок Join (33:00)

Join в кликхаусе - это плохо. ПОэтому есть некоторое облегчение для использования джоинов, особенно когда мы пользуемся чем то типа справочников или словарей (то есть когда нам нужно по айдишнику сделать какое то разименование, А НЕ КОГДА МЫ ДЖОИНИМ 2 ОГРОМНЫЕ ТАБЛИЦЫ). КОгда мы говорим про простые джоины, у нас есть специальный движок Join, который сильно облегчает операции:
- предназначен для предварительной подготовки данных для использования в операциях JOIN.
- Таблица используется в правой части секции JOIN или в функции joinGet ()
- Данные всегда в ОЗУ
- Данные хранятся на диске (опция persistent) (при аварийной остановке данные могут быть повреждены)
- Поддерживается DELETE мутации
- Нельзя использовать в GLOBAL JOIN (опция для дистрибьютед (шардированные) таблицы, там совсем иное поведение джоина)
- Не поддерживается сэмплирование
- Не поддерживается индексы и репликация

Параметры движка
- join_strictness – строгость JOIN (ANY , ALL)
- join_type – тип JOIN (INNER, LEFT, RIGHT, FULL, CROSS)
- k1[, k2, ...] – клечевые столбцы секции USING с которыми выполняется операция JOIN.

!!!! Параметры join_strictness и join_type должны быть такими же как и в той операции JOIN, в которой таблица будет использоваться. Если параметры не совпадает, ClickHouse не генерирует исклечение и может возвращать неверные данные

- persistent – хранить ли данные на диске
- join_use_nulls чем заполнять пустые ячейки полученных в ходе соединения таблиц (0 - значения по умолчание, 1 - NULL)
- max_rows_in_join – ограничивает на кол-во строк в хэш таблице используемой при соединении 2х таблиц. По умолчание 0.
- max_bytes_in_join - ограничивает на кол-во байт в хэш таблице используемой при соединении 2х таблиц. По умолчание 0.
- join_overflow_mode – когда достигнуто ограничение по кол-ву байт или строк, этот параметр определяет действие при переполнении.
  - По умолчание THROW - остановить запрос и прервать операцие.
  - Значение BREAK - прерывает операцие без исклечения.
- join_any_take_last_row – определяет какие строки присоединять при совпадении (0 - первая найденная в правой таблице, 1 – последняя найденная в правой таблице)

```sql
drop table if exists main_data;
drop table if exists desc_data;

/*
основные данные (чисто айдишник)
*/
CREATE TABLE main_data
(
    id UInt32,
    desc_id UInt32
)
ENGINE = TinyLog;
/*
справочник, в котором будет описание данного айдишника
*/
CREATE TABLE desc_data (
    desc_id UInt32,
    desc String
)
engine = Join(ANY, INNER , desc_id);

INSERT INTO main_data VALUES (1,10), (2,20), (3,30);
INSERT INTO desc_data VALUES (10, 'mysql'),(20, 'pg'),(30, 'ch');

SELECT * FROM main_data ANY LEFT JOIN desc_data USING (desc_id);
/*
Code: 264. DB::Exception: Received from localhost:9000. DB::Exception: Table 'default.desc_data (fd58b75a-fb73-493c-82d3-fed25ca66769)' has incompatible type of JOIN. (INCOMPATIBLE_TYPE_OF_JOIN)
*/
SELECT * FROM main_data ANY INNER JOIN desc_data USING (desc_id);

-- Также можно испльзовать функцию джоинГет
-- joinGet only supports StorageJoin of type Left Any
SELECT id, joinGet(desc_data, 'desc', toUInt32(desc_id)) as description
FROM main_data;

CREATE TABLE desc_data2 (
    desc_id UInt32,
    desc String
)
engine = Join(ANY, LEFT , desc_id);
INSERT INTO desc_data2 VALUES (10, 'mysql'),(20, 'pg'),(30, 'ch');
SELECT id, joinGet(desc_data2, 'desc', toUInt32(desc_id)) as description
FROM main_data;

```

Очень хорошая экономия, если много мелких справочников - вполне можно использовать этот движок. Также можно испльзовать функцию джоинГет. Имеет смысл для джоины таблицы, словаря, или нескольких таблиц

## Движок URL (44:00)

Удобно забирать цсв файлы или когда нужно ходить и периодически забирать файл (не апи, именно файл).
- Для работы с данными на удаленном сервере. Запросы INSERT и SELECT транслируется в POST и GET запросы. Например, можно обращаться к таблице в другом ClickHouse через http
- Поддерживается многопоточная запись и чтение
- Движок не хранит данные локально (только обращение куда то)
- Не поддерживается изменение данных с помощье ALTER
- Не поддерживается сэмплирование
- Не поддерживается индексы и репликация

```sql
CREATE TABLE url_engine_table 
(`SIC Code` Nullable(Int64), `Description` Nullable(String))
ENGINE = URL('https://cdn.wsform.com/wp-content/uploads/2020/06/industry_sic.csv', CSV);

SELECT * FROM url_engine_table;
```

Никакого кэширования нету на уровне кх! То есть каждый раз наш запрос превращается в http request

Чуть изменим - представим что у нас есть некоторая база. И там у нас лежит файл в формате `parquet`, можно обрабоать и так
```sql
SET param_base='https://huggingface.co/datasets/vivym/midjourney-messages/resolve/main/data/';

FROM url({base:String} || '000000.parquet')
SELECT *
LIMIT 1
Format JSONEachRow
SETTINGS max_http_get_redirects=1;
/*
{"id":"1144508197969854484","channel_id":"989268300473192561","content":"**adult Goku in Dragonball Z, walking on a beach, in a Akira Toriyama anime style** - Image #1 <@1016225582566101084>","timestamp":"2023-08-25T05:46:58.330000+00:00","image_id":"1144508197693046875","height":"1024","width":"1024","url":"https:\/\/cdn.discordapp.com\/attachments\/989268300473192561\/1144508197693046875\/anaxagore54_adult_Goku_in_Dragonball_Z_walking_on_a_beach_in_a__987e6fd5-64a1-43f6-83dd-c58d2eb42948.png","size":"1689284"}

1 row in set. Elapsed: 60.090 sec. Processed 34.81 thousand rows, 5.55 MB (579.33 rows/s., 92.29 KB/s.)
Peak memory usage: 211.39 MiB.
*/
```

Также мы можем использовать различные функции вычисления когда работаем с этим файлом
```sql
-- Count the size of all images in one file
FROM url({base:String} || '000000.parquet')
SELECT sum(size) AS size, formatReadableSize(size) AS readable
SETTINGS max_http_get_redirects=1;
/*
Query id: 9d0228ee-5d11-4fd1-a365-cd99d6cc7aa0

   ┌──────────size─┬─readable─┐
1. │ 3456458790156 │ 3.14 TiB │
   └───────────────┴──────────┘

1 row in set. Elapsed: 2.772 sec. Processed 1.00 million rows, 159.31 MB (360.77 thousand rows/s., 57.47 MB/s.)
Peak memory usage: 13.42 MiB.
*/

-- Count size of all images
FROM url({base:String} || '0000{00..03}.parquet')
SELECT sum(size) AS size, formatReadableSize(size) AS readable
SETTINGS max_http_get_redirects=1;
/*
Query id: cefec45e-d626-4aa2-91a0-85221ecc3d97

   ┌───────────size─┬─readable──┐
1. │ 11955008514044 │ 10.87 TiB │
   └────────────────┴───────────┘

1 row in set. Elapsed: 4.748 sec. Processed 4.00 million rows, 628.76 MB (842.44 thousand rows/s., 132.42 MB/s.)
Peak memory usage: 15.52 MiB.
*/

FROM url({base:String} || '0000{00..03}.parquet')
SELECT sum(size) AS size,
       formatReadableSize(size) AS readable,
       round(avg(width), 2) AS width,
       round(avg(height), 2) AS height
SETTINGS max_http_get_redirects=1;
/*
Query id: 7a32f537-387b-495c-b918-90f26362bc80

   ┌───────────size─┬─readable──┬───width─┬──height─┐
1. │ 11955008514044 │ 10.87 TiB │ 1480.62 │ 1430.83 │
   └────────────────┴───────────┴─────────┴─────────┘

1 row in set. Elapsed: 8.400 sec. Processed 4.00 million rows, 628.76 MB (476.19 thousand rows/s., 74.85 MB/s.)
Peak memory usage: 29.24 MiB.
*/
```

Функционал может быть довольно полезен для работы с другим кликхаусом!!

## Движок File

Управляет данными в одном файле на диске в указанном формате.

Примеры применения:
- Выгрузка данных из ClickHouse в файл.
- Преобразование данных из одного формата в другой. ( File([format](https://clickhouse.com/docs/ru/interfaces/formats#formats)) )
- Обновление данных в ClickHouse редактированием файла на диск

Движок File
- Поддерживается одновременное выполнение множества запросов SELECT
- запросы INSERT - сериализуется
- При операции CREATE создает директорие (можно поместить туда файл и прикрепить с помощье ATTACH )
- Поддерживается создание ещё не существуещего файла при запросе INSERT.
- Для существуещих файлов INSERT записывает в конец файла.
- Не поддерживается:
  - использование операций ALTER и SELECT...SAMPLE;
  - индексы;
  - репликация.

То есть мы можем работать с плоским файлом - просто с файлом нужного формата.

```sql
drop table if exists file_engine_table;
CREATE TABLE file_engine_table 
(name String, value UInt32) 
ENGINE=File(TabSeparated);

INSERT INTO file_engine_table VALUES ('test', 10), ('x',2);

-- посмотрим как этот файл лежит на диске 
select data_paths, metadata_path from system.tables where name = 'file_engine_table' format Vertical;
/*
Query id: 289913e2-47b0-4f74-b3a3-e9853b2f81d5

Row 1:
──────
data_paths:    ['/var/lib/clickhouse/store/a5e/a5e5ecc9-95bc-40c0-bdb6-b124e563cf1b//data.TabSeparated']
metadata_path: /var/lib/clickhouse/store/f89/f89784aa-6c33-4cdf-ac51-47a80e2404a0/file_engine_table.sql

1 row in set. Elapsed: 0.022 sec. 
*/
/*
$ cat /var/lib/clickhouse/store/a5e/a5e5ecc9-95bc-40c0-bdb6-b124e563cf1b//data.TabSeparated
test    10
x       2
*/
-- видим что это простой файл, разделенный табуляцией
```

## Движок Set

Есть операции выборки. Когда мы например ищем что у нас какой то субъект относится к одному из районов и мы сверяем значение с каким то множеством из тысяч адресов. Это одна из базовых операций и для таких операций используется движок Set (который по факту множество):
- множество в оперативной памяти (реализовано на hash таблице)
- используется в операторе IN (поиск в множестве) (нельзя сделать SELECT из таблицы)
- Можно вставлять данные через INSERT (Возможны дубликаты записей)
- Данные могут храниться на диске (опция persistent)

Это вспомогательный движок для ускорения рутинных операций.

## Движок Memory

Очень похож на движок Set,

- данные хранятся только в оперативной памяти в несжатом виде
- Уместно использовать на датасетах до 10М строк, для достижения очень высокой скорости
- Чтение распараллеливается
- Чтение и запись не блокирует друг друга (поскольку все в памяти)
- Индексы не поддерживается
- подходит для GLOBAL IN

```sql
drop table if exists SX;
drop table if exists MX;
drop table if exists HL;

-- создадим 2 таблицы - Set и Memory, и вставим по 30к записей
CREATE TABLE SX ( hbx UInt32 ) ENGINE = Set SETTINGS persistent=1;
CREATE TABLE MX ( hbx UInt32 ) ENGINE = Memory;

INSERT INTO MX SELECT number from numbers(30000);
/*
0 rows in set. Elapsed: 0.009 sec. Processed 30.00 thousand rows, 240.00 KB (3.22 million rows/s., 25.76 MB/s.)
Peak memory usage: 133.92 KiB.
*/
INSERT INTO SX SELECT number from numbers(30000);
/*
0 rows in set. Elapsed: 0.008 sec. Processed 30.00 thousand rows, 240.00 KB (3.86 million rows/s., 30.89 MB/s.)
Peak memory usage: 260.44 KiB.
*/

SELECT COUNT(*) FROM MX;
SELECT COUNT(*) FROM SX;  -- DB::Exception: Received from localhost:9000. DB::Exception: Method read is not supported by storage Set. (NOT_IMPLEMENTED)

-- теперь создадим основную табличку и вставим в нее много записей
CREATE TABLE HL (id UInt32, val UInt32)
ENGINE = MergeTree ORDER BY (val);
INSERT INTO HL SELECT number, number * 10 from numbers(30000000);

SELECT count(*) FROM HL WHERE val IN SX;
/*
   ┌─count()─┐
1. │    3000 │
   └─────────┘

1 row in set. Elapsed: 0.186 sec. Processed 30.00 million rows, 120.00 MB (161.23 million rows/s., 644.91 MB/s.)
Peak memory usage: 412.31 KiB.
*/
/*
мы обработали 30млн строк - шли по каждой строке и проверяли, есть ли она в SX, и это у нас заняло достаточно много времени.
*/
SELECT count(*) FROM HL WHERE val IN MX;
/*
   ┌─count()─┐
1. │    3000 │
   └─────────┘

1 row in set. Elapsed: 0.019 sec. Processed 38.19 thousand rows, 152.77 KB (1.99 million rows/s., 7.98 MB/s.)
Peak memory usage: 60.98 KiB.
*/
/*
Memory - это табличка, а не множество! Так что здесь кх может делать оптимизирующие вещи для поиска и получается сильно быстрее (0.019 sec против 0.186 sec)
*/

explain actions=1, indexes=1 SELECT count(*) FROM HL WHERE val IN SX;
/*
Query id: 01226b7f-f404-41d4-be0d-2da5680481ed

    ┌─explain───────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
 1. │ Expression ((Project names + Projection))                                                                                                                             │
 2. │ Actions: INPUT :: 0 -> count() UInt64 : 0                                                                                                                             │
 3. │ Positions: 0                                                                                                                                                          │
 4. │   Aggregating                                                                                                                                                         │
 5. │   Keys:                                                                                                                                                               │
 6. │   Aggregates:                                                                                                                                                         │
 7. │       count()                                                                                                                                                         │
 8. │         Function: count() → UInt64                                                                                                                                    │
 9. │         Arguments: none                                                                                                                                               │
10. │   Skip merging: 0                                                                                                                                                     │
11. │     Expression (Before GROUP BY)                                                                                                                                      │
12. │     Positions:                                                                                                                                                        │
13. │       Filter ((WHERE + Change column names to column identifiers))                                                                                                    │
14. │       Filter column: in(__table1.val, __set_4183759572131635556_1579914756063664651) (removed)                                                                        │
15. │       Actions: INPUT : 0 -> val UInt32 : 0                                                                                                                            │
16. │                COLUMN Const(Set) -> __set_4183759572131635556_1579914756063664651 Set : 1                                                                             │
17. │                ALIAS val : 0 -> __table1.val UInt32 : 2                                                                                                               │
18. │                FUNCTION in(val :: 0, __set_4183759572131635556_1579914756063664651 :: 1) -> in(__table1.val, __set_4183759572131635556_1579914756063664651) UInt8 : 3 │
19. │       Positions: 3                                                                                                                                                    │
20. │         ReadFromMergeTree (default.HL)                                                                                                                                │
21. │         ReadType: Default                                                                                                                                             │
22. │         Parts: 7                                                                                                                                                      │
23. │         Granules: 3665                                                                                                                                                │
24. │         Indexes:                                                                                                                                                      │
25. │           PrimaryKey                                                                                                                                                  │
26. │             Condition: true                                                                                                                                           │
27. │             Parts: 7/7                                                                                                                                                │
28. │             Granules: 3665/3665                                                                                                                                       │
    └───────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘

28 rows in set. Elapsed: 0.005 sec. 
*/
/*
иными словами - идет агрегация, затем идет фильтрация, затем - поиск по функции
FUNCTION in(val :: 0, __set_4183759572131635556_1579914756063664651 :: 1) -> in(__table1.val, __set_4183759572131635556_1579914756063664651) UInt8 : 3 
Поэтому у нас практически все гранулы перебираются
*/
explain actions=1, indexes=1  SELECT count(*) FROM HL WHERE val IN MX;
/*
Query id: 6badb7d3-fcbc-4f3e-9f3e-077b78ac2043

    ┌─explain─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
 1. │ CreatingSets (Create sets before main query execution)                                                                                                                      │
 2. │   Expression ((Project names + Projection))                                                                                                                                 │
 3. │   Actions: INPUT :: 0 -> count() UInt64 : 0                                                                                                                                 │
 4. │   Positions: 0                                                                                                                                                              │
 5. │     Aggregating                                                                                                                                                             │
 6. │     Keys:                                                                                                                                                                   │
 7. │     Aggregates:                                                                                                                                                             │
 8. │         count()                                                                                                                                                             │
 9. │           Function: count() → UInt64                                                                                                                                        │
10. │           Arguments: none                                                                                                                                                   │
11. │     Skip merging: 0                                                                                                                                                         │
12. │       Expression (Before GROUP BY)                                                                                                                                          │
13. │       Positions:                                                                                                                                                            │
14. │         Filter ((WHERE + Change column names to column identifiers))                                                                                                        │
15. │         Filter column: in(__table1.val, __set_12803441193917447534_14724933627980372700) (removed)                                                                          │
16. │         Actions: INPUT : 0 -> val UInt32 : 0                                                                                                                                │
17. │                  COLUMN Set -> __set_12803441193917447534_14724933627980372700 Set : 1                                                                                      │
18. │                  ALIAS val : 0 -> __table1.val UInt32 : 2                                                                                                                   │
19. │                  FUNCTION in(val :: 0, __set_12803441193917447534_14724933627980372700 :: 1) -> in(__table1.val, __set_12803441193917447534_14724933627980372700) UInt8 : 3 │
20. │         Positions: 3                                                                                                                                                        │
21. │           ReadFromMergeTree (default.HL)                                                                                                                                    │
22. │           ReadType: Default                                                                                                                                                 │
23. │           Parts: 1                                                                                                                                                          │
24. │           Granules: 1                                                                                                                                                       │
25. │           Indexes:                                                                                                                                                          │
26. │             PrimaryKey                                                                                                                                                      │
27. │               Keys:                                                                                                                                                         │
28. │                 val                                                                                                                                                         │
29. │               Condition: (val in 30000-element set)                                                                                                                         │
30. │               Parts: 1/7                                                                                                                                                    │
31. │               Granules: 1/3665                                                                                                                                              │
    └─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘

31 rows in set. Elapsed: 0.011 sec. Processed 30.03 thousand rows, 121.45 KB (2.75 million rows/s., 11.14 MB/s.)
Peak memory usage: 19.28 KiB.
*/
/*
Здесь у нас по другому идет фильтрация. Срабатывает индекс Primary Key. Поэтому использование хэша - немного не для таких операций. Оно для операций условий - когда мы используем не для выборки. Оно само быстрое, но в таких случаях как у нас - Memory эффективнее
select 310 in SX  --  в таких случаях Сет эффетивнее
*/
```

Мемори - это таблица, а Сет - это некий вектор, хранящийся в памяти и позволяющий быструю проверку того, есть элемент здесь или нет.

## Движок Merge

Очень хитрый движок

- не имеет отношение к семейству MergeTree (это именно движок слияния)
- позволяет делать запрос к нескольким таблицам одновременно (вариация UNION), (имена соединяемых таблиц можно задать через RegExp)
- INSERT не поддерживается
- `CREATE TABLE ... Engine=Merge(db_name, tables_regexp)` (имя БД тоже можно указать через RegExp)
- при выборке имеет виртуальный столбец _table (чтобы посмотреть, откуда данные)
- столбцы в таблице должны существовать в таблицах источниках

Для чего использовать:
- работа с большим набором таблиц как с одной (например с *Log - их нормально созавать десятками тысяч и в каждой хранить по паре миллионов строк)
- партиционирование существуещей таблицы с данными (когда у нас в старой много партиций, нам нужно ее переделать, но в старой таблице очень много данных - просто так пересоздать не получится)
  - создаете новую с партициями
  - создаете Merge таблицу для чтения из старой и новой
  - запись делаем только в новую
  - по истечении какого то времени, когда старую можно будет удалить - удаляем

```sql
drop table if exists logs_1;
drop table if exists logs_2;
drop table if exists logs_common;

CREATE TABLE logs_1 (id UInt32, val UInt32) ENGINE = TinyLog;
CREATE TABLE logs_2 (id UInt32, val UInt32) ENGINE = TinyLog;
INSERT INTO logs_1 (id, val) select number, number * 10 FROM numbers(10000000);
/*
Query id: d145a363-d95b-45bd-83ad-57528a0b1f47

Ok.

0 rows in set. Elapsed: 0.285 sec. Processed 10.00 million rows, 80.00 MB (35.09 million rows/s., 280.70 MB/s.)
Peak memory usage: 20.75 MiB.
*/
INSERT INTO logs_2 (id, val) select number, number * 200 FROM numbers(10000000);
/*
Query id: 4b00f6b1-9404-4d1d-9895-5ef75fae81a9

Ok.

0 rows in set. Elapsed: 0.274 sec. Processed 10.00 million rows, 80.00 MB (36.47 million rows/s., 291.74 MB/s.)
Peak memory usage: 20.75 MiB.

*/

CREATE TABLE logs_common (id UInt32, val UInt32)
ENGINE = Merge(currentDatabase(), '^logs_*');
-- Объединяем все таблицы, которые начинаются на logs_ 

SELECT count(*) FROM logs_common;
/*
Query id: c31a9f6e-07a4-4bb5-9dc3-391f96f236f2

   ┌──count()─┐
1. │ 20000000 │ -- 20.00 million
   └──────────┘

1 row in set. Elapsed: 0.069 sec. Processed 20.00 million rows, 80.00 MB (288.80 million rows/s., 1.16 GB/s.)
Peak memory usage: 12.10 MiB.
*/
-- то есть по факту мы прочитали из 2 таблиц сразу
```
Те поля, которые есть в Мердже, обязательно должны присутствовать по всех остальных таблицах! При этом полная идентичность структуры таблиц не требуется!

## Движки для интеграций

Clickhouse легко интегрируется с другими системами и базами данных; Для этого у него есть ряд движков, которые обеспечивает доступ к данным в других системах
- MySQL и MaterializedMySQL
- PostgreSQL и MaterializedPostgreSQL
- Hive
- MongoDB
- HDFS
- Kafka
- SQLite
- ODBC и JDBC

Для этого у КХ есть 2 очень важные опции: Materialized View и проекции

## Materialized View (1:17:00)

Это одна из киллер фич КХ:
- хранят данные, которые были выбраны соответствуещим запросом SELECT, указанным при создании
- содержимое может быть реплицировано
- SELECT можно делать как из MV так и из таргетной таблицы
- Принцип работы отличается от других СУБД
  - больше похоже на триггер AFTER INSERT
  -  Если в запросе материализованного представления есть агрегирование, оно применяется только к вставляемому блоку записей.
  - обновления в исходной таблице не влияет на данные в MV, только вставки

```sql
drop table if exists source_tbl;
CREATE TABLE source_tbl (num UInt64)
ENGINE = Log;

CREATE MATERIALIZED VIEW otus_mv
	ENGINE = TinyLog AS
	SELECT num * num as fld
	FROM source_tbl;

INSERT INTO source_tbl SELECT number FROM numbers(10);

SELECT * FROM otus_mv;
/*
Query id: 47b25493-88b1-4758-a970-2f2ff63ec45e

    ┌─fld─┐
 1. │   0 │
 2. │   1 │
 3. │   4 │
 4. │   9 │
 5. │  16 │
 6. │  25 │
 7. │  36 │
 8. │  49 │
 9. │  64 │
1.  │  81 │
    └─────┘

10 rows in set. Elapsed: 0.010 sec. 
*/

SELECT name, uuid, engine, metadata_path FROM system.tables t WHERE name ilike '%.inner%' or name='otus_mv'\G
/*
Query id: bb170e26-e4ad-46bf-95fd-760638d9d128

Row 1:
──────
name:          .inner_id.9098e606-55e2-424b-ba11-b21da6a02973
uuid:          926948e7-8b02-43b6-9ad4-496a571bcd66
engine:        TinyLog
metadata_path: /var/lib/clickhouse/store/f89/f89784aa-6c33-4cdf-ac51-47a80e2404a0/%2Einner_id%2E9098e606%2D55e2%2D424b%2Dba11%2Db21da6a02973.sql

Row 2:
──────
name:          otus_mv
uuid:          9098e606-55e2-424b-ba11-b21da6a02973
engine:        MaterializedView
metadata_path: /var/lib/clickhouse/store/f89/f89784aa-6c33-4cdf-ac51-47a80e2404a0/otus_mv.sql

2 rows in set. Elapsed: 0.008 sec. 
*/
/*
мы видим что name .inner_id и ууид одинаковые! 9098e606-55e2-424b-ba11-b21da6a02973 

*/

CREATE MATERIALIZED VIEW otus_pop_mv
	ENGINE = Log 
  POPULATE
  AS
	SELECT num * num as fld
	FROM source_tbl;

select * from otus_pop_mv;
```
.inner_id.9098e606-55e2-424b-ba11-b21da6a02973 - внутреннее имя создаваемой таргетной таблицы, rогда мы задаем ее неявно. Мы всегда можем таким образом найти таргетную таблицу, которая у нас создалась.

```sql
drop table if exists mem_target;

CREATE TABLE mem_target (num UInt64, fld UInt64)
ENGINE = SummingMergeTree ORDER BY (num);	

CREATE MATERIALIZED VIEW my_mv
	TO mem_target
	AS 
     SELECT num, num + 10 as fld
	FROM source_tbl;

SELECT * FROM my_mv;  -- 0 rows in set. Elapsed: 0.004 sec. 

INSERT INTO source_tbl SELECT intDiv(number,2) FROM numbers(10);

SELECT * FROM my_mv;  -- 5 rows in set. Elapsed: 0.005 sec.

/*
если сделаем еще раз инсерт - то вставка пройдет, но после мерджа движок схлопнет значения
*/
```

Сценарии использования MV
- Агрегация данных
- Обработка потоков данных из внешних источников
- Маршрутизация и преобразование данных (можно создать несколько MV для одного источника и направлять данные в разные таблицы в зависимости от условий)
- Дублирование данных для изменения ключа сортировки

## Проекции

Альтернатива МВ:
- данные проекций всегда согласованы 
- данные обновляется атомарно вместе с таблицей (данные хранятся в том же парте)
- содержимое проекций реплицируется вместе с таблицей
- проекция может быть автоматически использована для запроса SELECT (автоматически подставляет себя если условия группировки совпадает с тем, что указано в проекции)

Когда используется проекция (собледение всех условий):
- если выборка соответствует запросу проекции
- если 50% выбранных кусков содержат материализованные проекции. Проекции могут содержать данные, т.е. быть материализованы, либо могут быть пустые, если, например была применена команда `ALTER TABLE CLEAR PROJECTION`
- если количество выбранных строк меньше общего количества строк таблицы

```sql
drop table if exists visits;
CREATE TABLE visits
(
   user_id UInt64,
   user_name String,
   pages_visited Nullable(Float64),
   user_agent String,
   PROJECTION projection_visits_by_user
   (
       SELECT
           user_agent,
           sum(pages_visited)
       GROUP BY user_id, user_agent
   )
)
ENGINE = MergeTree()
ORDER BY user_agent;

INSERT INTO visits SELECT
    number, 'test', 1.5 * (number / 2),'Android'
FROM numbers(1, 100);
INSERT INTO visits SELECT
    number,'test',1. * (number / 2),'IOS'
FROM numbers(100, 500);
-- то есть по факту мы вставили 2 куска

SELECT
    user_agent,
    sum(pages_visited)
FROM visits
GROUP BY user_agent;
-- 2 rows in set. Elapsed: 0.019 sec.
SELECT
    user_id,
    sum(pages_visited)
FROM visits
GROUP BY user_id;
-- 599 rows in set. Elapsed: 0.046 sec.
-- второй запрос идет дольше
-- можно применить `explain description=1, indexes=1` чтобы проверить

/* user_id
   ┌─explain─────────────────────────────────────────────┐
1. │ Expression ((Project names + Projection))           │
2. │   Aggregating                                       │
3. │     Expression                                      │
4. │       ReadFromMergeTree (projection_visits_by_user) │
5. │       Indexes:                                      │
6. │         PrimaryKey                                  │
7. │           Condition: true                           │
8. │           Parts: 2/2                                │
9. │           Granules: 2/2                             │
   └─────────────────────────────────────────────────────┘

9 rows in set. Elapsed: 0.011 sec. 
*/
/* user_action
   ┌─explain─────────────────────────────────────────────┐
1. │ Expression ((Project names + Projection))           │
2. │   Aggregating                                       │
3. │     Expression                                      │
4. │       ReadFromMergeTree (projection_visits_by_user) │
5. │       Indexes:                                      │
6. │         PrimaryKey                                  │
7. │           Condition: true                           │
8. │           Parts: 2/2                                │
9. │           Granules: 2/2                             │
   └─────────────────────────────────────────────────────┘

9 rows in set. Elapsed: 0.007 sec. 
/*
```

## Kafka

что такое Kafka
- масштабируемая шина сообщений
- используется для построения Data Pipelines и ETL процессов
- лучше всего принцип работы продемонстрирован в данной визуализации
- основные понятия
  - Record – Запись, состоящая из клеча и значения
  - Topic – категория или имя потока куда публикуется записи
  - Producer – процесс публикуещий данные в топик
  - Consumer – процесс читаещий данные из топика
  - Consumer group - группа читателей из одного топика для балансировки нагрузки по чтение (Разные consumer groups читает независимо друг от друга.)
  - Offset – позиция записи
  - Partition – шард топика

```bash
cat > test_msg.json << EOL
{"Message":"Some message","Priority":"A1"}
EOL

# отправим сообщение 
cat test_msg.json | kafkacat -P  -b 127.0.0.1:29092  -t OtusTopic 

# проверим что оно дошло 
kafkacat -C  -b 127.0.0.1:29092  -t OtusTopic
```

```sql
DROP TABLE IF EXISTS kafka_tbl;

CREATE TABLE kafka_tbl (
	Message String,
	Priority String
) ENGINE = Kafka
SETTINGS kafka_broker_list = '127.0.0.1:29092',
kafka_topic_list = 'MyOtusTopic',
kafka_group_name = 'test-consumer-group', 
kafka_format = 'JSONEachRow';

SELECT *
FROM default.kafka_tbl
SETTINGS stream_like_engine_allow_direct_select = 1;

DROP TABLE IF EXISTS from_kafka_tbl;

CREATE TABLE from_kafka_tbl (
	Message String,
	Priority String
) ENGINE = MergeTree
ORDER BY Priority;

DROP VIEW IF EXISTS mv_kafka;
CREATE MATERIALIZED VIEW mv_kafka TO from_kafka_tbl AS SELECT * FROM kafka_tbl;

SELECT * FROM mv_kafka;
```

Движок Kafka:
- одна из самых частых интеграций
- при создании таблицы указывается
- не хранит данные самостоятельно (предназначен для подписки на потоки данных в конкретных топиках (consumer)). 
  - SELECT может прочесть запись только один раз, поэтому имеет смысл использовать MV
- и для публикации данных в конкретные топики (producer)

Обязательные настройки движка Kafka
- kafka_broker_list — перечень брокеров, разделенный запятыми
- kafka_topic_list — перечень необходимых топиков Kafka, разделенный запятыми
- kafka_group_name — группа потребителя Kafka. Если необходимо, чтобы сообщения не повторялись на кластере, необходимо использовать везде одно имя группы.
- kafka_format — формат сообщений, например JSONEachRow.
- Опциональные параметры, такие как размер блока, количество потребителей на таблицу и потоков, подробно описаны в документации.