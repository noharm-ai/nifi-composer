# nifi-composer - working for Nifi and Anony
Build NoHarm Integration

## 1. Install Docker compose 
Based on https://docs.docker.com/compose/install/linux/

For Ubuntu and Debian:
```sudo apt-get update```
```sudo apt-get install docker-compose-plugin```

For RPM-based distros:
```sudo yum update```
```sudo yum install docker-compose-plugin```

## 2. Clone the repository
```git clone https://github.com/noharm-ai/nifi-composer/ ```

## 3. Update the environment variables (noharm.env)

## 4. Compose Up

set dockerhub user and password:

```
docker login
cd nifi-composer
./update_secrets.sh
docker compose up -d
```

Wait until the containers are ready...

```docker logout```

## 5. Update Nifi Timezone
```docker exec --user="root" -it noharm-nifi /bin/bash``` 
```echo "java.arg.8=-Duser.timezone=America/Sao_Paulo" >> conf/bootstrap.conf```

## 6. Getname - Simple Test

```
curl https://nomedocliente.getname.noharm.ai/patient-name/12345
```

### 6.1. Getname - other specificaitons

[(https://github.com/noharm-ai/getname-api)](https://github.com/noharm-ai/getname-api)

## 7. Anony - Local Test

```
curl -X PUT -H 'Accept: application/json' -H 'Content-Type: application/json' http://localhost/clean -d '{"TEXT" : "FISIOTERAPIA TRAUMATO - MANHÃ  Henrique Dias, 38 anos. Exercícios metabólicos de extremidades inferiores. Realizo mobilização patelar e leve mobilização de flexão de joelho conforme liberado pelo Dr Marcelo Arocha. Oriento cuidados e posicionamentos."}'
```

### 7.1. Anony - other specificaitons

[(https://github.com/noharm-ai/noharm-anony)](https://github.com/noharm-ai/noharm-anony)

### Reference commands for Docker Compose: 
https://docs.docker.com/engine/reference/commandline/compose_up/
