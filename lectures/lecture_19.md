# Storage policy и резервное копирование

Почему мы делаем бэкапы
- катастрофические сбои, в результате которых удаляются все данные
- случайное удаление бд или таблицы
- отладка проблем с использованием производственных данных
- тестирование обновлений перед изменением схемы или версии
- загрузка схемы и конфигурации для новых установок

Что нужно спасать?

![Что нужно спасать?](images/19_01.png)

Варианты бэкапирования

![Варианты бэкапирования](images/19_02.png)

## утилита clickhouse-backup

Работает на го и на питоне, есть репа. Можно поднять в докере.

инструмент для простого резервного копирования и восстановления ClickHouse с поддержкой многих типов облачных и необлачных хранилищ
- простое создание и восстановление резервных копий всех или определенных таблиц
- эффективное хранение нескольких резервных копий в файловой системе
- загрузка и выгрузка с потоковым сжатием
- работает с aws, gcs, azure, tencent cos, ftp, sftp
- поддержка atomic database engine
- поддержка многодисковых инсталляций (размещение бэкапов на нескольких дисках)
- поддержка пользовательских типов удаленных хранилищ
- поддержка инкрементного резервного копирования на удаленное хранилище

Установка
```bash
# Grab the latest release from GitHub.
wget https://github.com/Altinity/clickhouse-backup/releases/download/v2.5.20/clickhouse-backup-linux-amd64.tar.gz
tar -xf clickhouse-backup-linux-amd64.tar.gz
# Install.
sudo install -o root -g root -m 0755 build/linux/amd64/clickhouse-backup/usr/local/bin
# Try it out.
/usr/local/bin/clickhouse-backup -v
```

Подготовка конфигов
```bash
sudo -u clickhouse mkdir /etc/clickhouse-backup
sudo -u clickhouse clickhouse-backup \ default-config > /etc/clickhouse-backup/config.yml
sudo -u vi /etc/clickhouse-backup/config.yml
# Прописываются секции general, clickhouse, s3
```
Это не дефолтный конфиг - это шаблон

Создание бэкапа

![Создание бэкапа](images/19_03.png)

Точно так же мы можем сделать руками:

![Создание бэкапа](images/19_04.png)

Восстановление из бэкапа

Точно так же мы можем сделать руками:

![Восстановление из бэкапа](images/19_06.png)

По сути, все бэкапы - это перебор хардлинками

Примеры команд для бэкапа и восстановления из бэкапа + полезные команды
```bash
# Back up everything locally.
sudo -u clickhouse clickhouse-backup create mybackup --rbac --configs
# Back up a single table locally.
sudo -u clickhouse clickhouse-backup create mybackup_table_local -t default.ex2
# Back up and upload a database to remote backup storage.
sudo -u clickhouse clickhouse-backup create_remote mybackup_database_remote -t 'default.*'

# Примеры команд для восстановления из бекапа
# Restore all data from already downloaded backup.
sudo -u clickhouse clickhouse-backup restore mybackup
# Restore a single table from local backup.
sudo -u clickhouse clickhouse-backup restore \ mybackup -t default.ex2
# Download and restore a single database.
sudo -u clickhouse clickhouse-backup restore_remote \ mybackup -t 'default.*'

# Полезные команды
# Listing your backups.
sudo -u clickhouse clickhouse-backup list
sudo -u clickhouse clickhouse-backup list local
sudo -u clickhouse clickhouse-backup list remote
# Deleting backups.
sudo -u clickhouse clickhouse-backup delete local mybackup
sudo -u clickhouse clickhouse-backup delete remote mybackup
```

встроенные backup/restore

```sql
-- Creating a full backup
BACKUP DATABASE my_database TO 'file:///backups/my_database_backup';
-- Creating an incremental backup
BACKUP DATABASE my_database TO 'file:///backups/my_database_backup_incremental' WITH increment;
-- Creating a differential backup
BACKUP DATABASE my_database TO 'file:///backups/my_database_backup_differential' WITH differential;
```

