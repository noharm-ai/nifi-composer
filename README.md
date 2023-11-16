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


### Reference commands for Docker Compose: https://docs.docker.com/engine/reference/commandline/compose_up/
