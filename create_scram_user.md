psql -h localhost -p 5432 --username=postgres postgres

SELECT * FROM pg_hba_file_rules();
SELECT pg_reload_conf();
SHOW password_encryption;
//SET password_encryption = 'scram';
SET password_encryption = 'md5';
# change password
\password postgres

# create user
CREATE ROLE usarioscram WITH LOGIN SUPERUSER PASSWORD 's1sadm1n';

# test user
psql -h localhost -p 5432 --username=usarioscram postgres


 psql --command="SET password_encryption = 'md5';" --command="CREATE ROLE usermd5 WITH LOGIN SUPERUSER PASSWORD 's1sadm1n'" --command="\du"