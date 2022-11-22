# pg8000
a dart port from https://github.com/tlocke/pg8000

SELECT * FROM pg_hba_file_rules();
SELECT pg_reload_conf();
SHOW password_encryption;
//SET password_encryption = 'scram';
SET password_encryption = 'md5';
# change password
\password postgres