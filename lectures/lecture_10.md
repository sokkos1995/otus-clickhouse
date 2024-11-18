# Джоины и агрегации

- Базовые соединения
  - INNER JOIN
  - LEFT OUTER JOIN
  - RIGHT OUTER JOIN
  - FULL OUTER JOIN
  - CROSS JOIN
- Дополнительные соединения
  - (LEFT / RIGHT) SEMI JOIN - тип джоина, который возвращает значения для всех строк главной таблицы, имеющих хотя бы одно совпадение в другой таблице. Возвращается только первое найденное совпадение
  - (LEFT / RIGHT) ANTI JOIN - тип джоина, который возвращает значения для всех несовпадающих строк из левой таблицы. Аналогично, RIGHT ANTI JOIN возвращает значения столбцов для всех несовпадающих правых строк таблицы.
  - (LEFT / RIGHT / INNER) ANY JOIN - тип джоина, который работает как LEFT OUTER JOIN, но с отключенным декартовым произведением.
  - INNER ANY JOIN — это INNER JOIN с отключенным декартовым произведением.
  - ASOF JOIN - уникальный джоин, который предоставляет возможности неточного сопоставления. Если строка не имеет точного соответствия, то вместо нее в качестве совпадения используется ближайшее совпадающее значение. Декартовое произведение отсутствует. 
  - PASTE JOIN - Результатом PASTE JOIN является таблица, содержащая все столбцы из левого подзапроса, а затем все столбцы из правого подзапроса. Строки сопоставляются на основе их позиций в исходных таблицах (порядок следования строк должен быть определен). Если подзапросы возвращают разное количество строк, лишние строки будут вырезаны.

## Что же не так с джоинами в кх?  30:00

Говорят, что ClickHouse плохо джоинит. Почему?
- Столбцовая структура хранения данных. - Мы храним в одной таблице максимум того, что можем собрать. То есть у нас таблица мало того что длинная - она еще и широкая. Таблицы, которые в кх весят 1Тб - это норма.
- Распределенная природа - накладные расходы на сетевую связь и передачу данных. (так как данных у нас очень много, их приходится сплитить (например, партиционировать), - чтобы вроде как они лежали у нас в одной таблице, но и чтоб таблица не уходила за 100Тб)
- Отсутствие индексов - ClickHouse не поддерживает традиционные индексы типа B-tree или bitmap, обычно используемые в базах данных, основанных на строках, для ускорения операций объединения. Вместо этого он полагается на сортировку и сжатие первичных ключей, которые не всегда оптимальны для запросов с большим количеством соединений.
- Не оптимизирует порядок JOIN-ов. Третяя таблица в запросе уже джоинится очень плохо
- Не фильтрует по ключу соединения (до версии 24.4)
- Не поддерживает сравнение значений ( >, <)  в качестве условий соединения (только через where)
- Не выбирает алгоритм JOIN-а, основываясь на собранной статистике (по умолчанию джоинит с помощью хэш джоина)
- Не обрабатывает исключения по памяти (джоинит в лоб, еще и правую таблицу будет запихивать целиком в хэш таблицу)

Как быть:
- Денормализация, избыточность
- Материализованные представления
- Выбор алгоритма объединения (тут нужно быть очень аккуратным - для того что мерджа нужны отсортированные данные!)
- Оптимизация структуры таблиц - минимизация объема данных для сканирования во время соединения
- Распределенные таблицы - минимизация межузловых соединений (по возможности) (если мы джоиним какую то таблицу на всю партиционированную таблицу - нужно и использовать глобал (но лучше не увлекаться, тк джоиним огромную таблицу), подглядывать в ддл (в секцую партишн бай))
- Использование массивов и вложенных данных (массивы очень здорово помогаеют)

## пратика (37 00)

