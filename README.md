# nifi-composer - NoHarm Package
Build NoHarm Integration

## 1. Install Docker compose 
Based on https://docs.docker.com/compose/install/linux/

For Ubuntu and Debian:
```
sudo apt-get update
sudo apt-get install docker-compose-plugin
```

For RPM-based distros:
```
sudo yum update
sudo yum install docker-compose-plugin
```

Docker Install Ubuntu
 - https://docs.docker.com/engine/install/ubuntu/

## 2. Clone the repository
```git clone https://github.com/noharm-ai/nifi-composer/ ```

## 3. Update the environment variables (noharm.env)

## 4. Compose Up

```
cd nifi-composer
./update_secrets.sh
sudo chown $USER /var/run/docker.sock
docker compose up -d
```

Wait until the containers/nifi web are ready...

```
docker logs noharm-nifi --tail 500 | grep "JettyServer NiFi has started"
```

```
docker exec --user="root" -t noharm-nifi sh -c /opt/nifi/scripts/ext/genkeypair.sh
docker exec --user="root" -t noharm-nifi apt update
docker exec --user="root" -t noharm-nifi apt install nano vim awscli wget -y
docker restart noharm-nifi
```
### 4.1 Validation

 - Check if the certificate is valid for 200 years (in the browser):
    - At Google Chrome menu: More tools - Developer tools - select the "Security" tab - View certificate
 - Check if aws is working ```docker exec --user="nifi" -t noharm-nifi aws s3 ls```

## 5. Getname - Simple Test

Check if service is working:

```
curl https://nomedocliente.getname.noharm.ai
```

Check if database connection is working:

```
curl https://nomedocliente.getname.noharm.ai/patient-name/12345
```

### 5.1. Getname - other specificaitons

[(https://github.com/noharm-ai/getname-api)](https://github.com/noharm-ai/getname-api)

## 6. Anony - Local Test

```
curl -X PUT -H 'Accept: application/json' -H 'Content-Type: application/json' http://localhost/clean -d '{"TEXT" : "FISIOTERAPIA TRAUMATO - MANHÃ  Henrique Dias, 38 anos. Exercícios metabólicos de extremidades inferiores. Realizo mobilização patelar e leve mobilização de flexão de joelho conforme liberado pelo Dr Marcelo Arocha. Oriento cuidados e posicionamentos."}'
```

### 6.1. Anony - other specificaitons

[(https://github.com/noharm-ai/noharm-anony)](https://github.com/noharm-ai/noharm-anony)

## 7. How to rebuild a single container

```
docker stop <servicename>
docker rm <servicename>
docker image ls #pra pegar o id do container
docker image rm <id do container>
docker compose up -d --build <servicename>
```
### Reference commands for Docker Compose: 
https://docs.docker.com/engine/reference/commandline/compose_up/
