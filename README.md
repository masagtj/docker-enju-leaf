# docker-enju-leaf

Docker image for [Next-L Enju Leaf](https://github.com/next-l/enju_leaf). Next-L Enju Leaf is an integrated library system developed by [Project Next-L](http://www.next-l.jp/).

## Launch Enju Leaf

1. Clone `docker-enju-leaf.git` and launch containers.

```
$ git clone https://github.com/masagtj/docker-enju-leaf.git
$ cd docker-enju-leaf
$ docker-compose up
```

2. Open `http://<DOCKER_HOST>:3000/`.
3. Administrator account is:
  * user: `enjuadmin`
  * password: `adminpassword`


## Build image

DB required for image build Use build-time arguments

```
docker run --name db -p 5432:5432 -e POSTGRES_USER=postgres -e POSTGRES_PASSWORD=password -e POSTGRES_DB=enju_production -d postgres:9.6
docker run --name redis -p 6379:6379 -d redis:latest
docker build -t docker-enju-leaf:1.2.2 . --build-arg temp_db_host=192.168.99.100
```


## Environment
### mail
* ENJU_HOST=enju hostname <default=localhost:3000>
* MAILER_DELIVERY_METHOD=:smtp
* MAILER_ADDRESS=""
* MAILER_PORT=
* MAILER_DOMAIN=""
* MAILER_USERNAME=""
* MAILER_PASSWORD=""
* MAILER_AUTH=login
* MAILER_TLS=true

### ldap
- LDAP_HOST="your ldap host"
- LDAP_PORT=389
- LDAP_LDAPS=false
- LDAP_DOMAIN="your domain"
- LDAP_BASEDN="ou=xx,dc=xx,dc=xx"
- LDAP_BIND_USERNAME="sAMAccountName"
- LDAP_BIND_FULL_NAME="displayName"
- LDAP_BIND_MAIL="mail"

### Relative URL
* RAILS_RELATIVE_URL_ROOT=/enju-leaf <default=/>

In the above case `http://<DOCKER_HOST>:3000/enju-leaf`