```sql
-- Создаем таблицы с 2 млн. и 2 млрд. строк
CREATE TABLE 2billion (idx Int64) ENGINE = Log;
CREATE TABLE 2million (idx Int64) ENGINE = Log;

INSERT INTO 2billion (idx) select * from numbers(1, 2000000000);
INSERT INTO 2million (idx) select * from numbers(1, 2000000000, 1000);

SET send_logs_level='trace'; -- чтобы показывались логи при джоинах
select count() 
from 2billion 
left join 2million using(idx);
-- этот джоин делаем правильно - в левой таблице данных больше!
/*
[bedd228ee7e4] 2024.11.17 09:34:43.828981 [ 65 ] {740e5c0c-629c-4b93-88f3-e44395c39a3e} <Debug> executeQuery: (from 127.0.0.1:44660) select count() from 2billion left join 2million using(idx); (stage: Complete)
[bedd228ee7e4] 2024.11.17 09:34:43.834093 [ 65 ] {740e5c0c-629c-4b93-88f3-e44395c39a3e} <Trace> Planner: Query to stage Complete
[bedd228ee7e4] 2024.11.17 09:34:43.843896 [ 65 ] {740e5c0c-629c-4b93-88f3-e44395c39a3e} <Trace> HashJoin: Keys: [(__table1.idx) = (__table2.idx)], datatype: EMPTY, kind: Left, strictness: All, right header: __table2.idx Int64 Int64(size = 0)
[bedd228ee7e4] 2024.11.17 09:34:43.847512 [ 65 ] {740e5c0c-629c-4b93-88f3-e44395c39a3e} <Trace> Planner: Query from stage FetchColumns to stage Complete
[bedd228ee7e4] 2024.11.17 09:34:43.914983 [ 855 ] {740e5c0c-629c-4b93-88f3-e44395c39a3e} <Trace> Allocator: Attempt to populate pages failed: errno: 22, strerror: Invalid argument (EINVAL is expected for kernels < 5.14)
[bedd228ee7e4] 2024.11.17 09:34:44.180805 [ 801 ] {740e5c0c-629c-4b93-88f3-e44395c39a3e} <Trace> Allocator: Attempt to populate pages failed: errno: 22, strerror: Invalid argument (EINVAL is expected for kernels < 5.14)
[bedd228ee7e4] 2024.11.17 09:34:44.270704 [ 801 ] {740e5c0c-629c-4b93-88f3-e44395c39a3e} <Trace> AggregatingTransform: Aggregating
[bedd228ee7e4] 2024.11.17 09:34:44.271585 [ 801 ] {740e5c0c-629c-4b93-88f3-e44395c39a3e} <Trace> Aggregator: Aggregation method: without_key
[bedd228ee7e4] 2024.11.17 09:34:44.271339 [ 851 ] {740e5c0c-629c-4b93-88f3-e44395c39a3e} <Trace> AggregatingTransform: Aggregating
[bedd228ee7e4] 2024.11.17 09:34:44.271729 [ 845 ] {740e5c0c-629c-4b93-88f3-e44395c39a3e} <Trace> AggregatingTransform: Aggregating
[bedd228ee7e4] 2024.11.17 09:34:44.271822 [ 845 ] {740e5c0c-629c-4b93-88f3-e44395c39a3e} <Trace> Aggregator: Aggregation method: without_key
[bedd228ee7e4] 2024.11.17 09:34:44.271777 [ 851 ] {740e5c0c-629c-4b93-88f3-e44395c39a3e} <Trace> Aggregator: Aggregation method: without_key
[bedd228ee7e4] 2024.11.17 09:34:44.273011 [ 855 ] {740e5c0c-629c-4b93-88f3-e44395c39a3e} <Trace> AggregatingTransform: Aggregating
[bedd228ee7e4] 2024.11.17 09:34:44.273184 [ 855 ] {740e5c0c-629c-4b93-88f3-e44395c39a3e} <Trace> Aggregator: Aggregation method: without_key
[bedd228ee7e4] 2024.11.17 09:36:57.671823 [ 851 ] {740e5c0c-629c-4b93-88f3-e44395c39a3e} <Trace> AggregatingTransform: Aggregated. 502275711 to 1 rows (from 0.00 B) in 133.831159189 sec. (3753055.074 rows/sec., 0.00 B/sec.)
[bedd228ee7e4] 2024.11.17 09:36:57.846921 [ 801 ] {740e5c0c-629c-4b93-88f3-e44395c39a3e} <Trace> AggregatingTransform: Aggregated. 499070670 to 1 rows (from 0.00 B) in 134.007464481 sec. (3724200.528 rows/sec., 0.00 B/sec.)
[bedd228ee7e4] 2024.11.17 09:36:57.864699 [ 855 ] {740e5c0c-629c-4b93-88f3-e44395c39a3e} <Trace> AggregatingTransform: Aggregated. 497042991 to 1 rows (from 0.00 B) in 134.025109022 sec. (3708581.135 rows/sec., 0.00 B/sec.)
[bedd228ee7e4] 2024.11.17 09:36:57.939978 [ 845 ] {740e5c0c-629c-4b93-88f3-e44395c39a3e} <Trace> AggregatingTransform: Aggregated. 501610628 to 1 rows (from 0.00 B) in 134.100505314 sec. (3740557.329 rows/sec., 0.00 B/sec.)
[bedd228ee7e4] 2024.11.17 09:36:57.940607 [ 845 ] {740e5c0c-629c-4b93-88f3-e44395c39a3e} <Trace> Aggregator: Merging aggregated data
[bedd228ee7e4] 2024.11.17 09:36:57.942403 [ 845 ] {740e5c0c-629c-4b93-88f3-e44395c39a3e} <Trace> HashTablesStatistics: Statistics updated for key=5756167190422974746: new sum_of_sizes=4, median_size=1
   ┌────count()─┐
1. │ 2000000000 │ -- 2.00 billion
   └────────────┘

-- самая важная часть! 
[bedd228ee7e4] 2024.11.17 09:36:57.953095 [ 65 ] {740e5c0c-629c-4b93-88f3-e44395c39a3e} <Debug> executeQuery: Read 2002000000 rows, 14.92 GiB in 134.134106 sec., 14925361.339494074 rows/sec., 113.87 MiB/sec.
[bedd228ee7e4] 2024.11.17 09:36:57.958726 [ 65 ] {740e5c0c-629c-4b93-88f3-e44395c39a3e} <Debug> MemoryTracker: Peak memory usage (for query): 164.27 MiB.
[bedd228ee7e4] 2024.11.17 09:36:57.959642 [ 65 ] {740e5c0c-629c-4b93-88f3-e44395c39a3e} <Debug> TCPHandler: Processed in 134.141921398 sec.

1 row in set. Elapsed: 134.135 sec. Processed 2.00 billion rows, 16.02 GB (14.93 million rows/s., 119.40 MB/s.)
Peak memory usage: 164.27 MiB.
*/
/*
executeQuery: Read 2002000000 rows, 14.92 GiB in 134.134106 sec., 14925361.339494074 rows/sec., 113.87 MiB/sec. 
- Мы считали 2млрд строк, 14Гб - это размер нашей таблички. 
HashJoin: Join data is being destroyed, 134217728 bytes and 2000000 rows in hash table
- сколько у нас данных в хэш таблице
*/

SET send_logs_level='trace'; 
select count(*) 
from 2billion 
right join 2million using(idx);
/*
right join - сделается также как и лефт. То есть имеется в виду таблица, которая идет вторая
*/
/*
hTablesStatistics: Statistics updated for key=16590220163726409389: new sum_of_sizes=4, median_size=1
   ┌─count()─┐
1. │ 2000000 │ -- 2.00 million
   └─────────┘
[bedd228ee7e4] 2024.11.17 09:41:50.042841 [ 65 ] {b00df1cc-a6b4-4e59-a7dc-e82b7c412b92} <Debug> executeQuery: Read 2002000000 rows, 14.92 GiB in 163.123392 sec., 12272917.914801575 rows/sec., 93.63 MiB/sec.
[bedd228ee7e4] 2024.11.17 09:41:50.073527 [ 65 ] {b00df1cc-a6b4-4e59-a7dc-e82b7c412b92} <Debug> MemoryTracker: Peak memory usage (for query): 175.54 MiB.
[bedd228ee7e4] 2024.11.17 09:41:50.075539 [ 65 ] {b00df1cc-a6b4-4e59-a7dc-e82b7c412b92} <Debug> TCPHandler: Processed in 163.168729619 sec.

1 row in set. Elapsed: 163.134 sec. Processed 2.00 billion rows, 16.02 GB (12.27 million rows/s., 98.18 MB/s.)
Peak memory usage: 175.54 MiB.
*/

select count() 
from 2million 
join 2billion using(idx);
/*
ТАК ДЕЛАТЬ НЕЛЬЗЯ!!!!! 
Поменяли таблицы местами - присоединяем большую таблицу

[bedd228ee7e4] 2024.11.17 09:57:16.614702 [ 65 ] {37838431-9b55-41a2-9d57-c9f567edd4ae} <Error> executeQuery: Code: 241. DB::Exception: Memory limit (total) exceeded: would use 12.45 GiB (attempt to allocate chunk of 8590288200 bytes), maximum: 6.90 GiB. OvercommitTracker decision: Query was selected to stop by OvercommitTracker.: While executing FillingRightJoinSide. (MEMORY_LIMIT_EXCEEDED) (version 24.8.4.13 (official build)) (from 127.0.0.1:44660) (in query: select count() from 2million join 2billion using(idx);), Stack trace (when copying this message, always include the lines below):
...

Elapsed: 631.028 sec. Processed 67.37 million rows, 538.97 MB (106.76 thousand rows/s., 854.11 KB/s.)
Peak memory usage: 12.01 GiB.

Received exception from server (version 24.8.4):
Code: 241. DB::Exception: Received from localhost:9000. DB::Exception: Memory limit (total) exceeded: would use 12.45 GiB (attempt to allocate chunk of 8590288200 bytes), maximum: 6.90 GiB. OvercommitTracker decision: Query was selected to stop by OvercommitTracker.: While executing FillingRightJoinSide. (MEMORY_LIMIT_EXCEEDED)
*/

/*
Что делать с таблицами в тех моментах когда мы не можем повлиять на то, как данные были разложены?
Можно сделать подзапрос, так подзапрос отработает (даже если мы к таблице из 2млн строк прибавим таблицу с 2млрд, но с предвариетльно отобранными столбцами)
*/
SET send_logs_level='trace'; 
select count() 
from 2million as 2m
join (
    select *
    from 2billion
    where idx IN (
        select idx
        from 2million
    )
) as 2b
using(idx);
/*
Тут уже в хэш таблицу пойдет не 2млрд, а 2 млн. Это кликхаус прожует и плохо ему не станет

   ┌─count()─┐
1. │ 2000000 │ -- 2.00 million
   └─────────┘
[bedd228ee7e4] 2024.11.17 09:59:46.015764 [ 64 ] {8307e32a-d136-4e1d-8d0f-4b3e6d03f9ea} <Debug> executeQuery: Read 2004000000 rows, 14.93 GiB in 102.353696 sec., 19579165.95410487 rows/sec., 149.38 MiB/sec.
[bedd228ee7e4] 2024.11.17 09:59:46.193760 [ 64 ] {8307e32a-d136-4e1d-8d0f-4b3e6d03f9ea} <Debug> MemoryTracker: Peak memory usage (for query): 209.27 MiB.
[bedd228ee7e4] 2024.11.17 09:59:46.194042 [ 64 ] {8307e32a-d136-4e1d-8d0f-4b3e6d03f9ea} <Debug> TCPHandler: Processed in 102.53481109 sec.

1 row in set. Elapsed: 102.354 sec. Processed 2.00 billion rows, 16.03 GB (19.58 million rows/s., 156.63 MB/s.)
Peak memory usage: 209.27 MiB.
*/
```

