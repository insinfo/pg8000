cd "C:\Program Files\PostgreSQL\14\data"
 Openssl genrsa -out server.key 4096

### https://stackoverflow.com/questions/43959324/chmod-og-rwx-server-key-in-windows/51463654#51463654
icacls server.key /reset
icacls server.key /inheritance:r /grant:r "CREATOR OWNER:F"

chmod og-rwx server.key

### 
Openssl req -new -x509 -days 3660 -key server.key -out server.crt


You are about to be asked to enter information that will be incorporated
into your certificate request.
What you are about to enter is what is called a Distinguished Name or a DN.
There are quite a few fields but you can leave some blank
For some fields there will be a default value,
If you enter '.', the field will be left blank.
-----
Country Name (2 letter code) [AU]:BR
State or Province Name (full name) [Some-State]:Rio de Janeiro
Locality Name (eg, city) []:Rio das Ostras
Organization Name (eg, company) [Internet Widgits Pty Ltd]:PMRO
Organizational Unit Name (eg, section) []:COTINF
Common Name (e.g. server FQDN or YOUR name) []:*.riodasostras.rj.gov.br
Email Address []:webmaster@riodasostras.rj.gov.br