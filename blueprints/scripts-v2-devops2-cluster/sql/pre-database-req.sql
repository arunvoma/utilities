CREATE DATABASE ambari; 
CREATE USER ambari WITH PASSWORD 'bigdata';
GRANT ALL PRIVILEGES ON DATABASE ambari TO ambari; 
CREATE DATABASE hive;
CREATE USER hive WITH PASSWORD 'hive';
GRANT ALL PRIVILEGES ON DATABASE hive TO hive;
CREATE DATABASE ranger;
CREATE USER rangeradmin WITH PASSWORD 'rangeradmin';
GRANT ALL PRIVILEGES ON DATABASE ranger TO rangeradmin;
GRANT rangeradmin to v_dbadmin;