## настройки

- Тип соединения по умолчанию можно переопределить с помощью join_default_strictness
- Поведение ClickHouse для ANY JOIN зависит от настройки any_join_distinct_right_table_keys
- join_algorithm
- join_any_take_last_row
- join_use_nulls
- partial_merge_join_optimizations
- partial_merge_join_rows_in_right_blocks
- join_on_disk_max_files_to_merge
- any_join_distinct_right_table_keys

```sql
drop table if exists 2billion;
drop table if exists 2million;
CREATE TABLE 2billion (idx Int64) ENGINE = MergeTree ORDER BY idx;
CREATE TABLE 2million (idx Int64) ENGINE = MergeTree ORDER BY idx;

INSERT INTO 2billion (idx) select * from numbers(1, 2000000000);
INSERT INTO 2million (idx) select * from numbers(1, 2000000000, 1000);

-- переопределим алгоритм - у нас таблицы отсортированы, так что все прокатит
SET send_logs_level='trace'; 
select count() 
from 2million 
join 2billion using(idx)
SETTINGS join_algorithm = 'full_sorting_merge';
/*
У меня не прокатила вставка

[bedd228ee7e4] 2024.11.17 10:07:46.409045 [ 65 ] {d8a752f6-bddc-4c14-9997-1495e03b9b8b} <Debug> executeQuery: Read 4000000 rows, 30.52 MiB in 0.186551 sec., 21441857.72255308 rows/sec., 163.59 MiB/sec.
[bedd228ee7e4] 2024.11.17 10:07:46.414208 [ 65 ] {d8a752f6-bddc-4c14-9997-1495e03b9b8b} <Debug> MemoryTracker: Peak memory usage (for query): 26.22 MiB.
[bedd228ee7e4] 2024.11.17 10:07:46.414396 [ 65 ] {d8a752f6-bddc-4c14-9997-1495e03b9b8b} <Debug> TCPHandler: Processed in 0.192875167 sec.

1 row in set. Elapsed: 0.187 sec. Processed 4.00 million rows, 32.00 MB (21.34 million rows/s., 170.73 MB/s.)
Peak memory usage: 26.22 MiB.

Обычный джоин - 
1 row in set. Elapsed: 0.366 sec. Processed 4.00 million rows, 32.00 MB (10.94 million rows/s., 87.50 MB/s.)
Peak memory usage: 163.71 MiB.
*/

```