Постановка на расписание
```bash
# Cron job for daily full backups at 2 AM
0 2 * * * clickhouse-client --query="BACKUP DATABASE my_database TO 'file:///backups/my_database_backup'"
```

Восстановление из бекапа
```sql
-- Restoring a full backup
RESTORE DATABASE my_database FROM 'file:///backups/my_database_backup';
-- Restoring an incremental backup
RESTORE DATABASE my_database FROM
'file:///backups/my_database_backup_incremental';
-- Restoring a differential backup
RESTORE DATABASE my_database FROM
'file:///backups/my_database_backup_differential';
```


## Storage policy

- правила хранения и управления данными (Storage policy определяет, как и где хранятся данные)
- контроллирует, где и как хранятся данные (Определяет места и методы хранения данных)
- оптимизирует производительность и использование ресурсов (Правильные политики хранения повышают производительность запросов и оптимизируют затраты на хранение данных.)

![что такое сторадж полиси](images/19_07.png)

Компоненты Storage policy
- Тома (Volumes) - Логическая группировка дисков.
- Диски (Disks) - Физические или логические единицы хранения, используемые для хранения данных.
- Конфигурация хранилища (Storage Configuration) - Настройка, определяющая, как используются диски и тома.
- Диаграмма, показывающая взаимосвязь между этими компонентами. (*)

Тома:
- Cостоят из нескольких дисков.
- Данные могут быть распределены по дискам одного volume для балансировки нагрузки.

Диски:
- Диски могут быть физическими дисками или логическими единицами, например сетевыми хранилищами.

Различные типы вольюмов (томов)
- Локальные: высокоскоростные SSD или HDD.
- Сетевые хранилища (NAS).
- Хранилище S3 для масштабируемого облачного хранения данных.

![Conf](images/19_08.png)

Различные типы дисков:
- Локальные диски: Высокая скорость, ограниченная емкость.
  - Плюсы: Низкая задержка, высокая производительность.
  - Минусы: ограниченная масштабируемость, более высокая стоимость за ГБ.
- Сетевые диски: Умеренная скорость, общие ресурсы.
  - Плюсы: Возможность совместного использования, умеренная масштабируемость.
  - Минусы: задержки в сети, возможные перегрузки.
- Облачные хранилища (S3, HDFS): Масштабируемое, экономичное.
  - Плюсы: Практически неограниченное хранилище, экономичность.
  - Минусы: большая задержка, зависимость от интернет-соединения.

```bash
/url_schema_mappers
/storage_configuration
```

Различные типы дисков
- локальные диски - высокая с
- сетевые
- облачные хранилища (s3, hdfs) - масштабируемое, экономичное

создание Storage policy

- Укажите диски, доступные для хранения.
- Сгруппируйте диски в тома.
- Создайте политику, обüединяющую тома.

плюсы использования Storage policy
- эффективный поиск данных и выполнение запросов
- оптимизация затрат на хранение данных за счет использования соответствующих типов дисков
- масштабируемость

Полезные запросы для проверки наших дисков
```bash
du -lh /var/lib/clickhouse
```

Полезные запросы
```sql
SELECT 
    name, 
    path,
    formatReadableSize(free_space) AS free,
    formatReadableSize(total_space) AS total,
    formatReadableSize(keep_free_space) AS reserved
FROM system.disks;
select policy_name, volume_name, disks from system.storage_policies;
SELECT name, disk_name, path FROM system.parts;
SELECT name, data_paths, metadata_path, storage_policy
FROM system.tables WHERE name LIKE 'sample%';
```

А можем рассмотреть пример с настройкой ттл на выгрузку на с3 вместо удаления?

еще к вопросам (можем на q&a, если долго настраивать) - А можем рассмотреть пример с настройкой ттл на выгрузку на с3 вместо удаления? ну и пример селекта этих данных с с3

https://clickhouse.com/docs/en/operations/backup