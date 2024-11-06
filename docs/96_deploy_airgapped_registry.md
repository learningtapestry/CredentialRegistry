# Deploy air-gapped registry application

## Tech notes
### SELinux
The sandbox environment uses the SElinux mode "enforcing", and it does not need to mount "/app" directory using the label ":z" or ":Z".  Instead of we use label "/app:z" the application container returns "Could not locate Gemfile" which indicates that the application is not able to access the "/app" directory for reading.

## Pre-requisites

## Instructions
1. Log in and create root directory
```
mkdir CredentialRegistry
cd CredentialRegistry
``` 
  
2. Retrieve bundles
```
curl https://credregbundle.s3-accelerate.amazonaws.com/credregapp-bundle-v2.tar.gz -o credregapp-bundle-v2.tar.gz
curl https://credregbundle.s3-accelerate.amazonaws.com/credentialregistry-app-latest-airgapped-v6.tar -o credentialregistry-app-latest-airgapped-v6.tar
```
3. Create docker-compose.yml file:
```
version: '3'
services:
  db:
    image: postgres:13.2-alpine
    environment:
      - POSTGRES_PASSWORD=postgres
    ports:
      - 5432:5432
    volumes:
      - postgres:/var/lib/postgresql/data

  redis:
    image: redis:5.0.5-alpine
    expose:
      - 6379

  app:
    image: credentialregistry-app:latest-airgapped-v6
    command: bash -c "bundle install && bin/rackup -o 0.0.0.0"
    env_file:
    volumes:
      - bundle:/usr/local/bundle
    ports:
      - 9292:9292
    depends_on:
      - db
      - redis
    security_opt:
      - seccomp:unconfined

volumes:
  bundle:
  postgres:
  rails_cache:
```
4. Untar bundle file
5. docker load -i [docker images]