## Внешние словари

ЧТобы не джоинить маленькие таблицы, в которых несколько десятков тысяч значений, можно использовать внешние словари. Когда у нас огронмые таблицы, внешние словари - это супер.

```sql
dictGet('dict_name', attr_names, id_expr)
dictGetOrDefault('dict_name', attr_names, id_expr, default_value_expr)
dictGetOrNull('dict_name', attr_name, id_expr)
```
Аргументы:
- dict_name - Имя словаря, строка;
- attr_names - Имя столбца словаря, строка, или кортеж имен столбцов, Tuple(String literal);
- id_expr - Ключ;
- default_value_expr - Значения, возвращаемые, если словарь не содержит строки с id_expr ключом.

## Predicate Pushdown

В версии 24.4 появился Predicate Pushdown. С ним джоины стали учитывать, что у нас написано в функции where. Он переопределяет условия фильтрации (предикаты) ближе к операторам, которые сканируют данные, что снижает объем обрабатываемых данных и улучшает использование индексов.
- Задается параметром optimize_move_to_prewhere (Default=1, то есть по дефолту включен)
- Работает только для таблиц с движком *MergeTree 
- Разное поведение для INNER и LEFT/RIGHT JOIN-ов (иннер - фильтр применяется для обеих таблиц, лефт/райт - только для левой или правой таблицы соответственно)

