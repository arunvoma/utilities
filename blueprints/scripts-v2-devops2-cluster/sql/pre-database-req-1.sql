
\connect ambari; 
alter user ambari CREATEDB;
create schema ambari authorization ambari;
alter schema ambari owner to ambari;
alter role ambari set search_path to 'ambari','public';
