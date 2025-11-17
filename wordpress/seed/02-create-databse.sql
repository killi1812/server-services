-- init.sql

CREATE DATABASE IF NOT EXISTS kupa;
CREATE DATABASE IF NOT EXISTS personal;

GRANT ALL PRIVILEGES ON kupa.* TO 'admin'@'%';
GRANT ALL PRIVILEGES ON personal.* TO 'admin'@'%';