Пример из [статьи](https://www.tinybird.co/blog-posts/clickhouse-joins-improvements)
```sql
SELECT * FROM test_table_1 as lhs
LEFT JOIN test_table_2 as rhs on lhs.id = rhs.id
WHERE lhs.id = 5;
```

Еще клик добавил преобразование outer join inner join:
- Автоматическое преобразование: Если условие фильтрации после (LEFT/RIGHT) OUTER JOIN отсекает ненужные строки, то OUTER JOIN преобразуется в INNER JOIN.
- Это приводит к возможностям для оптимизации, включая применение predicate pushdown в большем количестве сценариев. После замены JOIN наблюдаются улучшения в производительности запросов.

То есть идет преданализ запроса и преобразование случается если условие ниже соответствует этому запросу (тк иннер джоин оптимальнее).

## Агрегатные функции

Агрегация относится к таким операциям, когда больший набор строк свёртывается в меньший. Типичные агрегатные функции - COUNT, MIN, MAX, SUM и AVG.

Комбинатор — специальный суффикс, который добавляется к названию агрегатной функции и модифицирует логику работы этой функции. Для одной функции можно использовать несколько комбинаторов одновременно.

## Саммари

- лучший джоин в кликхаус - тот джоин, которого не было
- использовать можно, просто не нужно использовать терабайтные таблицы
- делаем подзапросы из агрегатов!