# Развертывание и базовая конфигурация, интерфейсы и инструменты

## Варианты установки

У вас есть такие варианты запуска ClickHouse в эксплуатации:
1. [ClickHouse Cloud](https://clickhouse.com/cloud): официальный ClickHouse as a service
   1. Managed сервисы от облачных провайдеров (Yandex, VK)
2. [Quick Install](https://clickhouse.com/docs/en/install#quick-install): легко загружаемый бинарник для тестирования и разработки.
3. [Production Deployments](https://clickhouse.com/docs/en/install#available-installation-options)
   1. ClickHouse can run on any Linux, FreeBSD, or macOS with x86-64, ARM, or PowerPC64LE CPU architecture
4. [Образ Docker](https://hub.docker.com/r/clickhouse/clickhouse-server/): официальный образ Docker в Docker Hub
5. [Homebrew](https://formulae.brew.sh/cask/clickhouse) для macOS
6. Кластер ClickHouse на базе Kubernetes [[1]](https://docs.altinity.com/altinitykubernetesoperator/kubernetesoperatorguide/) [[2]](https://geekops.guru/clickhouse-operator-chast-1-obzor-i-ystanovka-v-kubernetes/) (не рекомендуется для прода, больше для дев/стенд)
 
Quick Install

1. Команда для загрузки бинарника для вашей операционной системы (Linux, macOS and FreeBSD), который может использоваться для запуска сервера ClickHouse, clickhouse-client, clickhouse-local, ClickHouse Keeper и других инструментов
- curl https://clickhouse.com/ | sh 2. Запускаем ClickHouse Server
- ./clickhouse server
3. В новом терминале подкличаемся к клиенту
- ./clickhouse client

Docker image

Versions
- The latest tag points to the latest release of the latest stable branch.
- Branch tags like 22.2 point to the latest release of the corresponding branch.
- Full version tags like 22.2.3.5 point to the corresponding release.
- The tag head is built from the latest commit to the default branch.
- Each tag has optional -alpine suffix to reflect that it's built on top of alpine.

start server instance:
- docker run -d --name some-clickhouse-server --ulimit nofile=262144:262144 clickhouse/clickhouse-server
connect to it:
- from a native client
- docker run -it --rm --link some-clickhouse-server:clickhouse-server
          --entrypoint clickhouse-client clickhouse/clickhouse-server --host
          clickhouse-server
- docker exec -it some-clickhouse-server clickhouse-client
- using curl
- echo "SELECT 'Hello, ClickHouse!'" | docker run -i --rm --link
          some-clickhouse-server:clickhouse-server curlimages/curl
          'http://clickhouse-server:8123/?query=' -s --data-binary @-
  
  stopping / removing the container:
- docker stop some-clickhouse-server
- docker rm some-clickhouse-server


По лекции:
- 12:00 - препод поднимает виртуалку с голой убунтой, накатывает туда докер 
- накатывается слоедующий докер образ:
```bash
docker run -d --name some-clickhouse-server --ulimit nofile=262144:262144 clickhouse/clickhouse-server

# и внутри контенйнера
clickhouse-client
# без указания параметров клиент подключится к локальному кликхаусу!
show databases;
```

Второй вариант - [нативная установка](https://clickhouse.com/docs/en/install#quick-install). Устанавливаются 2 стандартные утилиты (`sudo apt-get install -y clickhouse-server clickhouse-client`), демонстрация на 18:30, при установке попросит установить пароль для дефолтного пользака. В отличии от докер образа, у нас только произойдет установка - нужно не забыть запустить клик `$ sudo service clickhouse-server start`

Еще вариант (для прода) - развернуть с помощью терраформа. [Вот](https://github.com/DWH-course-examples/dbt_clickhouse_lab/blob/main/main.tf) пример конфига для яндекс клауда. Мы указываем только параметры ресурса, который мы хотим развернуть. Плюс такого подхода - IAC (infra as code), то есть все находится в системе контроля версий (видна история изменений).

Packages
- clickhouse-common-static — Installs ClickHouse compiled binary files.
- clickhouse-server — Creates a symbolic link for clickhouse-server and installs the default server configuration. 
  Устанавливается clickhouse-server - это основное приложение, сама субд
- clickhouse-client — Creates a symbolic link for clickhouse-client and other
client-related tools. and installs client configuration files. Для доступа через cli
- clickhouse-common-static-dbg — Installs ClickHouse compiled binary files with
debug info.
- clickhouse-keeper - Used to install ClickHouse Keeper on dedicated ClickHouse
Keeper nodes. Installs ClickHouse Keeper and the default ClickHouse Keeper configuration files. Устанавливается на отдельных узлах в кластере (кликхаус достаточно привередлив к тем ресурсам, которые для него доступны)
 
Что такое Clickhouse Keeper:
- Сервер ClickHouse использует сервис координации ZooKeeper для репликации данных и выполнения распределенных DDL запросов. ClickHouse Keeper — это альтернативный сервис координации, совместимый с ZooKeeper (чтобы организовывать взаимодействие нескольких узлов, нескольких реплик в кластере кликхауса)
- По умолчании ClickHouse Keeper предоставляет те же гарантии, что и ZooKeeper. ClickHouse Keeper предоставляет совместимый клиент- серверный протокол, поэтому либой стандартный клиент ZooKeeper может использоваться для взаимодействия с ClickHouse Keeper.
- В производственной среде запускать ClickHouse Keeper на выделенных узлах. 

Зачем:
- Создан осеньи 2022 года. Текущие обновления
- Координатор как замена Zookeeper от Apache
- Написан на C++. Должен работать быстрее и кушать меньше памяти
- Меньше вопросов с настройкой, так как идет в комплекте

Нюансы:
- Мало документации
- Не хватает нормального конфига. Часть берется из основного конфига клика
- Нет режима суперпользователя
- Все же не совместим с Zookeeper (ошибки Coordination::Exception: Operation 101 is unknown (Unimplemented))

Еще один интересный вариант поднять кликхаус - своя собственная сборка. Команда кликхауса называет это non-production deployment. За основу берется код, который лежит в официальном [гитхаб-репозитории](https://github.com/ClickHouse/ClickHouse)

##  Базовая конфигурация, запуск и тестовые датасеты (36:00)

Есть 2 файла-шаблона config.xml и users.xml. Эти файлы можно рассматривать именно как шаблоны конфигурации. После установки рекомендуется все изменения делать в новых отдельных файлах. Разделение на эти 2 файла больше логическое - чтобы логически отделить параметры, которые относятся к пользователю (профили, квоты, способы авторизации) от конфигов, которые относятся ко всему серверу целиком. Еще одна причина держат изменения отдельно - это обновление кликхауса. Рано или поздно клик обновится и тогда мы рискуем остаться без своих кастомных настроек.

ClickHouse хранит конфигурацию в 2 различных конфигурационных файлах:
- /etc/clickhouse-server/config.xmlсодержит настройки сервера.
- /etc/clickhouse-server/users.xmlсодержит конфигурацию пользователей и настройки сервера, которые могут быть переопределены для каждого пользователя.

ВАЖНО! Непосредственно редактировать эти файлы не рекомендуется, вместо этого следует хранить конфигурацию в отдельных файлах в каталогах /etc/clickhouse-server/config.d/и /etc/clickhouse-server/users.d/.
 
### users.xml и config.xml

Содержатся:
- профили пользователей (profiles) - по умолчанию только 1, default, по имени пользователя
- пользователи (users) - здесь по большей части все закомментировано. Для пользователя default есть его объявление (что у нас действительно такой пользователь есть). Есть закомментированный раздел с грантами и квотами,
- квоты (quotas) - Все параметры, котоыре касаются квот, способов авторизации 

Параметры можно также посмотреть в табличке `system.settings`
```sql
SELECT * FROM system.settings WHERE name = 'queue_max_wait_ms' 
```
ClickHouse поставляется с таблицей system.settings, которая содержит настройки сеанса для текущего пользователя. Если настройка существует в таблице system.settings, то ее следует поместить в каталог users.d. В противном случае попробуйте использовать каталог config.d.
 
Главыный источник правды, где можно посмотреть все настройки - это [гитхаб репозиторий](https://github.com/ClickHouse/ClickHouse/blob/master/src/Core/Settings.h) и [мд-шка с пояснениями](https://github.com/ClickHouse/ClickHouse/blob/master/docs/en/operations/server-configuration-parameters/settings.md?plain=1). [Документация](https://clickhouse.com/docs/en/operations/settings/settings) может отставать, в нее могут забыть что то добавить, тут же мы можем переключиться на необходимую ветку и играться с настройками.

Часто встречающиеся настройки:
- max_memory_usage - это как раз первая настройка, которую стоит поменять/потюнить. Желательно эту настройку указывать в users.d/our_users.xml (в разделе с квотами)
- max_execution_time
- force_primary_key

Рекомендации после установки
1. Настройте параметры памяти:
  - max_memory_usage - параметр управляет максимальным объемом памяти, который может использовать ClickHouse.
2. Настройка количества потоков:
 - Например, можно увеличить количество потоков, используемых для операций SELECT, чтобы повысить производительность чтения. Также задается в users.xml
3. Настройка размера буфера:
 - Это позволит минимизировать количество операций дискового ввода-вывода. Его чаще всего уменьшают по сравнению со стандартным значением, чтобы быстрее происходило скидывание буффера на диск.
4. Настройте merge settings - как будет происходить мердж данных в клике (но по умолчанию в целом все норм)
5. Настройка параметров сжатия
6. Настройка параметров реплики
7. Отслеживайте производительность
8. Увеличьте количество открытых файловых дескрипторов: Увеличьте значение параметра "ulimit -n" не менее чем до 100000. Тк в клике сохранение данных происходит непосредственно на диск. В процессе работы может появиться много партов (много файлов), так что для кликхауса это действительно важный параметр.
9. Увеличьте объем разделяемой памяти: Увеличьте значение параметра "kernel.shmmax" не менее чем до 1 Гб. 
10. Настроить прозрачные огромные страницы ([transparent huge pages](https://habr.com/ru/companies/otus/articles/460403/)): Отключите прозрачные огромные страницы, добавив в командную строку ядра значение "transparent_hugepage=never".
11. Настроить планировщик: Измените планировщик с используемого по умолчанию "cfq" на "noop" или "deadline".
12. Оптимизировать работу сети: Увеличьте количество сетевых очередей, включите автонастройку TCP и отключите опции разгрузки.
13. Контролируйте загрузку системы: Используйте такие инструменты, как "top" или "htop", для мониторинга загрузки системы, использования памяти и дискового ввода-вывода.
14. Мониторинг производительности ClickHouse: Используйте встроенные средства мониторинга производительности ClickHouse для выявления и устранения узких мест в работе.

Рекомендации по выбору сервера
1. Идем поэтапно - память (RAM), процессоры, диски (SSD, NvMe)
 - Пример - 512GB, 2 проца Gold, ядер больше 16 (прод - больше 32)
2. Ограничения:
 - max_concurrent_queries_for_user и max_threads для пользователей
 - max_result_rows и max_result_bytes, чтобы избежать падения “веб-морды”
 - max_bytes_in_set и max_rows_in_join, чтобы ограничить джоины и распределенные запросы
 - max_bytes_before_external_group_by, в зависимости от объема оперативки
3. Еще:
 - Процессоры не армы!
 - Не забывайте про бекапы и где их в итоге нужно складывать
 - Оперативку считаем от объема словарей

Тестовые датасеты можно взять отсюда:
- [Example Datasets](https://clickhouse.com/docs/en/getting-started/example-datasets)
- [Advanced Tutorial](https://clickhouse.com/docs/en/tutorial)

## Интерфесы доступа

1. Сетевые интерфейсы (HTTP, TCP, gRPC)
2. Библиотеки (CLI, JDBC/ODBC driver, C++ client library)
3. Визуальные интерфейсы (Play UI, Advanced Dashboard, Binary symbols viewer for ClickHouse engineers)
4. Сторонние библиотеки (клиентские библиотеки, интеграции, визуальные интерфейсы)

Основные интерфейсы можно посмотреть вот на такой схеме:

![схема](images/03_01.png)

Часть из них - библиотеки, а часть - процессы, которые запускаются.

clickhouse-client позволяет не просто писать sql запромсы, но также и загружать данные в кликхаус. Самый простой вариант как можно получить данные из тестовых датасетов.

##  CLI (Command-Line Client)

clickhouse-client
- Клиент можно использовать в интерактивном и неинтерактивном (пакетном) режиме.
- Подключение через TCP :
  - ХОСТ и ПОРТ: обычно порт 9440 при использовании TLS или 9000 при отсутствии TLS.
  - ИМЯ БАЗЫ ДАННЫХ
  - ИМЯ ПОЛЬЗОВАТЕЛЯ И ПАРОЛЬ
```bash
clikhouse-client --host <HOSTNAME> \
    --secure \
    --port 9440 \
    --user <USERNAME> \
    --password <PASSWORD>

clikhouse-client --host HOSTNAME.clickhouse.cloud \
    --secure \
    --port 9440 \
    --user default \
    --password PASSWORD \
    --query "INSERT INTO cell_towers FORMAT CSVWithNames" \
    < cell_towers.csv

# варианты вставки данных
\copy (select * from table) to '~/filename' with csv;
cat ~/filename | clickhouse-client -h host -u user --password
--query="insert into table format CSV"
 
# еще варианты - в презе
```
 
Заметки по CLI

- В пакетном режиме по умолчанию TabSeparated
- Параметр --multiquery для выполнения нескольких запросов (кроме insert)
- \G для вертикального формата
- История командной строки записывается в ~/.clickhouse-client-history
- Для выхода из клиента - “exit”, “quit”, “logout”, “exit;”, “quit;”, “logout;”, “q”, “Q”, “:q”
- Для отмены запроса - ctrl+C (cmd+C). Повторно для завершения работы клиента
 
Конфигурация и параметры:

clickhouse-client использует первый существующий файл из следующих:
- Определяется в параметре --config-file.
- ./clickhouse-client.xml, .yaml, .yml
- ~/.clickhouse-client/config.xml, .yaml, .yml
- /etc/clickhouse-client/config.xml, .yaml, .yml

Параметры:
```
--host, -h
--port
--user, -u 
--password 
--ask-password 
--query, -q 
--queries-file 
--multiquery
--multiline, -m
--database, -d 
--format, -f 
--vertical, -E
--time, -t
--stacktrace
--config-file
--secure --history_file
--param_<name> 
--hardware-utilization
--print-profile-events 
--profile-events-delay-ms
```

Connection string

- Можно подключаться к нескольким хостам (URI)
- Кодировка нестандартных символов в процентах
```bash
clickhouse:[//[user[:password]@][hosts_and_ports]][/database][?query_parameters]
clickhouse-client clickhouse://localhost:9000 --query "SELECT 1"
clickhouse-client clickhouse:
clickhouse-client clickhouse://some_user%40some_mail.com@localhost:9000
clickhouse-client clickhouse://192.168.1.15,192.168.1.25
```

## Вставка данных

Примеры вставки данных есть в [документации](https://clickhouse.com/docs/en/getting-started/example-datasets/nyc-taxi)

## HTTP Interface

- Позволяет использовать ClickHouse на любой платформе с любого языка программирования в виде REST API
- HTTP port - 8123, HTTPS - 8443
- Web UI - http://localhost:8123/play (/dashboard)
 
Полезные запросы 
```bash
curl 'http://localhost:8123/ping'
curl 'http://localhost:8123/replicas_status'
# Для запросов, изменяющих данные - POST, GET - readonly.
curl 'http://localhost:8123/?query=SELECT%201'
echo -ne 'GET /?query=SELECT%201 HTTP/1.0\r\n\r\n' | nc localhost 8123
echo 'SELECT 1 FORMAT Pretty' | curl 'http://localhost:8123/?user=default&password=default' --data-binary @-
# Метод POST для передачи данных необходим для запросов INSERT.
echo 'CREATE TABLE t (a UInt8) ENGINE = Memory' | curl 'http://localhost:8123/' --data-binary @-
```
  
Сжатие
- Сжатие используется для уменьшения сетевого трафика при передаче большого количества данных или для создания дампов, которые сразу же сжимаются
- clickhouse-compressor для работы с внутренним форматом сжатия
- compress=1 в URL - сервер будет сжимать данные, которые он вам отправляет. decompress=1, сервер будет сжимать данные, которые вы передаете в методе POST.
- Вы также можете выбрать использование HTTP-сжатия
```bash
echo "SELECT 1" | gzip -c | curl -sS --data-binary @- -H 'Content-Encoding: gzip' 'http://localhost:8123/'
curl -vsS "http://localhost:8123/?enable_http_compression=1" -H 'Accept-Encoding: gzip' --output result.gz -d 'SELECT number FROM system.numbers LIMIT 3'
curl -sS "http://localhost:8123/?enable_http_compression=1" -H 'Accept-Encoding: gzip' -d 'SELECT number FROM system.numbers LIMIT 3' | gunzip -
```

Аутентификация
```bash
echo 'SELECT 1' | curl 'http://user:password@localhost:8123/' -d @-
echo 'SELECT 1' | curl 'http://localhost:8123/?user=user&password=password' -d @-
echo 'SELECT 1' | curl -H 'X-ClickHouse-User: user' -H 'X-ClickHouse-Key: password' 'http://localhost:8123/' -d @-
```
Примеры:
- https://github.demo.altinity.cloud:8443/play (user=demo/pw=demo)
  
Параметры
```bash
curl -sS "<address>?param_id=2&param_phrase=test" -d "SELECT * FROM table WHERE int_column = {id:UInt8} and string_column = {phrase:String}"
curl -sS "http://localhost:8123?param_arg1=abc%5C%09123" -d "SELECT splitByChar('\t', {arg1:String})"
```

##  Прочие интерфейсы и драйверы

JDBC/ODBC Drivers
- ClickHouse Java Libraries - Java-библиотеки для подключения к ClickHouse и обработки данных в различных форматах. Java-клиент - это асинхронная, легкая и не требующая больших затрат библиотека для ClickHouse, а драйверы JDBC и R2DBC построены поверх Java-клиента и имеют больше зависимостей и возможностей.
- ODBC Driver for ClickHouse - это официальная реализация драйвера ODBC для доступа к ClickHouse в качестве источника данных.

[ClickHouse JDBC Bridge](https://clickhouse.com/docs/en/integrations/jdbc/jdbc-with-clickhouse) в сочетании с функцией jdbc table или JDBC table engine позволяет ClickHouse получать доступ к данным из любого внешнего источника данных, для которого доступен драйвер JDBC:
- Это удобно, когда нет встроенного механизма интеграции, табличной функции или внешнего словаря для внешнего источника данных, но существует JDBC-драйвер для источника данных.
- Можно использовать ClickHouse JDBC Bridge как для чтения, так и для записи.
- Можно использовать параллельно для нескольких внешних источников данных.
 
Драйвер ClickHouse Open Database Connectivity(ODBC) позволяет пользователям подключать различные приложения к ClickHouse, например, подключать Microsoft Excel, Tableau Desktop и другие платформы. Официальный ODBC-драйвер для ClickHouse доступен в бинарных версиях для дистрибутивов Microsoft Windows и Linux. Его также можно установить путем компиляции исходного кода для других операционных систем, например Mac OS X.

Databases Interfaces
[PostgreSQL](https://clickhouse.com/docs/en/interfaces/postgresql)
- Протокол PostgreSQL wire
- В некотором смысле ClickHouse может притвориться экземпляром PostgreSQL, что позволит вам подключить к ClickHouse клиентское приложение PostgreSQL, которое еще не поддерживается ClickHouse напрямую (например, Amazon Redshift).
- Новый файл в config.d - определяем порт
- psql -p [port] -h [hostname] -U [username] [database_name]

[MySQL](https://clickhouse.com/docs/en/interfaces/mysql)
- Протокол MySQL wire
- Новый файл в config.d - определяем порт
- Подключение - mysql --protocol tcp -h [hostname] -u [username] -P [port_number] [database_name]
- Указывать в конфигурационном файле пароль пользователя с двойным SHA1, иначе некоторые клиенты не смогут пройти аутентификацию
 
ClickHouse может автоматически определять структуру входных данных почти во всех поддерживаемых форматах ввода (Schema Inference).
- Вывод схемы используется, когда ClickHouse необходимо прочитать данные в определенном формате, а их структура неизвестна.
```sql
select * from file('hobbies.jsonl');
describe file('hobbies.jsonl');

CREATE TABLE hobbies ENGINE=File(JSONEachRow, 'hobbies.jsonl');
clickhouse-local --file='hobbies.jsonl' --table='hobbies' --query='DESCRIBE TABLE hobbies'
```
- use_structure_from_insertion_table_in_table_functions
-- 0 - табличная функция будет извлекать структуру из данных.
-- 1 - функция таблицы будет использовать структуру из таблицы вставки.
-- 2 - ClickHouse автоматически определит, можно ли использовать структуру из
таблицы вставки или использовать вывод схемы. Значение по умолчанию.

Чтобы предотвратить вывод одной и той же схемы каждый раз, когда ClickHouse считывает данные из одного и того же файла, выведенная схема кэшируется, и при повторном обращении к тому же файлу ClickHouse будет использовать схему из кэша.
```sql
DESCRIBE TABLE s3('https://datasets-documentation.s3.eu-west-3.amazonaws.com/github/github-2022.ndjson.gz')
SETTINGS allow_experimental_object_type = 1
DESCRIBE TABLE s3('https://datasets-documentation.s3.eu-west-3.amazonaws.com/github/github-2022.ndjson.gz')
SETTINGS input_format_json_read_objects_as_strings = 1
SELECT schema, format, source FROM system.schema_inference_cache WHERE storage='S3'
SYSTEM DROP SCHEMA CACHE FOR S3
```
Для текстовых форматов ClickHouse считывает данные строка за строкой, извлекает значения столбцов в соответствии с форматом, а затем использует некоторые рекурсивные парсеры и эвристики для определения типа каждого значения
```sql
DESC format(JSONEachRow, '{"int" : 42, "float" : 42.42, "string" : "Hello, World!"}');
DESC format(CSV, '42,42.42,true,"Hello,World!"')
DESC format(Values, $$(42, 42.42, true, 'Hello,World!')$$)
```

## HW (1:30:00)

По дз, что отобразить в отчете,
- количество рпс, сколько запросов было обработано до изменения настроек и после. Замер делать с помощью clickhouse-benchmark . Отчет нужно будет скопировать 2 раза и поместить в свой отчет

## Заметки 

приберечь промокод для яндекс клауда до разворачивания кластеров на виртуалках. 

max_memory_usage - это как раз первая настройка, которую стоит поменять/потюнить. Особенно на би-ай учетки/аналитиков.

есть ссылки в конце презы для разных настроек